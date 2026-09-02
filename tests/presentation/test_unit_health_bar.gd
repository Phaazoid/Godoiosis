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

var _board := SharedBoard.new(SCENE_PATH)
var _scene: Node3D
var game: Node2D
var _unit_mirror: UnitMirror


func before() -> void:
	await _board.open(self, _clear_the_board)


func _clear_the_board() -> void:
	_board.game.scenario_manager.clear_board()
	_board.game.game_state = _board.game.GameState.IDLE


func before_test() -> void:
	await _board.reset(self)
	_scene = _board.scene
	game = _board.scene.game
	# Hermetic, and NOT optional (#350): is_on() falls through to user://settings.cfg, so without
	# this a suite asserting which units wear a bar reads the developer's own saved preference.
	_unit_mirror = _scene.get_node("UnitMirror") as UnitMirror


func after_test() -> void:
	await _board.check(self)


func after() -> void:
	_board.close()


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).is_not_null()   # fixture setup, not the claim under test
	return unit


# Move the pointer, the way the picker does. Everything past this line is the wire under test:
# battle3d hands the cell to HoverPresenter, which resolves the unit, which UnitMirror reads.
#
# It writes _pointer_cell directly, so it loses a race the poll can now start: since #471 the poll
# re-derives on CAMERA movement, from the REAL mouse. A case that MOVES the camera therefore points
# after the poll has settled, never before.
func _point_at(cell: Vector2i) -> void:
	var heights: BoardHeights = game.board_heights
	_scene._pointer_cell = BoardSpace.of_cell(cell, BoardSpace.top_row_of(heights.elevation_at(cell)))


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


func test_the_grid_says_what_the_unit_says() -> void:
	var unit := _spawn(PLAYER, Vector2i(2, 2))
	unit.set_current_hp(int(unit.get_max_hp() * 0.4))
	_point_at(unit.movement.cell)
	await _settle()

	var bar := _unit_mirror.bar_for(unit)
	# EXACT counts, no tolerance. #229's bar was rounded to whole texels, so its achievable
	# precision rode a width knob and this case had to carry a quantum; one cube per point of HP is
	# a COUNT, which is the whole argument for the grid — a player can read the number off it.
	assert_int(bar.block_count()).override_failure_message(
			"the grid does not have one socket per point of max HP").is_equal(unit.get_max_hp())
	assert_int(bar.filled_block_count()).override_failure_message(
			"the cubes standing proud do not match the unit's HP").is_equal(unit.get_current_hp())
	# Non-vacuity: a grid stuck full or stuck empty would satisfy a sloppier claim on some board.
	assert_bool(unit.get_current_hp() > 0 and unit.get_current_hp() < unit.get_max_hp()) \
			.override_failure_message(
			"the fixture did not actually wound the unit, so the counts prove nothing").is_true()
	# The two halves of the grid account for the whole of it — a lost cube is RECESSED, not gone,
	# which is what keeps max HP readable from the grid's own shape.
	assert_int(bar.block_count() - bar.filled_block_count()).is_equal(
			unit.get_max_hp() - unit.get_current_hp())
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
		# Two shapes since #314, displaced two ways: the plate and the state icons are quads that
		# carry their offset in the MESH, while an HP cube is a real solid placed by node position.
		# Both are legal here for the same reason — neither turns about its own origin.
		var mesh := quad.mesh as QuadMesh
		if mesh != null:
			if absf(mesh.center_offset.x) > 0.0001:
				displaced += 1
		elif absf(quad.position.x) > 0.0001:
			displaced += 1
	# Non-vacuity: "nothing billboards" is trivially true of a readout whose parts all sit dead
	# centre. The half-full fill and the inset number must BOTH actually be off-centre.
	assert_int(displaced).override_failure_message(
			"nothing was displaced, so laying it out in the parent's space proves nothing"
			).is_greater_equal(2)

	# The other half — WHO turns it — forks on a knob since #314 round 2, so it lives in the two
	# cases below rather than here. What this case still owns is that no CHILD turns itself,
	# whichever way the parent is pointed.


# The facing knob FORKS the cases that pin it (#449's law: a setting that forks a marker's
# lifecycle forks the cases that pin it). Each of the two below declares which branch it is in, so
# neither can pass by accident on a machine set the other way.

