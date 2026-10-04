extends RefCounted
# PlaySession — the transport-agnostic Play API core (docs/play-api.md, #46 M2).
# Owns the player's turn vocabulary, driving the REAL SquadManager / TurnManager /
# PlanResolver / RulesService. No side channels (Law #3). Commands return structured
# Dictionaries; play/board_view.gd renders them. The headless executor applies the
# resolved plan's EFFECTS (move = teleport, attack = apply_damage + element states;
# side-channel actions run their REAL execute() — it's pure synchronous logic) —
# i.e. game.gd.execute_orders minus the animation awaits, so preview == execution (Law #2).
# A mission is scored through the same MissionState the game's MissionController holds (#46).

var grid: TileMapLayer
var units_root: Node2D
var squad_manager: SquadManager
var turn_manager: TurnManager
var overlay_manager: OverlayManager
var terrain_states: TerrainStateManager   # twin of game.terrain_states; null on a board built without one
var board_heights: BoardHeights           # twin of game.board_heights (#257); null board reads flat
var gas_field: GasField                   # twin of game.gas_field (#508); null on a board built without one
var scenario_data: ScenarioData          # authored scenario metadata (#612); null on fresh new boards
var reserve_root: Node2D                  # where a drawn roster waits off the board (#46); null on a board built without one
var zone_manager: ZoneManager             # the zones the deployment cells are read from (#46)

var _handle_by_unit := {}      # Unit -> String (stable display handle)
var _next_player := 0
var _next_enemy := 0
var _downed_pending: Array[Unit] = []   # units downed mid-execute; ejected AFTER the pass (mirrors OrderExecutor._downed_pending)
# This mission's state and rules (#46) -- the SAME object the game's MissionController holds, so a
# headless run scores objectives, the clock and every latch exactly as the game does.
var mission: MissionState
# The pre-mission phase (#46): the shared PreMissionPhase with this session as its host, whether the
# phase is still open, and what the last Begin captured. A session lives as long as its board, so the
# bridge takes `staged` from here and keeps it across boards (MissionController._staged's twin).
var _phase: PreMissionPhase = null
var _deploying := false
var staged: PreMissionSnapshot = null

const PLAYER_GLYPHS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const ENEMY_GLYPHS := "abcdefghijklmnopqrstuvwxyz"

func _init(board: Dictionary) -> void:
	grid = board.grid
	units_root = board.units_root
	squad_manager = board.squad_manager
	turn_manager = board.turn_manager
	overlay_manager = board.overlay_manager
	terrain_states = board.get("terrain_states")
	board_heights = board.get("board_heights")
	gas_field = board.get("gas_field")
	scenario_data = board.get("scenario")
	reserve_root = board.get("reserve_root")
	zone_manager = board.get("zone_manager")
	mission = MissionState.new(zone_manager)
	if scenario_data != null:
		mission.apply_scenario(scenario_data)
	for unit in live_units():
		_register(unit)
	# The turn boundary's signal-driven halves (#898), heard in the order game.gd hears them.
	if not turn_manager.round_completed.is_connected(_on_round_completed):
		turn_manager.round_completed.connect(_on_round_completed)
	if not turn_manager.turn_started.is_connected(_on_turn_started):
		turn_manager.turn_started.connect(_on_turn_started)

func _register(unit: Unit) -> void:
	if _handle_by_unit.has(unit):
		return
	if unit.get_faction() == Team.Faction.ENEMY:
		_handle_by_unit[unit] = ENEMY_GLYPHS[_next_enemy] if _next_enemy < ENEMY_GLYPHS.length() else "?"
		_next_enemy += 1
	else:
		_handle_by_unit[unit] = PLAYER_GLYPHS[_next_player] if _next_player < PLAYER_GLYPHS.length() else "?"
		_next_player += 1
	if not unit.unit_died.is_connected(_on_unit_died):
		unit.unit_died.connect(_on_unit_died)
	if not unit.went_downed.is_connected(_on_unit_downed):
		unit.went_downed.connect(_on_unit_downed)

func _on_unit_died(unit: Unit) -> void:
	mission.note_unit_died(unit)   # FIRST, as game._on_unit_died: the mission may be protecting this one
	squad_manager.handle_unit_death(unit)

func _on_unit_downed(unit: Unit) -> void:
	# The down fires INSIDE the attack/counter pass (take_damage -> _go_downed). Defer the
	# squad ejection until the pass settles, exactly like OrderExecutor.on_unit_downed, so we never
	# restructure squads mid-resolution.
	if not _downed_pending.has(unit):
		_downed_pending.append(unit)

func _process_downed_pending() -> void:
	# Twin of OrderExecutor._process_downed_pending: eject each survivor-but-downed unit into a solo
	# squad. Skip any that got finished off (KILLED) later in the same pass — death already
	# cleaned those up.
	for unit in _downed_pending:
		if not is_instance_valid(unit) or unit.is_queued_for_deletion():
			continue
		squad_manager.handle_unit_downed(unit)
	_downed_pending.clear()

# ---- queries ----

func live_units() -> Array[Unit]:
	var result: Array[Unit] = []
	for child in units_root.get_children():
		if child is Unit and not child.is_queued_for_deletion():
			result.append(child)
	return result

func handle_for(unit: Unit) -> String:
	return _handle_by_unit.get(unit, "?")

func unit_by_handle(h: String) -> Unit:
	for unit in live_units() + reserve_units():
		if _handle_by_unit.get(unit, "") == h:
			return unit
	return null

# The drawn roster still waiting off the board (#46) -- named so the driver can deploy them.
func reserve_units() -> Array[Unit]:
	var result: Array[Unit] = []
	if reserve_root == null:
		return result
	for child in reserve_root.get_children():
		if child is Unit and not child.is_queued_for_deletion():
			result.append(child)
	return result

func _board() -> BoardContext:
	return BoardContext.new(grid, live_units(), squad_manager, terrain_states, zone_manager, board_heights, gas_field)

func active_faction() -> Team.Faction:
	return turn_manager.active_faction()

func _faction_name(f: Team.Faction) -> String:
	return Team.Faction.keys()[f]

func _squad_id(squad: Squad) -> int:
	return squad_manager.squads.find(squad)

func terrain_at(cell: Vector2i) -> Dictionary:
	var data := grid.get_cell_tile_data(cell)
	if data == null:
		# A HOLE AND THE EDGE OF THE WORLD ARE DIFFERENT ANSWERS (#875). No ground INSIDE the
		# board's own rect is a chasm a shove flies over and a landing dies in; no ground outside
		# it is simply off the map. Asked through the board so the view cannot disagree with the
		# rules about where a hole is -- the same reason `walkable` below comes from is_walkable.
		var absent := "void" if _board().is_void_at(cell) else "offmap"
		return {"exists": false, "walkable": false, "cost": 0, "type": absent}
	var cost := 0
	if data.has_custom_data("move_cost"):
		cost = int(data.get_custom_data("move_cost"))
	var kind := GridUtils.get_terrain_kind_at_cell(grid, cell)
	var kind_name: String = Terrain.Kind.keys()[kind]
	# Walkability comes from the board, never from a second read of the tile (#109). This used to
	# re-derive it off `walkable` custom data alone, so a FROZEN water tile rendered as impassable
	# in board_view while queue_move happily pathed across it — the headless VIEW contradicting the
	# headless RULES, which is exactly the Law #2 failure the Play API exists to catch.
	return {"exists": true, "walkable": _board().is_walkable(cell), "cost": cost, "type": kind_name.to_lower()}

# ---- affordances: what may this unit do RIGHT NOW (#613) ----
#
# WHY THESE EXIST. Driving the bridge, a third to a half of every command came back refused --
# `move` 55%, `attack` 61% -- because the only way to find out where a unit could go was to guess a
# cell and be told no. The rendered board says where everything IS; it never said what is LEGAL.
#
# EACH ONE CALLS THE GATE IT IS ANSWERING FOR, and that is the whole design rather than an
# implementation note. A second reachability walk here would be a second answer to "can this unit
# stand there" (Law #4), and the way it fails is silent and exact: the API starts offering a cell
# queue_move refuses, which is the bug these exist to remove, reintroduced one layer up.
# tests/play/test_affordances.gd drives both sides and asserts they agree cell for cell.

