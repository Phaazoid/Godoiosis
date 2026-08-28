# Standing squad rings (#423 slice 1). ALWAYS_SHOW_SQUAD_RINGS turns the membership ring from a
# SELECTION marker into a persistent one, and a persistent marker has to follow the unit it belongs
# to -- which is the bug this setting exposed.
#
# Driven through the real seams (spawn, join_squad, leave_squad, a resolution pass) rather than by
# calling the sweep directly, because the claim is that MEMBERSHIP CHANGES reach the channel at all.
# Asserted on OverlayManager's marker store and on the 3D mirror's anchors, never on pixels.
#
# Fixture is test_overlay_mirror's: the Battle3D scene with the boot board cleared.
extends GdUnitTestSuite

# preload, never load(): a per-test load() reloads the 5 MB mesh library every case (#621).
const SCENE: PackedScene = preload("res://Scenes/Battle3D/Battle3D.tscn")
const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER

var _scene: Node3D
var game: Node2D
var _overlays: BoardOverlays


func before_test() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	# This suite SWITCHES the setting on, and _state is a static that outlives a case -- so the
	# wipe is what stops the ON branch leaking into whatever runs next. (Reading the dev's own
	# cfg stopped being possible in #449: a headless process honours nobody's preferences.)
	PlayerSettings.reset_for_test()
	var packed := SCENE
	_scene = packed.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	game = _scene.game
	_overlays = _scene.get_node("BoardOverlays") as BoardOverlays
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	PlayerSettings.reset_for_test()
	get_tree().root.remove_child(_scene)
	_scene.free()


# process_frame resumes coroutines BEFORE node _process, so one frame is stale.
func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


func _om() -> OverlayManager:
	return game.overlay_manager


func _spawn(cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, PLAYER), cell)
	assert_object(unit).is_not_null()   # fixture setup, not the claim under test
	return unit


func _rings_on() -> void:
	PlayerSettings.set_on(PlayerSettings.Setting.ALWAYS_SHOW_SQUAD_RINGS, true)


func _pair() -> Array[Unit]:
	var leader := _spawn(Vector2i(2, 2))
	var member := _spawn(Vector2i(5, 2))
	game.squad_manager.join_squad(member, leader.squad)
	return [leader, member]


func _ringed_units() -> Array[Unit]:
	var ringed: Array[Unit] = []
	for key in _om().icons_by_unit:
		var unit := key as Unit
		if unit != null and _om().icons_by_unit[key].has(OverlayIcon.IconType.SQUADMEMBER):
			ringed.append(unit)
	return ringed


# Somewhere on the board with nobody on it. DERIVED, never a literal: update_hover_visuals returns
# early on a tileless cell, so a hardcoded "look away" cell that stops being painted turns every
# case using it into a silent no-op -- and which tiles exist is authored content (#449).
func _empty_cell() -> Vector2i:
	for cell: Vector2i in game.grid.get_used_cells():
		if game.get_unit_at_cell(cell) == null:
			return cell
	return GridUtils.NO_CELL


# --- The setting -------------------------------------------------------------------

# Off is a promise that nothing changed: the channel still belongs to the selection paths, so the
# setting cannot regress the old board simply by existing.
func test_off_by_default_a_join_leaves_no_standing_ring() -> void:
	assert_bool(PlayerSettings.is_on(PlayerSettings.Setting.ALWAYS_SHOW_SQUAD_RINGS)).is_false()
	_pair()
	await _settle()
	assert_array(_ringed_units()).override_failure_message(
			"a ring stood on the board with the setting OFF -- the selection paths no longer own the channel"
			).is_empty()


func test_on_a_two_member_squad_wears_rings_with_nothing_selected() -> void:
	_rings_on()
	var pair := _pair()
	await _settle()
	var ringed := _ringed_units()
	assert_int(ringed.size()).is_equal(2)
	assert_bool(ringed.has(pair[0]) and ringed.has(pair[1])).is_true()
	# Parity (#292): the 3D view carries the same two, so this is not a 2D-only feature.
	assert_int(_overlays.markers_of(BoardOverlays.Layer.GROUND_ICONS).size()).override_failure_message(
			"the standing rings never reached the 3D ground channel").is_equal(2)


func test_on_solo_squads_wear_none() -> void:
	_rings_on()
	_spawn(Vector2i(2, 2))
	_spawn(Vector2i(5, 2))
	await _settle()
	assert_array(_ringed_units()).override_failure_message(
			"a unit with no squadmates wore a membership ring").is_empty()


