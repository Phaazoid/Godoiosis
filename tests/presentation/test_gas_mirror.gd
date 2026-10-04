# GasMirror (#508): the store reaching the 3D drawing, on the real Battle3D host. The
# volume's compute passes cannot run headless (no RenderingDevice), so what is asserted here is what
# the mirror HANDS them -- the snapshot, the board textures, the region boxes -- plus the two parts it
# draws itself, the fog floor's mesh and the puffs' instances. Whether any of it LOOKS right is the
# dev's to judge in play; see the PR's How to check this.
#
# Every case paints through the store (GasField.set_level), never pokes the mirror, and waits for
# its poll -- a mirror that only works when a test calls it goes red here.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const PROLOG := "res://Scenarios/missions/Prolog.tres"

var _board := SharedBoard.new(SCENE_PATH)
var _scene: Node3D
var _game: Node2D
var _gas: GasMirror


func before() -> void:
	await _board.open(self)


func before_test() -> void:
	await _board.reset(self)
	_scene = _board.scene
	_game = _board.game
	_gas = _scene.get_node("GasMirror") as GasMirror


func after_test() -> void:
	Input.action_release(GasMirror.FLOOR_ACTION)
	BoardSpace.clear_staging()
	await _board.check(self)


func after() -> void:
	_board.close()


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


func _field() -> GasField:
	return _game.gas_field


# A cell with ground on all eight sides, so its neighbours are free to hold gas or not.
func _inland_cell() -> Vector2i:
	for cell: Vector2i in _game.grid.get_used_cells():
		var ringed := true
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if not GridUtils.has_ground(_game.grid, cell + Vector2i(dx, dy)):
					ringed = false
		if ringed:
			return cell
	return GridUtils.NO_CELL


func _loaded_cell() -> Vector2i:
	_scene.load_mission(PROLOG)
	await _settle()
	var cell := _inland_cell()
	assert_bool(cell != GridUtils.NO_CELL).override_failure_message(
		"no cell here is ringed by ground, so no case can paint around one").is_true()
	return cell


func _mix(index: int) -> void:
	Experiments.set_choice(Experiments.Flag.GAS_STYLE, index)
	await _settle()


# The real action, pressed the way the key presses it, so the mirror's own Input read is what answers.
func _hold_floor(held: bool) -> void:
	if held:
		Input.action_press(GasMirror.FLOOR_ACTION)
	else:
		Input.action_release(GasMirror.FLOOR_ACTION)
	await _settle()


# A kind whose look carries this extra, or the case has nothing to ask about.
func _kind_with(extra: GasLook.Extra) -> Gas.Kind:
	for kind: Gas.Kind in Gas.Kind.values():
		if GasLook.for_kind(kind).extra == extra:
			return kind
	assert_bool(false).override_failure_message(
		"no gas look carries extra %s, so this case asks about nothing" % GasLook.Extra.keys()[extra]).is_true()
	return Gas.Kind.STEAM


# Where the puff instances of one role stand. Read off the mirror's own record of what it handed the
# MultiMesh: the dummy renderer a headless run uses keeps no instance data, so every transform and
# custom datum read back off the MultiMesh is zero.
func _instances_of(role: int) -> Array[Vector3]:
	var found: Array[Vector3] = []
	for entry: Array in _gas.puff_entries():
		if int(entry[2]) == role:
			found.append(entry[0])
	return found


func test_the_camera_carries_the_volume_effect() -> void:
	var camera := _scene.get_node("CameraRig/Pitch/Camera") as Camera3D
	assert_object(camera.compositor).is_not_null()
	assert_bool(camera.compositor.compositor_effects.has(_gas.volume_effect())).override_failure_message(
		"the gas mirror's effect is not on the Battle3D camera, so the volume is never drawn").is_true()


func test_an_empty_board_hands_the_volume_nothing() -> void:
	await _loaded_cell()
	assert_object(_gas.volume_effect().current()).is_null()
	assert_bool(_gas.floor_node().visible or _gas.puff_node().visible).is_false()