func legal_moves(handle: String) -> Dictionary:
	var unit := unit_by_handle(handle)
	var gate := _controllable(unit, handle)
	if not gate.ok:
		return gate
	# THE set queue_move indexes -- not a copy of it. Both come back as Dictionaries keyed by cell
	# (which is why the gate spells it `.has(dest)`), so the keys ARE the answer.
	var range_info := RulesService.compute_move_range(unit, _board())
	var cells: Array[Vector2i] = []
	cells.assign(range_info.reachable.keys())
	# Reported separately rather than merged: these are reachable on foot and refused by cohesion,
	# and "your leader is too far" is a different fix from "that is too far to walk".
	var leashed: Array[Vector2i] = []
	leashed.assign(range_info.squad_unreachable.keys())
	return {"ok": true, "unit": handle, "from": unit.movement.cell, "cells": cells, "leashed": leashed}


func legal_targets(handle: String, attack_name := "") -> Dictionary:
	var unit := unit_by_handle(handle)
	var gate := _controllable(unit, handle)
	if not gate.ok:
		return gate
	if not unit.has_equipped_weapon():
		return {"ok": false, "error": "%s has no equipped weapon" % handle}
	var pick := _fire_pick(unit, handle, attack_name)
	if not pick.ok:
		return pick
	var origin := unit.get_projected_destination()
	var aiming: AttackData = pick.attack
	# Armed for the loop's declare(), whose stamp the whiff policy reads -- queue_attack's arming.
	unit.active_attack = aiming
	var board := _board()
	var out: Array[Dictionary] = []
	# The candidate set is the union over four facings -- what the red overlay draws -- and
	# can_hit_cell_from is what narrows it to the aim actually available. Both of queue_attack's
	# gates are applied here in its own order, so a cell offered can never be refused.
	for aim: Vector2i in Reach.get_all_attack_cells_from(unit, origin, aiming):
		if not Reach.can_hit_cell_from(unit, origin, aim, aiming, board):
			continue
		# Through Conduction, so a shock aim whose casualties arrive by the arc is OFFERED here and
		# ACCEPTED by queue_attack below -- the two gates are the same gate, stated twice. Whether
		# hitting nobody is a whiff is the game's own policy (aim_whiffs): a map-hitting aim never is.
		var victims := Conduction.sweep(unit, origin, aim, aiming, board).victims
		if SquadPlanValidator.aim_whiffs(AttackAction.declare(unit, origin, aim), not victims.is_empty()):
			continue
		var names: Array[String] = []
		for v: Unit in victims:
			names.append(handle_for(v))
		out.append({"cell": aim, "victims": names})
	unit.active_attack = null
	return {"ok": true, "unit": handle, "attack": _attack_label(aiming), "from": origin, "aims": out}


# The turn's own state, which the rendered board has never carried: whose turn it is, which squad
# holds the activation, what it has queued, and which squads are spent. 43 of the refusals were
# "another squad is already active" / "already acted" / "not the active faction" and 34 more were
# "no squad has queued orders" -- every one of them answerable from here, and from state that
# already exists. Nothing is stored; this is a read.
func status() -> Dictionary:
	var active: Squad = squad_manager.active_squad
	var acted: Array[int] = []
	var free: Array[int] = []
	for squad: Squad in squad_manager.squads:
		if squad.members.is_empty():
			continue
		if squad.members[0].get_faction() != turn_manager.active_faction():
			continue
		if squad.has_acted:
			acted.append(_squad_id(squad))
		else:
			free.append(_squad_id(squad))
	return {
		"faction": _faction_name(active_faction()),
		"active_squad": -1 if active == null else _squad_id(active),
		"queued": 0 if active == null else active.action_queue.size(),
		"acted": acted,
		"free": free,
		"pre_mission": _deploying,
	}


# ---- the pre-mission phase (#46) ----
#
# The SAME PreMissionPhase the game runs, with this session as its host: the six calls below are
# the headless twins of game.gd's spawn_reserve_unit / deploy_unit / undeploy_unit / is_deployed /
# can_spawn_at / get_unit_at_cell. Placement is per host by design (PreMission.gd); every RULE is the
# phase's, and tests/flow/test_pre_mission_two_hosts.gd holds the two hosts to one answer.

func spawn_reserve_unit(data: UnitData) -> Unit:
	var unit := UnitFactory.create_unit(data, null, Vector2i.ZERO)
	reserve_root.add_child(unit)
	_register(unit)
	return unit

# game.deploy_unit's steps, over this board.
func deploy_unit(unit: Unit, cell: Vector2i) -> bool:
	if unit == null or reserve_root == null or unit.get_parent() != reserve_root:
		push_error("deploy_unit: not a reserve unit")
		return false
	if not can_spawn_at(cell):
		return false
	reserve_root.remove_child(unit)
	units_root.add_child(unit)
	unit.movement.set_grid(grid)
	unit.movement.set_cell(cell)   # after set_grid: set_cell push_errors without one
	unit.movement.set_heights(board_heights)
	squad_manager.create_squad(unit)
	return true

# game.undeploy_unit's steps: release (no re-solo) before the reparent, then drop the grid.
func undeploy_unit(unit: Unit) -> void:
	if not is_deployed(unit):
		push_error("undeploy_unit: not a deployed unit")
		return
	squad_manager.release(unit)
	units_root.remove_child(unit)
	reserve_root.add_child(unit)
	unit.movement.set_grid(null)

func is_deployed(unit: Unit) -> bool:
	return unit != null and unit.get_parent() == units_root

func can_spawn_at(cell: Vector2i) -> bool:
	return RulesService.can_spawn_at(_board(), cell)

func get_unit_at_cell(cell: Vector2i) -> Unit:
	return _board().unit_at_cell(cell)

func is_deploying() -> bool:
	return _deploying

# The phase every load of a mission opens on (the bridge's `load` is the fresh-start door). Draws the
# roster the scenario names; returns how many stood up, and the phase stays open only if someone did
# -- a phase nobody stands in could never be committed, which is the game's own rule.
#
# `staged` is a buffer to replay instead of the authored walk (#763), MissionController.deploy_roster's
# shape: the caller decides which buffer, through PreMissionPhase.replay_for / kept_by_restart.
func start_pre_mission(staged_buffer: PreMissionSnapshot = null) -> int:
	if scenario_data == null or scenario_data.roster == "":
		return 0
	var scenario := scenario_data
	_phase = PreMissionPhase.new(self, zone_manager, squad_manager,
			func() -> int: return scenario.deployment_cap)
	var drawn := _phase.draw(scenario.roster, staged_buffer)
	_deploying = drawn > 0
	return drawn

func deployment_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if _phase != null:
		cells = _phase.open_deployment_cells()
	return cells

func deployed_count() -> int:
	return _phase.deployed_count() if _phase != null else 0

# The roster in ENTRY order, MissionController.roster_units()'s twin.
func roster_units() -> Array[Unit]:
	var units: Array[Unit] = []
	if _phase != null:
		units = _phase.units
	return units

# Why one more cannot be placed, or "" -- the phase's own sentence.
func deploy_block_reason() -> String:
	return _phase.deploy_block_reason() if _phase != null else ""

func deployment_cap() -> int:
	return _phase.cap() if _phase != null else PreMission.NO_CAP

func deploy(handle: String, cell: Vector2i) -> Dictionary:
	var gate := _phase_gate()
	if not gate.ok:
		return gate
	var unit := unit_by_handle(handle)
	if unit == null:
		return {"ok": false, "error": "no unit '%s'" % handle}
	if not unit.drawn_from_roster:
		return {"ok": false, "error": "%s is not part of the roster" % handle}
	if is_deployed(unit):
		return {"ok": false, "error": "%s is already deployed" % handle}
	var reason := _phase.deploy_block_reason()
	if reason != "":
		return {"ok": false, "error": reason}
	if not _phase.open_deployment_cells().has(cell):
		return {"ok": false, "error": "%s is not an open deployment cell" % str(cell)}
	if not deploy_unit(unit, cell):
		return {"ok": false, "error": "%s cannot be placed at %s" % [handle, str(cell)]}
	return {"ok": true, "summary": "%s deployed to %s" % [handle, str(cell)]}

