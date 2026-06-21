extends RefCounted
# PlaySession — the transport-agnostic Play API core (docs/play-api.md, #46 M2).
# Owns the player's turn vocabulary, driving the REAL SquadManager / TurnManager /
# PlanResolver / RulesService. No side channels (Law #3). Commands return structured
# Dictionaries; play/board_view.gd renders them. The headless executor applies the
# resolved plan's EFFECTS (move = teleport, attack = apply_damage + element states) —
# i.e. game.gd.execute_orders minus the animation awaits, so preview == execution (Law #2).

var grid: TileMapLayer
var units_root: Node2D
var squad_manager: SquadManager
var turn_manager: TurnManager
var overlay_manager: OverlayManager

var _handle_by_unit := {}      # Unit -> String (stable display handle)
var _next_player := 0
var _next_enemy := 0

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

func _on_unit_died(unit: Unit) -> void:
	squad_manager.handle_unit_death(unit)

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
	var ttype := "?"
	if data.has_custom_data("terrain_type"):
		ttype = str(data.get_custom_data("terrain_type"))
	return {"exists": true, "walkable": walkable, "cost": cost, "type": ttype}

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
	var any_ok := false
	for attack in AttackAction.create_volley(unit, origin, aim, victims):
		if squad_manager.queue_action(unit.squad, attack):
			any_ok = true
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
	var plan := squad_manager.resolve_plan(squad)
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
	return {"moves": moves, "attacks": attacks, "counters": counters}

func _describe_attack(atk: AttackAction) -> Dictionary:
	var r := atk.resolved
	var dmg := r.damage if r != null else 0
	var hp_after := r.target_hp_after if r != null else -1
	return {
		"actor": handle_for(atk.actor),
		"target": handle_for(atk.target),
		"dmg": dmg,
		"hp_after": hp_after,
		"lethal": hp_after <= 0,
	}

# ---- execute (headless application of the resolved plan) ----

func execute() -> Dictionary:
	var squad := squad_manager.active_squad
	if squad == null:
		return {"ok": false, "error": "no squad has queued orders"}
	squad_manager.validate_squad_plan(squad)
	if squad_manager.squad_has_invalid_actions(squad):
		return {"ok": false, "error": "plan has invalid actions; fix before executing"}

	var plan := squad_manager.resolve_plan(squad)   # resolve BEFORE moving (projected positions)
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
	target.combat.apply_damage(r.damage)
	for s in r.states_removed:
		target.remove_element_state(s)
	for s in r.states_added:
		target.add_element_state(s)
	var suffix := " (DIES)" if (target.is_queued_for_deletion() or target.get_current_hp() <= 0) else ""
	events.append("%s hits %s for %d%s" % [handle_for(actor), handle_for(target), r.damage, suffix])

# ---- turn flow ----

func end_turn() -> Dictionary:
	turn_manager.end_turn()
	var faction := turn_manager.active_faction()
	squad_manager.reset_faction_actions(faction)
	return {"ok": true, "faction": _faction_name(faction)}
