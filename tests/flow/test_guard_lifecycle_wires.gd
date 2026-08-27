# Guard's three GAME-LEVEL wires (#414), each of which is a whole feature that can be missing while
# every rule test stays green — #103's shape, three times over:
#
#   1. The lapse tick. "Lapses when its owner's faction's next turn begins" is one line in
#      game._run_turn_start_ticks; without it a Guard is immortal and the rule tests never notice,
#      because they call Unit.lapse_guard directly.
#   2. The ground markers. An armed Guard has to be visible on the board through the enemy phase,
#      which means it cannot ride the selection channel — and the refresh has to actually be called.
#   3. The save round trip. A live ward is battle state, and it is a PAIR, so it can only round-trip
#      through the entry-index re-link ScenarioManager owns.
#
# Fixture is the shared game-scene one -- see tests/README.md -> Testing the game scene.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(8):
		for y in range(3):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.LDR: 10}, faction), cell)
	assert_object(unit).is_not_null()
	return unit


# The WARD's half: the shield decal. Since #450 the blocker never wears one -- ask _guard_linked.
func _guard_marked(unit: Unit) -> bool:
	var icons: Dictionary = game.overlay_manager.icons_by_unit
	if not icons.has(unit):
		return false
	return (icons[unit] as Dictionary).has(OverlayIcon.IconType.GUARD_WARD)


# The BLOCKER's half: the arrow trail aimed at its ward (#450). Counted rather than merely
# non-empty, because a one-step trail is exactly two sprites (a start tile and an arrowhead) and
# "some arrows exist somewhere" would pass against a link drawn for the wrong pair.
func _guard_link_count() -> int:
	var sprites: Array[Sprite2D] = game.overlay_manager.guard_link_sprites
	var live := 0
	for sprite in sprites:
		if is_instance_valid(sprite):
			live += 1
	return live


func _guard_linked() -> bool:
	return _guard_link_count() == 2


# The GHOSTED pair a queued-but-unarmed Guard draws (#450 part 2). Counted as one shield plus a
# two-sprite trail, the same shape the armed pair is asserted at.
func _guard_preview_count() -> int:
	var om = game.overlay_manager
	return (om.guard_preview_icons as Array).size() + (om.guard_preview_links as Array).size()


# Where the link's TAIL sits -- the start tile, which is the only half still anchored to a cell.
# Read back through the grid rather than compared as world floats, since GridUtils.cell_world placed
# it and this is that call's own inverse.
func _guard_link_tail_cell() -> Vector2i:
	var sprites: Array[Sprite2D] = game.overlay_manager.guard_link_sprites
	return game.grid.local_to_map(game.grid.to_local(sprites[0].global_position))


# Where the link's HEAD sits, in world pixels. Deliberately NOT a cell: since #450 round 2 the head
# is inset half a cell so the ward's shield is legible under it, which puts it ON the boundary --
# where local_to_map answers with whichever side the floor lands on and would read as the blocker's
# own cell. The position is the fact; the cell is not.
func _guard_link_head_pos() -> Vector2:
	var sprites: Array[Sprite2D] = game.overlay_manager.guard_link_sprites
	return sprites[sprites.size() - 1].global_position


# --- 1. the lapse tick --------------------------------------------------------------------------

func test_a_factions_turn_start_lapses_its_own_guards_and_leaves_the_others() -> void:
	var player_blocker := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var player_ward := _spawn(Team.Faction.PLAYER, Vector2i(2, 0))
	var enemy_blocker := _spawn(Team.Faction.ENEMY, Vector2i(5, 0))
	var enemy_ward := _spawn(Team.Faction.ENEMY, Vector2i(6, 0))
	await await_idle_frame()
	player_blocker.arm_guard(player_ward, player_blocker.get_guard_range())
	enemy_blocker.arm_guard(enemy_ward, enemy_blocker.get_guard_range())

	game.turn_manager.turn_started.emit(Team.Faction.PLAYER)
	await await_idle_frame()

	assert_object(player_blocker.guard) \
		.override_failure_message("the player's Guard survived its own turn start -- it is immortal") \
		.is_null()
	assert_object(enemy_blocker.guard) \
		.override_failure_message("a turn start lapsed somebody ELSE's Guard") \
		.is_not_null()


# --- 2. the ground markers ----------------------------------------------------------------------

