extends SceneTree

# Headless profiler for ONE AI squad's DECISION -- AIController.plan_squad, the archetype call plus
# everything AITactics does inside it. See docs/performance.md for the recorded numbers.
#
#   godot --headless --path <repo> --script res://tools/profile_ai_turn.gd
#
# Lives outside tests/ for the same reason profile_group_move.gd does: it extends SceneTree, not
# GdUnitTestSuite, and the suite runner scans res://tests recursively. That file is the shape this
# one copies -- boot the REAL Main.tscn, load a REAL scenario, wrap the REAL call in
# Time.get_ticks_usec().
#
# WHAT THE SIGNATURE IS FOR, and how it differs from profile_group_move's: there it proves an
# optimisation changed nothing. Here the plan DELIBERATELY changes -- this profiler was written for
# the joint-scoring pass, whose whole point is that squads choose differently. So the signature is a
# DECISION RECORD (what did the AI do, at this commit), not an equivalence check. Diff two runs to
# read the behaviour change; never to assert one didn't happen.
#
# Castle Assault declares BOTH factions AI (ai_factions = [0, 1]), so every squad on the board is
# profiled without touching the dev overlay.

const SCENARIO := "res://Scenarios/Castle Assault.tres"

func _init() -> void:
	_run.call_deferred()

func _stamp(label: String, usec: int) -> void:
	print("  %-46s %8.2f ms" % [label, usec / 1000.0])

# Everything the AI decided, in queue order. Attacks name their aim cell and the attack they
# stamped, so a change of PICK is as visible as a change of TARGET.
func _plan_signature(squad: Squad) -> Array:
	var sig: Array = []
	for a in squad.action_queue:
		var detail := "-"
		if a.action_type == BaseAction.ActionType.MOVE:
			detail = str(a.get_destination())
		elif a is AttackAction:
			var atk := (a as AttackAction).fired_attack
			var name: String = atk.display_name if atk != null else "fists"
			detail = "%s@%s" % [name, str((a as AttackAction).target_cell)]
		sig.append("%s|%s|%s" % [
			a.actor.get_unit_name(),
			BaseAction.ActionType.keys()[a.action_type],
			detail])
	return sig

func _run() -> void:
	var main: Node = load("res://Scenes/Main.tscn").instantiate()
	root.add_child(main)
	for i in range(5):
		await process_frame

	var game: Node2D = main.get_node("GameContainer/GameView/Game")
	game.get_node("ScenarioManager").load_scenario(SCENARIO)
	for i in range(5):
		await process_frame

	var sm: SquadManager = game.squad_manager
	print("scenario  = ", SCENARIO)
	print("units     = ", game.units_root.get_child_count())
	print("ai        = ", game.ai_controller.ai_factions())

	var grand_total := 0
	for faction in game.ai_controller.ai_factions():
		var squads: Array[Squad] = AIController.actable_squads(faction, sm)
		print("\n%s -- %d actable squad(s)" % [Team.Faction.keys()[faction], squads.size()])
		for squad in squads:
			if not AIController.is_squad_actable(squad, faction):
				continue
			var board: BoardContext = game._board()
			var t := Time.get_ticks_usec()
			AIController.plan_squad(squad, board, sm)
			var cost := Time.get_ticks_usec() - t
			grand_total += cost
			_stamp("plan_squad (%d members)" % squad.get_members().size(), cost)
			for row in _plan_signature(squad):
				print("      ", row)

	print("\n  %-46s %8.2f ms" % ["WHOLE BOARD (every AI squad decides once)", grand_total / 1000.0])
	quit(0)