func test_held_in_place_the_grid_sits_on_the_boards_own_axes() -> void:
	# The DEFAULT since round 2 (dev: "they should not billboard towards the camera").
	_unit_mirror.hp_grid_faces_camera = false
	var unit := _spawn(PLAYER, Vector2i(2, 2))
	_point_at(unit.movement.cell)
	await _settle()
	var bar := _unit_mirror.bar_for(unit)
	assert_bool(bar.visible).is_true()
	assert_float(bar.global_rotation.y).override_failure_message(
			"the readout turned even though it is meant to be held in place").is_equal_approx(
			0.0, 0.001)


func test_the_knob_puts_the_grid_back_on_the_camera_view_plane() -> void:
	# The opt-in branch, and it must be the VIEW PLANE rather than the camera POSITION (#325
	# follow-up): FIXED_Y gives one yaw board-wide, while aiming each readout at the camera agrees
	# only at screen centre, which is what read as the crown and the bar sitting on different axes.
	_unit_mirror.hp_grid_faces_camera = true
	# ORBIT THE RIG FIRST. The fixture camera rests at yaw 0, where "held in place" and "facing the
	# camera" produce the identical rotation — so without this the case passes in both modes and
	# proves nothing (its own guard below caught exactly that). Both fields, because the rig eases
	# toward its target and would swing straight back.
	var rig: CameraRig3D = _scene.get_node("CameraRig")
	rig.rotation_degrees.y = 35.0
	rig._target_yaw_degrees = 35.0
	var unit := _spawn(PLAYER, Vector2i(2, 2))
	# Let the pointer poll consume the orbit BEFORE pointing. Since #471 it re-derives on camera
	# movement, and it derives from the REAL mouse — so a poll firing after _point_at overwrites the
	# synthetic pointer this case depends on. Ordering only: one poll settles its own baseline.
	await _settle()
	_point_at(unit.movement.cell)
	await _settle()
	var bar := _unit_mirror.bar_for(unit)
	var camera := bar.get_viewport().get_camera_3d()
	assert_object(camera).is_not_null()
	var facing: Vector3 = camera.global_transform.basis.z
	var wanted := atan2(facing.x, facing.z)
	assert_bool(absf(wanted) > 0.001).override_failure_message(
			"the camera happens to sit on the zero yaw, so this case cannot tell the two modes apart"
			).is_true()
	assert_float(bar.global_rotation.y).override_failure_message(
			"the readout is not aligned to the camera view plane").is_equal_approx(wanted, 0.001)


func test_every_face_wears_the_cage_and_only_the_top_is_shaded() -> void:
	# Round 2 took the cage OFF every non-front face to stop the tops reading as an extra row, and
	# that overshot: "now they don't look like cubes at all, just a green mass with black painted on"
	# (dev, 2026-08-22). The cage is what makes a cube read as a cube, so it is back on all six, and
	# the top is told apart by a darker vertex colour instead — which the black frame survives,
	# because black times any shade is still black.
	var unit := _spawn(PLAYER, Vector2i(2, 2))
	_point_at(unit.movement.cell)
	await _settle()   # a readout has to have drawn before the shared mesh exists

	var cube: ArrayMesh = UnitHealthBar.cube_mesh()
	assert_object(cube).override_failure_message("no cube mesh was built").is_not_null()
	assert_int(_flat_faces(cube)).override_failure_message(
			"a face lost its cage — the grid reads as one mass rather than as separate bricks"
			).is_equal(0)

	var colors: PackedColorArray = cube.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	assert_int(colors.size()).override_failure_message(
			"the cube carries no vertex colours, so nothing can shade one face").is_equal(24)
	assert_float(colors[UnitHealthBar.TOP_FACE * 4].r).override_failure_message(
			"the top face is not darker than the front, so the two still read as one surface"
			).is_less(colors[0].r)


