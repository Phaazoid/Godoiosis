# The hover health readout (#229): does pointing at a unit actually put a bar over it, does that
# bar say what the UNIT says, and does it follow the thing that is on screen?
#
# This is a WIRE, which is why every case drives the real chain rather than calling the bar:
# battle3d's picked cell -> HoverPresenter.pointer_source -> last_hovered_cell -> unit_at_pointer
# -> UnitMirror -> UnitHealthBar. Both ends of that chain were already correct and unconnected
# before this ticket, which is #103's shape exactly. Setting _pointer_cell is the one shortcut,
# and it stands in for moving the mouse — everything downstream of the picker is under test.
#
# Fixture is test_overlay_mirror's: the Battle3D scene with the boot board cleared and units
# spawned by hand, so nothing here can be reddened by a content commit repainting a mission.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER

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


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).is_not_null()   # fixture setup, not the claim under test
	return unit


# Move the pointer, the way the picker does. Everything past this line is the wire under test:
# battle3d hands the cell to HoverPresenter, which resolves the unit, which UnitMirror reads.
func _point_at(cell: Vector2i) -> void:
	var heights: BoardHeights = game.board_heights
	_scene._pointer_cell = BoardSpace.of_cell(cell, heights.elevation_at(cell))


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


func test_pointing_at_a_unit_puts_a_readout_over_that_unit_alone() -> void:
	var target := _spawn(PLAYER, Vector2i(2, 2))
	var bystander := _spawn(PLAYER, Vector2i(6, 2))
	_point_at(target.movement.cell)
	await _settle()

	# The claim is EXCLUSIVITY, not "a bar exists": a readout that shows over everybody is the
	# same failure as one that shows over nobody, and only one of those is visible in a screenshot.
	assert_array(_shown_bars()).contains_exactly([target])
	assert_bool(_unit_mirror.bar_for(bystander).visible).is_false()


func test_pointing_at_empty_ground_puts_every_readout_away() -> void:
	var unit := _spawn(PLAYER, Vector2i(2, 2))
	_point_at(unit.movement.cell)
	await _settle()
	assert_bool(_unit_mirror.bar_for(unit).visible).override_failure_message(
			"the readout never appeared, so its disappearing proves nothing").is_true()

	_point_at(Vector2i(9, 9))
	await _settle()
	assert_array(_shown_bars()).is_empty()


func test_the_fill_says_what_the_unit_says() -> void:
	var unit := _spawn(PLAYER, Vector2i(2, 2))
	unit.set_current_hp(int(unit.get_max_hp() * 0.4))
	_point_at(unit.movement.cell)
	await _settle()

	var bar := _unit_mirror.bar_for(unit)
	var expected := float(unit.get_current_hp()) / float(unit.get_max_hp())
	# Within one texel of the bar's OWN width, read off the bar rather than pinned: the fill is
	# rounded to whole texels on purpose, so the achievable precision is a function of a tuning
	# value, and asserting tighter than that would make a width knob able to turn the suite red.
	var quantum := 1.0 / bar.track_texels()
	assert_float(bar.fill_fraction()).is_equal_approx(expected, quantum)
	# Non-vacuity: a bar stuck full or stuck empty would satisfy a loose tolerance on some board.
	assert_bool(bar.fill_fraction() > 0.0 and bar.fill_fraction() < 1.0).override_failure_message(
			"the fixture did not actually wound the unit, so the fraction proves nothing").is_true()
	assert_str(bar.number_text()).contains(str(unit.get_current_hp()))


