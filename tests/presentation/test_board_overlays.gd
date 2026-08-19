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


# The sink deliberately has no whole-board wipe (#318): its layers are partitioned by writer, so
# emptying all of them is always one writer reaching across that line. A sweep over every visible
# quad still needs isolation, and arranging that is this suite's own business, not the sink's.
func _empty_every_layer(overlays: BoardOverlays) -> void:
	for layer: BoardOverlays.Layer in BoardOverlays.LAYERS.keys():
		overlays.clear(layer)


# --- Bracket tinting (#245) ---------------------------------------------------------

func test_a_bracket_layer_can_be_recoloured_at_runtime() -> void:
	# set_layer_modulate was FILL-only and push_error'd on anything else; the invalid-hover red
	# needs it on the BRACKET kind too. Asserted as a property (the layer took the tint, and the
	# tint is not the authored colour) rather than against a value -- the red is a knob.
	var overlays := _overlays()
	var authored := overlays.authored_color(BoardOverlays.Layer.HOVER)
	overlays.set_cells(BoardOverlays.Layer.HOVER, [Vector3i(0, 0, 0)])
	overlays.set_layer_modulate(BoardOverlays.Layer.HOVER, overlays.invalid_bracket_color)
	assert_that(overlays.layer_modulate(BoardOverlays.Layer.HOVER)).is_equal(overlays.invalid_bracket_color)
	assert_bool(overlays.invalid_bracket_color == authored).override_failure_message(
			"the invalid tint IS the authored colour, so nothing could ever look different").is_false()


func test_a_bracket_built_after_a_tint_comes_back_tinted() -> void:
	# The trap: the pool grows ON DEMAND, and _make_bracket read the AUTHORED colour. Tint a layer
	# whose pool is still empty, then ask for a marker, and the fresh node came back gold on a red
	# layer. Invisible to any case that tints a pool which already exists -- which is the only way
	# anyone would naturally write it, so the empty-pool ordering IS the case.
	var overlays: BoardOverlays = auto_free(BoardOverlays.new())
	add_child(overlays)
	var tint := overlays.invalid_bracket_color
	overlays.set_layer_modulate(BoardOverlays.Layer.HOVER, tint)   # pool still empty
	overlays.set_cells(BoardOverlays.Layer.HOVER, [Vector3i(0, 0, 0)])
	var seen := false
	for child in overlays.get_children():
		var bracket := child as MeshInstance3D
		if bracket == null:
			continue
		var material := bracket.material_override as StandardMaterial3D
		if material == null:
			continue
		seen = true
		assert_that(material.albedo_color).override_failure_message(
				"a bracket built after the tint came back the authored colour").is_equal(tint)
	assert_bool(seen).override_failure_message("no bracket node was built at all").is_true()


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
	_empty_every_layer(overlays)  # the demo's zone patch legitimately coexists; isolate for the color sweep
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


# Clearing is PER LAYER and reaches no further — the property the writer partition rests on
# (#318). A clear that spilled into a neighbouring layer would desync whichever writer caches
# for it, which is exactly the board-load bug in miniature.
func test_clear_empties_its_own_layer_and_leaves_the_others_standing() -> void:
	var overlays := _overlays()
	overlays.set_cells(BoardOverlays.Layer.MOVE, [Vector3i(2, 0, 2)])
	overlays.set_cells(BoardOverlays.Layer.ATTACK, [Vector3i(3, 0, 2)])
	overlays.clear(BoardOverlays.Layer.MOVE)
	assert_int(overlays.marker_count(BoardOverlays.Layer.MOVE)).is_equal(0)
	assert_int(overlays.marker_count(BoardOverlays.Layer.ATTACK)).is_equal(1)


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


# --- Markup lies on the surface it marks (#281) ------------------------------------

# A fresh sink rather than the demo scene's: these cases read a single quad's transform, and the
# demo's own zone patch would put other visible quads in the same child sweep.
func _bare_overlays() -> BoardOverlays:
	var overlays: BoardOverlays = auto_free(BoardOverlays.new())
	add_child(overlays)
	return overlays


