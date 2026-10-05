# The text board shows fire, ice and height (#46). Playtesters on The Dry Field could not see a fire
# spreading toward them, and on Terraces could not tell a ramp from a wall: the overview drew only a
# ground kind, and nothing anywhere drew height.
#
# Glyphs are read off BoardView's own GROUND table and heights off the BoardHeights store, so a
# re-chosen glyph or a re-authored board moves both sides together.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const BoardView := preload("res://play/board_view.gd")
const PlaySession := preload("res://play/play_session.gd")

var _board: Dictionary
var _sess


func before_test() -> void:
	_board = BoardBuilder.build(self, "TerrainViewRoot")
	auto_free(_board.root)
	BoardBuilder.paint_rect(_board.grid, Rect2i(0, 0, 8, 6))
	BoardBuilder.spawn(_board, UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), "Hero",
			Team.Faction.PLAYER), Vector2i(0, 0))
	BoardBuilder.spawn(_board, UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), "Foe",
			Team.Faction.ENEMY), Vector2i(7, 5))
	_sess = PlaySession.new(_board)


# The `width`-wide slot a grid view draws for `cell` in `text`, found by the header's first column.
static func _slot(text: String, cell: Vector2i, offset: int, width: int) -> String:
	var header := ""
	var row := ""
	for line in text.split("\n"):
		if header == "" and line.begins_with("      "):
			header = line
		elif line.begins_with("y=%3d " % cell.y):
			row = line
	if header == "" or row == "":
		return ""
	var first_x := int(header.substr(6, 3))
	return row.substr(6 + (cell.x - first_x) * 3 + offset, width)


func test_a_burning_cell_draws_as_fire_and_the_legend_names_it() -> void:
	var cell := Vector2i(3, 2)
	var fire := ResolvedCellEffect.new()
	fire.cell = cell
	fire.states_added.assign([Terrain.TileState.BURNING])
	(_board.terrain_states as TerrainStateManager).apply(fire)

	var text: String = BoardView.render_overview(_sess)

	var glyph: String = BoardView.GROUND["burning"][0]
	assert_str(_slot(text, cell, 1, 1)).override_failure_message("the burning cell did not draw as fire:\n%s"
			% text).is_equal(glyph)
	assert_str(text).contains("%s %s" % [glyph, BoardView.GROUND["burning"][1]])


func test_the_terrain_view_shows_a_ramp_and_the_overview_points_to_it() -> void:
	assert_str(BoardView.render_overview(_sess)).override_failure_message(
			"a flat, gasless board pointed at `terrain`").not_contains("see `terrain`")
	var cell := Vector2i(4, 3)
	var heights: BoardHeights = _board.board_heights
	heights.set_cell(cell, Terrain.UNITS_PER_LEVEL, Terrain.RampRise.NORTH)

	var view: String = BoardView.render_terrain(_sess)

	assert_str(_slot(view, cell, 0, 3)).override_failure_message("the ramp's cell did not read as one:\n%s"
			% view).is_equal("%2dn" % heights.elevation_at(cell))
	assert_str(BoardView.render_overview(_sess)).contains("see `terrain`")


func test_the_terrain_view_lists_gas() -> void:
	var cell := Vector2i(2, 4)
	var gas: GasField = _board.gas_field
	gas.set_level(cell, Gas.Kind.STEAM, Gas.Level.MEDIUM)

	var view: String = BoardView.render_terrain(_sess)

	assert_str(view).contains("%s %s" % [str(cell), Gas.display_name(Gas.Kind.STEAM)])
