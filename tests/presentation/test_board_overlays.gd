# BoardOverlays (#213 / #222): the layer table's completeness (law-style), the
# unshaded ruling on every quad and billboard (the dev's markup-is-not-terrain
# call), set_cells/set_markers replace semantics (idempotent, no accumulation),
# the render-layer mask contract, the hover bracket, the ruling-respecting
# reachable set, and the demo wire in the real scene. Colors, sorts, lifts and
# bracket proportions are feel values — asserted present, never pinned to numbers.
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


func test_every_fill_and_marker_material_is_unshaded() -> void:
	# The dev's ruling (#214/#222): gameplay markup must never read as terrain, so
	# every quad is UNSHADED and every billboard unshaded — lighting cannot touch it.
	var overlays := _overlays()
	overlays.set_cells(BoardOverlays.Layer.MOVE, [Vector3i(2, 0, 2)])
	overlays.set_markers(BoardOverlays.Layer.TERRAIN,
			[{"pos": Vector3(2.5, 1.0, 2.5), "texture": GridUtils.ERROR_ICON, "modulate": Color.WHITE}])
	overlays.set_markers(BoardOverlays.Layer.ICONS,
			[{"pos": Vector3(2.5, 1.0, 2.5), "texture": GridUtils.ERROR_ICON, "modulate": Color.WHITE}])
	var quads := 0
	var billboards := 0
	for child in overlays.get_children():
		if child is Sprite3D:
			billboards += 1
			assert_bool((child as Sprite3D).shaded).is_false()
			continue
		var quad := child as MeshInstance3D
		if quad != null and quad.material_override is StandardMaterial3D:
			quads += 1
			var material := quad.material_override as StandardMaterial3D
			assert_int(material.shading_mode).is_equal(BaseMaterial3D.SHADING_MODE_UNSHADED)
	assert_bool(quads > 0 and billboards > 0).is_true()


func test_fill_quads_never_render_on_the_unit_layer() -> void:
	# The drift test: either side moving its layer bit reds this.
	var overlays := _overlays()
	overlays.set_cells(BoardOverlays.Layer.MOVE, [Vector3i(2, 0, 2)])
	var sprite: UnitSprite3D = auto_free(UnitSprite3D.new())
	var quad_seen := false
	for child in overlays.get_children():
		var quad := child as MeshInstance3D
		if quad != null and quad.visible and quad.material_override is StandardMaterial3D:
			quad_seen = true
			assert_int(int(quad.layers) & int(sprite.layers)).is_equal(0)
	assert_bool(quad_seen).is_true()


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
		var quad := child as MeshInstance3D
		if quad != null and quad.visible and quad.material_override is StandardMaterial3D:
			assert_that((quad.material_override as StandardMaterial3D).albedo_color).is_equal(expected_color)


func test_set_markers_replaces_wholesale_and_carries_the_variant() -> void:
	var overlays := _overlays()
	var arrow := GridUtils.ERROR_ICON
	var first: Array[Dictionary] = [
		{"pos": Vector3(2.5, 1.0, 2.5), "texture": arrow, "modulate": Color(1, 0.25, 0.25, 0.85)},
		{"pos": Vector3(3.5, 1.0, 2.5), "texture": arrow, "modulate": Color.WHITE},
	]
	overlays.set_markers(BoardOverlays.Layer.PATH_ARROWS, first)
	assert_int(overlays.marker_count(BoardOverlays.Layer.PATH_ARROWS)).is_equal(2)
	assert_that(overlays.markers_of(BoardOverlays.Layer.PATH_ARROWS)).is_equal(first)
	# The pool re-tints and re-textures on replace — a shrunk set hides extras, not leaks them.
	var second: Array[Dictionary] = [
		{"pos": Vector3(5.5, 1.0, 5.5), "texture": arrow, "modulate": Color(0.4, 1, 0.45, 0.9)},
	]
	overlays.set_markers(BoardOverlays.Layer.PATH_ARROWS, second)
	assert_int(overlays.marker_count(BoardOverlays.Layer.PATH_ARROWS)).is_equal(1)
	var tinted := 0
	for child in overlays.get_children():
		var quad := child as MeshInstance3D
		if quad != null and quad.visible and quad.material_override is StandardMaterial3D:
			var material := quad.material_override as StandardMaterial3D
			if material.albedo_texture == arrow:
				tinted += 1
				assert_that(material.albedo_color).is_equal(Color(0.4, 1, 0.45, 0.9))
	assert_int(tinted).is_equal(1)


func test_set_layer_modulate_recolors_a_fill_pool_live() -> void:
	# The heal-green reach / aim pulse channel: the 2D layer's live modulate arrives
	# as a runtime recolor, never a rebuild.
	var overlays := _overlays()
	overlays.set_cells(BoardOverlays.Layer.ATTACK, [Vector3i(2, 0, 2), Vector3i(3, 0, 2)])
	var green := Color(0, 1, 0, 0.5)
	overlays.set_layer_modulate(BoardOverlays.Layer.ATTACK, green)
	assert_that(overlays.layer_modulate(BoardOverlays.Layer.ATTACK)).is_equal(green)
	# A marker created AFTER the recolor joins at the live color, not the table's.
	overlays.set_cells(BoardOverlays.Layer.ATTACK,
			[Vector3i(2, 0, 2), Vector3i(3, 0, 2), Vector3i(4, 0, 2), Vector3i(5, 0, 2)])
	var seen := 0
	for child in overlays.get_children():
		var quad := child as MeshInstance3D
		if quad != null and quad.visible and quad.material_override is StandardMaterial3D:
			var material := quad.material_override as StandardMaterial3D
			if material.albedo_color == green:
				seen += 1
	assert_int(seen).is_equal(4)


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
		# Brackets are the code-built ArrayMesh; fill/sprite quads share a PlaneMesh.
		if bracket != null and bracket.visible and bracket.mesh is ArrayMesh:
			bracket_seen = true
			assert_that(bracket.position).is_equal(BoardSpace.cell_center(cell))
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