func test_the_readout_draws_NOTHING_behind_the_cubes() -> void:
	# "This is a 3D display, we don't need one at all... it's just a weird black rectangle floating in
	# space" (dev, 2026-08-22). The backing quad is DELETED, and its absence is what this pins: every
	# cube wears its own cage, so nothing needs a surface behind it to be separated from the board.
	# Stated as a RELATIONSHIP — no quad sits behind the frontmost face a cube presents — rather than
	# as "there is no node called the plate", which the next backing under another name would pass.
	# It also covers the z-fight that killed the last version: at a recess of 0 a cube's own back face
	# sits at depth 0, so anything drawn there is coplanar with it.
	# A unit carrying a STATE, so the readout really does draw a quad — the state row's icons are the
	# only ones left. Otherwise the walk below would have nothing to enumerate and would pass on an
	# empty set, which is a true answer reached without looking at anything.
	var unit := _wet(Vector2i(2, 2))
	_point_at(unit.movement.cell)
	await _settle()
	var bar := _unit_mirror.bar_for(unit)

	var texel := 1.0 / UnitSprite3D.texels_per_unit
	# The cubes' own front plane: proud centre plus half a block.
	var front: float = bar.block_depth(0) + bar.block_size_texels() * 0.5 * texel
	var quads := 0
	for child in bar.get_children():
		var quad := child as MeshInstance3D
		if quad == null or not (quad.mesh is QuadMesh):
			continue
		quads += 1
		assert_float(quad.position.z).override_failure_message(
				"a flat quad is drawn behind the grid — the readout has grown a backing again"
				).is_greater_equal(front)
	assert_int(quads).override_failure_message(
			"the readout drew no quads at all, so this case checked nothing"
			).is_greater(0)


# How many of a cube's six faces collapse all four UVs onto one point — i.e. sample a single texel,
# and so tint to a flat colour carrying no frame.
func _flat_faces(mesh: ArrayMesh) -> int:
	var uvs: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var flat := 0
	for face in 6:
		var first: Vector2 = uvs[face * 4]
		var same := true
		for corner in 4:
			if not uvs[face * 4 + corner].is_equal_approx(first):
				same = false
		if same:
			flat += 1
	return flat


func test_the_hp_digits_sit_in_FRONT_of_the_cubes_rather_than_inside_them() -> void:
	# Round 1 shipped the digits INVISIBLE and no knob could have rescued them: the label was placed
	# at the cube's CENTRE depth, the cubes are opaque and write depth, so the text was buried inside
	# a solid and depth-rejected. Asserted as the relationship rather than a value — the label must
	# clear the front FACE, which is half a block further toward the camera than the centre.
	var unit := _spawn(PLAYER, Vector2i(2, 2))
	_point_at(unit.movement.cell)
	await _settle()
	var bar := _unit_mirror.bar_for(unit)
	assert_bool(bar.number_shown()).override_failure_message(
			"the digits are not up, so their depth proves nothing").is_true()

	var texel := 1.0 / UnitSprite3D.texels_per_unit
	var cube_front: float = bar.block_size_texels() * texel   # a cube spans 0 .. block, front at the top
	var label: Label3D = null
	for child in bar.get_children():
		var found := child as Label3D
		if found != null and found.visible and found.text == bar.number_text():
			label = found
			break
	assert_object(label).override_failure_message("no visible HP label to measure").is_not_null()
	assert_float(label.position.z).override_failure_message(
			"the HP digits sit at or behind the cubes' front face, so an opaque cube hides them"
			).is_greater(cube_front)


func test_the_readout_sorts_above_every_unit_and_every_overlay() -> void:
	# A relationship, not values: the readout describes a unit, so it can never sort behind one,
	# and units already sort above all board markup. Pins the band the way the existing consts are
	# pinned rather than restating their numbers.
	assert_int(BoardOverlays.UNIT_HUD_RENDER_PRIORITY).is_greater(BoardOverlays.UNIT_RENDER_PRIORITY)
	assert_int(BoardOverlays.UNIT_RENDER_PRIORITY).is_greater(BoardOverlays.FLAME_RENDER_PRIORITY)
	for layer: BoardOverlays.Layer in BoardOverlays.LAYERS:
		var spec: Dictionary = BoardOverlays.LAYERS[layer]
		assert_int(BoardOverlays.UNIT_HUD_RENDER_PRIORITY).is_greater(spec["sort"])


# --- The health-bar preference (#350, three-valued since #418) ---------------------------------
# The third reason a readout is up, and the only one that is a PREFERENCE rather than a derivation.
# Driven through PlayerSettings, never by poking UnitMirror, because the store is what the settings
# page writes and the gate is what reads it — the wire is the whole point.
#
# THIS SUITE DECLARES ITS BRANCH (#449): every case below names the mode it is in, because a
# setting that forks which units wear a bar forks the cases that pin them.

func _set_bars(mode: PlayerSettings.HealthBars) -> void:
	PlayerSettings.set_choice(PlayerSettings.Setting.HEALTH_BARS, mode)


