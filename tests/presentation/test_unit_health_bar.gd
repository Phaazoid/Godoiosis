# The hover health readout (#229): does pointing at a unit actually put a bar over it, does that
# bar say what the UNIT says, and does it follow the thing that is on screen?
#
# Since #350 it also covers the third reason a bar is up — the player asked for all of them — and
# the crowding rule that rides with it. Those cases live at the bottom, driven through the store.
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
		var label := child as Label3D
		if label != null:
			assert_int(label.billboard).override_failure_message(
					"the number billboards itself, so it turns about its own origin and shears away "
					+ "from the bar as the camera orbits").is_equal(BaseMaterial3D.BILLBOARD_DISABLED)
			if absf(label.position.x) > 0.0001:
				displaced += 1
			continue
		var quad := child as MeshInstance3D
		if quad == null:
			continue
		var material := quad.material_override as StandardMaterial3D
		assert_int(material.billboard_mode).override_failure_message(
				"'%s' billboards itself; only the parent may carry the orientation"
				% quad.name).is_equal(BaseMaterial3D.BILLBOARD_DISABLED)
		if absf((quad.mesh as QuadMesh).center_offset.x) > 0.0001:
			displaced += 1
	# Non-vacuity: "nothing billboards" is trivially true of a readout whose parts all sit dead
	# centre. The half-full fill and the inset number must BOTH actually be off-centre.
	assert_int(displaced).override_failure_message(
			"nothing was displaced, so laying it out in the parent's space proves nothing"
			).is_greater_equal(2)

	# And the other half: something has to turn it now that its parts do not turn themselves --
	# to the camera VIEW PLANE, which is what BILLBOARD_FIXED_Y does to every sprite around it
	# (#325 follow-up). Pointing at the camera POSITION instead is the same angle only at screen
	# centre, which is why the crown and the bar read as sitting on different axes.
	var camera := bar.get_viewport().get_camera_3d()
	assert_object(camera).is_not_null()
	var facing: Vector3 = camera.global_transform.basis.z
	assert_float(bar.global_rotation.y).override_failure_message(
			"the readout is not aligned to the camera view plane").is_equal_approx(
			atan2(facing.x, facing.z), 0.001)


func test_the_readout_sorts_above_every_unit_and_every_overlay() -> void:
	# A relationship, not values: the readout describes a unit, so it can never sort behind one,
	# and units already sort above all board markup. Pins the band the way the existing consts are
	# pinned rather than restating their numbers.
	assert_int(BoardOverlays.UNIT_HUD_RENDER_PRIORITY).is_greater(BoardOverlays.UNIT_RENDER_PRIORITY)
	assert_int(BoardOverlays.UNIT_RENDER_PRIORITY).is_greater(BoardOverlays.FLAME_RENDER_PRIORITY)
	for layer: BoardOverlays.Layer in BoardOverlays.LAYERS:
		var spec: Dictionary = BoardOverlays.LAYERS[layer]
		assert_int(BoardOverlays.UNIT_HUD_RENDER_PRIORITY).is_greater(spec["sort"])


# --- The always-show setting (#350) -----------------------------------------------------------
# The third reason a readout is up, and the only one that is a PREFERENCE rather than a derivation.
# Driven through PlayerSettings, never by poking UnitMirror, because the store is what the settings
# page writes and the gate is what reads it — the wire is the whole point.

func _set_always_on(on: bool) -> void:
	PlayerSettings.set_on(PlayerSettings.Setting.ALWAYS_SHOW_HEALTH, on)


func test_the_setting_puts_a_readout_over_every_unit_at_once() -> void:
	var first := _spawn(PLAYER, Vector2i(2, 2))
	var second := _spawn(PLAYER, Vector2i(6, 2))
	var third := _spawn(PLAYER, Vector2i(9, 5))
	_point_at(Vector2i(20, 20))   # empty ground: nothing is hovered, nothing is planned
	_set_always_on(true)
	await _settle()

	# The inverse of the hover case's exclusivity claim: every unit, not one.
	var shown := _shown_bars()
	assert_array(shown).contains([first, second, third])
	assert_int(shown.size()).is_equal(3)


