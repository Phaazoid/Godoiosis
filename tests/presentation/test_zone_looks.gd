# How a zone looks on the board (#955 part 1), driven through the REAL zone draw
# (OverlayManager.redraw_zones, the door every caller uses) and asserted on what each view holds: the
# diorama's rim marks, wall and emblems in BoardOverlays and ZoneWalls, and the flat view's twin sprites.
# Colours are asserted as COPIES of the kind's layer colour, never as numbers (the parallel-stacks
# doctrine, test_overlay_mirror's shape).
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"

var _board := SharedBoard.new(SCENE_PATH)
var _scene: Node3D
var game: Node2D
var _overlays: BoardOverlays
var _mirror: OverlayMirror

# Two cells side by side (six outward edges) and one alone (four). Built fresh per case: the store keeps
# what it is handed.
func _zones() -> Dictionary:
	return {
		"cap": {"kind": ZoneManager.Kind.CAPTURE, "cells": [Vector2i(1, 1), Vector2i(2, 1)]},
		"ext": {"kind": ZoneManager.Kind.EXTRACTION, "cells": [Vector2i(6, 6)]},
	}


const ZONE_CELLS: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1), Vector2i(6, 6)]


func before() -> void:
	await _board.open(self, _clear_the_board)


func _clear_the_board() -> void:
	_board.game.scenario_manager.clear_board()
	_board.game.game_state = _board.game.GameState.IDLE


func before_test() -> void:
	await _board.reset(self)
	_scene = _board.scene
	game = _board.game
	_overlays = _scene.get_node("BoardOverlays") as BoardOverlays
	_mirror = _scene.get_node("OverlayMirror") as OverlayMirror
	game.zone_manager.load_dict(_zones())
	_om().redraw_zones(game.zone_manager)


func after_test() -> void:
	await _board.check(self)


func after() -> void:
	_board.close()


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


func _om() -> OverlayManager:
	return game.overlay_manager


func _full(layer: BoardOverlays.Layer) -> Color:
	var colour := _overlays.layer_modulate(layer)
	colour.a = 1.0
	return colour


# The flat view's rim sprites, leaving out its emblems.
func _flat_rims() -> Array[Sprite2D]:
	var rims: Array[Sprite2D] = []
	for sprite in _om()._zone_sprites:
		if is_instance_valid(sprite) and not ZoneMarks.EMBLEMS.values().has(sprite.texture):
			rims.append(sprite)
	return rims


func _texture_counts(textures: Array) -> Dictionary:
	var counts := {}
	for texture: Variant in textures:
		counts[texture] = int(counts.get(texture, 0)) + 1
	return counts


func test_every_zone_cell_wears_a_rim_and_nothing_is_washed() -> void:
	await _settle()
	var washed := _overlays.cells_of(BoardOverlays.Layer.ZONE_CAPTURE).size() \
			+ _overlays.cells_of(BoardOverlays.Layer.ZONE_EXTRACTION).size()
	assert_int(washed).override_failure_message("a zone is still washed under its rim").is_equal(0)
	var marks := _overlays.markers_of(BoardOverlays.Layer.ZONE_MARKS)
	assert_int(marks.size()).is_equal(3)
	var tints: Array[Color] = []
	for mark in marks:
		tints.append(mark["modulate"])
	assert_int(tints.count(_full(BoardOverlays.Layer.ZONE_CAPTURE))).is_equal(2)
	assert_int(tints.count(_full(BoardOverlays.Layer.ZONE_EXTRACTION))).is_equal(1)
	# A lone cell faces out on all four sides, and wears the art made for exactly that.
	var lone := ZoneMarks.texture(ZoneMarks.Side.N | ZoneMarks.Side.E | ZoneMarks.Side.S | ZoneMarks.Side.W)
	var textures: Array = marks.map(func(mark: Dictionary) -> Texture2D: return mark["texture"])
	assert_bool(textures.has(lone)).is_true()


# A ground mark's quad is sized by its art's pixels, so art at the wrong resolution spills past its cell
# (#955's first play: every edge half a cell outside the zone). Asked of the drawn quads themselves.
func test_every_zone_mark_covers_exactly_its_own_cell() -> void:
	await _settle()
	var drawn: Array[Vector2i] = []
	for node: Variant in _overlays._pool_for(BoardOverlays.Layer.ZONE_MARKS):
		var quad := node as MeshInstance3D
		if not quad.visible:
			continue
		var box: AABB = quad.transform * quad.mesh.get_aabb()
		var middle := box.get_center() / BoardSpace.CELL_SIZE
		var cell := Vector2i(floori(middle.x), floori(middle.z))
		assert_bool(ZONE_CELLS.has(cell)).override_failure_message(
				"a zone mark is centred on %s, outside the zone" % cell).is_true()
		assert_vector(Vector2(box.size.x, box.size.z)).override_failure_message(
				"the mark on %s is %s across, not one cell" % [cell, box.size]).is_equal_approx(
				Vector2.ONE * BoardSpace.CELL_SIZE, Vector2.ONE * 0.001)
		assert_vector(Vector2(box.position.x, box.position.z)).is_equal_approx(
				Vector2(cell) * BoardSpace.CELL_SIZE, Vector2.ONE * 0.001)
		drawn.append(cell)
	assert_int(drawn.size()).is_equal(3)