func _ramp_at(cell: Vector2i, level: int) -> BoardHeights:
	var heights := BoardHeights.new()
	heights.set_cell(cell, level, Terrain.RampRise.EAST)
	return heights


# The quad's own facing, which is what "flat against the ground" means. basis.y is the normal; it
# carries no art scale, so it compares clean.
func _normal_of(overlays: BoardOverlays) -> Vector3:
	for child in overlays.get_children():
		var quad := child as MeshInstance3D
		if quad != null and quad.visible and quad.mesh is PlaneMesh:
			return quad.basis.y.normalized()
	return Vector3.ZERO


func test_a_fill_on_a_ramp_lies_on_the_slope_instead_of_hanging_level_through_it() -> void:
	# The fill half of #281, and with it the anchoring defect it shared a cause with: _fill resolved
	# a cell to its RULES level (the ramp's low edge) while every marker went through surface_point's
	# midpoint, so a move tile and a path arrow on one ramp cell disagreed by half a level.
	# Both halves are derived from the seam here, never from a literal.
	var cell := Vector2i(3, 2)
	var heights := _ramp_at(cell, 1)
	var overlays := _bare_overlays()
	overlays.set_cells(BoardOverlays.Layer.MOVE, [BoardSpace.of_cell(cell, 1)], heights)

	var expected := BoardSpace.surface_transform(cell, heights)
	assert_that(_normal_of(overlays)).is_equal(expected.basis.y.normalized())
	assert_bool(_normal_of(overlays).is_equal_approx(Vector3.UP)).override_failure_message(
			"the fill is still level -- it would cut through the slope").is_false()

	for child in overlays.get_children():
		var quad := child as MeshInstance3D
		if quad != null and quad.visible and quad.mesh is PlaneMesh:
			# The clearance rides the surface normal, so the height is the surface's plus a lift
			# smaller than the half-level the ramp midpoint itself contributes.
			var above := quad.position.y - expected.origin.y
			assert_float(above).is_between(0.0, BoardSpace.CELL_SIZE * 0.5)


func test_a_marker_lies_on_the_slope_its_own_cell_carries() -> void:
	var cell := Vector2i(3, 2)
	var heights := _ramp_at(cell, 1)
	var surface := BoardSpace.surface_transform(cell, heights)
	var overlays := _bare_overlays()
	overlays.set_markers(BoardOverlays.Layer.PATH_ARROWS, [{
		"pos": surface.origin, "texture": GridUtils.ERROR_ICON,
		"modulate": Color.WHITE, "basis": surface.basis,
	}])
	assert_that(_normal_of(overlays)).is_equal(surface.basis.y.normalized())


func test_an_entry_with_no_basis_still_draws_flat() -> void:
	# Every pre-#281 caller -- and the ghost channel, which ignores the key -- omits it.
	var overlays := _bare_overlays()
	overlays.set_markers(BoardOverlays.Layer.PATH_ARROWS, [
		{"pos": Vector3(2.5, 1.0, 2.5), "texture": GridUtils.ERROR_ICON, "modulate": Color.WHITE}])
	assert_that(_normal_of(overlays)).is_equal(Vector3.UP)


func test_a_pooled_marker_reused_on_flat_ground_drops_the_tilt_it_had() -> void:
	# Marker nodes are REUSED between frames, so the tilt is written unconditionally rather than only
	# when a cell ramps. A mutant that sets the basis only for ramps passes every case above and
	# fails here: walk an arrow off a ramp and it keeps sloping over flat ground forever.
	var cell := Vector2i(3, 2)
	var surface := BoardSpace.surface_transform(cell, _ramp_at(cell, 1))
	var overlays := _bare_overlays()
	overlays.set_markers(BoardOverlays.Layer.PATH_ARROWS, [{
		"pos": surface.origin, "texture": GridUtils.ERROR_ICON,
		"modulate": Color.WHITE, "basis": surface.basis,
	}])
	assert_that(_normal_of(overlays)).is_not_equal(Vector3.UP)   # the precondition, not the claim

	overlays.set_markers(BoardOverlays.Layer.PATH_ARROWS, [
		{"pos": Vector3(9.5, 1.0, 9.5), "texture": GridUtils.ERROR_ICON, "modulate": Color.WHITE}])
	assert_that(_normal_of(overlays)).is_equal(Vector3.UP)