func test_an_always_on_readout_keeps_its_digits_for_hover_alone() -> void:
	# The crowding answer #313 already reached one level down, reused rather than re-decided: a bar
	# that is up for a non-hover reason is bar-only, and pointing at it reveals the number.
	var pointed := _spawn(PLAYER, Vector2i(2, 2))
	var other := _spawn(PLAYER, Vector2i(6, 2))
	_set_always_on(true)
	_point_at(pointed.movement.cell)
	await _settle()

	assert_bool(_unit_mirror.bar_for(pointed).visible).is_true()
	assert_bool(_unit_mirror.bar_for(other).visible).is_true()
	assert_bool(_unit_mirror.bar_for(pointed).number_shown()).override_failure_message(
			"the hovered unit lost its digits").is_true()
	assert_bool(_unit_mirror.bar_for(other).number_shown()).override_failure_message(
			"every always-on bar carries digits, which is the crowding #313 already ruled on").is_false()


func test_turning_the_setting_off_returns_the_board_to_hover_only() -> void:
	# The off state is #229's behaviour, not "bars we forgot to clear" — a stale bar left standing
	# would look identical to the feature working right up until you moved the mouse.
	var unit := _spawn(PLAYER, Vector2i(2, 2))
	_set_always_on(true)
	_point_at(Vector2i(20, 20))
	await _settle()
	assert_bool(_unit_mirror.bar_for(unit).visible).is_true()   # precondition, via the real path

	_set_always_on(false)
	await _settle()

	assert_array(_shown_bars()).is_empty()


# --- The element-state row (#357) --------------------------------------------------------------
# The first deliberate occupant of the head channel #346 freed: what this unit IS, above the bar
# that says how hurt it is. Driven through the same wire as everything above — states go on the
# UNIT, the pointer moves, and the row is read off the meshes. Nothing here calls the bar directly.

func _wet(cell: Vector2i) -> Unit:
	var unit := _spawn(PLAYER, cell)
	unit.add_element_state(Elemental.State.WET)
	return unit


func test_a_hovered_units_row_shows_one_icon_per_held_state() -> void:
	var unit := _wet(Vector2i(2, 2))
	_point_at(Vector2i(2, 2))
	await _settle()
	var bar: UnitHealthBar = _unit_mirror.bar_for(unit)
	assert_bool(bar.visible).is_true()
	assert_int(bar.state_icon_count()).is_equal(1)

	# CHILLED reaches the row through StateIcons like any other state — it holds a placeholder
	# texture rather than its own art, and the row cannot tell the difference.
	unit.add_element_state(Elemental.State.CHILLED)
	await _settle()
	assert_int(bar.state_icon_count()).is_equal(2)


func test_a_hovered_unit_with_no_states_wears_no_row() -> void:
	var unit := _spawn(PLAYER, Vector2i(2, 2))
	_point_at(Vector2i(2, 2))
	await _settle()
	var bar: UnitHealthBar = _unit_mirror.bar_for(unit)
	assert_bool(bar.visible).is_true()   # the BAR is up; the row is what must be empty
	assert_int(bar.state_icon_count()).is_equal(0)