func test_an_armed_guard_shields_the_ward_and_points_a_link_at_it_from_the_blocker() -> void:
	# #450 replaced #414's marks-both-ends rule, which this case used to carry IN ITS NAME. The
	# board has to say which end is which -- both ends wearing the same shield said only that the
	# two were connected, and the direction was readable off the queue row alone, i.e. not at all
	# during the enemy phase.
	var blocker := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var ward := _spawn(Team.Faction.PLAYER, Vector2i(2, 0))
	await await_idle_frame()
	blocker.arm_guard(ward, blocker.get_guard_range())

	game.refresh_guard_markers()

	assert_bool(_guard_marked(ward)).override_failure_message(
		"no shield under the WARD -- it is the one end that wears one").is_true()
	assert_bool(_guard_marked(blocker)).override_failure_message(
		"the BLOCKER wears a shield; #450 gave it the arrow's tail instead").is_false()
	assert_bool(_guard_linked()).override_failure_message(
		"expected a two-sprite link from blocker to ward, got %d sprites" % _guard_link_count()) \
		.is_true()


func test_queueing_and_executing_a_guard_leaves_the_marker_on_the_board() -> void:
	# THE sequence a player performs, which every other case in this file skips: queue the order,
	# press Execute, look at the board. The cases below arm the ward by calling arm_guard and then
	# call refresh_guard_markers by hand — i.e. they set the state directly instead of driving the
	# real path, which is the blind spot #114 exists to name. If the marker never appears in play,
	# this is the case that says so.
	var blocker := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var ward := _spawn(Team.Faction.PLAYER, Vector2i(2, 0))
	var _enemy := _spawn(Team.Faction.ENEMY, Vector2i(6, 0))
	await await_idle_frame()
	game.squad_manager.join_squad(ward, blocker.squad)

	game.queue_guard(blocker, ward)
	assert_bool(blocker.has_action_type_queued(BaseAction.ActionType.GUARD)) \
		.override_failure_message("fixture failed to queue the Guard").is_true()

	await game.order_executor.execute_orders(blocker.squad.get_leader())

	assert_object(blocker.guard) \
		.override_failure_message("the pass did not arm the Guard at all").is_not_null()
	assert_bool(_guard_marked(ward)) \
		.override_failure_message("no ground marker under the WARD after a real queue-and-execute") \
		.is_true()
	assert_bool(_guard_linked()) \
		.override_failure_message("no link from the BLOCKER after a real queue-and-execute") \
		.is_true()


func test_a_queued_guard_previews_ghosted_and_goes_solid_once_it_arms() -> void:
	# A Guard was the only queued verb that showed NOTHING on the board until Execute (#450 part 2):
	# a move gets arrows and a ghost, an ignite gets a ghosted icon, a Guard got a queue row. It now
	# draws the same pair the armed one does, at the plan-time alpha -- and the difference matters,
	# because identical marks would tell the player they are covered while the cover is still a plan.
	var blocker := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var ward := _spawn(Team.Faction.PLAYER, Vector2i(2, 0))
	var _enemy := _spawn(Team.Faction.ENEMY, Vector2i(6, 0))
	await await_idle_frame()
	game.squad_manager.join_squad(ward, blocker.squad)

	game.queue_guard(blocker, ward)
	await await_idle_frame()

	assert_int(_guard_preview_count()).override_failure_message(
		"a queued Guard drew no ghost -- it is the only queued verb that previews nothing") \
		.is_equal(3)
	assert_bool(_guard_marked(ward)).override_failure_message(
		"the queued Guard drew a SOLID shield -- the board is promising cover that is not live yet") \
		.is_false()
	assert_int(_guard_link_count()).override_failure_message(
		"the queued Guard drew a solid link").is_equal(0)
	var ghost: Sprite2D = game.overlay_manager.guard_preview_icons[0]
	assert_float(ghost.modulate.a).override_failure_message(
		"the ghost is as opaque as an armed ward, so the board cannot say 'not yet'") \
		.is_less(OverlayManager.GUARD_RING_COLOR.a)

	await game.order_executor.execute_orders(blocker.squad.get_leader())

	assert_int(_guard_preview_count()).override_failure_message(
		"the ghost outlived the plan it previewed and now sits beside the real mark").is_equal(0)
	assert_bool(_guard_marked(ward)).override_failure_message(
		"the armed shield never replaced the ghost").is_true()
	assert_bool(_guard_linked()).override_failure_message(
		"the armed link never replaced the ghost").is_true()


