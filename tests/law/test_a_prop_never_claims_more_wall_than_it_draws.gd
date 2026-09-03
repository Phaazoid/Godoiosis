# A wall the rules stop a shot on, that the player can see straight over (#660).
#
# #660 gave every standing prop a RULES height the sight trace reads as a column. It is deliberately
# a second column beside `prop_height_scale` rather than derived from it, because #642 ruled that
# knob a 3/4-perspective LOOK correction that must never source legality. The cost of that split is
# that the two can disagree, and one direction of disagreement is a real bug the player experiences:
# a shot that dies on a wall drawn far shorter than the rule reads.
#
# The art's ceiling is measured, not guessed. A PLANE slab is built from y = 0 to PLANE_HEIGHT
# (13/16 of a cell) and `prop_height_scale` caps at 2.5, so a wall tops out near two LEVELS however
# it is authored -- `GridUtils.MAX_DRAWABLE_RULE_HEIGHT`, in the board's height units.
#
# THIS IS A CEILING, NOT AN AGREEMENT CHECK, and that is on purpose. The drawn height resolves a
# LIVE knob (`block_height_scale`, a Game-tab row), so a law asserting the two agree would go red on
# a purely cosmetic tuning pass -- a rules test failing for a looks reason, which is the shape of
# lint that gets disabled rather than obeyed. A ceiling moves only when the ART does, and #642's
# prop stack is what moves it.
#
# Reads the COMMITTED tileset, because what ships is what has to be true.
extends GdUnitTestSuite

const TILESET_PATH := "res://Resources/TestTiles.tres"

var _tiles: TileSet


func before_test() -> void:
	_tiles = load(TILESET_PATH) as TileSet
	assert_object(_tiles).override_failure_message(
		"the board's tileset failed to load from %s" % TILESET_PATH).is_not_null()


func _atlas() -> TileSetAtlasSource:
	return _tiles.get_source(_tiles.get_source_id(0)) as TileSetAtlasSource


# Every tile, not just the ones that author the column: the RESOLVED height is what the trace reads,
# so a shape default that outran the art would be just as wrong as an authored value that did.
func test_no_tile_claims_more_wall_than_the_art_can_draw() -> void:
	var source := _atlas()
	var checked := 0
	for i in source.get_tiles_count():
		var coords := source.get_tile_id(i)
		if source.get_tile_size_in_atlas(coords) != Vector2i.ONE:
			continue
		var data := source.get_tile_data(coords, 0)
		var height := GridUtils.prop_rule_height_of(data)
		if height == 0:
			continue
		checked += 1
		assert_int(height).override_failure_message(
			"tile %s (%s) claims %d units of wall, but the art draws at most %d -- a shot would die on a wall the player can see over"
			% [coords, GridUtils.PropShape.keys()[GridUtils.prop_shape_of(data)], height,
				GridUtils.MAX_DRAWABLE_RULE_HEIGHT]
			).is_less_equal(GridUtils.MAX_DRAWABLE_RULE_HEIGHT)
	assert_int(checked).override_failure_message(
		"no tile in the sheet stands up at all, so this law checked nothing").is_greater(0)


# The panel must not be able to author past the ceiling the law enforces. Without this the slider
# and the law are two answers to "how tall may a wall be", and the one the dev can reach wins.
func test_the_objects_panel_cannot_author_past_the_ceiling() -> void:
	var row := {}
	for field: Dictionary in ObjectKnobs.FIELDS:
		if field["layer"] == "prop_rule_height":
			row = field
	assert_bool(row.is_empty()).override_failure_message(
		"the Objects panel no longer offers a rules height, so nothing authors this column"
		).is_false()
	assert_int(int(row["max"])).override_failure_message(
		"the Rules height slider reaches past what the art can draw"
		).is_equal(GridUtils.MAX_DRAWABLE_RULE_HEIGHT)
	# A visible slider must never be able to write the INHERIT sentinel: dragging to 0 would silently
	# re-tick the inherit box it sits under.
	assert_int(int(row["min"])).override_failure_message(
		"the Rules height slider can write 0, which reads back as 'inherit'").is_greater(0)
