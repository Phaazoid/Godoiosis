extends RefCounted
# PlaySession — the transport-agnostic Play API core (docs/play-api.md, #46 M2).
# Owns the player's turn vocabulary, driving the REAL SquadManager / TurnManager /
# PlanResolver / RulesService. No side channels (Law #3). Commands return structured
# Dictionaries; play/board_view.gd renders them. The headless executor applies the
# resolved plan's EFFECTS (move = teleport, attack = apply_damage + element states;
# side-channel actions run their REAL execute() — it's pure synchronous logic) —
# i.e. game.gd.execute_orders minus the animation awaits, so preview == execution (Law #2).

var grid: TileMapLayer
var units_root: Node2D
var squad_manager: SquadManager
var turn_manager: TurnManager
var overlay_manager: OverlayManager
var terrain_states: TerrainStateManager   # twin of game.terrain_states; null on a board built without one
var board_heights: BoardHeights           # twin of game.board_heights (#257); null board reads flat
var scenario_data: ScenarioData           # authored scenario metadata (#612); null on fresh new boards

var _handle_by_unit := {}      # Unit -> String (stable display handle)
var _next_player := 0
var _next_enemy := 0
var _downed_pending: Array[Unit] = []   # units downed mid-execute; ejected AFTER the pass (mirrors OrderExecutor._downed_pending)
var _mission_contested := false         # "both sides were up at once" latch (mirrors MissionController._contested)

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
	scenario_data = board.get("scenario")
	if scenario_data != null and scenario_data.contested:
		_mission_contested = true
	for unit in live_units():
		_register(unit)

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
	for unit in live_units():
		if _handle_by_unit.get(unit, "") == h:
			return unit
	return null

func _board() -> BoardContext:
	return BoardContext.new(grid, live_units(), squad_manager, terrain_states, null, board_heights)

func active_faction() -> Team.Faction:
	return turn_manager.active_faction()

func _faction_name(f: Team.Faction) -> String:
	return Team.Faction.keys()[f]

func _squad_id(squad: Squad) -> int:
	return squad_manager.squads.find(squad)

func terrain_at(cell: Vector2i) -> Dictionary:
	var data := grid.get_cell_tile_data(cell)
	if data == null:
		return {"exists": false, "walkable": false, "cost": 0, "type": "offmap"}
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


func legal_targets(handle: String) -> Dictionary:
	var unit := unit_by_handle(handle)
	var gate := _controllable(unit, handle)
	if not gate.ok:
		return gate
	if not unit.has_equipped_weapon():
		return {"ok": false, "error": "%s has no equipped weapon" % handle}
	var origin := unit.get_projected_destination()
	var aiming := unit.get_fired_attack()
	var board := _board()
	var out: Array[Dictionary] = []
	# The candidate set is the union over four facings -- what the red overlay draws -- and
	# can_hit_cell_from is what narrows it to the aim actually available. Both of queue_attack's
	# gates are applied here in its own order, so a cell offered can never be refused.
	for aim: Vector2i in Reach.get_all_attack_cells_from(unit, origin, aiming):
		if not Reach.can_hit_cell_from(unit, origin, aim, aiming, board):
			continue
		var victims := RulesService.gather_attack_victims(unit, \
				Reach.get_affected_cells_from(unit, origin, aim, aiming, board), board, aiming)
		if victims.is_empty():
			continue   # queue_attack refuses an aim that hits nobody; so does this
		var names: Array[String] = []
		for v: Unit in victims:
			names.append(handle_for(v))
		out.append({"cell": aim, "victims": names})
	return {"ok": true, "unit": handle, "from": origin, "aims": out}


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
	}


# ---- commands (mutating) — all flow through the real SquadManager (Law #3) ----