func test_queueing_a_move_drags_the_link_along_with_the_shield() -> void:
	# #450's fourth refresh moment, and the one the other three cannot cover. The ward's shield is an
	# OverlayIcon that re-reads its own projected cell every frame; the blocker's link is a static
	# sprite. Without the refresh_guard_markers call in refresh_action_queue the shield walks and the
	# arrow stays, pointing at a cell nobody is standing on -- and every case above still passes,
	# because none of them ever changes a plan. Driven through squad_manager.queue_action so the real
	# squad_action_queued -> refresh_action_queue chain is what does the work.
	var blocker := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var ward := _spawn(Team.Faction.PLAYER, Vector2i(2, 0))
	await await_idle_frame()
	game.squad_manager.join_squad(ward, blocker.squad)
	blocker.arm_guard(ward, blocker.get_guard_range())
	game.refresh_guard_markers()
	assert_bool(_guard_linked()).override_failure_message("fixture drew no link to begin with").is_true()

	var move := MoveAction.new()
	move.init(blocker, [Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)], null)
	assert_bool(game.squad_manager.queue_action(blocker.squad, move)) \
		.override_failure_message("fixture failed to queue the move").is_true()
	await await_idle_frame()

	assert_vector(blocker.get_projected_destination()) \
		.override_failure_message("fixture's move did not move the projection").is_equal(Vector2i(2, 1))
	assert_bool(_guard_linked()).override_failure_message(
		"the link vanished instead of following -- (2,1) is still adjacent to the ward").is_true()
	assert_vector(_guard_link_tail_cell()).override_failure_message(
		"the link still starts from the cell the blocker LEFT").is_equal(Vector2i(2, 1))
	# The head lands on the segment the moved pair now SHARES -- strictly between the two centres.
	# Pinned as a RELATIONSHIP, exactly like the case below and for exactly its reason: the inset is a
	# Game-tab knob. This line used to assert `from.lerp(to, 0.5)`, which pinned the knob's VALUE while
	# claiming not to, and the dev's own tuning pass (0.5 -> 0.4, `c70c2e9`) reddened a case about
	# whether the arrow FOLLOWED. Any inset the dev can dial still passes; an arrow left on the cell
	# the blocker vacated is off this line entirely. Tuning razor, tests/README.md #8.
	var from := GridUtils.cell_world(game.grid, Vector2i(2, 1))
	var to := GridUtils.cell_world(game.grid, Vector2i(2, 0))
	var head := _guard_link_head_pos()
	var span := to - from
	assert_float(absf(span.cross(head - from)) / span.length()).override_failure_message(
		"the head is off the line between the moved blocker and its ward").is_less(0.5)
	var along := (head - from).dot(span) / span.length_squared()
	assert_float(along).override_failure_message(
		"the head never left the blocker's own cell centre").is_greater(0.0)
	assert_float(along).override_failure_message(
		"the head ran past the ward's centre").is_less(1.0)


func test_the_link_head_stops_short_of_the_cell_the_shield_is_on() -> void:
	# Round 2, found in play: "the shield just isn't as readable as I'd like it to be under the
	# arrowhead." The arrow tile's ink runs x=0..11 of 16 and the shield's x=1..13, so drawn on the
	# ward's own cell the arrow covered eleven of the shield's thirteen columns.
	#
	# Pinned as a RELATIONSHIP against the ward's centre, never as the inset's number -- that value
	# is a Game-tab knob and the tuning razor forbids a test that reddens when the dev turns it.
	# What must stay true is only the direction: the head sits strictly BLOCKER-side of the shield.
	var blocker := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var ward := _spawn(Team.Faction.PLAYER, Vector2i(2, 0))
	await await_idle_frame()
	blocker.arm_guard(ward, blocker.get_guard_range())

	game.refresh_guard_markers()

	var ward_centre := GridUtils.cell_world(game.grid, Vector2i(2, 0))
	var blocker_centre := GridUtils.cell_world(game.grid, Vector2i(1, 0))
	var head := _guard_link_head_pos()
	assert_float(head.distance_to(ward_centre)).override_failure_message(
		"the head sits ON the ward's cell centre, i.e. on top of the shield") \
		.is_greater(0.0)
	assert_float(head.distance_to(blocker_centre)).override_failure_message(
		"the head was inset PAST the blocker -- it should stop between the pair, not behind it") \
		.is_greater(0.0)
	assert_float(head.distance_to(ward_centre)).override_failure_message(
		"the head is closer to the ward than to the blocker, so it still crowds the shield") \
		.is_less_equal(head.distance_to(blocker_centre))


