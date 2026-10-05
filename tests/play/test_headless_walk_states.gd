# What a headless walk does to its walker (#884), played where the game plays it (#46). The headless
# pass teleported every mover and never applied a walk's own states, so a wader came out of the ford
# dry headlessly while the queue said WET. Both hosts now play ResolvedPlan.walk_moments, which also
# puts the soaking BEFORE a shot that lands on the walker after it -- the ordering
# tests/flow/test_watch_shot_interrupts_the_walk.gd pins game-side. Every case holds the board to the
# preview's own projection, so none pins what a shock does to a soaked unit.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const SHALLOW_WATER := Vector2i(6, 6)   # TestTiles' wadeable water (#116)
const FORD := Vector2i(2, 0)


func after_test() -> void:
	ReactionCatalog.refresh()   # H.only_electrocution's catalog goes with the case


func _data(unit_name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, fac)


# {board, session, crosser}: a crosser at (0,0) west of a one-cell ford.
func _ford(root_name: String) -> Dictionary:
	var b := BoardBuilder.build(self, root_name)
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 10, 10))
	BoardBuilder.paint_cell(b.grid, FORD, SHALLOW_WATER)
	var crosser: Unit = BoardBuilder.spawn(b, _data("Crosser", PLAYER), Vector2i(0, 0))
	crosser.equipped_weapon = H.make_weapon(4)
	crosser.unit_instance.stats[Stats.Stat.MHP] = 80
	crosser.set_current_hp(crosser.get_max_hp())
	return {"board": b, "crosser": crosser}


func _sorted(states: Array[Elemental.State]) -> Array[Elemental.State]:
	var copy: Array[Elemental.State] = states.duplicate()
	copy.sort()
	return copy


# Queues the crosser's walk east to x = 3 through the ford, executes, and answers what the preview
# projected for it before the pass ran.
func _cross(sess, crosser: Unit) -> Array[Elemental.State]:
	var moved: Dictionary = sess.queue_move(sess.handle_for(crosser), Vector2i(3, 0))
	assert_bool(moved.ok).override_failure_message("fixture: the walk did not queue: %s" % str(moved.get("error", ""))).is_true()
	var sm: SquadManager = sess.squad_manager
	var plan: ResolvedPlan = sm.resolve_plan(crosser.squad, sess._board())
	var walk: MoveAction = null
	for action in crosser.squad.action_queue:
		if action is MoveAction and action.actor == crosser:
			walk = action as MoveAction
	assert_bool(walk != null and walk.get_move_path().has(FORD)) \
		.override_failure_message("fixture: the walk does not cross the ford").is_true()
	assert_bool(walk.resolved != null and walk.resolved.states_added.has(Elemental.State.WET)) \
		.override_failure_message("fixture: the walk soaked nobody").is_true()
	var predicted := _sorted(PlanResolver.projected_states(crosser, plan.hypo))
	assert_bool((sess.execute() as Dictionary).ok).override_failure_message("the pass did not execute").is_true()
	return predicted


func test_a_wader_comes_out_of_the_ford_as_the_preview_said() -> void:
	var f := _ford("HeadlessWadeRoot")
	var crosser: Unit = f.crosser
	var sess = PlaySession.new(f.board)

	var predicted := _cross(sess, crosser)

	assert_bool(predicted.has(Elemental.State.WET)).override_failure_message(
			"fixture: the preview does not soak the wader").is_true()
	assert_array(_sorted(crosser.element_states)).override_failure_message(
			"the wader ended the pass %s where the preview said %s" % [str(crosser.element_states), str(predicted)]) \
		.is_equal(predicted)


# The crosser shape: a shock watch over the ford fires on the step that soaks the crosser, so the
# soaking has to land before the shot does, or the shot strips nothing and the crosser walks off wet.
func test_a_crosser_shocked_mid_ford_ends_the_pass_as_the_preview_said() -> void:
	H.only_electrocution()
	var f := _ford("HeadlessShockedFordRoot")
	var crosser: Unit = f.crosser
	var watcher: Unit = BoardBuilder.spawn(f.board, _data("Watcher", ENEMY), Vector2i(2, 3))
	watcher.equipped_weapon = H.make_weapon(4)
	(watcher.get_equipped_weapon() as WeaponInstance).template.main_attack.elemental_damage_type = \
		Elemental.Element.SHOCK
	var footprint: Array[Vector2i] = [FORD]
	watcher.arm_watch(watcher.movement.cell, FORD, footprint, watcher.get_default_attack())
	assert_object(watcher.watch).override_failure_message("fixture: the watch did not arm").is_not_null()
	var sess = PlaySession.new(f.board)

	var predicted := _cross(sess, crosser)

	assert_bool(predicted.has(Elemental.State.WET)).override_failure_message(
			"fixture: the preview keeps the crosser wet, so the shot stripped nothing").is_false()
	assert_array(_sorted(crosser.element_states)).override_failure_message(
			"the crosser ended the pass %s where the preview said %s" % [str(crosser.element_states), str(predicted)]) \
		.is_equal(predicted)


# The other side of the same order: a shot the walk took BEFORE the water lands before the soaking.
# The walker starts Chilled, which keeps a soaking off (#1092), and a fire watch short of the ford
# thaws it -- so the resolve soaks it at the ford and the preview ends WET. Soaking it any earlier
# meets the Chill still standing, and it walks off dry.
func test_a_soaking_lands_after_a_shot_the_walk_took_before_the_water() -> void:
	var thaw: Array[ElementalReaction] = [H.stripping(Elemental.Element.FIRE, Elemental.State.CHILLED)]
	H.only_reactions(thaw)
	var f := _ford("HeadlessThawedFordRoot")
	var crosser: Unit = f.crosser
	crosser.add_element_state(Elemental.State.CHILLED, 3)
	var short_of_the_ford := Vector2i(1, 0)
	var watcher: Unit = BoardBuilder.spawn(f.board, _data("Watcher", ENEMY), Vector2i(1, 3))
	watcher.equipped_weapon = H.make_weapon(4)
	(watcher.get_equipped_weapon() as WeaponInstance).template.main_attack.elemental_damage_type = \
		Elemental.Element.FIRE
	var footprint: Array[Vector2i] = [short_of_the_ford]
	watcher.arm_watch(watcher.movement.cell, short_of_the_ford, footprint, watcher.get_default_attack())
	assert_object(watcher.watch).override_failure_message("fixture: the watch did not arm").is_not_null()
	var sess = PlaySession.new(f.board)

	var predicted := _cross(sess, crosser)

	assert_bool(predicted.has(Elemental.State.WET)).override_failure_message(
			"fixture: the preview does not soak the thawed walker").is_true()
	assert_array(_sorted(crosser.element_states)).override_failure_message(
			"the walker ended the pass %s where the preview said %s" % [str(crosser.element_states), str(predicted)]) \
		.is_equal(predicted)