# set_current_hp is Unit's one door for WRITING hp, so this is the honest fixture rather than a
# shortcut: what is under test is the gate READING the number, not how the number got there.
func _wound(unit: Unit) -> Unit:
	unit.set_current_hp(unit.get_max_hp() - 1)
	assert_int(unit.get_current_hp()).is_less(unit.get_max_hp())   # fixture setup, not the claim
	return unit


func test_the_setting_puts_a_readout_over_every_unit_at_once() -> void:
	var first := _spawn(PLAYER, Vector2i(2, 2))
	var second := _spawn(PLAYER, Vector2i(6, 2))
	var third := _spawn(PLAYER, Vector2i(9, 5))
	_point_at(Vector2i(20, 20))   # empty ground: nothing is hovered, nothing is planned
	_set_bars(PlayerSettings.HealthBars.EVERY)
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
	_set_bars(PlayerSettings.HealthBars.EVERY)
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
	_set_bars(PlayerSettings.HealthBars.EVERY)
	_point_at(Vector2i(20, 20))
	await _settle()
	assert_bool(_unit_mirror.bar_for(unit).visible).is_true()   # precondition, via the real path

	_set_bars(PlayerSettings.HealthBars.HOVERED)
	await _settle()

	assert_array(_shown_bars()).is_empty()


func test_damaged_only_thins_the_board_down_to_the_hurt() -> void:
	# #418's whole ask. The claim is a PARTITION and needs both sides in one case: a mode that shows
	# everybody and a mode that shows nobody each satisfy half of it.
	var hurt := _wound(_spawn(PLAYER, Vector2i(2, 2)))
	var whole := _spawn(PLAYER, Vector2i(6, 2))
	_point_at(Vector2i(20, 20))   # empty ground: nothing is hovered, nothing is planned
	_set_bars(PlayerSettings.HealthBars.DAMAGED)
	await _settle()

	assert_array(_shown_bars()).contains_exactly([hurt])
	assert_bool(_unit_mirror.bar_for(whole).visible).override_failure_message(
			"a unit at full HP wore a bar under 'damaged only'").is_false()


func test_damaged_only_still_answers_the_cursor() -> void:
	# The mode narrows the PREFERENCE disjunct and must not touch the hover one — "damaged only"
	# that also stopped answering the cursor would have taken #229 away.
	var whole := _spawn(PLAYER, Vector2i(2, 2))
	_set_bars(PlayerSettings.HealthBars.DAMAGED)
	_point_at(whole.movement.cell)
	await _settle()

	assert_bool(_unit_mirror.bar_for(whole).visible).override_failure_message(
			"pointing at a full-HP unit no longer shows its readout").is_true()


func test_a_body_keeps_its_readout_under_damaged_only() -> void:
	# _go_downed clings at 1 HP, so a body is damaged by the ordinary rule rather than by a clause
	# of its own — which is what keeps #322's glyph and rescue clock up in this mode.
	var body := _spawn(PLAYER, Vector2i(2, 2))
	body._go_downed(false)   # the dev-bypass form: down it without the Will spend or a maim
	assert_bool(body.is_downed()).is_true()   # fixture setup, not the claim
	_point_at(Vector2i(20, 20))
	_set_bars(PlayerSettings.HealthBars.DAMAGED)
	await _settle()

	assert_array(_shown_bars()).contains([body])