func test_every_mix_draws_the_volume_and_the_puffs_and_no_floor() -> void:
	var cell := await _loaded_cell()
	_field().set_level(cell, Gas.Kind.STEAM, Gas.MAX_LEVEL)
	for index in GasMirror.MIXES.size():
		await _mix(index)
		assert_object(_gas.volume_effect().current()).override_failure_message(
			"mix %d hands the volume nothing" % index).is_not_null()
		assert_bool(_gas.puff_node().visible).override_failure_message("mix %d draws no puffs" % index).is_true()
		assert_bool(_gas.floor_node().visible).override_failure_message(
			"mix %d draws the floor with the key up" % index).is_false()


func test_holding_the_key_shows_the_floor_and_fades_the_cloud() -> void:
	var cell := await _loaded_cell()
	_field().set_level(cell, Gas.Kind.SMOKE, Gas.Level.THICK)
	await _settle()
	assert_float(_gas.volume_effect().current().params.march3.w).is_equal(1.0)
	await _hold_floor(true)
	assert_bool(_gas.floor_node().visible).override_failure_message(
		"holding the floor key does not show the floor").is_true()
	assert_bool(_gas.puff_node().visible).override_failure_message(
		"the puffs still stand over the floor while the key is held").is_false()
	assert_float(_gas.volume_effect().current().params.march3.w).override_failure_message(
		"the volume is not handed the held strength").is_equal(_gas.held_cloud_strength)
	await _hold_floor(false)
	assert_bool(_gas.floor_node().visible).is_false()
	assert_bool(_gas.puff_node().visible).is_true()
	assert_float(_gas.volume_effect().current().params.march3.w).is_equal(1.0)


func test_the_flat_view_stands_the_gas_down() -> void:
	var cell := await _loaded_cell()
	_field().set_level(cell, Gas.Kind.STEAM, Gas.Level.THICK)
	await _hold_floor(true)
	var was: int = _scene.get("view")
	_scene.set("view", 1)   # View.FLAT_2D (HD_2D, FLAT_2D, CORNER)
	await _settle()
	assert_bool(_gas.floor_node().visible or _gas.puff_node().visible).is_false()
	assert_object(_gas.volume_effect().current()).is_null()
	_scene.set("view", was)


func test_the_layering_switch_picks_the_callback_point() -> void:
	var cell := await _loaded_cell()
	_field().set_level(cell, Gas.Kind.SMOKE, Gas.Level.THICK)
	Experiments.set_on(Experiments.Flag.GAS_OVER_UNITS, true)
	await _settle()
	assert_int(_gas.volume_effect().effect_callback_type).is_equal(
		CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT)
	Experiments.set_on(Experiments.Flag.GAS_OVER_UNITS, false)
	await _settle()
	assert_int(_gas.volume_effect().effect_callback_type).is_equal(
		CompositorEffect.EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT)


func test_the_board_texture_says_what_the_store_holds() -> void:
	var cell := await _loaded_cell()
	var east := cell + Vector2i(1, 0)
	_field().set_level(cell, Gas.Kind.STEAM, Gas.Level.THICK)
	_field().set_level(cell, Gas.Kind.SMOKE, Gas.Level.THIN)
	_field().set_level(east, Gas.Kind.POISON, Gas.Level.MEDIUM)
	await _settle()
	var image := (_gas.board_textures()[0] as Texture2D).get_image()
	var rect: Rect2i = _game.grid.get_used_rect()
	var bits := image.get_pixelv(cell - rect.position)
	var held := roundi(bits.r * 255.0)
	var near := roundi(bits.g * 255.0)
	var neighbours := roundi(bits.b * 255.0)
	assert_int(held).is_equal(Gas.kind_mask(_field().packed_at(cell)))
	assert_int(near).override_failure_message("the poison next door is not among the kinds near").is_equal(
		Gas.kind_mask(_field().packed_at(cell)) | Gas.kind_mask(_field().packed_at(east)))
	# The neighbour bits run row by row from the north-west, skipping the cell itself: east is bit 4.
	assert_int(neighbours).is_equal(1 << 4)