func undeploy(handle: String) -> Dictionary:
	var gate := _phase_gate()
	if not gate.ok:
		return gate
	var unit := unit_by_handle(handle)
	if unit == null:
		return {"ok": false, "error": "no unit '%s'" % handle}
	if not unit.drawn_from_roster:
		return {"ok": false, "error": "%s is not part of the roster" % handle}
	if not is_deployed(unit):
		return {"ok": false, "error": "%s is already in reserve" % handle}
	undeploy_unit(unit)
	return {"ok": true, "summary": "%s back to the reserve" % handle}

func reposition(handle: String, cell: Vector2i) -> Dictionary:
	var gate := _phase_gate()
	if not gate.ok:
		return gate
	var unit := unit_by_handle(handle)
	if unit == null:
		return {"ok": false, "error": "no unit '%s'" % handle}
	if not is_deployed(unit):
		return {"ok": false, "error": "%s is in reserve -- deploy it instead" % handle}
	if not _phase.reposition_cells(unit).has(cell):
		return {"ok": false, "error": "%s cannot move to %s" % [handle, str(cell)]}
	_phase.reposition(unit, cell)
	return {"ok": true, "summary": "%s moved to %s" % [handle, str(cell)]}

# The phase's one exit, refused in the game's own words. The snapshot is the commit's capture (#763),
# held for slice 3's restart.
func begin() -> Dictionary:
	var gate := _phase_gate()
	if not gate.ok:
		return gate
	var refusal := _phase.commit_block_reason()
	if refusal != "":
		return {"ok": false, "error": refusal}
	staged = _phase.capture(scenario_data.resource_path if scenario_data != null else "")
	_deploying = false
	return {"ok": true, "summary": "mission begun with %d deployed" % _phase.deployed_count()}

# ---- the loadout screen's writes (#46 slice 2a) ----
# Gear, jobs and mods, each through the door the screen calls: Loadout.move, Loadout.set_job, and the
# fitting card's own library plus WeaponInstance.fit_block_reason. Any roster unit, deployed or in
# reserve, since the screen's cards cover both; STASH names the phase's stash at either end of a give.

const STASH := "stash"

func stash() -> Array[Item]:
	var items: Array[Item] = []
	if _phase != null:
		items = _phase.loadout.stash
	return items

# The jobs this unit's picker would list -- the Loadout's answer, and none outside the phase.
func offered_jobs_for(unit: Unit) -> Array[String]:
	var ids: Array[String] = []
	if _deploying:
		ids = _phase.loadout.offered_jobs_for(unit)
	return ids

# The mods the fitting card's library would offer this weapon, keyed as the card keys them.
func offered_mods_for(weapon: WeaponInstance) -> Dictionary:
	if not _deploying or weapon == null or weapon.template == null:
		return {}
	return WeaponModCatalog.offerable_for(weapon.template.weapon_type, _phase.loadout.available_mods)

# A fitted mod's name as the library keys it -- found by PATH, offerable_for's own match, since a
# repaired load hands back a copy (#608). `mods` is WeaponModCatalog.get_mods(), passed in because
# that call rescans the folder. A mod from outside the catalogue falls back to its own name.
func mod_key(mod: WeaponModData, mods: Dictionary) -> String:
	for key in mods:
		var known: WeaponModData = mods[key]
		if mod.resource_path != "" and known.resource_path == mod.resource_path:
			return str(key)
	return mod.display_name if mod.display_name != "" else mod.id

func give(from_name: String, slot: int, to_name: String) -> Dictionary:
	var gate := _phase_gate()
	if not gate.ok:
		return gate
	var source := _gear_holder(from_name)
	if not source.ok:
		return source
	var target := _gear_holder(to_name)
	if not target.ok:
		return target
	var from_unit: Unit = source.unit
	var to_unit: Unit = target.unit
	var item := _gear_at(from_unit, slot)
	var refusal := _phase.loadout.move(item, from_unit, to_unit)
	if refusal != "":
		return {"ok": false, "error": refusal}
	return {"ok": true, "summary": "%s: %s -> %s" % [item.shown_name(), from_name, to_name]}

func set_job(handle: String, job_id: String) -> Dictionary:
	var gate := _phase_gate()
	if not gate.ok:
		return gate
	var who := _gear_holder(handle)
	if not who.ok:
		return who
	var unit: Unit = who.unit
	if unit == null:
		return {"ok": false, "error": "the stash holds no job"}
	var refusal := _phase.loadout.set_job(unit, job_id)
	if refusal != "":
		return {"ok": false, "error": refusal}
	return {"ok": true, "summary": "%s job: %s" % [handle, job_id if job_id != "" else "none"]}

# `space` is 1-based, as every fit_block_reason sentence counts them.
func fit(holder_name: String, slot: int, mod_name: String, space: int) -> Dictionary:
	var gate := _phase_gate()
	if not gate.ok:
		return gate
	var held := _weapon_at(holder_name, slot)
	if not held.ok:
		return held
	var weapon: WeaponInstance = held.weapon
	var offered := offered_mods_for(weapon)
	if not offered.has(mod_name):
		return {"ok": false, "error": "this mission offers no mod '%s' for %s" % [mod_name, weapon.shown_name()]}
	var mod: WeaponModData = offered[mod_name]
	var refusal := weapon.fit_block_reason(space - 1, mod)
	if refusal != "":
		return {"ok": false, "error": refusal}
	weapon.fit(space - 1, mod)
	return {"ok": true, "summary": "%s fitted to %s, space %d" % [mod_name, weapon.shown_name(), space]}

# Coming off is never refused, as on the card: the library is not depleted by a fit.
func unfit(holder_name: String, slot: int, mod_name: String) -> Dictionary:
	var gate := _phase_gate()
	if not gate.ok:
		return gate
	var held := _weapon_at(holder_name, slot)
	if not held.ok:
		return held
	var weapon: WeaponInstance = held.weapon
	var mods := WeaponModCatalog.get_mods()
	for i in range(weapon.space_count()):
		for mod: WeaponModData in weapon.space(i):
			if mod_key(mod, mods) == mod_name:
				weapon.unfit(mod)
				return {"ok": true, "summary": "%s taken off %s" % [mod_name, weapon.shown_name()]}
	return {"ok": false, "error": "%s has no mod '%s' fitted" % [weapon.shown_name(), mod_name]}

# ---- the inspect dock (#46 slice 2b) ----
# Its six verbs, in EITHER phase, through GearVerbs -- the rule the dock's buttons and the replay
# viewer ask. Who may use the dock is game.can_control's rule (RulesService.command_block_reason); a
# reserve unit is refused because the dock is reached from the board. A change re-resolves the active
# squad, the twin of game.gd's loadout_changed wire: Equip swaps which weapon a queued attack fires with.
func gear(handle: String, verb_name: String, slot: int) -> Dictionary:
	var verb := GearVerbs.from_name(verb_name)
	if verb == -1:
		return {"ok": false, "error": "no gear verb '%s'" % verb_name}
	var unit := unit_by_handle(handle)
	if unit == null:
		return {"ok": false, "error": "no unit '%s'" % handle}
	if not is_deployed(unit):
		return {"ok": false, "error": "%s is in reserve -- the dock is reached from the board" % handle}
	var reason := RulesService.command_block_reason(unit, turn_manager.active_faction())
	if reason != "":
		return {"ok": false, "error": reason}
	var refusal := GearVerbs.perform(unit, verb as GearVerbs.Verb, slot)
	if refusal != "":
		return {"ok": false, "error": refusal}
	var squad := squad_manager.active_squad
	if squad != null:
		squad_manager.validate_squad_plan(squad, squad_manager.resolve_plan(squad, _board()))
	return {"ok": true, "summary": "%s: %s" % [handle, verb_name]}