func test_a_queued_order_keeps_a_full_health_units_readout_under_damaged_only() -> void:
	# THE CLAUSE #418 MAY NOT TOUCH. Law #2 says the queue never lies and #354 ruled a prediction
	# survives to the end of its pass, so a preference that could hide what the queue is promising
	# would undo both. Its own case under the NEW mode, because the always-on cases above cannot
	# see it: with EVERY set, every bar is up for the preference anyway.
	var attacker := _spawn(PLAYER, Vector2i(2, 2))
	attacker.equipped_weapon = H.make_weapon()   # pattern-less: Reach falls back to adjacency
	var target := _spawn(Team.Faction.ENEMY, Vector2i(3, 2))
	assert_int(target.get_current_hp()).is_equal(target.get_max_hp())   # fixture: NOT damaged

	game.enter_attack_mode(attacker)
	game.selected_unit = attacker
	game._on_left_click(target.movement.cell)   # the dispatcher idiom: declare, gate, resolve
	_point_at(Vector2i(20, 20))                 # nothing hovered, so only the plan can hold it up
	_set_bars(PlayerSettings.HealthBars.DAMAGED)
	await _settle()

	assert_bool(_unit_mirror.bar_for(target).visible).override_failure_message(
			"a preference hid a unit the queue is about to change -- Law #2").is_true()


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

	# Derived from the knobs, never pinned: the claim is the RELATIONSHIP (clear of the grid's top,
	# flush with its left), which survives every retune of the values underneath it.
	var texel := 1.0 / UnitSprite3D.texels_per_unit
	var icon: float = roundf(_unit_mirror.state_icon_texels)
	# The grid's own extent, ASKED of the readout rather than rebuilt from the knobs: since #314 it
	# is derived from cube size, cage and row width together, and a second derivation here is a copy
	# that would go stale the next time the layout grows an input.
	var stack: Vector2 = bar.stack_size_texels()
	var bar_h: float = stack.y
	var track: float = stack.x
	var gap: float = roundf(_unit_mirror.state_icon_gap_texels)

	assert_float(bar.state_icon_size().x).is_equal_approx(icon * texel, 0.001)
	assert_float(bar.state_icon_size().y).is_equal_approx(icon * texel, 0.001)

	var offset := bar.state_icon_offset(0)
	# Its BOTTOM edge clears the grid's top edge by the gap.
	assert_float(offset.y - bar.state_icon_size().y * 0.5).is_equal_approx(
			(bar_h * 0.5 + gap) * texel, 0.001)
	# Its LEFT edge sits on the grid's left edge — "centered left", the dev's words.
	assert_float(offset.x - bar.state_icon_size().x * 0.5).is_equal_approx(
			-track * 0.5 * texel, 0.001)


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

	_set_bars(PlayerSettings.HealthBars.EVERY)
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
	_set_bars(PlayerSettings.HealthBars.EVERY)
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


func test_the_clock_is_never_smaller_than_the_hp_digits() -> void:
	# The dev's floor, stated in play (2026-08-21): "any number needs to be at least as big as the
	# numbers in the healthbar to be readable. Smaller than that is just impossible." A RELATIONSHIP,
	# not a value — retuning the HP number moves both sides, so nothing here pins a tuning knob.
	var body := _downed(Vector2i(2, 2))
	_point_at(Vector2i(2, 2))
	await _settle()
	var bar: UnitHealthBar = _unit_mirror.bar_for(body)
	assert_float(bar.number_glyph_height()).is_greater(0.0)   # non-vacuity, not a threshold
	assert_float(bar.downed_count_glyph_height()).override_failure_message(
			"the rescue clock is drawn smaller than the HP digits — the dev's legibility floor") \
			.is_greater_equal(bar.number_glyph_height())


# --- The zoom overrides the preference (2026-08-28) ---------------------------------------------
# Found in play once #418 shipped: during a battle zoom the clash read ONE-SIDED, because the
# target already wore a bar through `foretold` while the attacker wore nothing. The rule the dev
# asked for is that the setting stops applying while a fight is being played out.
#
# THESE CASES DECLARE THEIR BRANCH (#449) and it is HOVERED -- the shipped default, and the only
# branch where the override is observable at all: under EVERY every bar is up regardless, so a case
# written there would pass without any of this.
#
# The BYSTANDER is the subject on purpose. The attacker and target are both reachable through the
# gate's existing disjuncts, so a case that looked at them would go green with the override deleted.

# The real pass, started but deliberately NOT awaited, so a case can read the board WHILE it runs --
# test_predicted_health's idiom, and the state under test exists only mid-pass.
func _run_pass(leader: Unit, done: Array) -> void:
	await game.order_executor.execute_orders(leader)
	done[0] = true


# Queue a real swing through the dispatcher, the way the #418 foretold case does.
func _aim_at(attacker: Unit, cell: Vector2i) -> void:
	game.enter_attack_mode(attacker)
	game.selected_unit = attacker
	game._on_left_click(cell)