func _controllable(unit: Unit, handle: String) -> Dictionary:
	if unit == null:
		return {"ok": false, "error": "no unit '%s'" % handle}
	if unit.get_faction() != turn_manager.active_faction():
		return {"ok": false, "error": "%s is not on the active faction (%s)" % [handle, _faction_name(active_faction())]}
	if unit.squad.has_acted:
		return {"ok": false, "error": "%s's squad has already acted this turn" % handle}
	return {"ok": true}

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
	if not squad_manager.queue_action(unit.squad, move):
		return {"ok": false, "error": "another squad is already active this turn"}
	return {"ok": true, "summary": "%s -> move %s" % [handle, str(dest)], "valid": move.is_valid}

func queue_attack(handle: String, aim: Vector2i) -> Dictionary:
	var unit := unit_by_handle(handle)
	var gate := _controllable(unit, handle)
	if not gate.ok:
		return gate
	if not unit.has_equipped_weapon():
		return {"ok": false, "error": "%s has no equipped weapon" % handle}
	var origin := unit.get_projected_destination()
	# Aiming: the live pick IS the question, and it is exactly what declare() stamps below (#102).
	# Play never sets active_attack, so today this is always the weapon's main -- the headless
	# side has no way to select a secondary at all (#110).
	var aiming := unit.get_fired_attack()
	# The board carries the elevations for the vertical-tolerance half of the gate (#258),
	# mirroring the player's click exactly.
	if not Reach.can_hit_cell_from(unit, origin, aim, aiming, _board()):
		return {"ok": false, "error": "%s cannot hit %s from %s" % [handle, str(aim), str(origin)]}
	var affected := Reach.get_affected_cells_from(unit, origin, aim, aiming, _board())
	var victims := RulesService.gather_attack_victims(unit, affected, _board(), aiming)
	if victims.is_empty():
		return {"ok": false, "error": "no valid targets at %s" % str(aim)}
	# Store ONE aim order (target=null); resolve_plan derives the volley/victims at resolve time
	# (#15), mirroring game.gd. Pre-expanding a volley here made resolve_plan re-expand each member
	# -> N^2 hits for AoE weapons. `victims` above is used only to validate + describe the aim.
	# declare() stamps fired_attack (#78) -- Play aims fire what the unit would (rune carvings
	# included), same as the player's click and the AI.
	var any_ok := squad_manager.queue_action(unit.squad, AttackAction.declare(unit, origin, aim))
	if not any_ok:
		return {"ok": false, "error": "another squad is already active this turn"}
	var names: Array[String] = []
	for v in victims:
		names.append(handle_for(v))
	return {"ok": true, "summary": "%s -> attack %s (hits %s)" % [handle, str(aim), ", ".join(names)]}

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
	if not squad_manager.queue_action(rescuer.squad, action):
		return {"ok": false, "error": "%s can't rescue now (already has a main action, or another squad is active)" % rescuer_handle}
	return {"ok": true, "summary": "%s -> rescue %s" % [rescuer_handle, target_handle]}

# Guard (#414): become a nearby ally's bodyguard — the same GuardAction the menu queues, gated on the
# same RulesService.guard_candidates query the menu's row is built from. Its own verb rather than a
# queue_simple_action pass-through, for the reason rescue/intimidate have one: it takes a real unit.
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
	if not squad_manager.queue_action(unit.squad, action):
		return {"ok": false, "error": "%s can't Guard now (already has a main action, or another squad is active)" % handle}
	return {"ok": true, "summary": "%s -> guard %s" % [handle, ward_handle]}

# Overwatch (#413): aim an attack and hold fire — the same OverwatchAction the menu queues, gated on
# the same two questions its ring row asks, the attack's own can_overwatch capability and whether the
# aim is legal at all. Play never sets active_attack, so this watches with what the unit would fire.
func overwatch(handle: String, aim: Vector2i) -> Dictionary:
	var unit := unit_by_handle(handle)
	var gate := _controllable(unit, handle)
	if not gate.ok:
		return gate
	var aiming := unit.get_fired_attack()
	if aiming == null or not unit.attack_can_overwatch(aiming):
		return {"ok": false, "error": "%s's attack cannot stand watch" % handle}
	var origin := unit.get_projected_destination()
	# The player's click gate, which is now one predicate rather than this pair (#756): a directional
	# aim needs a facing whose spread survives the terrain, a point aim needs the cell itself. The
	# dud-aim refusal that stood below is inside it -- a facing watching no cells is not aimable.
	if not Reach.can_aim_at(unit, origin, aim, aiming, _board()):
		return {"ok": false, "error": "%s cannot aim at %s from %s" % [handle, str(aim), str(origin)]}
	var action := OverwatchAction.new()
	action.init(unit, aim, aiming)
	if not squad_manager.queue_action(unit.squad, action):
		return {"ok": false, "error": "%s can't stand watch now (already has a main action, or another squad is active)" % handle}
	return {"ok": true, "summary": "%s -> overwatch %s" % [handle, str(aim)]}