func test_a_fill_pooled_off_a_ramp_drops_the_tilt_too() -> void:
	# The same reuse hazard on the set_cells path, which writes a whole transform per frame.
	var cell := Vector2i(3, 2)
	var overlays := _bare_overlays()
	overlays.set_cells(BoardOverlays.Layer.MOVE, [BoardSpace.of_cell(cell, 1)], _ramp_at(cell, 1))
	assert_that(_normal_of(overlays)).is_not_equal(Vector3.UP)

	overlays.set_cells(BoardOverlays.Layer.MOVE, [BoardSpace.of_cell(Vector2i(9, 9), 0)], BoardHeights.new())
	assert_that(_normal_of(overlays)).is_equal(Vector3.UP)


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


# --- Sort order against the 2D authority -------------------------------------------

func test_terrain_state_sorts_under_the_plan_exactly_as_2d_orders_it() -> void:
	# Reported in play: freeze icons drew over path arrows and over planning ghosts. The 2D is
	# the authority and it is unambiguous — TERRAIN_Z_INDEX is "above the board, below unit
	# sprites" while arrows sit higher — and the 3D table had TERRAIN at the TOP of its range.
	# Tie the two orders together rather than pinning either number, so changing EITHER side
	# reds and the sorts stay free to be retuned.
	var terrain_under_arrows_in_2d: bool = OverlayManager.TERRAIN_Z_INDEX < MoveAction.ARROW_BASE_Z_INDEX
	var terrain: int = BoardOverlays.LAYERS[BoardOverlays.Layer.TERRAIN]["sort"]
	var preview: int = BoardOverlays.LAYERS[BoardOverlays.Layer.TERRAIN_PREVIEW]["sort"]
	var arrows: int = BoardOverlays.LAYERS[BoardOverlays.Layer.PATH_ARROWS]["sort"]
	assert_bool(terrain_under_arrows_in_2d).override_failure_message(
			"the 2D order changed; decide the 3D order deliberately rather than following this test").is_true()
	assert_bool(terrain < arrows).override_failure_message(
			"terrain state (%d) sorts at or above path arrows (%d) — the 3D contradicts the 2D" % [terrain, arrows]).is_true()
	assert_int(preview).override_failure_message(
			"the preview channel drifted from the live one").is_equal(terrain)


func test_the_zone_layers_copy_the_2d_zone_colors() -> void:
	# Parallel stacks: a mirrored colour is COPIED from the 2D's own constant, never
	# restated. Asserted against OverlayManager rather than against literals, so changing
	# one side alone goes red instead of silently drifting (#231).
	assert_that(BoardOverlays.LAYERS[BoardOverlays.Layer.ZONE_PATROL]["color"]) \
		.is_equal(OverlayManager.ZONE_PATROL_MODULATE)
	assert_that(BoardOverlays.LAYERS[BoardOverlays.Layer.ZONE_HIGHLIGHT]["color"]) \
		.is_equal(OverlayManager.ZONE_HIGHLIGHT_MODULATE)