func test_the_row_sits_clear_above_the_bar_and_flush_with_its_left_edge() -> void:
	var unit := _wet(Vector2i(2, 2))
	_point_at(Vector2i(2, 2))
	await _settle()
	var bar: UnitHealthBar = _unit_mirror.bar_for(unit)

	# Derived from the knobs, never pinned: the claim is the RELATIONSHIP (clear of the outline's
	# top, flush with its left), which survives every retune of the values underneath it.
	var texel := 1.0 / UnitSprite3D.texels_per_unit
	var icon: float = roundf(_unit_mirror.state_icon_texels)
	var edge: float = roundf(_unit_mirror.bar_outline_texels)
	var bar_h: float = roundf(_unit_mirror.bar_height_texels)
	var track: float = roundf(_unit_mirror.bar_width_texels)
	var gap: float = roundf(_unit_mirror.state_icon_gap_texels)

	assert_float(bar.state_icon_size().x).is_equal_approx(icon * texel, 0.001)
	assert_float(bar.state_icon_size().y).is_equal_approx(icon * texel, 0.001)

	var offset := bar.state_icon_offset(0)
	# Its BOTTOM edge clears the outline's top edge by the gap.
	assert_float(offset.y - bar.state_icon_size().y * 0.5).is_equal_approx(
			(bar_h * 0.5 + edge + gap) * texel, 0.001)
	# Its LEFT edge sits on the outline's left edge — "centered left", the dev's words.
	assert_float(offset.x - bar.state_icon_size().x * 0.5).is_equal_approx(
			-(track * 0.5 + edge) * texel, 0.001)


func test_the_row_grows_rightward_without_moving_the_first_icon() -> void:
	var unit := _wet(Vector2i(2, 2))
	_point_at(Vector2i(2, 2))
	await _settle()
	var bar: UnitHealthBar = _unit_mirror.bar_for(unit)
	var alone := bar.state_icon_offset(0).x

	unit.add_element_state(Elemental.State.CHILLED)
	await _settle()

	# LEFT-aligned, not centred: a second state must push rightward off a fixed left edge. A row
	# that re-centred would pass a count test and still slide under the bar every time a state
	# landed, which is the thing you would notice and a counter would not.
	assert_float(bar.state_icon_offset(0).x).override_failure_message(
			"the first icon moved when a second arrived — the row is centring, not left-aligning") \
			.is_equal_approx(alone, 0.001)
	assert_float(bar.state_icon_offset(1).x).is_greater(bar.state_icon_offset(0).x)


func test_a_state_leaving_takes_its_icon_away() -> void:
	var unit := _wet(Vector2i(2, 2))
	unit.add_element_state(Elemental.State.CHILLED)
	_point_at(Vector2i(2, 2))
	await _settle()
	var bar: UnitHealthBar = _unit_mirror.bar_for(unit)
	assert_int(bar.state_icon_count()).is_equal(2)   # precondition, via the real path

	unit.remove_element_state(Elemental.State.WET)
	await _settle()

	# The pool only ever GROWS, so the retired slot is still there — parked, not drawn. A row that
	# forgot to park it would keep claiming a state the unit shed.
	assert_int(bar.state_icon_count()).is_equal(1)


func test_the_row_rides_the_bars_own_visibility_and_not_a_rule_of_its_own() -> void:
	# The one-gate claim (#350), asserted where it is visible: a wet unit nobody is pointing at
	# wears nothing, and the SETTING alone is enough to put its states on the board.
	var unit := _wet(Vector2i(2, 2))
	_point_at(Vector2i(20, 20))   # empty ground: not hovered, no plan
	await _settle()
	var bar: UnitHealthBar = _unit_mirror.bar_for(unit)
	assert_bool(bar.visible).is_false()

	_set_always_on(true)
	await _settle()

	assert_bool(bar.visible).is_true()
	assert_int(bar.state_icon_count()).override_failure_message(
			"the row did not follow the bar up — it has grown a visibility rule of its own") \
			.is_equal(1)


# --- The downed readout (#322) --------------------------------------------------------
# The complaint these answer: a body and a living unit clinging on both read "1/20", because
# _go_downed parks a downed unit at exactly 1 HP. So the claim under test is never "the glyph
# exists" — it is that the two board states RENDER DIFFERENTLY.

func _downed(cell: Vector2i) -> Unit:
	var unit := _spawn(PLAYER, cell)
	unit.force_down()   # the dev bypass: straight into DOWNED, no Will spend, no maim
	return unit