func test_the_readout_rides_the_ghost_when_a_move_is_planned() -> void:
	var unit := _spawn(PLAYER, Vector2i(2, 2))
	var origin := unit.movement.cell
	game.enter_move_mode(unit)
	game.selected_unit = unit
	game._on_left_click(Vector2i(3, 2))   # the documented dispatcher idiom: queue the move
	await _settle()
	# The precondition IS the trap: with a ghost standing in, the unit's own sprite is hidden, so
	# anything parented to it would be invisible from here on.
	assert_bool(_unit_mirror.sprite_for(unit).visible).override_failure_message(
			"no ghost stood in, so this case is not exercising the projected branch").is_false()

	var destination := unit.get_projected_destination()
	assert_that(destination).is_not_equal(origin)
	_point_at(destination)   # hover resolves at the PROJECTED cell, so this is what picks the unit
	await _settle()

	var bar := _unit_mirror.bar_for(unit)
	assert_bool(bar.visible).is_true()
	var heights: BoardHeights = game.board_heights
	var seat := BoardSpace.surface_point(destination, heights)
	assert_float(bar.position.x).is_equal_approx(seat.x, 0.001)
	assert_float(bar.position.z).is_equal_approx(seat.z, 0.001)
	# And demonstrably NOT over the cell it is leaving — the failure this branch exists to prevent.
	var left_behind := BoardSpace.surface_point(origin, heights)
	assert_bool(absf(bar.position.x - left_behind.x) > 0.001
			or absf(bar.position.z - left_behind.z) > 0.001).override_failure_message(
			"the readout stayed on the cell the unit is vacating").is_true()


func test_the_readout_is_one_display_and_not_parts_that_drift() -> void:
	# Found in play (dev, 2026-08-15): the number "kinda floats apart depending on the angle".
	# Every element billboards INDEPENDENTLY, so a displacement written to node `position` is a
	# WORLD offset — the bar turns under orbit while the number stays put, and they shear apart.
	# The invariant that fixes it: displacement lives in billboard-LOCAL space (QuadMesh's
	# center_offset, Label3D's offset), so every child sits at local origin.
	#
	# Asserting the invariant rather than a rendered position, because the drift only appears at
	# camera angles a headless run does not have — this is the property the angle can't move.
	var unit := _spawn(PLAYER, Vector2i(2, 2))
	unit.set_current_hp(int(unit.get_max_hp() * 0.5))   # part-full, so the fill is displaced too
	_point_at(unit.movement.cell)
	await _settle()
	var bar := _unit_mirror.bar_for(unit)
	assert_bool(bar.visible).override_failure_message(
			"the readout never appeared, so its parts cannot be checked").is_true()

	var displaced := 0
	for child in bar.get_children():
		var element := child as Node3D
		assert_that(element.position).override_failure_message(
				"'%s' is displaced by node position, which does not ride the billboard"
				% element.name).is_equal(Vector3.ZERO)
		var quad := child as MeshInstance3D
		if quad != null and absf((quad.mesh as QuadMesh).center_offset.x) > 0.0001:
			displaced += 1
		var label := child as Label3D
		if label != null and absf(label.offset.x) > 0.0001:
			displaced += 1
	# Non-vacuity, and it is the whole point: "everything sits at the origin" is trivially true of a
	# readout that displaces nothing at all. The half-full fill and the inset number must BOTH be
	# off-centre, and both in local space.
	assert_int(displaced).override_failure_message(
			"nothing was displaced, so displacing it in the right space proves nothing"
			).is_greater_equal(2)


func test_the_readout_sorts_above_every_unit_and_every_overlay() -> void:
	# A relationship, not values: the readout describes a unit, so it can never sort behind one,
	# and units already sort above all board markup. Pins the band the way the existing consts are
	# pinned rather than restating their numbers.
	assert_int(BoardOverlays.UNIT_HUD_RENDER_PRIORITY).is_greater(BoardOverlays.UNIT_RENDER_PRIORITY)
	assert_int(BoardOverlays.UNIT_RENDER_PRIORITY).is_greater(BoardOverlays.FLAME_RENDER_PRIORITY)
	for layer: BoardOverlays.Layer in BoardOverlays.LAYERS:
		var spec: Dictionary = BoardOverlays.LAYERS[layer]
		assert_int(BoardOverlays.UNIT_HUD_RENDER_PRIORITY).is_greater(spec["sort"])