func test_the_picked_zone_highlight_sorts_above_the_zones_it_highlights() -> void:
	# A RELATIONSHIP, not numbers. In 2D the highlight wins by tree order (it is appended
	# last); 3D has no tree order for this, so the sort number carries the whole fact — and
	# an equal sort would also mean an equal geometric lift, i.e. z-fighting.
	var highlight: int = BoardOverlays.LAYERS[BoardOverlays.Layer.ZONE_HIGHLIGHT]["sort"]
	for zone: BoardOverlays.Layer in [BoardOverlays.Layer.ZONE_PATROL,
			BoardOverlays.Layer.ZONE_CAPTURE, BoardOverlays.Layer.ZONE_EXTRACTION]:
		var sort: int = BoardOverlays.LAYERS[zone]["sort"]
		assert_int(highlight).override_failure_message(
				"the picked-zone highlight sorts at %d, not above zone layer %d at %d" \
				% [highlight, zone, sort]).is_greater(sort)
	# The three zone kinds share one band — they never overlap in 2D either.
	assert_int(BoardOverlays.LAYERS[BoardOverlays.Layer.ZONE_PATROL]["sort"]) \
		.is_equal(BoardOverlays.LAYERS[BoardOverlays.Layer.ZONE_CAPTURE]["sort"])


func test_no_overlay_layer_can_sort_over_a_unit() -> void:
	# The structural half, and the one that covers planning ghosts: a ghost is a UnitSprite3D,
	# so board markup must sit below UNIT_RENDER_PRIORITY by construction — not because the
	# numbers happen to land that way today. A new layer added above units reds here.
	for layer: BoardOverlays.Layer in BoardOverlays.LAYERS:
		var sort: int = BoardOverlays.LAYERS[layer]["sort"]
		assert_int(sort).override_failure_message(
				"layer %d sorts at %d, at or above UNIT_RENDER_PRIORITY — it would draw over units and ghosts" \
				% [layer, sort]).is_less(BoardOverlays.UNIT_RENDER_PRIORITY)


func test_no_overlay_layer_can_sort_over_the_flame() -> void:
	# Fire's 3D form is a standing effect, not markup lying on the face (#245, found in play: a
	# frost icon at sort 2 drew over a flame sitting at the default 0, and the fire read as
	# erased). Structural, like the unit pin above — a new layer added above the flame reds here
	# rather than being discovered by painting ice on a bonfire.
	for layer: BoardOverlays.Layer in BoardOverlays.LAYERS:
		var sort: int = BoardOverlays.LAYERS[layer]["sort"]
		assert_int(sort).override_failure_message(
				"layer %d sorts at %d, at or above FLAME_RENDER_PRIORITY — it would draw over fire" \
				% [layer, sort]).is_less(BoardOverlays.FLAME_RENDER_PRIORITY)
	# ...and the flame still sits BELOW units, so the flame-vs-sprite trade #236 argued over
	# (and the dev reverted) is untouched by giving the flame a band of its own.
	assert_int(BoardOverlays.FLAME_RENDER_PRIORITY).override_failure_message(
			"the flame now sorts at or above units, which re-opens #236's swallowed-body trade") \
			.is_less(BoardOverlays.UNIT_RENDER_PRIORITY)


func test_markup_that_hangs_in_the_air_sorts_above_markup_that_lies_on_the_floor() -> void:
	# A RELATIONSHIP, not a value (#325 follow-up, found in play: the crown drew under the
	# squad rings). Every FILL/SPRITE layer is markup lying on the board face; a BILLBOARD
	# stands in the volume above it, so it can never sort behind one -- the dev put it as
	# rings are on the floor and should not draw above anything. Pinning the relation rather
	# than the numbers leaves both free to be retuned.
	var floor_top := -9999
	var air_low := 9999
	for layer: BoardOverlays.Layer in BoardOverlays.LAYERS:
		var spec: Dictionary = BoardOverlays.LAYERS[layer]
		if spec["kind"] == BoardOverlays.Kind.BILLBOARD:
			air_low = mini(air_low, spec["sort"])
		else:
			floor_top = maxi(floor_top, spec["sort"])
	# Non-vacuity: with no billboard layer declared, the compare below is trivially true.
	assert_int(air_low).override_failure_message(
			"no BILLBOARD layer is declared, so this case proves nothing").is_not_equal(9999)
	assert_int(air_low).override_failure_message(
			"a layer hanging in the air sorts at %d, at or below floor markup at %d" \
			% [air_low, floor_top]).is_greater(floor_top)