# STASH or a roster unit's handle -> {ok, unit}, the unit null for the stash. The screen's cards are
# the roster's, so an enemy or an authored unit has no gear to give.
func _gear_holder(holder_name: String) -> Dictionary:
	if holder_name == STASH:
		return {"ok": true, "unit": null}
	var unit := unit_by_handle(holder_name)
	if unit == null:
		return {"ok": false, "error": "no unit '%s'" % holder_name}
	if not unit.drawn_from_roster:
		return {"ok": false, "error": "%s is not part of the roster" % holder_name}
	return {"ok": true, "unit": unit}

# What sits at that slot of a unit's inventory or the stash, or null -- which Loadout.move refuses in
# its own words.
func _gear_at(holder: Unit, slot: int) -> Item:
	var items: Array[Item] = holder.inventory if holder != null else _phase.loadout.stash
	if slot < 0 or slot >= items.size():
		return null
	return items[slot]

func _weapon_at(holder_name: String, slot: int) -> Dictionary:
	var who := _gear_holder(holder_name)
	if not who.ok:
		return who
	var weapon := _gear_at(who.unit, slot) as WeaponInstance
	if weapon == null:
		return {"ok": false, "error": "%s slot %d holds no weapon" % [holder_name, slot]}
	return {"ok": true, "weapon": weapon}

func _phase_gate() -> Dictionary:
	if not _deploying:
		return {"ok": false, "error": "the pre-mission phase is not open"}
	return {"ok": true}

# Every battle verb refuses while the phase is open: the mission has not started.
func _battle_gate() -> Dictionary:
	if _deploying:
		return {"ok": false, "error": "the mission has not begun -- deploy, then begin"}
	return {"ok": true}


# ---- commands (mutating) — all flow through the real SquadManager (Law #3) ----

func _controllable(unit: Unit, handle: String) -> Dictionary:
	var phase := _battle_gate()
	if not phase.ok:
		return phase
	if unit == null:
		return {"ok": false, "error": "no unit '%s'" % handle}
	if not is_deployed(unit):
		return {"ok": false, "error": "%s is in reserve" % handle}
	if unit.get_faction() != turn_manager.active_faction():
		return {"ok": false, "error": "%s is not on the active faction (%s)" % [handle, _faction_name(active_faction())]}
	if unit.squad.has_acted:
		return {"ok": false, "error": "%s's squad has already acted this turn" % handle}
	# One squad plans at a time -- the menu's own rule, which the order chokepoint leaves to its
	# callers (SquadManager.try_queue_action). Without it a second squad silently took the activation.
	if squad_manager.is_another_squad_active(unit.squad):
		return {"ok": false, "error": "squad %d has orders queued -- execute or cancel them before ordering %s" % [
			_squad_id(squad_manager.active_squad), handle]}
	return {"ok": true}

# WHICH attack an aim fires (#615): the one NAMED, else the default -- the menu's pick, made
# headlessly. An attack that cannot fire is refused in the menu's own words, so a refusal and a
# greyed row cannot disagree (#166).
func _fire_pick(unit: Unit, handle: String, attack_name: String) -> Dictionary:
	var attack: AttackData = unit.get_default_attack()
	if attack_name != "":
		attack = unit.fire_attack_named(attack_name)
		if attack == null:
			return {"ok": false, "error": "%s has no attack named '%s' (can fire: %s)" % [
				handle, attack_name, _names_of(unit.get_selectable_attacks())]}
	elif attack == null:
		# The ring offers no row here either (#1215); a null pick would resolve as bare fists.
		return {"ok": false, "error": "%s has nothing it can fire" % handle}
	var reason := unit.attack_block_reason(attack)
	if reason != "":
		return {"ok": false, "error": "%s can't fire %s: %s" % [handle, _attack_label(attack), reason]}
	return {"ok": true, "attack": attack}

static func _attack_label(attack: AttackData) -> String:
	return attack.display_name if attack != null else "(unarmed)"

static func _names_of(attacks: Array[AttackData]) -> String:
	var names: Array[String] = []
	for attack: AttackData in attacks:
		names.append(_attack_label(attack))
	return ", ".join(names) if not names.is_empty() else "nothing"

func queue_move(handle: String, dest: Vector2i) -> Dictionary:
	var unit := unit_by_handle(handle)
	var gate := _controllable(unit, handle)
	if not gate.ok:
		return gate
	if dest == unit.movement.cell:
		return {"ok": false, "error": "%s is already at %s" % [handle, str(dest)]}
	var range_info := RulesService.compute_move_range(unit, _board())
	if not range_info.reachable.has(dest):
		var hint := " (reachable but outside leader range)" if range_info.squad_unreachable.has(dest) else ""
		return {"ok": false, "error": "%s cannot reach %s%s" % [handle, str(dest), hint]}
	var path := RulesService.reconstruct_path(range_info.came_from, unit.movement.cell, dest)
	var move := MoveAction.new()
	move.init(unit, path, GridUtils.get_terrain_icon_at_cell(grid, dest))
	var refusal := squad_manager.try_queue_action(unit.squad, move)
	if refusal != "":
		return {"ok": false, "error": "%s can't move to %s: %s" % [handle, str(dest), refusal]}
	return {"ok": true, "summary": "%s -> move %s" % [handle, str(dest)], "valid": move.is_valid}

func queue_attack(handle: String, aim: Vector2i, attack_name := "") -> Dictionary:
	var unit := unit_by_handle(handle)
	var gate := _controllable(unit, handle)
	if not gate.ok:
		return gate
	if not unit.has_equipped_weapon():
		return {"ok": false, "error": "%s has no equipped weapon" % handle}
	var pick := _fire_pick(unit, handle, attack_name)
	if not pick.ok:
		return pick
	# The pick lives for this one aim, as the menu arms it and exit_current_mode clears it: left
	# standing it would be the next unnamed aim's, and a rune's counter (RuneData.counter_attack).
	unit.active_attack = pick.attack
	var result := _queue_armed_attack(unit, handle, aim)
	unit.active_attack = null
	return result

func _queue_armed_attack(unit: Unit, handle: String, aim: Vector2i) -> Dictionary:
	var origin := unit.get_projected_destination()
	# Aiming: the live pick IS the question, and it is exactly what declare() stamps below (#102).
	var aiming := unit.get_fired_attack()
	# The board carries the elevations for the vertical-tolerance half of the gate (#258),
	# mirroring the player's click exactly.
	if not Reach.can_hit_cell_from(unit, origin, aim, aiming, _board()):
		return {"ok": false, "error": "%s cannot hit %s from %s" % [handle, str(aim), str(origin)]}
	# The current is reach here too, matching legal_targets and the game's own queue gate, and the
	# whiff is the game's own policy: a map-hitting aim at nobody still lands on the ground (#47).
	# declare() stamps fired_attack (#78) -- Play aims fire what the unit would (rune carvings
	# included), same as the player's click and the AI.
	var order := AttackAction.declare(unit, origin, aim)
	var victims := Conduction.sweep(unit, origin, aim, aiming, _board()).victims
	if SquadPlanValidator.aim_whiffs(order, not victims.is_empty()):
		return {"ok": false, "error": "no valid targets at %s" % str(aim)}
	# Store ONE aim order (target=null); resolve_plan derives the volley/victims at resolve time
	# (#15), mirroring game.gd. Pre-expanding a volley here made resolve_plan re-expand each member
	# -> N^2 hits for AoE weapons. `victims` above is used only to validate + describe the aim.
	var refusal := squad_manager.try_queue_action(unit.squad, order)
	if refusal != "":
		return {"ok": false, "error": "%s can't attack %s: %s" % [handle, str(aim), refusal]}
	var names: Array[String] = []
	for v in victims:
		names.append(handle_for(v))
	var hits: String = ", ".join(names) if not names.is_empty() else "nobody"
	return {"ok": true, "summary": "%s -> attack %s with %s (hits %s)" % [handle, str(aim), _attack_label(aiming), hits]}

func cancel(handle: String) -> Dictionary:
	var unit := unit_by_handle(handle)
	if unit == null:
		return {"ok": false, "error": "no unit '%s'" % handle}
	squad_manager.remove_actions_for_unit(unit)
	return {"ok": true, "summary": "cancelled %s's orders" % handle}

