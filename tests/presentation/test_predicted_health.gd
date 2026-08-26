# The predicted health readout (#313): while a plan is queued, does the bar over a unit show what
# that plan is going to do to it — and does it show it to exactly the units the plan touches?
#
# This is a WIRE, so every case queues a REAL order through the real declare path and then reads
# the RENDERED bar. Nothing here calls set_prediction: both ends of this were already correct and
# unconnected before the ticket (PlanResolver has held the number since #124, UnitHealthBar has held
# a bar since #229), which is #103's shape exactly, and only the wire between them is new.
#
# Every expected number is DERIVED from the seam under test — the plan's own hypothetical, run
# through the one display clamp — never typed in. The damage a fixture weapon does is a function of
# tuning values, and pinning one here would make a stat nudge turn this suite red.
#
# Fixture is test_unit_health_bar's: the Battle3D scene with the boot board cleared and units
# spawned by hand, so nothing here can be reddened by a content commit repainting a mission.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _scene: Node3D
var game: Node2D
var _unit_mirror: UnitMirror


func before_test() -> void:
	# Hermetic, and NOT optional (#350): is_on() falls through to user://settings.cfg, so without
	# this a suite asserting which units wear a bar reads the developer's own saved preference.
	PlayerSettings.reset_for_test()
	get_tree().root.size = Vector2i(1280, 720)
	var packed := load(SCENE_PATH) as PackedScene
	_scene = packed.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	game = _scene.game
	_unit_mirror = _scene.get_node("UnitMirror") as UnitMirror
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	# The readout gate is `hovered or foretold or always_on` (#350/#354) and every case in this file
	# is about the FORETOLD leg. Hover was silently absent before #520 only because nothing moved the
	# camera during a player's own pass -- now the camera goes to the action, so where a stationary
	# cursor points afterwards is a different cell, and one of them can hold a unit. Cutting the leg
	# is what the file already says it wants ("the pointer is nowhere"); leaving it live made these
	# cases pass or fail on whatever the PREVIOUS suite left the mouse doing.
	_unit_mirror.hovered_unit_source = Callable()
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_scene)
	_scene.free()


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


func _spawn(faction: Team.Faction, cell: Vector2i, armed := true, overrides := {}) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data(overrides, faction), cell)
	assert_object(unit).is_not_null()   # fixture setup, not the claim under test
	if armed:
		unit.equipped_weapon = H.make_weapon()   # pattern-less: Reach falls back to adjacency
	return unit


# Aim and commit, through the mode the player uses. enter_attack_mode + selected_unit is the
# documented dispatcher idiom this suite's sibling already uses for a move; everything past the
# click — declare()'s stamp, queue_action's gates, the resolve, the repaint — is under test.
func _aim_at(attacker: Unit, cell: Vector2i) -> void:
	game.enter_attack_mode(attacker)
	game.selected_unit = attacker
	game._on_left_click(cell)


func _plan() -> ResolvedPlan:
	var squads: SquadManager = game.squad_manager
	return squads.resolved_plan_for(squads.active_squad)


# What the PLAN says this unit ends the pass at, as a readout would show it. The same two calls
# UnitMirror makes — this suite is asserting that the bar draws this number, not that the number
# itself is right (tests/law owns the ladder).
func _predicted(unit: Unit) -> int:
	var plan := _plan()
	assert_object(plan).override_failure_message(
			"nothing was queued, so there is no prediction to check").is_not_null()
	return LethalityRules.displayed_hp(PlanResolver.projected_hp(unit, plan.hypo),
			PlanResolver.projected_lifecycle(unit, plan.hypo))


func _shown_bars() -> Array[Unit]:
	var shown: Array[Unit] = []
	for child in game.units_root.get_children():
		var unit := child as Unit
		if unit == null:
			continue
		var bar := _unit_mirror.bar_for(unit)
		if bar != null and bar.visible:
			shown.append(unit)
	return shown


# The queue panel's own "before -> after" text, read off the built rows. Walked rather than reached
# for by path: the row is code-built and the label is a grandchild of the icon it annotates.
func _queue_row_after() -> int:
	var found := _find_delta_label(game.squad_action_queue_control)
	assert_object(found).override_failure_message(
			"the queue panel drew no HP delta, so it cannot be compared with anything").is_not_null()
	return int(found.text.split("->")[1])


func _find_delta_label(node: Node) -> Label:
	var label := node as Label
	if label != null and label.text.contains("->"):
		return label
	for child in node.get_children():
		var hit := _find_delta_label(child)
		if hit != null:
			return hit
	return null