func test_a_unit_sprite_actually_carries_that_priority() -> void:
	# Test the wire: the constant is worth nothing if no sprite reads it, and ghosts are built
	# by UnitMirror through the same plain constructor rather than for_unit_data.
	var sprite := UnitSprite3D.new()
	assert_int(sprite.render_priority).override_failure_message(
			"UnitSprite3D does not apply UNIT_RENDER_PRIORITY — the constant is inert").is_equal(
			BoardOverlays.UNIT_RENDER_PRIORITY)
	sprite.free()


# --- Atlas cuts on a marker quad (#316) ---------------------------------------------

# A synthetic sheet, never the real overlay art: what a marker's tile looks like is authored
# content, and the rule under test is the UV arithmetic, which any two-cell sheet exercises.
func _atlas_cut(sheet: Vector2i, region: Rect2) -> AtlasTexture:
	var image := Image.create_empty(sheet.x, sheet.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var cut := AtlasTexture.new()
	cut.atlas = ImageTexture.create_from_image(image)
	cut.region = region
	return cut


func _only_visible_quad(overlays: BoardOverlays) -> MeshInstance3D:
	for child in overlays.get_children():
		var quad := child as MeshInstance3D
		if quad != null and quad.visible:
			return quad
	return null


func test_an_atlas_cut_draws_its_own_tile_and_not_the_whole_sheet() -> void:
	# #316: a StandardMaterial3D ignores an AtlasTexture's region, so the target-pick marker
	# came out as the ENTIRE 32x16 sheet squashed into one cell -- half the plain fill, half
	# the marker, both at 2:1. The quad's SIZE was right all along (AtlasTexture.get_size()
	# reports the region), which is exactly why this reads as a stretch rather than a miss.
	var overlays: BoardOverlays = auto_free(BoardOverlays.new())
	add_child(overlays)
	var cut := _atlas_cut(Vector2i(32, 16), Rect2(16, 0, 16, 16))
	overlays.set_markers(BoardOverlays.Layer.TARGET_PICK,
			[{"pos": Vector3(2.5, 1.0, 2.5), "texture": cut, "modulate": Color.WHITE}])
	var material := _only_visible_quad(overlays).material_override as StandardMaterial3D
	assert_that(material.uv1_scale).is_equal(Vector3(0.5, 1.0, 1.0))
	assert_that(material.uv1_offset).is_equal(Vector3(0.5, 0.0, 0.0))


func test_a_pooled_quad_drops_the_cut_uvs_when_it_next_draws_a_plain_texture() -> void:
	# The pooling trap the tilt and the art scale are already written against: the node that
	# drew the cut is REUSED, so UVs left behind would crop whatever art lands on it next.
	var overlays: BoardOverlays = auto_free(BoardOverlays.new())
	add_child(overlays)
	var cut := _atlas_cut(Vector2i(32, 16), Rect2(16, 0, 16, 16))
	overlays.set_markers(BoardOverlays.Layer.TARGET_PICK,
			[{"pos": Vector3(2.5, 1.0, 2.5), "texture": cut, "modulate": Color.WHITE}])
	var quad := _only_visible_quad(overlays)
	overlays.set_markers(BoardOverlays.Layer.TARGET_PICK,
			[{"pos": Vector3(3.5, 1.0, 2.5), "texture": GridUtils.ERROR_ICON, "modulate": Color.WHITE}])
	assert_object(_only_visible_quad(overlays)).override_failure_message(
			"the pool grew instead of reusing — this case no longer tests reuse").is_same(quad)
	var material := quad.material_override as StandardMaterial3D
	assert_that(material.uv1_scale).is_equal(Vector3.ONE)
	assert_that(material.uv1_offset).is_equal(Vector3.ZERO)
