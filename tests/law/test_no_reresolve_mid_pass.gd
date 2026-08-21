# A running pass owns its plan: nothing re-derives the queue while it is playing (#361).
#
# A kill mid-pass fires `unit_died` SYNCHRONOUSLY -- inside AttackAction.execute, while OrderExecutor
# sits mid-await -- and game._on_unit_died ends by refreshing the action queue for
# `squad_manager.active_squad`, which during a pass IS the squad executing. Every order is still in
# `squad.action_queue` (only _end_squad_turn drains them), so that refresh re-resolved the WHOLE plan
# against a board the pass had already mutated, and PlanResolver._hypo_for seeds from LIVE HP -- so
# an attack that had already landed was re-simulated with its own damage already subtracted, and the
# panel's rows were rebuilt from that phantom while the player watched.
#
# Execution itself was never wrong, which is why this went unnoticed: resolve_plan derives fresh
# AttackActions every call (#15) and execute_orders iterates a plan it captured in a local, so the
# damage lands as previewed. What the phantom DID reach was the rows, the shove/deposit overlays,
# validate's is_valid writes, SquadManager._last_resolved_plan, and GuardAction.resolved_spent --
# a stored, still-pending order, i.e. the one path this had into execution.
#
# Both halves are asserted here, and the second is not decoration: the fix must not buy an honest
# panel by changing what the pass does.
#
# Needs the real game scene -- the death handler, the panel and the executor are all game.gd's
# wiring, and a resolve-only test can see none of it. Fixture is tests/ui/test_game_scene_smoke.gd's.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const PAINTED_W := 8
const PAINTED_H := 4

var _main: Node
var game: Node2D

# Sampled INSIDE the mid-pass death, because that is the only moment the phantom exists -- by the
# time execute_orders returns, _end_squad_turn has emptied the panel. Suite fields rather than
# locals: a GDScript lambda captures locals BY VALUE, so an assignment inside one never escapes.
var _sampled_summaries: PackedStringArray = []
var _sampled_stored: ResolvedPlan = null
var _sampled_executing: ResolvedPlan = null


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(PAINTED_W):
		for y in range(PAINTED_H):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()
	_sampled_summaries = []
	_sampled_stored = null
	_sampled_executing = null


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(faction: Team.Faction, cell: Vector2i, overrides: Dictionary = {}) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data(overrides, faction), cell)
	assert_object(unit).override_failure_message("fixture failed to spawn at %s" % cell).is_not_null()
	unit.equipped_weapon = H.make_weapon()
	return unit


# What the queue PANEL currently shows for the rows the PLAYER authored, read the way the panel
# itself renders them -- _last_entries is what show_display_entries was handed, so this is the
# visible fact rather than a re-derivation of it. Section-scoped because a derived REACTION is a
# CounterAttackAction, i.e. an AttackAction too, and the header is the only thing separating them.
func _attack_row_summaries() -> PackedStringArray:
	var out: PackedStringArray = []
	var in_attacks := false
	for entry: ActionQueueDisplayEntry in game.squad_action_queue_control._last_entries:
		if entry == null:
			continue
		if entry.entry_type == ActionQueueDisplayEntry.EntryType.HEADER:
			in_attacks = entry.label == "ATTACK"
			continue
		if not in_attacks or entry.entry_type != ActionQueueDisplayEntry.EntryType.ACTION:
			continue
		var attack := entry.action as AttackAction
		if attack != null:
			out.append(attack.get_outcome_summary())
	return out


func _queue_attack(attacker: Unit, target: Unit) -> void:
	var aim := AttackAction.declare(attacker, attacker.movement.cell, target.movement.cell)
	assert_bool(game.squad_manager.queue_action(attacker.squad, aim)) \
		.override_failure_message("fixture failed to queue %s's aim" % attacker.get_unit_name()).is_true()


# The kill sits in the MIDDLE of the queue on purpose. A kill in slot one leaves no already-landed
# damage for the re-resolve to count twice, so the phantom plan comes out numerically identical to
# the real one and this case would be blind to the bug it exists for.
func test_a_kill_mid_pass_does_not_re_derive_the_queue_it_is_playing() -> void:
	var bram: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.LDR: 10}, Team.Faction.PLAYER), Vector2i(2, 0))
	bram.equipped_weapon = H.make_weapon()
	var cass := _spawn(Team.Faction.PLAYER, Vector2i(2, 2))
	var ariel := _spawn(Team.Faction.PLAYER, Vector2i(4, 0))
	# Roomy enough to eat both hits without reaching a lethality rung -- the target has to still be
	# standing at the end, or "execution was unaffected" has nothing left to measure.
	var yara := _spawn(Team.Faction.ENEMY, Vector2i(2, 1), {Stats.Stat.MHP: 30})
	var xan := _spawn(Team.Faction.ENEMY, Vector2i(4, 1))
	await await_idle_frame()
	game.squad_manager.join_squad(cass, bram.squad)
	game.squad_manager.join_squad(ariel, bram.squad)
	var squad: Squad = bram.squad
	assert_int(squad.get_members().size()) \
		.override_failure_message("fixture failed to build the three-member squad").is_equal(3)

	# Already DOWNED, so the queued hit predicts KILLED whatever the placeholder damage is (Fork 3):
	# tuning a real attack onto the overkill ceiling would make this hostage to weapon numbers.
	xan.take_damage(xan.get_current_hp())
	assert_bool(xan.is_downed()).override_failure_message("fixture failed to DOWN the mid-queue victim").is_true()

	_queue_attack(bram, yara)    # lands first
	_queue_attack(ariel, xan)    # KILLS mid-pass -> fires unit_died
	_queue_attack(cass, yara)    # has not run when the death fires

	game.refresh_action_queue(squad)   # the real path: resolve -> publish -> render the rows
	var previewed := _attack_row_summaries()
	assert_int(previewed.size()) \
		.override_failure_message("fixture failed to put three attack rows on the panel").is_equal(3)
	var start_hp := yara.get_current_hp()
	var previewed_damage := 0
	for attack: AttackAction in game.squad_manager.resolved_plan_for(squad).attacks:
		if attack.target == yara:
			previewed_damage += attack.resolved.damage
	assert_int(previewed_damage) \
		.override_failure_message("fixture previewed no damage on the surviving target").is_greater(0)

	# Connected AFTER game.spawn_unit wired _on_unit_died, so this runs once that handler has had
	# its chance to refresh -- the sample is of the state the death LEFT behind.
	xan.unit_died.connect(func(_u: Unit) -> void:
		_sampled_summaries = _attack_row_summaries()
		_sampled_stored = game.squad_manager.resolved_plan_for(squad)
		_sampled_executing = game.order_executor.executing_plan
	)

	await game.order_executor.execute_orders(bram)

	assert_array(_sampled_summaries) \
		.override_failure_message("the queue was re-derived mid-pass: rows went from %s to %s, re-simulating attacks that had already landed" \
			% [previewed, _sampled_summaries]) \
		.is_equal(previewed)
	assert_object(_sampled_stored) \
		.override_failure_message("the last stored resolve is not the plan being executed -- something re-resolved during the pass") \
		.is_same(_sampled_executing)
	assert_object(_sampled_executing) \
		.override_failure_message("the death never fired inside a running pass -- the case proves nothing").is_not_null()

	# The other half: an honest panel must not have been bought by changing the pass.
	assert_bool(yara.is_active()) \
		.override_failure_message("fixture target did not survive both hits").is_true()
	assert_int(yara.get_current_hp()) \
		.override_failure_message("execution stopped matching the preview -- Law #2 broken the other way") \
		.is_equal(start_hp - previewed_damage)
