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

var _handle_by_unit := {}      # Unit -> String (stable display handle)
var _next_player := 0
var _next_enemy := 0
var _downed_pending: Array[Unit] = []   # units downed mid-execute; ejected AFTER the pass (mirrors game._downed_pending)

const PLAYER_GLYPHS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const ENEMY_GLYPHS := "abcdefghijklmnopqrstuvwxyz"

func _init(board: Dictionary) -> void:
	grid = board.grid
	units_root = board.units_root
	squad_manager = board.squad_manager
	turn_manager = board.turn_manager
	overlay_manager = board.overlay_manager
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
	# squad ejection until the pass settles, exactly like game._on_unit_downed, so we never
	# restructure squads mid-resolution.
	if not _downed_pending.has(unit):
		_downed_pending.append(unit)

func _process_downed_pending() -> void:
	# Twin of game._process_downed_pending: eject each survivor-but-downed unit into a solo
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
	return BoardContext.new(grid, live_units(), squad_manager)

func active_faction() -> Team.Faction:
	return turn_manager.active_faction()

func _faction_name(f: Team.Faction) -> String:
	return Team.Faction.keys()[f]

func _squad_id(squad: Squad) -> int:
	return squad_manager.squads.find(squad)

func terrain_at(cell: Vector2i) -> Dictionary:
	var data := grid.get_cell_tile_data(cell)
	if data == null:
		return {"exists": false, "walkable": false, "cost": 0, "type": "void"}
	var walkable := false
	if data.has_custom_data("walkable"):
		walkable = bool(data.get_custom_data("walkable"))
	var cost := 0
	if data.has_custom_data("move_cost"):
		cost = int(data.get_custom_data("move_cost"))
	var kind := GridUtils.get_terrain_kind_at_cell(grid, cell)
	var kind_name: String = Terrain.Kind.keys()[kind]
	return {"exists": true, "walkable": walkable, "cost": cost, "type": kind_name.to_lower()}

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
	if not unit.combat.can_hit_cell_from(origin, aim):
		return {"ok": false, "error": "%s cannot hit %s from %s" % [handle, str(aim), str(origin)]}
	var affected := unit.combat.get_affected_cells_from(origin, aim)
	var victims := RulesService.gather_attack_victims(unit, affected, _board())
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
	var action := RescueAction.new()
	action.init(rescuer, target)
	if not squad_manager.queue_action(rescuer.squad, action):
		return {"ok": false, "error": "%s can't rescue now (already has a main action, or another squad is active)" % rescuer_handle}
	return {"ok": true, "summary": "%s -> rescue %s" % [rescuer_handle, target_handle]}

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

# Spring Load: self-targeted weapon rearm (a main action, #73) — the same SpringLoadAction
# the menu queues, driving the generic Unit.can_reload_weapon()/reload_weapon() seam.
func spring_load(handle: String) -> Dictionary:
	var unit := unit_by_handle(handle)
	var gate := _controllable(unit, handle)
	if not gate.ok:
		return gate
	if not unit.can_reload_weapon():
		return {"ok": false, "error": "%s can't spring-load (weapon already ready, or nothing to reload)" % handle}
	var action := SpringLoadAction.new()
	action.init(unit)
	if not squad_manager.queue_action(unit.squad, action):
		return {"ok": false, "error": "%s can't spring-load now (already has a main action, or another squad is active)" % handle}
	return {"ok": true, "summary": "%s -> spring load" % handle}

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
	if GridUtils.manhattan_distance(member.movement.cell, leader.movement.cell) > reach:
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
	squad_manager.validate_squad_plan(squad)
	if squad_manager.squad_has_invalid_actions(squad):
		var errs: Array[String] = []
		for action in squad.action_queue:
			if not action.is_valid:
				errs.append("%s: %s" % [handle_for(action.actor), ", ".join(action.validation_errors)])
		return {"ok": false, "error": "plan has invalid actions", "invalid": errs}
	var plan := squad_manager.resolve_plan(squad, _board())
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
	return {"moves": moves, "attacks": attacks, "counters": counters, "side_actions": side_actions}

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
	squad_manager.validate_squad_plan(squad)
	if squad_manager.squad_has_invalid_actions(squad):
		return {"ok": false, "error": "plan has invalid actions; fix before executing"}

	var plan := squad_manager.resolve_plan(squad, _board())   # resolve BEFORE moving (projected positions)
	var events: Array[String] = []

	# 1) moves — teleport, the headless stand-in for tweened MoveAction.execute()
	for action in squad.action_queue.duplicate():
		if action.action_type == BaseAction.ActionType.MOVE and action.is_valid and not action.is_hold_position:
			var mv := action as MoveAction
			mv.actor.movement.set_cell(mv.get_destination())
			events.append("%s moves to %s" % [handle_for(mv.actor), str(mv.get_destination())])

	# 2) attacks, then 3) counters — apply resolved outcomes (mirrors AttackAction.execute guards)
	for atk in plan.attacks:
		_apply_attack(atk, events)
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

	# 5) eject units downed during the pass into solo squads (mirrors game._process_downed_pending)
	_process_downed_pending()

	# clear the squad's orders + mark acted (mirrors execute_orders' tail)
	if is_instance_valid(squad):
		for action in squad.action_queue.duplicate():
			squad_manager.remove_action(squad, action)
		squad_manager.set_has_acted(squad, true)

	return {"ok": true, "events": events}

func _apply_attack(atk: AttackAction, events: Array[String]) -> void:
	var actor := atk.actor
	var target := atk.target
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
	target.combat.apply_damage(r.damage)   # routes through Unit.take_damage -> down/kill rung
	for s in r.states_removed:
		target.remove_element_state(s)
	for s in r.states_added:
		target.add_element_state(s)
	events.append("%s hits %s for %d%s" % [handle_for(actor), handle_for(target), r.damage, _lethality_tag(r.lethality)])
	# Knockback (#84): the headless stand-in for AttackAction.execute()'s shove — the resolver
	# already picked the landing cell (stopped at any wall/unit/edge), so this just applies it.
	if r.knockback_applied and is_instance_valid(target):
		target.movement.set_cell(r.knockback_to)
		events.append("%s is shoved to %s" % [handle_for(target), str(r.knockback_to)])
	# Post-fire economy (#73/#84): mirror AttackAction.execute()'s readiness/charge hook — the
	# headless executor bypasses that method, so without this the play path diverges from the game
	# (a fired Spring stays sprung; a Blowback keeps its charge). Lead volley member with a real
	# weapon attack only; counters fire main (no stamped attack), so they never reach here.
	if not atk.is_secondary_hit and atk.fired_attack is WeaponAttackData:
		var weapon := actor.get_equipped_weapon() as WeaponInstance
		if weapon != null:
			weapon.consume_readiness_for(atk.fired_attack as WeaponAttackData)

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
	var board := _board()
	turn_manager.end_turn(board.present_factions())
	# Mirror the game's auto-skip: pass over factions with no commandable units (e.g. only
	# downed), guarding against an all-downed board where this would loop with nothing to stop on.
	while not board.faction_has_active_units(turn_manager.active_faction()) and board.has_active_units():
		turn_manager.end_turn(board.present_factions())
	var faction := turn_manager.active_faction()
	squad_manager.reset_faction_actions(faction)
	return {"ok": true, "faction": _faction_name(faction)}