# ---- rescue + squad management (drives the same SquadManager / RescueAction as the player) ----

func rescue(rescuer_handle: String, target_handle: String) -> Dictionary:
	var rescuer := unit_by_handle(rescuer_handle)
	var gate := _controllable(rescuer, rescuer_handle)
	if not gate.ok:
		return gate
	var target := unit_by_handle(target_handle)
	if target == null:
		return {"ok": false, "error": "no unit '%s'" % target_handle}
	if not RulesService.adjacent_downed_allies(rescuer, _board()).has(target):
		return {"ok": false, "error": "%s is not an adjacent downed ally of %s" % [target_handle, rescuer_handle]}
	# The headless API has no tile pick either, so it takes the first landing like the AI (#116) --
	# the deterministic answer the rule gave before the player was handed the choice.
	var action := RescueAction.new()
	action.init(rescuer, target, RulesService.rescue_landings(rescuer, target, _board())[0])
	var refusal := squad_manager.try_queue_action(rescuer.squad, action)
	if refusal != "":
		return {"ok": false, "error": "%s can't rescue %s: %s" % [rescuer_handle, target_handle, refusal]}
	return {"ok": true, "summary": "%s -> rescue %s" % [rescuer_handle, target_handle]}

# Guard (#414): become a nearby ally's bodyguard — the same GuardAction the menu queues, gated on the
# same RulesService.guard_candidates query the menu's row is built from. Its own verb rather than a
# queue_simple_action pass-through, for the reason rescue has one: it takes a real unit.
func guard(handle: String, ward_handle: String) -> Dictionary:
	var unit := unit_by_handle(handle)
	var gate := _controllable(unit, handle)
	if not gate.ok:
		return gate
	var ward := unit_by_handle(ward_handle)
	if ward == null:
		return {"ok": false, "error": "no unit '%s'" % ward_handle}
	if not RulesService.guard_candidates(unit, _board()).has(ward):
		return {"ok": false, "error": "%s is not an ally within %s's Guard range" % [ward_handle, handle]}
	var action := GuardAction.new()
	action.init(unit, ward)
	var refusal := squad_manager.try_queue_action(unit.squad, action)
	if refusal != "":
		return {"ok": false, "error": "%s can't guard %s: %s" % [handle, ward_handle, refusal]}
	return {"ok": true, "summary": "%s -> guard %s" % [handle, ward_handle]}

# Overwatch (#413): aim an attack and hold fire — the same OverwatchAction the menu queues, picking
# from the list the menu's Overwatch rows read (#590 split it from the fire view, so the main is never
# a watch unless it is watch-only), named or else the first -- normally the only one (#615).
func overwatch(handle: String, aim: Vector2i, attack_name := "") -> Dictionary:
	var unit := unit_by_handle(handle)
	var gate := _controllable(unit, handle)
	if not gate.ok:
		return gate
	var watches := unit.overwatch_attacks()
	if watches.is_empty():
		return {"ok": false, "error": "%s has nothing to stand watch with" % handle}
	var aiming: AttackData = watches[0]
	if attack_name != "":
		aiming = unit.watch_attack_named(attack_name)
		if aiming == null:
			return {"ok": false, "error": "%s has no watch named '%s' (can watch with: %s)" % [
				handle, attack_name, _names_of(watches)]}
	var origin := unit.get_projected_destination()
	# The player's click gate, which is now one predicate rather than this pair (#756): a directional
	# aim needs a facing whose spread survives the terrain, a point aim needs the cell itself. The
	# dud-aim refusal that stood below is inside it -- a facing watching no cells is not aimable.
	if not Reach.can_aim_at(unit, origin, aim, aiming, _board()):
		return {"ok": false, "error": "%s cannot aim at %s from %s" % [handle, str(aim), str(origin)]}
	var action := OverwatchAction.new()
	action.init(unit, aim, aiming)
	# Whether this watch can fire at all is the order's own gate (OverwatchAction.actor_block_reason),
	# answered by the chokepoint in the menu's words (#662).
	var refusal := squad_manager.try_queue_action(unit.squad, action)
	if refusal != "":
		return {"ok": false, "error": "%s can't watch with %s: %s" % [handle, aiming.display_name, refusal]}
	return {"ok": true, "summary": "%s -> overwatch %s with %s" % [handle, str(aim), aiming.display_name]}

# Reload: self-targeted weapon rearm (a main action, #73 as Spring Load, generalized #84) — the
# same ReloadAction the menu queues, driving the generic Unit.can_reload_weapon()/reload_weapon()
# seam. One command for every family: a Springspear's spring, a Carbine's magazine, a Spitter's
# tank injection -- which is why the refusal is READ rather than restated here (#97): only the
# family knows whether it is full or simply has no vial to draw on.
func reload(handle: String) -> Dictionary:
	var unit := unit_by_handle(handle)
	var gate := _controllable(unit, handle)
	if not gate.ok:
		return gate
	var action := ReloadAction.new()
	action.init(unit)
	var refusal := squad_manager.try_queue_action(unit.squad, action)
	if refusal != "":
		return {"ok": false, "error": "%s can't reload: %s" % [handle, refusal]}
	return {"ok": true, "summary": "%s -> %s" % [handle, unit.reload_label().to_lower()]}

# Rev: self-targeted Chainsword rev-up (a main action, #84) — the same RevAction the menu
# queues, driving the generic Unit.can_rev_weapon()/rev_weapon() seam. While revved, this
# unit's attacks ignore the target's DEF (PlanResolver mitigation stage).
func rev(handle: String) -> Dictionary:
	var unit := unit_by_handle(handle)
	var gate := _controllable(unit, handle)
	if not gate.ok:
		return gate
	var action := RevAction.new()
	action.init(unit)
	var refusal := squad_manager.try_queue_action(unit.squad, action)
	if refusal != "":
		return {"ok": false, "error": "%s can't rev: %s" % [handle, refusal]}
	return {"ok": true, "summary": "%s -> rev" % handle}

# Burrow: the Drill's self-targeted entrenchment (a main action, #84) — the same BurrowAction the
# Weapon Action menu queues. Its consequence is TERRAIN: a COVER tile deposited on the burrower's
# cell by the resolver's plan (see execute's cell-effect step), granting flat DEF to whoever
# stands there.
func burrow(handle: String) -> Dictionary:
	var unit := unit_by_handle(handle)
	var gate := _controllable(unit, handle)
	if not gate.ok:
		return gate
	var action := BurrowAction.new()
	action.init(unit)
	var refusal := squad_manager.try_queue_action(unit.squad, action)
	if refusal != "":
		return {"ok": false, "error": "%s can't burrow: %s" % [handle, refusal]}
	return {"ok": true, "summary": "%s -> burrow" % handle}

# member joins leader's squad — one join_squad call covers both "squad up" (leader was solo) and
# "join squad", with the player's own eligibility: same faction, within the leader's LDR range,
# nothing has committed to acting yet.
func join(member_handle: String, leader_handle: String) -> Dictionary:
	var member := unit_by_handle(member_handle)
	var leader := unit_by_handle(leader_handle)
	if member == null:
		return {"ok": false, "error": "no unit '%s'" % member_handle}
	if not is_deployed(member):
		return {"ok": false, "error": "%s is in reserve" % member_handle}
	if leader == null:
		return {"ok": false, "error": "no unit '%s'" % leader_handle}
	if not is_deployed(leader):
		return {"ok": false, "error": "%s is in reserve" % leader_handle}
	if member == leader:
		return {"ok": false, "error": "a unit can't join itself"}
	if member.squad == leader.squad:
		return {"ok": false, "error": "%s is already in %s's squad" % [member_handle, leader_handle]}
	if leader.get_faction() != active_faction():
		return {"ok": false, "error": "can only reorganize your own (%s) squads this turn" % _faction_name(active_faction())}
	if member.get_faction() != leader.get_faction():
		return {"ok": false, "error": "different factions can't squad up"}
	var gate := _squad_change_gate(member.squad, leader.squad)
	if not gate.ok:
		return gate
	if member.has_any_actions():
		return {"ok": false, "error": "%s has queued orders — cancel them before squadding up" % member_handle}
	var reach := leader.squad.get_max_squad_range()
	if not SquadCohesion.in_range(leader.squad, leader.movement.cell, member, member.movement.cell, _board()):
		return {"ok": false, "error": "%s is outside %s's leader range (%d)" % [member_handle, leader_handle, reach]}
	squad_manager.join_squad(member, leader.squad)
	return {"ok": true, "summary": "%s joined %s's squad" % [member_handle, leader_handle]}