func test_a_zoomed_fight_puts_a_bar_over_everyone_whatever_the_setting() -> void:
	_set_bars(PlayerSettings.HealthBars.HOVERED)
	var attacker := _spawn(PLAYER, Vector2i(2, 2))
	attacker.equipped_weapon = H.make_weapon()   # pattern-less: Reach falls back to adjacency
	var target := _spawn(Team.Faction.ENEMY, Vector2i(3, 2))
	var bystander := _spawn(PLAYER, Vector2i(9, 5))   # not in the plan, not hovered, full HP
	_aim_at(attacker, target.movement.cell)
	_point_at(Vector2i(20, 20))
	await _settle()

	assert_bool(_unit_mirror.bar_for(bystander).visible).override_failure_message(
			"the bystander already wore a bar before the pass, so this case proves nothing").is_false()

	var done := [false]
	_run_pass(attacker, done)
	var barred := false
	var sampled := 0
	for _frame in 600:
		await await_idle_frame()
		if done[0]:
			break
		sampled += 1
		if _unit_mirror.bar_for(bystander).visible:
			barred = true
			break

	assert_int(sampled).override_failure_message(
			"the pass ended before a single frame could be sampled, so this case cannot see mid-pass"
			).is_greater(0)
	assert_bool(barred).override_failure_message(
			"a full-HP bystander wore no bar while a fight played out -- the zoom did not override the setting"
			).is_true()

	while not done[0]:
		await await_idle_frame()


func test_the_forced_bars_leave_when_the_pass_does() -> void:
	# The half that catches a flag which is SET and never cleared -- and the one the mirror's
	# placement is designed for: beat_profile is held between passes, so a readout wired to that
	# would keep every bar on the board up for ever after the first clash.
	_set_bars(PlayerSettings.HealthBars.HOVERED)
	var attacker := _spawn(PLAYER, Vector2i(2, 2))
	attacker.equipped_weapon = H.make_weapon()
	var target := _spawn(Team.Faction.ENEMY, Vector2i(3, 2))
	var bystander := _spawn(PLAYER, Vector2i(9, 5))
	_aim_at(attacker, target.movement.cell)
	_point_at(Vector2i(20, 20))
	await _settle()

	await game.order_executor.execute_orders(attacker)
	await _settle()

	assert_bool(_unit_mirror.bar_for(bystander).visible).override_failure_message(
			"the bystander kept its bar after the pass ended -- the override never released"
			).is_false()


func test_a_walk_only_pass_leaves_the_setting_alone() -> void:
	# The borrowed half of the rule (_shows_a_fight): under ALWAYS every beat is cinematic, so
	# "is this pass cinematic" alone would force bars on for a squad that did nothing but walk.
	# An empty sheet means no main actions, which is the tear-out's rule and now this one's.
	_set_bars(PlayerSettings.HealthBars.HOVERED)
	var mover := _spawn(PLAYER, Vector2i(2, 2))
	var bystander := _spawn(PLAYER, Vector2i(9, 5))
	game.enter_move_mode(mover)
	game.selected_unit = mover
	game._on_left_click(Vector2i(4, 2))
	_point_at(Vector2i(20, 20))
	await _settle()

	var done := [false]
	_run_pass(mover, done)
	var barred := false
	var sampled := 0
	for _frame in 600:
		await await_idle_frame()
		if done[0]:
			break
		sampled += 1
		if _unit_mirror.bar_for(bystander).visible:
			barred = true
			break

	assert_int(sampled).override_failure_message(
			"the walk ended before a single frame could be sampled, so this case is vacuous"
			).is_greater(0)
	assert_bool(barred).override_failure_message(
			"a pass of nothing but walking forced bars on -- the fight half of the rule is not applying"
			).is_false()

	while not done[0]:
		await await_idle_frame()


# --- The digits preference reaches the board (#394) -----------------------------------------

func test_the_digits_preference_puts_numbers_on_an_unhovered_bar() -> void:
	# The WIRE for #394's move. This value was a dev knob on UnitMirror with no test at all; moving
	# it to PlayerSettings is only done if the store actually reaches the readout, and the reader is
	# a per-frame reconcile that now takes the answer as a parameter rather than off a property.
	#
	# The case above is its OFF half, already shipped: an always-on bar carries no digits by default.
	var pointed := _spawn(PLAYER, Vector2i(2, 2))
	var other := _spawn(PLAYER, Vector2i(6, 2))
	_set_bars(PlayerSettings.HealthBars.EVERY)
	PlayerSettings.set_on(PlayerSettings.Setting.UNHOVERED_BAR_NUMBERS, true)
	_point_at(pointed.movement.cell)
	await _settle()

	assert_bool(_unit_mirror.bar_for(other).number_shown()).override_failure_message(
			"the digits preference did not reach a bar that is up without the cursor on it"
			).is_true()
	assert_bool(_unit_mirror.bar_for(pointed).number_shown()).override_failure_message(
			"the hovered unit lost its digits").is_true()