# Rally: self-targeted Will restore (a main action) — the same RallyAction the menu queues.
func rally(handle: String) -> Dictionary:
	var unit := unit_by_handle(handle)
	var gate := _controllable(unit, handle)
	if not gate.ok:
		return gate
	if not unit.can_rally():
		return {"ok": false, "error": "%s can't rally (Will full, in crisis, or nothing left to restore)" % handle}
	var action := RallyAction.new()
	action.init(unit)
	if not squad_manager.queue_action(unit.squad, action):
		return {"ok": false, "error": "%s can't rally now (already has a main action, or another squad is active)" % handle}
	return {"ok": true, "summary": "%s -> rally" % handle}

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
	var refusal := unit.reload_block_reason()
	if refusal != "":
		return {"ok": false, "error": "%s can't reload: %s" % [handle, refusal]}
	var action := ReloadAction.new()
	action.init(unit)
	if not squad_manager.queue_action(unit.squad, action):
		return {"ok": false, "error": "%s can't reload now (already has a main action, or another squad is active)" % handle}
	return {"ok": true, "summary": "%s -> %s" % [handle, unit.reload_label().to_lower()]}

# Rev: self-targeted Chainsword rev-up (a main action, #84) — the same RevAction the menu
# queues, driving the generic Unit.can_rev_weapon()/rev_weapon() seam. While revved, this
# unit's attacks ignore the target's DEF (PlanResolver mitigation stage).
func rev(handle: String) -> Dictionary:
	var unit := unit_by_handle(handle)
	var gate := _controllable(unit, handle)
	if not gate.ok:
		return gate
	if not unit.can_rev_weapon():
		return {"ok": false, "error": "%s can't rev (no chainsword equipped)" % handle}
	var action := RevAction.new()
	action.init(unit)
	if not squad_manager.queue_action(unit.squad, action):
		return {"ok": false, "error": "%s can't rev now (already has a main action, or another squad is active)" % handle}
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
	if not unit.can_burrow_weapon():
		return {"ok": false, "error": "%s can't burrow (no drill equipped)" % handle}
	var action := BurrowAction.new()
	action.init(unit)
	if not squad_manager.queue_action(unit.squad, action):
		return {"ok": false, "error": "%s can't burrow now (already has a main action, or another squad is active)" % handle}
	return {"ok": true, "summary": "%s -> burrow" % handle}

# member joins leader's squad — one join_squad call covers both "squad up" (leader was solo) and
# "join squad", with the player's own eligibility: same faction, within the leader's LDR range,
# nothing has committed to acting yet.
func join(member_handle: String, leader_handle: String) -> Dictionary:
	var member := unit_by_handle(member_handle)
	var leader := unit_by_handle(leader_handle)
	if member == null:
		return {"ok": false, "error": "no unit '%s'" % member_handle}
	if leader == null:
		return {"ok": false, "error": "no unit '%s'" % leader_handle}
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
	return {"moves": moves, "attacks": attacks, "counters": counters,
			"side_actions": side_actions, "tile_hits": tile_hits}

func _describe_attack(atk: AttackAction) -> Dictionary:
	var r := atk.resolved
	var dmg := r.damage if r != null else 0
	var hp_after := r.target_hp_after if r != null else -1
	var lethality := r.lethality if r != null else ResolvedOutcome.Lethality.NONE
	var skipped := r.skipped if r != null else false
	return {
		"actor": handle_for(atk.actor),
		"target": handle_for(atk.target),
		"dmg": dmg,
		"hp_after": hp_after,
		"lethality": lethality,   # NONE / DOWNED / KILLED (mirrors Unit.take_damage — Law #2)
		"skipped": skipped,       # counter-er was downed/killed earlier this pass -> no counter
	}