# ------------------------------------------------------------------------------
#  A plan puts a readout up, and only over what it touches
# ------------------------------------------------------------------------------

func test_a_queued_attack_puts_a_readout_over_its_target_with_no_pointer_near_it() -> void:
	var attacker := _spawn(PLAYER, Vector2i(2, 2))
	var victim := _spawn(ENEMY, Vector2i(3, 2))
	# Out of the fixture weapon's adjacency reach and out of its (single-cell) footprint, but still
	# on the cleared board — the sibling suite stands a bystander here for the same reason.
	var bystander := _spawn(ENEMY, Vector2i(6, 2))
	_aim_at(attacker, victim.movement.cell)
	await _settle()

	# The pointer is nowhere — this readout is up because of the PLAN, which is the whole ticket.
	# The claim is REACH: the unit the plan changes wears one, a unit it does not touch does not.
	# (The attacker may wear one too, from a counter the plan derives; that is the feature working,
	# and asserting it here would pin whether the fixture weapon counters.)
	assert_array(_shown_bars()).contains([victim])
	assert_bool(_unit_mirror.bar_for(bystander).visible).override_failure_message(
			"a unit the plan never touches is wearing a prediction").is_false()


func test_cancelling_the_order_puts_every_prediction_away() -> void:
	var attacker := _spawn(PLAYER, Vector2i(2, 2))
	var victim := _spawn(ENEMY, Vector2i(3, 2))
	_aim_at(attacker, victim.movement.cell)
	await _settle()
	assert_bool(_unit_mirror.bar_for(victim).visible).override_failure_message(
			"no readout appeared, so its disappearing proves nothing").is_true()

	game._on_right_click()   # the board is at rest, so this is the LIFO undo
	await _settle()
	assert_array(_shown_bars()).is_empty()


# ------------------------------------------------------------------------------
#  What it draws
# ------------------------------------------------------------------------------

# What the grid says the plan leaves this unit at, read off the CUBES: the ones still standing once
# the doomed go, or the standing ones plus the sockets a heal will refill. This is what #313's notch
# said in one mark, and with one cube per point of HP it is a COUNT rather than a pixel-snapped
# position — so these cases carry no tolerance, and no width knob can turn them red.
func _grid_predicts(bar: UnitHealthBar, healing: bool) -> int:
	if healing:
		return bar.filled_block_count() + bar.doomed_block_count()
	return bar.filled_block_count() - bar.doomed_block_count()


func test_the_doomed_cubes_are_exactly_the_ones_the_plan_takes() -> void:
	var attacker := _spawn(PLAYER, Vector2i(2, 2))
	var victim := _spawn(ENEMY, Vector2i(3, 2))
	_aim_at(attacker, victim.movement.cell)
	await _settle()

	var bar := _unit_mirror.bar_for(victim)
	var predicted := _predicted(victim)
	# Non-vacuity: a prediction at 0 or at full would satisfy the arithmetic below without saying
	# anything. A precondition on the FIXTURE (did the hit land, did it leave them standing), stated
	# as a message rather than as a threshold the tuning could move.
	assert_bool(predicted > 0 and predicted < victim.get_max_hp()).override_failure_message(
			"the fixture attack did not wound-but-spare the victim, so the cubes prove nothing"
			).is_true()

	assert_int(bar.block_count()).is_equal(victim.get_max_hp())
	assert_int(bar.filled_block_count()).is_equal(victim.get_current_hp())
	assert_int(_grid_predicts(bar, false)).is_equal(predicted)
	# And the span is actually drawn, or "the plan takes some" is a claim about nothing.
	assert_int(bar.doomed_block_count()).is_greater(0)


func test_a_predicted_down_shows_one_hp_and_raises_the_alarm() -> void:
	var attacker := _spawn(PLAYER, Vector2i(2, 2))
	var victim := _spawn(ENEMY, Vector2i(3, 2))
	victim.set_current_hp(2)   # low enough that the fixture's hit is a would-be-down, not a scratch
	_aim_at(attacker, victim.movement.cell)
	await _settle()

	var plan := _plan()
	assert_int(PlanResolver.projected_lifecycle(victim, plan.hypo)).override_failure_message(
			"the fixture attack did not fell the victim, so there is no alarm to check"
			).is_equal(Unit.LifecycleState.DOWNED)
	# The threaded number is NEGATIVE here — that is the ladder's arithmetic, not a readout — and
	# the clamp is what turns it into the 1 HP a downed unit really clings at. Drawn raw, the notch
	# would sit at the left edge and the bar would claim a kill.
	assert_int(PlanResolver.projected_hp(victim, plan.hypo)).override_failure_message(
			"the raw prediction is not negative, so the clamp is not being exercised").is_less(0)

	var bar := _unit_mirror.bar_for(victim)
	assert_int(_grid_predicts(bar, false)).override_failure_message(
			"the grid does not leave exactly the one cube a downed unit clings at").is_equal(1)
	assert_bool(bar.alarm_running()).override_failure_message(
			"a plan that fells a unit did not raise the alarm").is_true()