func leave(handle: String) -> Dictionary:
	var unit := unit_by_handle(handle)
	if unit == null:
		return {"ok": false, "error": "no unit '%s'" % handle}
	if not is_deployed(unit):
		return {"ok": false, "error": "%s is in reserve" % handle}
	if not unit.has_squad():
		return {"ok": false, "error": "%s is already solo" % handle}
	if unit.get_faction() != active_faction():
		return {"ok": false, "error": "can only reorganize your own squads this turn"}
	var gate := _squad_change_gate(unit.squad, unit.squad)
	if not gate.ok:
		return gate
	squad_manager.leave_squad(unit)
	return {"ok": true, "summary": "%s left its squad (now solo)" % handle}

func disband(handle: String) -> Dictionary:
	var unit := unit_by_handle(handle)
	if unit == null:
		return {"ok": false, "error": "no unit '%s'" % handle}
	if not is_deployed(unit):
		return {"ok": false, "error": "%s is in reserve" % handle}
	if not unit.has_squad():
		return {"ok": false, "error": "%s isn't in a multi-unit squad" % handle}
	if not unit.is_leader():
		return {"ok": false, "error": "only the leader can disband (%s isn't its squad's leader)" % handle}
	if unit.get_faction() != active_faction():
		return {"ok": false, "error": "can only reorganize your own squads this turn"}
	var gate := _squad_change_gate(unit.squad, unit.squad)
	if not gate.ok:
		return gate
	squad_manager.disband_squad(unit.squad)
	return {"ok": true, "summary": "%s disbanded its squad" % handle}

# Once any squad has committed to acting this turn, membership is frozen (mirrors the player UI,
# which only offers squad options when no squad is active and neither squad has acted).
func _squad_change_gate(squad_a: Squad, squad_b: Squad) -> Dictionary:
	if squad_manager.active_squad != null:
		return {"ok": false, "error": "a squad is already acting this turn — squad changes are locked"}
	if squad_a.has_acted or squad_b.has_acted:
		return {"ok": false, "error": "a squad that has acted can't change this turn"}
	return {"ok": true}

# ---- preview (pure look-ahead) ----

func preview() -> Dictionary:
	var phase := _battle_gate()
	if not phase.ok:
		return phase
	var squad := squad_manager.active_squad
	if squad == null:
		return {"ok": false, "error": "no squad has queued orders"}
	# Resolve BEFORE validating, and hand the plan over (2026-08-02): "does this aim still hit
	# anyone" is the resolve's answer, and a validate with no plan leaves attacks unjudged. Also
	# collapses the double resolve this function used to do.
	var plan := squad_manager.resolve_plan(squad, _board())
	squad_manager.validate_squad_plan(squad, plan)
	if squad_manager.squad_has_invalid_actions(squad):
		var errs: Array[String] = []
		for action in squad.action_queue:
			if not action.is_valid:
				errs.append("%s: %s" % [handle_for(action.actor), ", ".join(action.validation_errors)])
		return {"ok": false, "error": "plan has invalid actions", "invalid": errs}
	return {"ok": true, "plan": _describe_plan(squad, plan)}

func _describe_plan(squad: Squad, plan: ResolvedPlan) -> Dictionary:
	var moves: Array = []
	for action in squad.action_queue:
		if action.action_type == BaseAction.ActionType.MOVE and not action.is_hold_position:
			moves.append({"actor": handle_for(action.actor), "dest": action.get_destination()})
	var attacks: Array = []
	for atk in plan.attacks:
		attacks.append(_describe_attack(atk))
	var counters: Array = []
	for ctr in plan.counters:
		counters.append(_describe_attack(ctr))
	# Side-channel tail generically, in registry order (BaseAction.SIDE_CHANNEL_ORDER) — a
	# newly registered type appears here with no per-type mirror to maintain.
	var side_actions: Array = []
	for type in BaseAction.SIDE_CHANNEL_ORDER:
		for action in squad.action_queue:
			if action.action_type != type:
				continue
			var entry := {
				"actor": handle_for(action.actor),
				"type": action.get_action_name(),
				"description": action.get_description(),
			}
			var target: Variant = action.get("target")
			if target is Unit:
				entry["target"] = handle_for(target)
			side_actions.append(entry)
	# What the end of the turn will do to this squad on the tiles it stops on (#419) — the headless
	# twin of the panel's END OF TURN section.
	var tile_hits: Array = []
	for hit in plan.tile_hits:
		tile_hits.append({"actor": handle_for(hit.actor), "description": hit.get_description()})
	# Who the pass's own terrain drops into the water (#922), in the order they go under.
	var sinks: Array = []
	for sink in plan.sinks:
		var lethality: String = ResolvedOutcome.Lethality.keys()[sink.resolved.lethality]
		sinks.append({"actor": handle_for(sink.actor), "description": sink.get_description(),
				"lethality": lethality})
	return {"moves": moves, "attacks": attacks, "counters": counters,
			"side_actions": side_actions, "tile_hits": tile_hits, "sinks": sinks}

func _describe_attack(atk: AttackAction) -> Dictionary:
	var r := atk.resolved
	var dmg := r.damage if r != null else 0
	var hp_after := r.target_hp_after if r != null else -1
	var lethality := r.lethality if r != null else ResolvedOutcome.Lethality.NONE
	var skipped := r.skipped if r != null else false
	return {
		"actor": handle_for(atk.actor),
		"target": handle_for(atk.target),
		"attack": _attack_label(atk.fired_attack),   # the stamp, read back -- what the pick reached (#615)
		"dmg": dmg,
		"hp_after": hp_after,
		"lethality": lethality,   # NONE / DOWNED / KILLED (mirrors Unit.take_damage — Law #2)
		"skipped": skipped,       # counter-er was downed/killed earlier this pass -> no counter
	}

# ---- execute (headless application of the resolved plan) ----

