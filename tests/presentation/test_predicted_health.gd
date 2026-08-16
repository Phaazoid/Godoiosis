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
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_scene)
	_scene.free()


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


func _spawn(faction: Team.Faction, cell: Vector2i, armed := true) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
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

func test_the_notch_sits_at_the_hp_the_plan_predicts() -> void:
	var attacker := _spawn(PLAYER, Vector2i(2, 2))
	var victim := _spawn(ENEMY, Vector2i(3, 2))
	_aim_at(attacker, victim.movement.cell)
	await _settle()

	var bar := _unit_mirror.bar_for(victim)
	var predicted := _predicted(victim)
	# Non-vacuity: a notch at 0 or at full would satisfy a loose tolerance without saying anything.
	# This is a precondition on the FIXTURE (did the hit land, did it leave them standing), stated
	# as a message rather than as a threshold the tuning could move.
	assert_bool(predicted > 0 and predicted < victim.get_max_hp()).override_failure_message(
			"the fixture attack did not wound-but-spare the victim, so the notch proves nothing"
			).is_true()

	var expected := float(predicted) / float(victim.get_max_hp())
	# Within one texel of the bar's OWN width: the notch is pixel-snapped like the fill, so the
	# achievable precision is a function of a width knob and asserting tighter would let a tuning
	# value turn this red.
	assert_float(bar.notch_fraction()).is_equal_approx(expected, 1.0 / bar.track_texels())
	# And the span between now and then is actually drawn, or the notch is a mark on nothing.
	assert_float(bar.doomed_fraction()).is_greater(0.0)


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
	assert_float(bar.notch_fraction()).is_equal_approx(1.0 / float(victim.get_max_hp()),
			1.0 / bar.track_texels())
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
	# The span is the same SHAPE in both directions, so the only structural claim is which side of
	# the fill it lands on — above it for a heal, and drawn rather than collapsed to nothing.
	assert_float(bar.notch_fraction()).is_greater(bar.fill_fraction())
	assert_float(bar.doomed_fraction()).is_greater(0.0)
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
	assert_float(bar.notch_fraction()).is_equal_approx(
			float(panel_says) / float(victim.get_max_hp()), 1.0 / bar.track_texels())