func test_a_queued_heal_draws_its_span_above_the_current_health() -> void:
	var healer := _spawn(PLAYER, Vector2i(2, 2))
	# A real heal is authored ally-splash-capable — RulesService.gather_attack_victims' targeting
	# gate is what lets the aim find an ally at all.
	var weapon := H.make_weapon()
	weapon.template.main_attack.heals = true
	weapon.template.main_attack.hits_allies = true
	healer.equipped_weapon = weapon
	var patient := _spawn(PLAYER, Vector2i(3, 2))
	patient.set_current_hp(1)

	_aim_at(healer, patient.movement.cell)
	await _settle()

	var bar := _unit_mirror.bar_for(patient)
	assert_bool(bar.visible).override_failure_message(
			"the heal put no readout over its target").is_true()
	assert_int(_predicted(patient)).is_greater(patient.get_current_hp())
	# The span is the same SHAPE in both directions, so the structural claim is which cubes it lands
	# on — a heal marks EMPTY sockets it will refill, which is the half a damage prediction cannot
	# produce, and those cubes are still sunk in the plate because the heal has not happened yet.
	assert_int(_grid_predicts(bar, true)).is_equal(_predicted(patient))
	assert_int(bar.doomed_block_count()).is_greater(0)
	assert_bool(bar.block_is_filled(patient.get_current_hp())).override_failure_message(
			"the first cube the heal would restore is already standing, so the readout is claiming "
			+ "health the unit does not have yet").is_false()
	assert_bool(bar.alarm_running()).override_failure_message(
			"a heal raised the felling alarm").is_false()


# ------------------------------------------------------------------------------
#  Law #4: two surfaces, one prediction
# ------------------------------------------------------------------------------

func test_the_queue_panel_and_the_bar_predict_the_same_hp() -> void:
	# Law #2 says the queue never lies; #313 draws that same claim a second place. Two spellings of
	# the display clamp is how they would come to disagree — the panel showed 1 for a predicted down
	# while the raw number the bar would read is negative — so both go through
	# LethalityRules.displayed_hp and this is the case that would catch them parting.
	var attacker := _spawn(PLAYER, Vector2i(2, 2))
	var victim := _spawn(ENEMY, Vector2i(3, 2))
	victim.set_current_hp(2)   # the down case: raw and displayed disagree, so the clamp is in play
	_aim_at(attacker, victim.movement.cell)
	await _settle()

	var bar := _unit_mirror.bar_for(victim)
	var panel_says := _queue_row_after()
	assert_int(panel_says).is_equal(_predicted(victim))
	assert_int(_grid_predicts(bar, false)).is_equal(panel_says)


# ------------------------------------------------------------------------------
#  It stays up THROUGH the pass (#354)
# ------------------------------------------------------------------------------

# The real pass, started but deliberately NOT awaited, so the case can look at the board WHILE it
# runs. `done` is a one-slot array because a coroutine has no other way to hand a fact back.
func _start_pass(unit: Unit, done: Array) -> void:
	await game.order_executor.execute_orders(unit)
	done[0] = true


