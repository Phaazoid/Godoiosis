# BoardOverlays (#213): the layer table's completeness (law-style), set_cells'
# replace semantics (idempotent, no accumulation), the mask contract between fill
# decals and UnitSprite3D render layers (the drift test), the hover bracket, the
# ruling-respecting reachable set, and the demo wire in the real scene. Colors,
# sorts and bracket proportions are feel values — asserted present, never pinned
# to numbers.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/LookDev/LookDev.tscn"
const UnitWalkDemo := preload("res://Scenes/LookDev/unit_walk_demo.gd")

var _scene: Node3D


func before_test() -> void:
	_scene = (load(SCENE_PATH) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(_scene)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_scene)
	_scene.free()


func _overlays() -> BoardOverlays:
	return _scene.get_node("BoardOverlays") as BoardOverlays


# --- The table and the contract ----------------------------------------------------

func test_every_layer_is_declared_in_the_table() -> void:
	for layer: BoardOverlays.Layer in BoardOverlays.Layer.values():
		assert_bool(BoardOverlays.LAYERS.has(layer)).is_true()
		var spec: Dictionary = BoardOverlays.LAYERS[layer]
		assert_bool(spec.has("color") and spec.has("sort") and spec.has("kind")).is_true()


func test_fill_decals_never_paint_the_unit_render_layer() -> void:
	# The drift test: either side moving its layer bit reds this.
	var overlays := _overlays()
	overlays.set_cells(BoardOverlays.Layer.MOVE, [Vector3i(2, 0, 2)])
	var sprite: UnitSprite3D = auto_free(UnitSprite3D.new())
	var decal_seen := false
	for child in overlays.get_children():
		var decal := child as Decal
		if decal != null and decal.visible:
			decal_seen = true
			assert_int(decal.cull_mask & sprite.layers).is_equal(0)
	assert_bool(decal_seen).is_true()


# --- set_cells semantics -----------------------------------------------------------

func test_set_cells_places_tinted_fills_at_the_cells() -> void:
	var overlays := _overlays()
	overlays.clear_all()  # the demo's zone patch legitimately coexists; isolate for the color sweep
	var cells: Array[Vector3i] = [Vector3i(2, 0, 2), Vector3i(3, 0, 2), Vector3i(9, 2, 3)]
	overlays.set_cells(BoardOverlays.Layer.MOVE, cells)
	assert_int(overlays.marker_count(BoardOverlays.Layer.MOVE)).is_equal(3)
	assert_that(overlays.cells_of(BoardOverlays.Layer.MOVE)).is_equal(cells)
	var expected_color: Color = BoardOverlays.LAYERS[BoardOverlays.Layer.MOVE]["color"]
	for child in overlays.get_children():
		var decal := child as Decal
		if decal != null and decal.visible:
			assert_that(decal.modulate).is_equal(expected_color)


func test_a_smaller_set_replaces_the_previous_one() -> void:
	var overlays := _overlays()
	overlays.set_cells(BoardOverlays.Layer.MOVE,
			[Vector3i(2, 0, 2), Vector3i(3, 0, 2), Vector3i(4, 0, 2)])
	overlays.set_cells(BoardOverlays.Layer.MOVE, [Vector3i(5, 0, 5)])
	assert_int(overlays.marker_count(BoardOverlays.Layer.MOVE)).is_equal(1)
	assert_int(overlays.cells_of(BoardOverlays.Layer.MOVE).size()).is_equal(1)


func test_clear_and_clear_all_empty_the_layers() -> void:
	var overlays := _overlays()
	overlays.set_cells(BoardOverlays.Layer.MOVE, [Vector3i(2, 0, 2)])
	overlays.set_cells(BoardOverlays.Layer.ATTACK, [Vector3i(3, 0, 2)])
	overlays.clear(BoardOverlays.Layer.MOVE)
	assert_int(overlays.marker_count(BoardOverlays.Layer.MOVE)).is_equal(0)
	assert_int(overlays.marker_count(BoardOverlays.Layer.ATTACK)).is_equal(1)
	overlays.clear_all()
	assert_int(overlays.marker_count(BoardOverlays.Layer.ATTACK)).is_equal(0)


func test_hover_is_a_bracket_mesh_at_the_cell() -> void:
	var overlays := _overlays()
	var cell := Vector3i(4, 0, 4)
	overlays.set_cells(BoardOverlays.Layer.HOVER, [cell])
	assert_int(overlays.marker_count(BoardOverlays.Layer.HOVER)).is_equal(1)
	var bracket_seen := false
	for child in overlays.get_children():
		var bracket := child as MeshInstance3D
		if bracket != null and bracket.visible:
			bracket_seen = true
			assert_that(bracket.position).is_equal(BoardSpace.cell_center(cell))
			assert_object(bracket.mesh).is_not_null()
	assert_bool(bracket_seen).is_true()


# --- find_reachable under the traversal ruling -------------------------------------

func test_reachable_respects_the_ramp_ruling_and_the_cap() -> void:
	var tops: Dictionary[Vector2i, int] = {
		Vector2i(0, 0): 1, Vector2i(1, 0): 2, Vector2i(2, 0): 2, Vector2i(3, 0): 2,
	}
	var exits: Dictionary[Vector2i, Array] = {
		Vector2i(1, 0): [Vector2i(2, 0), Vector2i(0, 0)],
	}
	var one_step := UnitWalkDemo.find_reachable(Vector3i(0, 0, 0), 1, tops, {}, exits)
	assert_that(one_step).is_equal([Vector3i(1, 1, 0)] as Array[Vector3i])
	var three_steps := UnitWalkDemo.find_reachable(Vector3i(0, 0, 0), 3, tops, {}, exits)
	assert_int(three_steps.size()).is_equal(3)
	var no_ramp := UnitWalkDemo.find_reachable(Vector3i(0, 0, 0), 3, tops, {}, {})
	assert_int(no_ramp.size()).is_equal(0)  # the climb needs the ramp


# --- The demo wire -----------------------------------------------------------------

func test_selection_paints_move_and_attack_and_deselect_clears() -> void:
	var demo := _scene.get_node("WalkDemo")
	var overlays := _overlays()
	var unit: UnitSprite3D = demo.units()[0]  # on the plain at (5, 8)
	demo._select(unit)
	var move_cells := overlays.cells_of(BoardOverlays.Layer.MOVE)
	assert_bool(move_cells.size() > 0).is_true()
	assert_bool(move_cells.has(Vector3i(5, 0, 7))).is_true()  # an adjacent plain cell
	assert_bool(overlays.cells_of(BoardOverlays.Layer.ATTACK).size() > 0).is_true()
	demo._select(unit)  # clicking the selected unit deselects
	assert_int(overlays.marker_count(BoardOverlays.Layer.MOVE)).is_equal(0)
	assert_int(overlays.marker_count(BoardOverlays.Layer.ATTACK)).is_equal(0)


func test_the_zone_patch_outlives_selection_churn() -> void:
	var demo := _scene.get_node("WalkDemo")
	var overlays := _overlays()
	assert_int(overlays.cells_of(BoardOverlays.Layer.ZONE_EXTRACTION).size()).is_equal(9)
	var unit: UnitSprite3D = demo.units()[0]
	demo._select(unit)
	demo._select(unit)
	assert_int(overlays.cells_of(BoardOverlays.Layer.ZONE_EXTRACTION).size()).is_equal(9)
