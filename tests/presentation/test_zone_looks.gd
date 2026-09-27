# The zone-look experiment (#955 part 1), driven through the REAL zone draw (OverlayManager.redraw_zones,
# the door every caller uses) and the REAL experiment store, and asserted on what BoardOverlays holds.
# The look is read every frame, so a flip must show on the next frame with nothing else redrawn --
# that WIRE is the case this suite exists for. Colours are asserted as COPIES of the kind's live layer
# colour, never as numbers (the parallel-stacks doctrine, test_overlay_mirror's shape).
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


func _look(which: ZoneMarks.Look) -> void:
	Experiments.set_choice(Experiments.Flag.ZONE_LOOK, which)


func _wash_cells() -> int:
	return _overlays.cells_of(BoardOverlays.Layer.ZONE_CAPTURE).size() \
			+ _overlays.cells_of(BoardOverlays.Layer.ZONE_EXTRACTION).size()


func _full(layer: BoardOverlays.Layer) -> Color:
	var colour := _overlays.layer_modulate(layer)
	colour.a = 1.0
	return colour


func test_under_the_tint_the_zones_wash_and_wear_no_edge() -> void:
	await _settle()
	assert_int(ZoneMarks.look()).override_failure_message(
			"a headless run reads the declared default, and that default is today's look").is_equal(
			ZoneMarks.Look.TINT)
	assert_int(_wash_cells()).is_equal(3)
	assert_int(_overlays.markers_of(BoardOverlays.Layer.ZONE_MARKS).size()).is_equal(0)


func test_an_edge_look_replaces_the_wash_with_one_mark_per_zone_cell() -> void:
	_look(ZoneMarks.Look.PAINTED_EDGE)
	await _settle()
	assert_int(_wash_cells()).override_failure_message(
			"the wash still draws under an edge look -- the edge was meant to replace it").is_equal(0)
	var marks := _overlays.markers_of(BoardOverlays.Layer.ZONE_MARKS)
	assert_int(marks.size()).is_equal(3)
	var tints: Array[Color] = []
	for mark in marks:
		tints.append(mark["modulate"])
	assert_int(tints.count(_full(BoardOverlays.Layer.ZONE_CAPTURE))).is_equal(2)
	assert_int(tints.count(_full(BoardOverlays.Layer.ZONE_EXTRACTION))).is_equal(1)
	# A lone cell faces out on all four sides, and wears the art made for exactly that.
	var lone := ZoneMarks.texture(ZoneMarks.Look.PAINTED_EDGE,
			ZoneMarks.Side.N | ZoneMarks.Side.E | ZoneMarks.Side.S | ZoneMarks.Side.W)
	var textures: Array = marks.map(func(mark: Dictionary) -> Texture2D: return mark["texture"])
	assert_bool(textures.has(lone)).is_true()


# THE WIRE: nothing redraws the zones between the flips, so only the per-frame read of the look can
# move the board.
func test_flipping_the_look_switches_the_board_on_the_next_frame() -> void:
	await _settle()
	assert_int(_wash_cells()).is_equal(3)
	_look(ZoneMarks.Look.SOFT_RIM)
	await _settle()
	assert_int(_wash_cells()).is_equal(0)
	assert_int(_overlays.markers_of(BoardOverlays.Layer.ZONE_MARKS).size()).is_equal(3)
	_look(ZoneMarks.Look.TINT)
	await _settle()
	assert_int(_wash_cells()).is_equal(3)
	assert_int(_overlays.markers_of(BoardOverlays.Layer.ZONE_MARKS).size()).is_equal(0)


func test_the_light_wall_stands_one_strip_per_outward_edge() -> void:
	_look(ZoneMarks.Look.LIGHT_WALL)
	await _settle()
	var walls := _mirror.get_node_or_null("ZoneWalls") as ZoneWalls
	assert_object(walls).override_failure_message("look C built no wall").is_not_null()
	assert_bool(walls.visible).is_true()
	assert_int(walls.strip_count).override_failure_message(
			"two cells side by side have six outward edges and a lone cell four").is_equal(10)
	# ...and it goes when the look does.
	_look(ZoneMarks.Look.PAINTED_EDGE)
	await _settle()
	assert_bool(walls.visible).is_false()


func test_every_zone_wears_one_emblem_inside_it_and_a_claimed_one_wears_nothing() -> void:
	_look(ZoneMarks.Look.PAINTED_EDGE)
	await _settle()
	var emblems := _overlays.markers_of(BoardOverlays.Layer.ZONE_EMBLEMS)
	assert_int(emblems.size()).is_equal(2)
	var textures: Array = emblems.map(func(mark: Dictionary) -> Texture2D: return mark["texture"])
	assert_bool(textures.has(ZoneMarks.emblem_of(ZoneManager.Kind.CAPTURE))).is_true()
	assert_bool(textures.has(ZoneMarks.emblem_of(ZoneManager.Kind.EXTRACTION))).is_true()

	# Claimed, the zone stops being drawn -- its emblem and its edge go with it.
	_om().redraw_zones(game.zone_manager, ["cap"])
	await _settle()
	emblems = _overlays.markers_of(BoardOverlays.Layer.ZONE_EMBLEMS)
	assert_int(emblems.size()).override_failure_message(
			"a claimed zone the board no longer draws still wears its emblem").is_equal(1)
	assert_object(emblems[0]["texture"]).is_same(ZoneMarks.emblem_of(ZoneManager.Kind.EXTRACTION))
	assert_int(_overlays.markers_of(BoardOverlays.Layer.ZONE_MARKS).size()).is_equal(1)


func test_the_emblem_is_under_every_look() -> void:
	for which: ZoneMarks.Look in ZoneMarks.Look.values():
		_look(which)
		await _settle()
		assert_int(_overlays.markers_of(BoardOverlays.Layer.ZONE_EMBLEMS).size()).override_failure_message(
				"look %s dropped the emblems" % ZoneMarks.Look.keys()[which]).is_equal(2)