# ---- execute (headless application of the resolved plan) ----

func execute() -> Dictionary:
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
			action.execute()
			events.append(action.get_description())

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
	events.append("MISSION %s" % mission)
	return {"ok": true, "events": events, "mission": mission}

# Play the resolved terrain deposits into the live store (twin of OrderExecutor._apply_cell_effects, minus
# the redraw). Preview and execution consume the SAME ResolvedCellEffect objects (R3).
func _apply_cell_effects(cell_effects: Array[ResolvedCellEffect], events: Array[String]) -> void:
	if terrain_states == null:
		return
	for effect in cell_effects:
		terrain_states.apply(effect)
		for state in effect.states_added:
			events.append("%s becomes %s" % [str(effect.cell), Terrain.TileState.keys()[state]])


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
	target.take_damage(r.damage)   # routes through Unit.take_damage -> down/kill rung
	for s in r.states_removed:
		target.remove_element_state(s)
	for s in r.states_added:
		target.add_element_state(s, r.state_turns.get(s, 0))
	events.append("%s hits %s for %d%s" % [handle_for(actor), handle_for(target), r.damage, _lethality_tag(r.lethality)])
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
func _spend_firing_costs(atk: AttackAction, actor: Unit) -> void:
	if atk.is_secondary_hit:
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

func objectives() -> Array[MissionRules.Objective]:
	var result: Array[MissionRules.Objective] = []
	if scenario_data != null:
		result.assign(scenario_data.objectives)
	return result

func zones() -> Dictionary:
	return scenario_data.zones if scenario_data != null else {}

func round_limit() -> int:
	return scenario_data.round_limit if scenario_data != null else 0

func lose_conditions() -> Array[MissionRules.LoseCondition]:
	var result: Array[MissionRules.LoseCondition] = []
	if scenario_data != null:
		result.assign(scenario_data.lose_conditions)
	return result

# The headless twin of MissionController: the SAME MissionRules call the game makes, with the
# same caller-held `contested` latch (see MissionRules.evaluate -- a live read could never end a
# mission). The game's version also raises a banner and locks the board; headless has no use for
# either, so this reports and nothing more.
func mission_outcome() -> MissionRules.Outcome:
	var board := _board()
	if not _mission_contested:
		_mission_contested = MissionRules.is_contested(board)
	return MissionRules.evaluate(board, _mission_contested)

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
	# A finished mission does not hand off (mirrors game.end_turn's bail on mission_controller
	# .is_over()). Refusing rather than silently passing keeps a headless run from grinding out
	# turns on a board nobody can still win or lose.
	var already := mission_tag()
	if already != "":
		return {"ok": false, "error": "mission is over (%s)" % already, "mission": already}

	var board := _board()
	turn_manager.end_turn(board.present_factions())
	# Mirror the game's auto-skip: pass over factions with no commandable units (e.g. only
	# downed), guarding against an all-downed board where this would loop with nothing to stop on.
	while not board.faction_has_active_units(turn_manager.active_faction()) and board.has_active_units():
		turn_manager.end_turn(board.present_factions())
	var faction := turn_manager.active_faction()
	squad_manager.reset_faction_actions(faction)

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
	var log: Array[String] = []
	while _is_ai_faction(turn_manager.active_faction()):
		var acting := turn_manager.active_faction()
		log.append_array(_take_ai_turn(acting))
		if mission_tag() != "":
			break
		turn_manager.end_turn(_board().present_factions())
		var next := turn_manager.active_faction()
		if next == acting:
			break   # nobody else to hand to; do not spin
		squad_manager.reset_faction_actions(next)
	faction = turn_manager.active_faction()
	return {"ok": true, "faction": _faction_name(faction), "ai_events": log}


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
