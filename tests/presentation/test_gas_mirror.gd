# GasMirror (#508's look harness): the store reaching the 3D drawing, on the real Battle3D host. The
# volume's compute passes cannot run headless (no RenderingDevice), so what is asserted here is what
# the mirror HANDS them -- the snapshot, the board textures, the region boxes -- plus the two parts it
# draws itself, the fog floor's mesh and the puffs' instances. Whether any of it LOOKS right is the
# dev's to judge in play; see the PR's How to check this.
#
# Every case paints through the store (GasField.set_amount), never pokes the mirror, and waits for
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


func _style(index: int) -> void:
	Experiments.set_choice(Experiments.Flag.GAS_STYLE, index)
	await _settle()


func test_the_camera_carries_the_volume_effect() -> void:
	var camera := _scene.get_node("CameraRig/Pitch/Camera") as Camera3D
	assert_object(camera.compositor).is_not_null()
	assert_bool(camera.compositor.compositor_effects.has(_gas.volume_effect())).override_failure_message(
		"the gas mirror's effect is not on the Battle3D camera, so the volume is never drawn").is_true()


func test_an_empty_board_hands_the_volume_nothing() -> void:
	await _loaded_cell()
	assert_object(_gas.volume_effect().current()).is_null()
	assert_bool(_gas.floor_node().visible or _gas.puff_node().visible).is_false()


func test_each_style_draws_only_its_own_parts() -> void:
	var cell := await _loaded_cell()
	_field().set_amount(cell, Gas.Kind.STEAM, Gas.MAX_AMOUNT)
	# Realistic: the volume alone.
	await _style(0)
	assert_object(_gas.volume_effect().current()).is_not_null()
	assert_bool(_gas.volume_effect().current().pixel).is_false()
	assert_bool(_gas.floor_node().visible or _gas.puff_node().visible).is_false()
	# Pixel puffs: the floor and the puffs, no volume.
	await _style(1)
	assert_object(_gas.volume_effect().current()).is_null()
	assert_bool(_gas.floor_node().visible and _gas.puff_node().visible).is_true()
	# Realistic + puffs: the volume and the puffs, no floor.
	await _style(2)
	assert_object(_gas.volume_effect().current()).is_not_null()
	assert_bool(_gas.puff_node().visible).is_true()
	assert_bool(_gas.floor_node().visible).is_false()
	# Pixel volume: the volume, marched per art pixel.
	await _style(3)
	assert_bool(_gas.volume_effect().current().pixel).is_true()
	assert_bool(_gas.floor_node().visible or _gas.puff_node().visible).is_false()


func test_the_flat_view_stands_the_gas_down() -> void:
	var cell := await _loaded_cell()
	_field().set_amount(cell, Gas.Kind.STEAM, 8)
	await _style(1)
	var was: int = _scene.get("view")
	_scene.set("view", 1)   # View.FLAT_2D (HD_2D, FLAT_2D, CORNER)
	await _settle()
	assert_bool(_gas.floor_node().visible or _gas.puff_node().visible).is_false()
	await _style(0)
	assert_object(_gas.volume_effect().current()).is_null()
	_scene.set("view", was)


func test_the_layering_switch_picks_the_callback_point() -> void:
	var cell := await _loaded_cell()
	_field().set_amount(cell, Gas.Kind.SMOKE, 8)
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
	_field().set_amount(cell, Gas.Kind.STEAM, 7)
	_field().set_amount(cell, Gas.Kind.SMOKE, 3)
	_field().set_amount(east, Gas.Kind.POISON, 5)
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
	_field().set_amount(cell, Gas.Kind.STEAM, 9)
	await _settle()
	assert_int(_gas.region_boxes().size()).is_equal(1)
	assert_bool(_gas.region_boxes()[0].has_point(BoardSpace.surface_point(cell, _game.board_heights)
		+ Vector3(0, 0.1, 0))).is_true()
	_field().clear()
	await _settle()
	assert_int(_gas.region_boxes().size()).is_equal(0)


func test_gas_on_a_staged_cell_rides_the_diorama() -> void:
	var cell := await _loaded_cell()
	_field().set_amount(cell, Gas.Kind.STEAM, 9)
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
	_field().set_amount(cell, Gas.Kind.FROST, 6)
	await _style(1)
	var mesh := _gas.floor_node().mesh as ArrayMesh
	assert_object(mesh).is_not_null()
	var lift := (_scene.get_node("BoardOverlays") as BoardOverlays).gas_floor_lift()
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_int(vertices.size()).is_greater(0)
	for v in vertices:
		var want := BoardSpace.world_y_of_height(Terrain.height_at_uv(corners, v.x - cell.x, v.z - cell.y)) + lift
		assert_float(v.y).override_failure_message(
			"a floor vertex at %s floats off the surface (want y %f)" % [v, want]).is_equal_approx(want, 0.0001)


func test_puff_counts_follow_the_style_and_the_slot_table() -> void:
	var cell := await _loaded_cell()
	# Any gas whose extra is not the bolt, which appears over only some cells by design.
	var kind := Gas.Kind.STEAM
	for k: Gas.Kind in Gas.Kind.values():
		if GasLook.for_kind(k).extra != GasLook.Extra.BOLT:
			kind = k
			break
	var extra := GasLook.for_kind(kind).extra
	var extras := 2 if extra == GasLook.Extra.SNOW or extra == GasLook.Extra.SOOT else 1
	_field().set_amount(cell, kind, Gas.MAX_AMOUNT)
	var shown_slots := 0
	var crowns := 0
	for slot: Array in GasMirror.SLOTS:
		if Gas.MAX_AMOUNT >= int(slot[1]):
			shown_slots += 1
		if slot[4]:
			crowns += 1
	await _style(1)
	# A full cell shows every slot plus its extras.
	assert_int(_gas.puff_node().multimesh.instance_count).is_equal(shown_slots + extras)
	await _style(2)
	assert_int(_gas.puff_node().multimesh.instance_count).is_equal(crowns)
	await _style(0)
	assert_bool(_gas.puff_node().visible).is_false()


func test_every_gas_node_stays_off_the_ground_layer() -> void:
	# The damp blot's decal paints the ground layer (#358); anything else on it is darkened.
	for node: GeometryInstance3D in [_gas.floor_node(), _gas.puff_node()]:
		assert_int(node.layers).is_equal(BoardOverlays.WORLD_RENDER_LAYER)