# The ring_hue trap. A hue is dealt once at the first squadmate and NEVER reset, so gating the sweep
# on "does this squad have a colour" would leave the leftover member wearing one forever.
func test_on_a_squad_that_shrank_back_to_one_wears_none() -> void:
	_rings_on()
	var pair := _pair()
	await _settle()
	assert_int(_ringed_units().size()).is_equal(2)   # precondition, not the claim
	game.squad_manager.leave_squad(pair[1])
	await _settle()
	assert_bool(pair[0].squad.ring_hue != Color.WHITE).override_failure_message(
			"the shrunken squad lost its dealt hue -- this case no longer covers the trap it was written for"
			).is_true()
	assert_array(_ringed_units()).override_failure_message(
			"a lone unit kept its squad ring -- the sweep is gated on the dealt hue, not on membership"
			).is_empty()


# --- The wire ----------------------------------------------------------------------

# THE bug persistence exposed. A marker used to STORE the cell it was built on and the mirror
# anchored on that copy; markers rebuilt every repaint hid it, but a standing ring outlives the
# move, so the copy went stale and the ring stayed on the cell its unit walked off (#308).
func test_a_standing_ring_follows_the_unit_that_moved() -> void:
	_rings_on()
	var pair := _pair()
	await _settle()
	var moved_to := Vector2i(5, 5)
	pair[1].movement.set_cell(moved_to)
	await _settle()
	var heights: BoardHeights = game.board_heights
	var expected := BoardSpace.surface_transform(moved_to, heights).origin
	var found := false
	for marker: Dictionary in _overlays.markers_of(BoardOverlays.Layer.GROUND_ICONS):
		if (marker["pos"] as Vector3).is_equal_approx(expected):
			found = true
	assert_bool(found).override_failure_message(
			"no ring sits on the cell the unit moved to -- the anchor is a stored copy again"
			).is_true()


# The rings stand down for the WHOLE resolution pass (a marker sits on its unit's projected
# destination, which mid-pass is a cell the unit has not reached) and come back on the settled
# board. The restore is last in _end_squad_turn because that method OPENS by clearing the channel --
# an ordering no assertion about the two ends could catch.
func test_rings_come_back_after_a_pass_settles() -> void:
	_rings_on()
	var pair := _pair()
	await _settle()
	assert_int(_ringed_units().size()).is_equal(2)   # precondition, not the claim
	await game.order_executor.execute_orders(pair[0])
	await _settle()
	assert_int(_ringed_units().size()).override_failure_message(
			"the standing rings never came back after the pass -- the restore runs before the clear"
			).is_equal(2)


# The per-squad redraw clears the WHOLE icon channel and then draws ONE squad, and HoverPresenter
# calls it on every hover-move preview. Standing rings are the first thing that ever needed to
# survive that, so without a standing set inside the redraw, hovering one squad silently strips
# every OTHER squad's rings -- the state the board would sit in for most of a feel-test.
func test_hovering_one_squad_keeps_another_squads_standing_rings() -> void:
	_rings_on()
	var first := _pair()
	var second_leader := _spawn(Vector2i(8, 2))
	var second_member := _spawn(Vector2i(9, 2))
	game.squad_manager.join_squad(second_member, second_leader.squad)
	await _settle()
	assert_int(_ringed_units().size()).is_equal(4)   # precondition, not the claim
	# The seam HoverPresenter drives when the cursor crosses a reachable cell.
	game.overlay_manager.redraw_squad_unit_icons(first[0].squad)
	await _settle()
	var ringed := _ringed_units()
	assert_bool(ringed.has(second_leader) and ringed.has(second_member)).override_failure_message(
			"the other squad lost its standing rings when this one was redrawn -- a per-squad redraw clears the whole channel"
			).is_true()
	assert_int(ringed.size()).is_equal(4)


# THE BUG THE DEV FOUND BY PLAYING (2026-08-21): rings drew at load and then vanished, and only a
# hover brought them back. _hover_idle clears the icon channel on EVERY hover change while nothing
# is selected -- hovering bare ground included -- so the first mouse movement after the board came
# up wiped the standing set. Every case above passed because none of them ever moved the mouse,
# which is the one thing a player does constantly.
func test_hovering_empty_ground_does_not_wipe_the_standing_rings() -> void:
	_rings_on()
	var pair := _pair()
	await _settle()
	assert_int(_ringed_units().size()).is_equal(2)   # precondition, not the claim
	# The real seam: HoverPresenter's IDLE branch, over a cell with no unit on it.
	var empty := _empty_cell()
	assert_bool(empty != GridUtils.NO_CELL).override_failure_message(
			"the fixture board has no empty painted tile to look away at").is_true()
	game.hover_presenter.update_hover_visuals(empty)
	await _settle()
	var ringed := _ringed_units()
	assert_bool(ringed.has(pair[0]) and ringed.has(pair[1])).override_failure_message(
			"moving the cursor over empty ground wiped the standing rings -- a SELECTION clear is removing markers the selection does not own"
			).is_true()