func test_the_regions_follow_the_paint() -> void:
	var cell := await _loaded_cell()
	_field().set_level(cell, Gas.Kind.STEAM, Gas.Level.THICK)
	await _settle()
	assert_int(_gas.region_boxes().size()).is_equal(1)
	assert_bool(_gas.region_boxes()[0].has_point(BoardSpace.surface_point(cell, _game.board_heights)
		+ Vector3(0, 0.1, 0))).is_true()
	_field().clear()
	await _settle()
	assert_int(_gas.region_boxes().size()).is_equal(0)


func test_gas_on_a_staged_cell_rides_the_diorama() -> void:
	var cell := await _loaded_cell()
	_field().set_level(cell, Gas.Kind.STEAM, Gas.Level.THICK)
	var cells: Array[Vector2i] = [cell]
	var lift := Vector3(0.0, 40.0, 0.0)
	BoardSpace.stage(cells, lift)
	await _settle()
	var boxes := _gas.region_boxes()
	assert_int(boxes.size()).is_equal(1)
	var on_the_board := BoardSpace.surface_point(cell, _game.board_heights)
	assert_bool(boxes[0].has_point(on_the_board + lift + Vector3(0, 0.1, 0))).override_failure_message(
		"the staged cell's gas stayed behind on the board instead of going up with it").is_true()
	assert_float(_gas.volume_effect().current().params.stage.w).is_equal(1.0)


func test_the_floor_lies_on_the_true_surface_of_a_corner_cell() -> void:
	var cell := await _loaded_cell()
	var base: int = _game.board_heights.elevation_at(cell)
	var corners := Vector4i(base + Terrain.UNITS_PER_LEVEL, base, base, base)
	assert_bool(Terrain.is_legal_corners(corners) and not Terrain.is_planar_form(corners)) \
		.override_failure_message("the test's corner form %s is not a legal non-planar cell" % corners).is_true()
	_game.board_heights.set_corners(cell, corners)
	_field().set_level(cell, Gas.Kind.FROST, Gas.Level.MEDIUM)
	await _settle()
	var mesh := _gas.floor_node().mesh as ArrayMesh
	assert_object(mesh).is_not_null()
	var lift := (_scene.get_node("BoardOverlays") as BoardOverlays).gas_floor_lift()
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_int(vertices.size()).is_greater(0)
	for v in vertices:
		var want := BoardSpace.world_y_of_height(Terrain.height_at_uv(corners, v.x - cell.x, v.z - cell.y)) + lift
		assert_float(v.y).override_failure_message(
			"a floor vertex at %s floats off the surface (want y %f)" % [v, want]).is_equal_approx(want, 0.0001)


func test_puff_counts_follow_each_mix_slot_table() -> void:
	var cell := await _loaded_cell()
	# Any gas whose extra is not the bolt, which belongs to a strike rather than a cell.
	var kind := Gas.Kind.STEAM
	for k: Gas.Kind in Gas.Kind.values():
		if GasLook.for_kind(k).extra != GasLook.Extra.BOLT:
			kind = k
			break
	var extra := GasLook.for_kind(kind).extra
	var extras := 2 if extra == GasLook.Extra.SNOW or extra == GasLook.Extra.SOOT else 1
	_field().set_level(cell, kind, Gas.MAX_LEVEL)
	for index in GasMirror.MIXES.size():
		var shown_slots := 0
		for slot: Array in GasMirror.MIXES[index].slots:
			if Gas.MAX_LEVEL >= int(slot[1]):
				shown_slots += 1
		await _mix(index)
		# A full cell shows every slot of the mix's table plus its extras.
		assert_int(_gas.puff_node().multimesh.instance_count).override_failure_message(
			"mix %d" % index).is_equal(shown_slots + extras)