func execute() -> Dictionary:
	var phase := _battle_gate()
	if not phase.ok:
		return phase
	var squad := squad_manager.active_squad
	if squad == null:
		return {"ok": false, "error": "no squad has queued orders"}
	var plan := squad_manager.resolve_plan(squad, _board())   # resolve BEFORE moving (projected positions)
	# ...and before validating, so the whiff clause has the plan to read (2026-08-02). Same order
	# the game uses in refresh_action_queue.
	squad_manager.validate_squad_plan(squad, plan)
	if squad_manager.squad_has_invalid_actions(squad):
		return {"ok": false, "error": "plan has invalid actions; fix before executing"}

	var events: Array[String] = []

	# 1) moves — teleport, the headless stand-in for tweened MoveAction.execute()
	for action in squad.action_queue.duplicate():
		if action.action_type == BaseAction.ActionType.MOVE and action.is_valid and not action.is_hold_position:
			var mv := action as MoveAction
			mv.actor.movement.set_cell(mv.get_destination())
			events.append("%s moves to %s" % [handle_for(mv.actor), str(mv.get_destination())])

	# 1b) the watches those walks walked into (#413), in trigger order — the twin of the move phase's
	# own interrupts. Only the MID-WALK ones: a shot a shove set off belongs after the volley that
	# threw somebody into it, and attack_playback() below is where it lands (#567). Headless there is
	# no walk to halt, so this is the event log's order and nothing else.
	for shot in plan.mid_walk_shots():
		_apply_attack(shot, events)

	# 2) attacks, then the terrain deposits they (and any Burrow order) produced, then 3) counters.
	# Same order as OrderExecutor.execute_orders — a tile deposited this pass is live for the counters that
	# follow it, and for every later pass.
	for atk in plan.attack_playback():
		_apply_attack(atk, events)
	_apply_cell_effects(plan.cell_effects, events)
	# ...and whoever the melt took the floor from goes under (#922), before any counter -- MIRRORS
	# OrderExecutor.execute_orders. SinkAction.execute is synchronous pure playback, so the real one runs.
	_apply_sinks(plan.sinks_at(SinkAction.Moment.DEPOSITS_LAND), events)
	for ctr in plan.counters:
		_apply_attack(ctr, events)

	# 4) side-channel tail in registry order (BaseAction.SIDE_CHANNEL_ORDER). These executes
	# are synchronous pure logic (no animation), so the REAL action runs — no per-type headless
	# mirror to maintain. The event logs the ORDER executed, matching game.gd (an execute whose
	# target was finished off mid-pass no-ops just as silently there).
	for type in BaseAction.SIDE_CHANNEL_ORDER:
		for action in squad.action_queue.duplicate():
			if action.action_type != type:
				continue
			# R7 liveness (#1005) -- MIRRORS execute_orders' own collection filter. Both twins read
			# the resolver's stamp rather than asking the board, which is what keeps them one
			# answer; the went_downed wire bug is what a hand-copied twin with its own opinion
			# costs (will-and-death.md).
			if action.resolved_actor_felled:
				continue
			action.execute()
			events.append(action.get_description())
			# ...then the shots THIS order set off (#1003) -- MIRRORS execute_orders' own interleave,
			# which is the third and last playback partition. An Overwatch armed onto a cell an
			# enemy already occupies fires here, after the counters, because that is where the
			# arming happens.
			for shot in plan.shots_fired_during(action):
				_apply_attack(shot, events)

	# 4b) the melts only a counter or a tail shot made (#922) -- the pass has settled.
	_apply_sinks(plan.sinks_at(SinkAction.Moment.PASS_END), events)

	# 5) eject units downed during the pass into solo squads (mirrors OrderExecutor._process_downed_pending)
	_process_downed_pending()

	# clear the squad's orders + mark acted (mirrors execute_orders' tail)
	if is_instance_valid(squad):
		for action in squad.action_queue.duplicate():
			squad_manager.remove_action(squad, action)
		squad_manager.set_has_acted(squad, true)

	# The pass has settled -- the same point OrderExecutor asks MissionController.check() (#96).
	var mission := mission_tag()
	if mission == "":
		return {"ok": true, "events": events}
	events.append(_mission_line(mission))
	return {"ok": true, "events": events, "mission": mission}

# The event line a finished mission logs, shared by execute() and end_turn so the dedupe matches.
func _mission_line(tag: String) -> String:
	return "MISSION %s" % tag

# Play the resolved terrain deposits into the live store (twin of OrderExecutor._apply_cell_effects, minus
# the redraw). Preview and execution consume the SAME ResolvedCellEffect objects (R3).
func _apply_cell_effects(cell_effects: Array[ResolvedCellEffect], events: Array[String]) -> void:
	if terrain_states == null:
		return
	for effect in cell_effects:
		terrain_states.apply(effect)
		for state in effect.states_added:
			events.append("%s becomes %s" % [str(effect.cell), Terrain.TileState.keys()[state]])
		if gas_field != null:
			gas_field.apply(effect)
		for kind: Gas.Kind in effect.gas_added:
			events.append("%s gains %s %s" % [str(effect.cell), Gas.Level.keys()[effect.gas_added[kind]], Gas.name_of(kind)])


func _apply_sinks(sinks: Array[SinkAction], events: Array[String]) -> void:
	for sink in sinks:
		sink.execute()
		events.append(sink.get_description())


func _apply_attack(atk: AttackAction, events: Array[String]) -> void:
	var actor := atk.actor
	var target := atk.target
	# The watch absorbs its one trigger (#413) — MIRRORS AttackAction.execute, including its
	# position: above every early-out, because a shot that whiffs or lands on an empty cell has
	# still been taken. Lead volley member only.
	if atk.is_watch_shot and not atk.is_secondary_hit and actor != null and is_instance_valid(actor):
		actor.spend_watch()
	# Post-fire economy, ABOVE the early-outs because that is where the twin puts it: execute()
	# gates only the UNIT consequence on a target, so a cell attack with no victim still spends what
	# firing costs. Returning first (as this did until #97) meant a headless cell shot rearmed itself
	# for free -- a real divergence the Carbine already had and nothing had asked about.
	if actor != null and is_instance_valid(actor):
		_spend_firing_costs(atk, actor)
	if actor == null or target == null:
		return
	if not is_instance_valid(actor) or not is_instance_valid(target):
		return
	if actor.is_queued_for_deletion() or target.is_queued_for_deletion():
		return
	var r := atk.resolved
	if r == null:
		return
	if r.skipped:
		return   # counter-er was downed/killed earlier this pass — no-op (matches the preview)
	# Guard (#414) — MIRRORS AttackAction.execute (the hand-copied twin): the resolver already moved
	# the victim to the blocker, so the only thing left for execution is spending the live ward.
	if atk.blocked_for != null:
		target.spend_guard()
	target.take_damage(r.damage, r.non_blow())   # routes through Unit.take_damage -> rung and limb
	for s in r.states_removed:
		target.remove_element_state(s)
	for s in r.states_added:
		target.add_element_state(s, r.state_turns.get(s, 0))
	var dropped := " (payload)" if atk.dropped_by != null else ""
	events.append("%s hits %s for %d%s%s" % [handle_for(actor), handle_for(target), r.damage, _lethality_tag(r.lethality), dropped])
	# Knockback (#84): the headless stand-in for AttackAction.execute()'s shove — the resolver
	# already picked the landing cell (stopped at any wall/unit/edge), so this just applies it.
	if r.knockback_applied and is_instance_valid(target):
		target.movement.set_cell(r.knockback_to)
		events.append("%s is shoved to %s" % [handle_for(target), str(r.knockback_to)])
	# The void door (#259) — MIRRORS AttackAction.execute exactly (the hand-copied twin): a
	# 0-damage take_damage cannot kill an ACTIVE unit, so removal is applied here or nowhere.
	# The ONE thing deliberately not copied is that twin's plummet (#431): a headless session has
	# no sprite to fall, and the rule outcome is identical either way.
	if r.removed and is_instance_valid(target):
		events.append("%s falls into the void" % handle_for(target))
		target.die()

	# The watch this blow broke (#810) — MIRRORS AttackAction.execute (the hand-copied twin). Here
	# rather than in _spend_firing_costs beside the other post-fire hooks, deliberately: those are
	# the ATTACKER's costs and are gated on is_secondary_hit, while this is the TARGET's watch and
	# every volley member has its own. MARKS, never lapses — Unit.cancel_watch says why.
	if r.cancels_watch and is_instance_valid(target):
		target.cancel_watch()

# Post-fire economy (#73/#84/#697/#97): mirrors AttackAction.execute()'s readiness/charge/vial/tank
# hooks — the headless executor bypasses that method entirely, so without this the play path
# diverges from the game (a fired Spring stays sprung; a Blowback keeps its charge; a cast draws on
# an attunement and never burns it; a supercharged spray never empties its tank). Lead volley member
# only. Counters DO reach here — they stamp main (CounterAttackAction.create_counter_volley), so a
# family whose main spends is charged for reactive fire too, while a Stab/Smash main with
# consumes_readiness = false is the no-op it always was.
#
# Every one of these is a SPEND the resolver already decided: it records a burn only when the
# attunement changed the damage, and a charge only when the pass still had one to give. There is
# nothing to judge here.
#
# A PAYLOAD spends nothing (#1058) -- MIRRORS AttackAction.execute: it was never fired, the hit that
# dropped it was.
func _spend_firing_costs(atk: AttackAction, actor: Unit) -> void:
	if atk.is_secondary_hit or atk.dropped_by != null:
		return
	var r := atk.resolved
	if atk.fired_attack is WeaponAttackData:
		var weapon := actor.get_equipped_weapon() as WeaponInstance
		if weapon != null:
			weapon.consume_readiness_for(atk.fired_attack as WeaponAttackData)
	if r == null:
		return
	if r.burned_vial != null:
		actor.attunement = null
	if r.charge_spent:
		var tank := actor.get_equipped_weapon() as WeaponInstance
		if tank != null:
			tank.spend_charge()

