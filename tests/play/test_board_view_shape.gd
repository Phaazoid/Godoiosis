# The headless unit line draws an attack's SHAPE (#1079): for a path shape that is the tiles its
# paths visit, since its stamp is empty -- a driver reading the bridge must see the same footprint
# the game lands. Asserts through render_overview, so the wire from the unit to the pattern string
# is covered as well as the format. Shapes are built, never loaded.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")
const BoardView := preload("res://play/board_view.gd")

var _board: Dictionary


func before_test() -> void:
	_board = BoardBuilder.build(self)
	auto_free(_board.root)
	BoardBuilder.paint_rect(_board.grid, Rect2i(-2, -2, 12, 12))


func test_a_path_shape_draws_the_tiles_its_paths_visit() -> void:
	var data := UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), "Ross", Team.Faction.PLAYER)
	var fighter := BoardBuilder.spawn(_board, data, Vector2i.ZERO)
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = WeaponAttackData.new()
	template.main_attack.power = 6
	P.stamped(template.main_attack, 0, [] as Array[Vector2i])
	template.main_attack.attack_shape = P.pathed([
		[Vector2i(0, -1), Vector2i(0, -2), Vector2i(0, -1)] as Array[Vector2i],
	] as Array[Array])
	fighter.add_item(WeaponInstance.make(template))

	var text := BoardView.render_overview(PlaySession.new(_board))
	assert_str(text).override_failure_message(
		"the path shape's footprint is missing from the unit line:\n%s" % text
	).contains("CHAINSWORD pow6 Facing[#/#/+]")