func test_a_body_and_a_living_unit_at_one_hp_read_differently() -> void:
	var body := _downed(Vector2i(2, 2))
	var clinging := _spawn(PLAYER, Vector2i(6, 2))
	clinging.set_current_hp(1)
	_point_at(Vector2i(20, 20))   # neither is hovered; the SETTING puts both bars up
	_set_always_on(true)
	await _settle()

	var body_bar: UnitHealthBar = _unit_mirror.bar_for(body)
	var clinging_bar: UnitHealthBar = _unit_mirror.bar_for(clinging)
	# The premise, asserted rather than assumed: the gauges genuinely say the same thing.
	assert_str(body_bar.number_text()).override_failure_message(
			"the two units no longer read the same HP — this case has stopped testing the bug") \
			.is_equal(clinging_bar.number_text())

	assert_bool(body_bar.downed_count_shown()).override_failure_message(
			"the body wears no rescue clock — its readout is still the living unit's") \
			.is_true()
	assert_str(body_bar.downed_count_text()).is_equal(str(body.downed_turns_remaining))
	assert_int(body_bar.state_icon_count()).is_equal(1)

	assert_bool(clinging_bar.downed_count_shown()).override_failure_message(
			"a living unit at 1 HP wears a rescue clock — the readout is reading the NUMBER, not the lifecycle") \
			.is_false()
	assert_int(clinging_bar.state_icon_count()).is_equal(0)


func test_the_rescue_clock_follows_the_countdown_down() -> void:
	var body := _downed(Vector2i(2, 2))
	_point_at(Vector2i(2, 2))
	await _settle()
	var bar: UnitHealthBar = _unit_mirror.bar_for(body)
	var opening := bar.downed_count_text()

	body.tick_downed_countdown()
	await _settle()

	# A count drawn once and never again would pass every other case in this block. The redraw gate
	# compares a signature, so a clock left out of it freezes on whatever it first drew.
	assert_str(bar.downed_count_text()).override_failure_message(
			"the clock did not move when the countdown ticked — it is frozen on its first value") \
			.is_not_equal(opening)
	assert_str(bar.downed_count_text()).is_equal(str(body.downed_turns_remaining))


func test_standing_a_body_back_up_takes_the_glyph_and_the_clock_away() -> void:
	var body := _downed(Vector2i(2, 2))
	_point_at(Vector2i(2, 2))
	await _settle()
	var bar: UnitHealthBar = _unit_mirror.bar_for(body)
	assert_int(bar.state_icon_count()).is_equal(1)   # precondition, via the real path

	body.revive()
	await _settle()

	assert_bool(bar.downed_count_shown()).override_failure_message(
			"a revived unit still wears its rescue clock").is_false()
	assert_int(bar.state_icon_count()).is_equal(0)


func test_the_clock_rides_the_row_rather_than_the_bar() -> void:
	var body := _downed(Vector2i(2, 2))
	_point_at(Vector2i(2, 2))
	await _settle()
	var bar: UnitHealthBar = _unit_mirror.bar_for(body)
	# One icon in the row: the glyph. The count sits past its right edge.
	var glyph_right: float = bar.state_icon_offset(0).x + bar.state_icon_size().x * 0.5
	assert_float(bar.downed_count_offset().x).is_greater(glyph_right)
	var alone := bar.downed_count_offset().x

	body.add_element_state(Elemental.State.WET)
	await _settle()

	# A state landing on a downed body pushes the glyph rightward, and the count must go with it.
	# Anchored to the BAR instead, the count would sit still here and start overlapping the row the
	# moment a unit held anything — which a count-and-text test would never see.
	assert_int(bar.state_icon_count()).is_equal(2)
	assert_float(bar.downed_count_offset().x).override_failure_message(
			"the clock stayed put when the row grew — it is anchored to the bar, not to the row") \
			.is_greater(alone)