func test_every_strike_has_one_bolt_under_its_glow() -> void:
	var cell := await _loaded_cell()
	var kind := _kind_with(GasLook.Extra.BOLT)
	assert_float(GasLook.for_kind(kind).flash).override_failure_message(
		"the gas whose extra is the bolt does not flash, so no strike would carry it").is_greater(0.0)
	for offset: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, -1), Vector2i(1, 1)]:
		_field().set_level(cell + offset, kind, Gas.Level.THICK)
	await _settle()
	var strikes := _gas.strike_points()
	var bolts := _instances_of(GasMirror.EXTRA_ROLES[GasLook.Extra.BOLT])
	assert_int(strikes.size()).override_failure_message("the storm has no strikes at all").is_greater(0)
	assert_int(bolts.size()).override_failure_message(
		"%d strikes glow but %d bolts stand" % [strikes.size(), bolts.size()]).is_equal(strikes.size())
	for bolt in bolts:
		var under_a_glow := false
		for glow: Vector3 in strikes.values():
			under_a_glow = under_a_glow or Vector2(bolt.x, bolt.z).is_equal_approx(Vector2(glow.x, glow.z))
		assert_bool(under_a_glow).override_failure_message(
			"a bolt at %s stands under no strike's glow" % bolt).is_true()


func test_the_haze_stands_lower_than_the_full_cloud() -> void:
	var cell := await _loaded_cell()
	_field().set_level(cell, Gas.Kind.STEAM, Gas.MAX_LEVEL)
	await _mix(0)
	var full_top := _gas.region_boxes()[0].end.y
	var haze := -1
	for index in GasMirror.MIXES.size():
		if float(GasMirror.MIXES[index].height) < 1.0:
			haze = index
	assert_int(haze).override_failure_message("no mix thins the volume, so there is no haze to ask about") \
		.is_greater_equal(0)
	await _mix(haze)
	assert_float(_gas.region_boxes()[0].end.y).override_failure_message(
		"the haze's region box stands as tall as the full cloud's").is_less(full_top)


func test_frost_falls_as_snow_in_every_mix() -> void:
	var cell := await _loaded_cell()
	_field().set_level(cell, _kind_with(GasLook.Extra.SNOW), Gas.MAX_LEVEL)
	for index in GasMirror.MIXES.size():
		await _mix(index)
		assert_int(_instances_of(GasMirror.EXTRA_ROLES[GasLook.Extra.SNOW]).size()).override_failure_message(
			"mix %d draws no snow" % index).is_greater(0)


func test_every_gas_node_stays_off_the_ground_layer() -> void:
	# The damp blot's decal paints the ground layer (#358); anything else on it is darkened.
	for node: GeometryInstance3D in [_gas.floor_node(), _gas.puff_node()]:
		assert_int(node.layers).is_equal(BoardOverlays.WORLD_RENDER_LAYER)


# Holding the floor key also draws NEXT round (#508): the floor's shader in outline-only mode, built
# from GasField.next_round -- the round's own rule -- so the outline and the round cannot disagree.
# The cell is FOUND, not named: any one a thick puff would spill out of (the content razor).
func test_holding_the_key_outlines_next_round_as_the_round_will_play_it() -> void:
	_scene.load_mission(PROLOG)
	await _settle()
	var board: BoardContext = _game._board()
	var cell := GridUtils.NO_CELL
	for candidate: Vector2i in _game.grid.get_used_cells():
		_field().set_level(candidate, Gas.Kind.STEAM, Gas.Level.THICK)
		if _field().next_round(board).size() > 1:
			cell = candidate
			break
		_field().set_level(candidate, Gas.Kind.STEAM, Gas.Level.NONE)
	assert_bool(cell != GridUtils.NO_CELL).override_failure_message(
		"no cell on this board would spill a thick puff, so there is no next round to outline").is_true()
	await _settle()
	assert_bool(_gas.forecast_node().visible).override_failure_message(
		"next round is outlined with the key up").is_false()

	await _hold_floor(true)
	var expected := _field().next_round(_game._board())
	assert_bool(_gas.forecast_node().visible).override_failure_message(
		"holding the floor key does not outline next round").is_true()
	var drawn := _gas.forecast_cells()
	assert_int(drawn.size()).is_equal(expected.size())
	for at: Vector2i in expected:
		assert_int(drawn.get(at, -1)).override_failure_message("the outline disagrees with the round at %s" % [at]).is_equal(expected[at])

	await _hold_floor(false)
	assert_bool(_gas.forecast_node().visible).is_false()