# ---- mission metadata & outcome (#96, #612) ----
# Read off the mission and the zone store the scorer reads (#46), never the scenario a second time.

func objectives() -> Array[MissionRules.Objective]:
	return mission.objectives.duplicate()

func zones() -> Dictionary:
	return zone_manager.to_dict() if zone_manager != null else {}

func round_limit() -> int:
	return mission.round_limit

func lose_conditions() -> Array[MissionRules.LoseCondition]:
	return mission.lose_conditions.duplicate()

# MissionController.check()'s rule half: the SAME MissionState the game holds, which latches the
# ending. Asked only where the board has settled -- the end of a pass, the end-of-turn burn, the
# hand-off -- as the game asks it. The game also raises a banner and locks the board; headless has no
# use for either, so this reports and nothing more.
func mission_outcome() -> MissionRules.Outcome:
	return mission.evaluate(_board())

# "VICTORY" / "DEFEAT", or "" while the mission is ongoing -- so callers can test one string
# instead of importing the enum.
func mission_tag() -> String:
	match mission_outcome():
		MissionRules.Outcome.VICTORY:
			return "VICTORY"
		MissionRules.Outcome.DEFEAT:
			return "DEFEAT"
		_:
			return ""

func _lethality_tag(lethality: ResolvedOutcome.Lethality) -> String:
	match lethality:
		ResolvedOutcome.Lethality.KILLED:
			return " (DIES)"
		ResolvedOutcome.Lethality.DOWNED:
			return " (DOWNED)"
		_:
			return ""

# ---- turn flow ----

func end_turn() -> Dictionary:
	var phase := _battle_gate()
	if not phase.ok:
		return phase
	# A finished mission does not hand off (mirrors game.end_turn's bail on mission_controller
	# .is_over()). Refusing rather than silently passing keeps a headless run from grinding out
	# turns on a board nobody can still win or lose.
	var already := mission_tag()
	if already != "":
		return {"ok": false, "error": "mission is over (%s)" % already, "mission": already}

	# The side that just played burns BEFORE it hands off, and a burn that ends the mission does not
	# hand off at all -- both mirror game.end_turn (#898).
	var log: Array[String] = _end_of_turn_tiles(turn_manager.active_faction())
	if mission_tag() != "":
		return _turn_result(log)

	# The hand-off runs the round tick and the turn-start ticks through the handlers wired in _init.
	turn_manager.end_turn(_board().present_factions())
	# Mirror the game's auto-skip: pass over factions with no commandable units (e.g. only
	# downed), guarding against an all-downed board where this would loop with nothing to stop on.
	# The board is re-read per pass, and the mission check mirrors game._on_turn_started's before it
	# skips -- the round that just completed may have run the mission clock out (#46).
	while mission_tag() == "":
		var board := _board()
		if board.faction_has_active_units(turn_manager.active_faction()) or not board.has_active_units():
			break
		turn_manager.end_turn(board.present_factions())
	squad_manager.reset_faction_actions(turn_manager.active_faction())

	# THE OPPONENT ACTS (#665). Until this existed, a headless "playthrough" was played against a
	# stationary board: end_turn advanced the faction and nothing else, so every enemy sat still
	# for the whole match while the reports read like real engagements -- the counters in them are
	# derived from the DRIVER's own attacks during resolution, never an enemy taking a turn.
	#
	# Which factions are AI is not a new flag: ScenarioData.ai_factions already declares it per
	# board (#150), and both shipped missions declare ENEMY. A board built without a scenario (the
	# test fixtures) declares nobody and is unaffected.
	#
	# Loops, because several AI factions can follow one another, and re-reads the faction each pass
	# rather than assuming one hand-off.
	while _is_ai_faction(turn_manager.active_faction()):
		var acting := turn_manager.active_faction()
		log.append_array(_take_ai_turn(acting))
		if mission_tag() != "":
			break
		# The AI's own end of turn burns too -- AIController.take_faction_turn ends on game.end_turn.
		log.append_array(_end_of_turn_tiles(acting))
		if mission_tag() != "":
			break
		turn_manager.end_turn(_board().present_factions())
		var next := turn_manager.active_faction()
		if next == acting:
			break   # nobody else to hand to; do not spin
		squad_manager.reset_faction_actions(next)
	return _turn_result(log)


# What end_turn hands back. A mission the boundary ended (headlessly, only a burn can) is reported
# the way execute() reports one; an AI pass that ended it has already logged the line.
func _turn_result(events: Array[String]) -> Dictionary:
	var mission := mission_tag()
	if mission != "" and not events.has(_mission_line(mission)):
		events.append(_mission_line(mission))
	var result := {"ok": true, "faction": _faction_name(turn_manager.active_faction()), "ai_events": events}
	if mission != "":
		result["mission"] = mission
	return result


# One faction's end-of-turn tiles (#898, the soak since #508): the hits
# OrderExecutor.apply_end_of_turn_tiles plays, minus the camera. TileHitAction.execute is synchronous,
# so the real one runs.
func _end_of_turn_tiles(faction: Team.Faction) -> Array[String]:
	var events: Array[String] = []
	if terrain_states == null:
		return events
	for hit in TurnBoundary.tile_hits(live_units(), terrain_states, gas_field, faction):
		hit.execute()
		if hit.gas >= 0:
			for gained in hit.resolved.states_added:
				events.append("%s gains %s from %s" % [handle_for(hit.actor),
						Elemental.state_display_name(gained), Gas.display_name(hit.gas as Gas.Kind)])
			continue
		events.append("%s takes %d from %s%s" % [handle_for(hit.actor), hit.resolved.damage,
				Terrain.tile_state_display_name(hit.state), _lethality_tag(hit.resolved.lethality)])
	_process_downed_pending()
	return events


# The two signal-driven halves of the boundary, connected in _init. round_completed fires before
# turn_started, so a round's tile tick lands before the incoming faction's own ticks.
func _on_round_completed() -> void:
	if terrain_states != null:
		terrain_states.tick_states()
	if gas_field != null:
		gas_field.tick(_board())   # game._on_round_completed's twin (#508)
	mission.advance_round()   # the clock's ONE tick, LAST as the game orders it; the turn-start check sees it


func _on_turn_started(faction: Team.Faction) -> void:
	TurnBoundary.turn_start_ticks(live_units(), faction)
	squad_manager.enforce_contact()   # AFTER the ticks, as game._on_turn_started orders them


func _is_ai_faction(faction: Team.Faction) -> bool:
	return scenario_data != null and scenario_data.ai_factions.has(faction)


# One AI faction's whole turn, through the SAME decision the game uses -- AIController's statics,
# not a headless copy of them (Law #4). What differs here is only what is missing: no camera pan,
# no pacing beat, and execute() rather than the animated OrderExecutor.
func _take_ai_turn(faction: Team.Faction) -> Array[String]:
	var events: Array[String] = []
	for squad: Squad in AIController.actable_squads(faction, squad_manager):
		if mission_tag() != "":
			break
		# Revalidated per squad for the same reason the game revalidates: the squad that just
		# acted may have downed this one's leader.
		if not AIController.is_squad_actable(squad, faction):
			continue
		AIController.plan_squad(squad, _board(), squad_manager)
		if squad_manager.active_squad != squad:
			# The archetype queued nothing at all (no reachable enemy, nothing fireable). Mark the
			# squad spent so the faction's turn terminates -- the game reaches the same state via
			# _end_squad_turn, and without it a hold-only squad would be offered again forever.
			squad_manager.set_has_acted(squad, true)
			continue
		var res := execute()
		if res.ok:
			for e in res.get("events", []):
				events.append(str(e))
		else:
			# An AI plan the resolver refuses is a bug worth surfacing, not a silent skip -- the
			# game's own answer to this (#103) is that an AI squad refused there must still end its
			# turn, or the identical plan is re-offered every turn forever.
			events.append("%s squad could not act: %s" % [_faction_name(faction), str(res.error)])
			squad_manager.set_has_acted(squad, true)
	return events
