extends SceneTree

# A WHOLE BATTLE, headless, with the AI on both sides -- what the profiler beside it is to one
# squad's decision, this is to a game. Castle Assault declares both factions AI, so it plays itself:
#
#   godot --headless --path <repo> --script res://tools/replay_battle.gd > replay.log 2>&1
#
# Lives outside tests/ for profile_ai_turn.gd's reason (extends SceneTree, and the suite runner scans
# res://tests recursively), and it is that file's shape widened from one call to sixteen rounds.
#
# WHAT IT IS FOR: a DECISION RECORD to diff, never an equivalence check. The whole point of an AI
# change is that the AI decides differently, so a diff between two runs is how you READ that change
# -- never how you assert one did not happen. It is also not a test: nothing here asserts, and a
# green suite is no reason to skip reading a run.
#
# It exists because a green suite cannot see a squad standing still. #720's bug lived in the layer
# that decides where to STAND while every fixture pinned the layer that attacks, so all six passed
# while five units revved beside a body for thirteen rounds. Twenty-five seconds of this found it.
# Per queued order it logs the footprint's occupants, the resolved rows and the plan's MARGINAL
# score; per REV a `diag` line naming what the engagement layer answered, which is where that bug
# was actually visible; plus every HP change, down and death, and the map once.
#
# Two mechanics worth keeping: `load_scenario` does NOT start the clock (`_begin_turn` does), and the
# unit hooks ride `squad_created` because every spawn makes a solo squad -- so they are attached
# before the first turn without a second walk over the board.
const SCENARIO := "res://Scenarios/Castle Assault.tres"
const MAX_ROUNDS := 16
const MAX_SECONDS := 300.0

var game: Node2D
var sm: SquadManager
var seq := 0
var round_no := 1
var last_score := {}

func _init() -> void:
	_run.call_deferred()

func _fac(f: int) -> String:
	return Team.Faction.keys()[f]

func _u(unit: Unit) -> String:
	if unit == null or not is_instance_valid(unit):
		return "<freed>"
	return "%s(%s@%s hp%d %s)" % [unit.get_unit_name(), _fac(unit.get_faction()), str(unit.movement.cell),
			unit.get_current_hp(), Unit.LifecycleState.keys()[unit.lifecycle_state]]

func _log(msg: String) -> void:
	seq += 1
	var f: int = game.turn_manager.active_faction()
	print("[%04d r%d %s] %s" % [seq, round_no, _fac(f), msg])

func _hook(unit: Unit) -> void:
	if unit.has_meta("replay_hooked"):
		return
	unit.set_meta("replay_hooked", true)
	unit.unit_instance.hp_changed.connect(func(cur, mx): _log("    HP %s -> %d/%d" % [_u(unit), cur, mx]))
	unit.went_downed.connect(func(u): _log("    DOWNED %s" % _u(u)))
	unit.unit_died.connect(func(u): _log("    DIED %s" % _u(u)))

func _on_squad_created(squad: Squad) -> void:
	if squad.leader != null:
		_hook(squad.leader)

func _dump_board() -> void:
	for unit in game.units_root.get_children():
		if unit is Unit:
			var names := []
			for a in unit.get_selectable_attacks():
				names.append(a.display_name if a != null else "fists")
			_log("  unit %s squad=%s weapons=%s" % [_u(unit), str(unit.squad.get_instance_id() % 1000) if unit.squad != null else "-", str(names)])

func _dump_map() -> void:
	var b: BoardContext = game._board()
	var rect: Rect2i = b.grid.get_used_rect()
	_log("map used rect %s  ('.' ground, '#' unwalkable, digit = prop rule height, letter = unit initial+faction)" % str(rect))
	var header := "      "
	for x in range(rect.position.x, rect.end.x):
		header += "%3d" % x
	_log(header)
	for y in range(rect.position.y, rect.end.y):
		var row := "y%3d: " % y
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			var glyph := "."
			if not b.is_walkable(cell):
				glyph = "#"
			var h: int = b.prop_rule_height_at(cell)
			if h > 0:
				glyph = str(h)
			var u := b.unit_at_cell(cell)
			if u != null:
				glyph = ("P" if u.get_faction() == Team.Faction.PLAYER else "E")
			row += "  " + glyph
		_log(row)

func _on_turn_started(faction: int) -> void:
	last_score.clear()
	_log("--- TURN START %s (round %d)" % [_fac(faction), round_no])
	_dump_board()