# The regression the ticket was filed for. Every case above asserts on a plan that never RUNS, which
# is exactly why the suite stayed green while bars winked out one at a time in play.
#
# Two attackers on purpose: a lone attack applies its damage and calls finish_execution() in the same
# synchronous block, so there would be no mid-pass frame to look at. With two, the first hit lands
# while the second is still lunging — the dev's report ("disappearing as soon as each individual unit
# is done") is precisely that gap.
func test_a_readout_survives_its_own_hit_landing_and_leaves_when_the_pass_does() -> void:
	var first := _spawn(PLAYER, Vector2i(2, 2))
	var second := _spawn(PLAYER, Vector2i(2, 3))
	game.squad_manager.join_squad(second, first.squad)   # ONE squad, so ONE plan resolves both aims
	var struck := _spawn(ENEMY, Vector2i(3, 2))
	var waiting := _spawn(ENEMY, Vector2i(3, 3))
	_aim_at(first, struck.movement.cell)
	_aim_at(second, waiting.movement.cell)
	await _settle()

	var struck_hp := struck.get_current_hp()
	var waiting_hp := waiting.get_current_hp()
	assert_bool(_unit_mirror.bar_for(struck).visible).override_failure_message(
			"no readout appeared before the pass, so its surviving one would prove nothing").is_true()

	var done := [false]
	_start_pass(first, done)
	var landed := false
	for _frame in 600:
		await await_idle_frame()
		if done[0] or not is_instance_valid(struck):
			break
		if struck.get_current_hp() != struck_hp:
			landed = true
			break
	assert_bool(landed).override_failure_message(
			"the first hit never landed mid-pass, so there is no moment of impact to check").is_true()
	# One more frame: the mirror POLLS, so the bar the old rule would have hidden is only actually
	# hidden a frame after the HP moved. Asserting on the frame the damage lands passes either way.
	await await_idle_frame()

	assert_bool(done[0]).override_failure_message(
			"the pass finished before the assert, so this case cannot see mid-pass at all").is_false()
	assert_int(waiting.get_current_hp()).override_failure_message(
			"the second hit had already landed, so the pass is not staggered here").is_equal(waiting_hp)
	assert_bool(_unit_mirror.bar_for(struck).visible).override_failure_message(
			"the readout went away at the moment of impact — #354").is_true()

	while not done[0]:
		await await_idle_frame()
	await _settle()
	# And the other half of the ticket: they leave TOGETHER, when the pass ends, not one at a time.
	assert_array(_shown_bars()).is_empty()


# The boundary the display clamp hides. A unit at exactly 1 HP that the plan puts on the floor has a
# predicted HP of 1 (LethalityRules.displayed_hp mirrors _go_downed's cling) and a current HP of 1 —
# so a rule comparing those two numbers reads "this plan does nothing to them" for the single unit
# the plan hurts most. The suite's other down case sits at 2 HP, one point clear of the collision.
func test_a_unit_at_one_hp_the_plan_fells_still_wears_a_readout() -> void:
	var attacker := _spawn(PLAYER, Vector2i(2, 2))
	var victim := _spawn(ENEMY, Vector2i(3, 2))
	victim.set_current_hp(1)
	_aim_at(attacker, victim.movement.cell)
	await _settle()

	assert_int(PlanResolver.projected_lifecycle(victim, _plan().hypo)).override_failure_message(
			"the fixture attack did not fell the victim, so the clamp collision is not in play"
			).is_equal(Unit.LifecycleState.DOWNED)
	# The precondition IS the bug: assert the two displayed numbers really do collide, or this case
	# quietly stops testing the boundary the moment the clamp or the ladder moves.
	assert_int(_predicted(victim)).is_equal(victim.get_current_hp())

	var bar := _unit_mirror.bar_for(victim)
	assert_bool(bar.visible).override_failure_message(
			"a unit this plan fells wears no readout at all — #354").is_true()
	assert_bool(bar.alarm_running()).override_failure_message(
			"the felling alarm never raised, because the visibility gate ran ahead of it").is_true()


# The same collision one rung along, and the reason membership cannot be an HP question alone: a
# Crisis stands the unit back up at exactly CRISIS_REVIVE_HP, so a unit sitting on that number ends
# the pass at the HP it started with. Nothing about its HP moved; everything about its situation did.
func test_a_crisis_at_the_revive_hp_still_wears_a_readout() -> void:
	var attacker := _spawn(PLAYER, Vector2i(2, 2))
	var victim := _spawn(ENEMY, Vector2i(3, 2), true, {Stats.Stat.WIL: UnitInstance.MAX_WILL})
	victim.unit_instance.jobs.append("berserker")   # arms Crisis the way content does (#158)
	victim.set_current_hp(Abilities.CRISIS_REVIVE_HP)
	_aim_at(attacker, victim.movement.cell)
	await _settle()

	var hypo: Dictionary = _plan().hypo
	assert_bool(PlanResolver.plan_fells(victim, hypo)).override_failure_message(
			"the fixture attack did not drive the victim into Crisis, so this case proves nothing"
			).is_true()
	assert_int(PlanResolver.projected_hp(victim, hypo)).override_failure_message(
			"the projection moved the victim's HP, so the collision under test is absent"
			).is_equal(victim.get_current_hp())

	assert_bool(_unit_mirror.bar_for(victim).visible).override_failure_message(
			"a unit this plan drives into Crisis wears no readout at all — #354").is_true()