# The same clear, reached the other way: hovering a unit that is not in a standing squad.
func test_hovering_a_solo_unit_does_not_wipe_another_squads_standing_rings() -> void:
	_rings_on()
	var pair := _pair()
	var loner := _spawn(Vector2i(9, 6))
	await _settle()
	assert_int(_ringed_units().size()).is_equal(2)   # the loner has no squadmates, so no ring
	game.hover_presenter.update_hover_visuals(loner.movement.cell)
	await _settle()
	var ringed := _ringed_units()
	assert_bool(ringed.has(pair[0]) and ringed.has(pair[1])).override_failure_message(
			"hovering an unsquadded unit wiped the other squad's standing rings"
			).is_true()


# THE OTHER BRANCH OF #449, and the dev's ruling on it (2026-08-21): a standing squad wears its
# rings AND its leader's crown, so the crown does not come down on the way out of a hover.
# test_overlay_mirror pins the setting-OFF twin -- there the hover-raised crown DOES clear -- and
# that case went red on the dev's own machine precisely because nothing said this branch existed.
func test_the_crown_stands_with_the_rings_and_outlives_a_hover_out() -> void:
	_rings_on()
	var pair := _pair()
	await _settle()
	var crown: Texture2D = OverlayManager.ICON_TEXTURES[OverlayIcon.IconType.CROWN]
	assert_int(_overlays.markers_of(BoardOverlays.Layer.ICONS).size()).override_failure_message(
			"the standing sweep put rings down without the leader's crown").is_equal(1)

	# Hover the MEMBER and then look away: the clear that raises a selection crown and drops it.
	game.hover_presenter.update_hover_visuals(pair[1].movement.cell)
	await _settle()
	var empty := _empty_cell()
	assert_bool(empty != GridUtils.NO_CELL).override_failure_message(
			"the fixture board has no empty painted tile to look away at").is_true()
	game.hover_presenter.update_hover_visuals(empty)
	await _settle()

	var heads := _overlays.markers_of(BoardOverlays.Layer.ICONS)
	assert_int(heads.size()).override_failure_message(
			"the leader's crown came down with the hover -- a standing squad wears BOTH"
			).is_equal(1)
	# Searched rather than indexed: an empty channel is the very thing this case catches, and
	# heads[0] would ERROR out of the case instead of failing it with the message above.
	var still_crowned := false
	for marker in heads:
		if marker["texture"] == crown:
			still_crowned = true
	assert_bool(still_crowned).override_failure_message(
			"what survived on the head channel is not the crown").is_true()
	assert_int(_ringed_units().size()).override_failure_message(
			"the rings came down with the hover").is_equal(2)


# --- Solo units wear no ring (#441) ------------------------------------------------

# The dev found this in Prolog: a solo unit flashed a WHITE ring between AI turns. redraw_squad_unit_icons
# drew a ring for every member of whatever squad it was handed, and two of its three callers had no
# membership gate -- so a solo squad, whose ring_hue is still the UNDEALT Color.WHITE sentinel, wore one.
# Predates the standing-rings setting entirely (verified identical on main), so this drives the DEFAULT
# off state; the case below covers the setting-on half.
#
# Driven through the executor rather than the seam, because the timing is the tell: _end_squad_turn
# drains the queue with remove_action, each firing action_cancelled -> game._on_unit_action_cancelled
# -> the ungated redraw. That is exactly "after one ends their move and another starts theirs".
func test_a_solo_unit_wears_no_ring_after_its_turn_resolves() -> void:
	var loner := _spawn(Vector2i(3, 3))
	assert_bool(loner.squad.has_squadmates()).is_false()   # fixture setup, not the claim
	# The hold order a squad's own activation queues -- what puts an action in the queue for
	# _end_squad_turn to cancel.
	game.squad_manager.setup_hold_move_actions(loner.squad)
	await game.order_executor.execute_orders(loner)
	await _settle()
	assert_array(_ringed_units()).override_failure_message(
			"a solo unit wore a squad ring -- ring_hue's undealt WHITE sentinel reached the screen as a colour"
			).is_empty()
	assert_int(_overlays.markers_of(BoardOverlays.Layer.GROUND_ICONS).size()).override_failure_message(
			"the solo ring reached the 3D ground channel").is_equal(0)


# The same, with standing rings ON: a solo squad is still not membership, so the setting must not
# become a second way for one to appear.
func test_a_solo_unit_wears_no_ring_with_standing_rings_on() -> void:
	_rings_on()
	var pair := _pair()
	var loner := _spawn(Vector2i(3, 3))
	await _settle()
	assert_int(_ringed_units().size()).override_failure_message(
			"the standing sweep drew a ring for the solo squad").is_equal(2)
	game.squad_manager.setup_hold_move_actions(loner.squad)
	await game.order_executor.execute_orders(loner)
	await _settle()
	var ringed := _ringed_units()
	assert_bool(ringed.has(loner)).override_failure_message(
			"the solo unit picked up a ring when its own turn resolved").is_false()
	assert_bool(ringed.has(pair[0]) and ringed.has(pair[1])).override_failure_message(
			"the real squad lost its standing rings when a solo unit's turn resolved"
			).is_true()