func _on_queued(squad: Squad, action: BaseAction) -> void:
	var actor: Unit = action.actor
	var t: String = BaseAction.ActionType.keys()[action.action_type]
	if action.action_type == BaseAction.ActionType.MOVE:
		_log("Q %s MOVE -> %s" % [_u(actor), str(action.get_destination())])
		return
	if not (action is AttackAction):
		var dest := actor.get_projected_destination()
		var near := []
		for other in game.units_root.get_children():
			if other is Unit and Team.is_enemy(actor.get_faction(), other.get_faction()) \
					and GridUtils.manhattan_distance(dest, other.movement.cell) <= 1:
				near.append(_u(other))
		_log("Q %s %s from %s | enemies adjacent: %s" % [_u(actor), t, str(dest), str(near)])
		if action.action_type == BaseAction.ActionType.REV:
			var b: BoardContext = game._board()
			var leader: Unit = actor.squad.get_leader()
			var eng: Unit = AITactics.choose_engagement_target(leader, b, sm)
			var near_e: Unit = AITactics.nearest_enemy(actor, b)
			var reach: Dictionary = RulesService.compute_move_range(actor, b).reachable
			var own_dest := Vector2i(999, 999)
			if near_e != null:
				own_dest = AITactics.best_attack_destination(actor, near_e, b)
			_log("      diag mov=%d reachable=%d has(4,2)=%s | leader %s engages %s -> %s | own nearest %s -> best dest %s" % [
					actor.get_mov(), reach.size(), str(reach.has(Vector2i(4, 2))), leader.get_unit_name(),
					_u(eng) if eng != null else "null",
					str(AITactics.best_attack_destination(leader, eng, b)) if eng != null else "-",
					_u(near_e) if near_e != null else "null", str(own_dest)])
		return
	var aim := action as AttackAction
	var board: BoardContext = game._board()
	var origin := actor.get_projected_destination()
	var atk_name: String = aim.fired_attack.display_name if aim.fired_attack != null else "fists"
	var footprint := Reach.get_affected_cells_from(actor, origin, aim.target_cell, aim.fired_attack)
	var occupants := []
	for cell in footprint:
		var o := board.projected_unit_at_cell(cell)
		if o != null:
			occupants.append(_u(o))
	var plan := sm.resolve_plan(squad, board)
	var rows := []
	for a in plan.attacks:
		if a.source_aim == aim and a.target != null and a.resolved != null:
			rows.append("%s dmg%d %s after%d" % [a.target.get_unit_name(), a.resolved.damage,
					ResolvedOutcome.Lethality.keys()[a.resolved.lethality], a.resolved.target_hp_after])
	var score: Vector3i = AITactics._score_plan(actor.get_faction(), plan)
	var prev: Vector3i = last_score.get(squad, Vector3i.ZERO)
	last_score[squad] = score
	_log("Q %s ATTACK %s @%s from %s | in footprint: %s | rows: %s | plan %s marginal %s" % [
			_u(actor), atk_name, str(aim.target_cell), str(origin), str(occupants), str(rows), str(score), str(score - prev)])

func _run() -> void:
	var main: Node = load("res://Scenes/Main.tscn").instantiate()
	root.add_child(main)
	for i in range(5):
		await process_frame
	game = main.get_node("GameContainer/GameView/Game")
	sm = game.squad_manager
	sm.squad_action_queued.connect(_on_queued)
	sm.squad_created.connect(_on_squad_created)
	game.turn_manager.turn_started.connect(_on_turn_started)
	game.turn_manager.round_completed.connect(func():
		_log("=== ROUND %d COMPLETE" % round_no)
		round_no += 1)
	game.get_node("ScenarioManager").load_scenario(SCENARIO)
	for i in range(2):
		await process_frame
	_log("loaded; ai = %s" % str(game.ai_controller.ai_factions()))
	_dump_map()
	game.mission_controller._begin_turn()   # load_scenario does not start the clock; begin_mission does
	var t0 := Time.get_ticks_msec()
	while not game.mission_controller.is_over() and round_no <= MAX_ROUNDS \
			and (Time.get_ticks_msec() - t0) < MAX_SECONDS * 1000.0:
		await process_frame
	_log("END over=%s round=%d elapsed=%.1fs" % [str(game.mission_controller.is_over()), round_no,
			(Time.get_ticks_msec() - t0) / 1000.0])
	_dump_board()
	quit(0)