func test_a_spent_guard_stops_being_marked() -> void:
	# It protects nobody now; leaving the mark up would promise cover that is gone.
	var blocker := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var ward := _spawn(Team.Faction.PLAYER, Vector2i(2, 0))
	await await_idle_frame()
	blocker.arm_guard(ward, blocker.get_guard_range())
	game.refresh_guard_markers()

	blocker.spend_guard()
	game.refresh_guard_markers()

	assert_bool(_guard_marked(ward)).is_false()
	assert_int(_guard_link_count()).override_failure_message(
		"a spent Guard left its link on the board").is_equal(0)


func test_a_guard_marker_survives_a_selection_clear() -> void:
	# The whole reason it is not on the selection channel: a standing reaction has to stay readable
	# while the player clicks elsewhere and all through the enemy's phase.
	var blocker := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var ward := _spawn(Team.Faction.PLAYER, Vector2i(2, 0))
	await await_idle_frame()
	blocker.arm_guard(ward, blocker.get_guard_range())
	game.refresh_guard_markers()

	game.clear_selection_icons()

	assert_bool(_guard_marked(ward)).is_true()
	assert_bool(_guard_linked()).override_failure_message(
		"the link went with the selection channel -- it must outlive a selection clear too").is_true()


# --- 3. the save round trip ---------------------------------------------------------------------

func test_a_live_guard_survives_a_capture_and_apply() -> void:
	var blocker := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var ward := _spawn(Team.Faction.PLAYER, Vector2i(2, 0))
	await await_idle_frame()
	game.squad_manager.join_squad(ward, blocker.squad)
	blocker.arm_guard(ward, blocker.get_guard_range())

	var snapshot: ScenarioData = game.scenario_manager.capture_scenario("guard-roundtrip")
	game.scenario_manager.clear_board()
	game.scenario_manager.apply_scenario(snapshot)
	await await_idle_frame()

	var reloaded_blocker: Unit = game.get_unit_at_cell(Vector2i(1, 0))
	var reloaded_ward: Unit = game.get_unit_at_cell(Vector2i(2, 0))
	assert_object(reloaded_blocker).override_failure_message("the board did not reload").is_not_null()
	assert_object(reloaded_blocker.guard) \
		.override_failure_message("the Guard was lost on save/load").is_not_null()
	assert_object(reloaded_blocker.guard.ward).is_same(reloaded_ward)
	assert_bool(reloaded_blocker.guard.spent).is_false()


func test_a_spent_guard_round_trips_as_spent() -> void:
	# The other half: "already used" and "never had one" are different facts, and a save that
	# forgot the flag would hand the player a fresh block on load.
	var blocker := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var ward := _spawn(Team.Faction.PLAYER, Vector2i(2, 0))
	await await_idle_frame()
	game.squad_manager.join_squad(ward, blocker.squad)
	blocker.arm_guard(ward, blocker.get_guard_range())
	blocker.spend_guard()

	var snapshot: ScenarioData = game.scenario_manager.capture_scenario("guard-roundtrip-spent")
	game.scenario_manager.clear_board()
	game.scenario_manager.apply_scenario(snapshot)
	await await_idle_frame()

	var reloaded_blocker: Unit = game.get_unit_at_cell(Vector2i(1, 0))
	assert_object(reloaded_blocker.guard).is_not_null()
	assert_bool(reloaded_blocker.guard.spent).is_true()


func test_a_board_with_no_guards_round_trips_with_none() -> void:
	# The control for both cases above: without it they pass against a loader that arms everybody.
	var a := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var b := _spawn(Team.Faction.PLAYER, Vector2i(2, 0))
	await await_idle_frame()
	game.squad_manager.join_squad(b, a.squad)

	var snapshot: ScenarioData = game.scenario_manager.capture_scenario("guard-roundtrip-none")
	game.scenario_manager.clear_board()
	game.scenario_manager.apply_scenario(snapshot)
	await await_idle_frame()

	assert_object((game.get_unit_at_cell(Vector2i(1, 0)) as Unit).guard).is_null()
	assert_object((game.get_unit_at_cell(Vector2i(2, 0)) as Unit).guard).is_null()