func test_the_wall_stands_one_strip_per_outward_edge_and_goes_with_the_last_zone() -> void:
	await _settle()
	var walls := _mirror.get_node_or_null("ZoneWalls") as ZoneWalls
	assert_object(walls).override_failure_message("a drawn zone built no wall").is_not_null()
	assert_bool(walls.visible).is_true()
	# The decal law walks what EXISTS, and the wall exists only once a zone is drawn -- so it is asked
	# here: off the ground layer, or the damp blot darkens it.
	assert_int(walls.layers & BoardOverlays.GROUND_RENDER_LAYER).override_failure_message(
			"the wall is on the ground layer").is_equal(0)
	assert_int(walls.strip_count).override_failure_message(
			"two cells side by side have six outward edges and a lone cell four").is_equal(10)
	var none_left: Array[String] = ["cap", "ext"]
	_om().redraw_zones(game.zone_manager, none_left)
	await _settle()
	assert_bool(walls.visible).override_failure_message(
			"the wall still stands with no zone drawn").is_false()


# The wall stands just INSIDE its zone: on the border it shares a plane with the face of any block there
# (#955's second report, a crate flickering through it). Every vertex, a hair off in each direction.
func test_the_wall_stands_inside_its_zone_never_on_its_border() -> void:
	await _settle()
	var walls := _mirror.get_node_or_null("ZoneWalls") as ZoneWalls
	assert_object(walls).is_not_null()
	var vertices: PackedVector3Array = walls.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_int(vertices.size()).is_greater(0)
	for vertex in vertices:
		var at := vertex / BoardSpace.CELL_SIZE
		var inside := true
		for dx: float in [-0.001, 0.001]:
			for dz: float in [-0.001, 0.001]:
				inside = inside and ZONE_CELLS.has(Vector2i(floori(at.x + dx), floori(at.z + dz)))
		assert_bool(inside).override_failure_message(
				"a wall vertex at (%.3f, %.3f) stands on or outside its zone's border" % [at.x, at.z]).is_true()


func test_every_zone_wears_one_emblem_and_a_claimed_one_wears_nothing() -> void:
	await _settle()
	var emblems := _overlays.markers_of(BoardOverlays.Layer.ZONE_EMBLEMS)
	assert_int(emblems.size()).is_equal(2)
	var textures: Array = emblems.map(func(mark: Dictionary) -> Texture2D: return mark["texture"])
	assert_bool(textures.has(ZoneMarks.emblem_of(ZoneManager.Kind.CAPTURE))).is_true()
	assert_bool(textures.has(ZoneMarks.emblem_of(ZoneManager.Kind.EXTRACTION))).is_true()

	# Claimed, the zone stops being drawn -- its emblem and its rim go with it.
	var claimed: Array[String] = ["cap"]
	_om().redraw_zones(game.zone_manager, claimed)
	await _settle()
	emblems = _overlays.markers_of(BoardOverlays.Layer.ZONE_EMBLEMS)
	assert_int(emblems.size()).override_failure_message(
			"a claimed zone the board no longer draws still wears its emblem").is_equal(1)
	assert_object(emblems[0]["texture"]).is_same(ZoneMarks.emblem_of(ZoneManager.Kind.EXTRACTION))
	assert_int(_overlays.markers_of(BoardOverlays.Layer.ZONE_MARKS).size()).is_equal(1)


# The flat view's twin (#292 parity): every zone cell wears a rim there too, one tile across, on its
# own cell, in its kind's colour -- and the SAME texture object the diorama draws, so the two views
# cannot disagree about what a zone looks like.
func test_the_flat_view_wears_the_same_rim_on_every_zone_cell() -> void:
	await _settle()
	var grid := _om().board_tilemap as TileMapLayer
	var rims := _flat_rims()
	assert_int(rims.size()).override_failure_message(
			"the flat view draws %d rims for 3 zone cells" % rims.size()).is_equal(3)
	var flat_textures: Array = []
	for rim in rims:
		var cell := grid.local_to_map(rim.position)
		assert_bool(ZONE_CELLS.has(cell)).override_failure_message(
				"a flat rim sits on %s, outside the zone" % cell).is_true()
		assert_vector(rim.texture.get_size() * rim.scale).override_failure_message(
				"the flat rim on %s is not one tile across" % cell).is_equal_approx(
				Vector2(grid.tile_set.tile_size), Vector2.ONE * 0.001)
		var kind: ZoneManager.Kind = ZoneManager.Kind.CAPTURE
		if cell == Vector2i(6, 6):
			kind = ZoneManager.Kind.EXTRACTION
		assert_that(rim.modulate).is_equal(ZoneMarks.colour_of(kind))
		flat_textures.append(rim.texture)
	var marks := _overlays.markers_of(BoardOverlays.Layer.ZONE_MARKS)
	var diorama_textures: Array = marks.map(func(mark: Dictionary) -> Texture2D: return mark["texture"])
	assert_bool(_texture_counts(flat_textures) == _texture_counts(diorama_textures)).override_failure_message(
			"the flat view and the diorama draw different rim art").is_true()


# A zone knob moves BOTH views: the diorama re-reads ZoneMarks every frame, and the flat sprites have to
# be rebuilt with the new art -- the half a knob written for one view forgets.
func test_a_zone_knob_moves_the_flat_view_too() -> void:
	await _settle()
	var before: Array = []
	for rim in _flat_rims():
		before.append(rim.texture)
	var old := ZoneMarks.ZONE_RIM_WIDTH
	GameKnobs.write_static(_scene, "ZONE_RIM_WIDTH", old + 0.1)
	var after := _flat_rims()
	var stale := 0
	for rim in after:
		if before.has(rim.texture):
			stale += 1
	GameKnobs.write_static(_scene, "ZONE_RIM_WIDTH", old)
	assert_int(after.size()).is_equal(3)
	assert_int(stale).override_failure_message(
			"%d flat rims kept their art through a knob move" % stale).is_equal(0)
