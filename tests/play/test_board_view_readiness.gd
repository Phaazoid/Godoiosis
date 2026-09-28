# The headless unit line names a weapon's LIVE state (#663): a driver that ran its Carbine dry could
# not tell from the board that it had, so its next order was refused for a reason nothing showed.
# The line reads the family's own status_text -- the same answer the ring's count comes from (#1045)
# -- and asserts through render_overview, so the wire from the unit to the string is covered too.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")
const BoardView := preload("res://play/board_view.gd")

var _board: Dictionary


func before_test() -> void:
	_board = BoardBuilder.build(self)
	auto_free(_board.root)
	BoardBuilder.paint_rect(_board.grid, Rect2i(-2, -2, 12, 12))


func _overview() -> String:
	return BoardView.render_overview(PlaySession.new(_board))


func test_the_unit_line_carries_the_magazine_and_follows_it() -> void:
	var data := UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), "Noemie", Team.Faction.PLAYER)
	var gunner := BoardBuilder.spawn(_board, data, Vector2i.ZERO)
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CARBINE
	template.main_attack = WeaponAttackData.new()
	template.main_attack.requires_readiness = true
	template.main_attack.consumes_readiness = true
	var carbine := WeaponInstance.make(template) as CarbineWeaponInstance
	gunner.add_item(carbine)

	var full := _overview()
	assert_str(full).override_failure_message("the unit line hides the magazine:\n%s" % full) \
		.contains("[%s]" % carbine.status_text())

	carbine.shots_remaining = 0
	var dry := _overview()
	assert_str(dry).contains("[%s]" % carbine.status_text())
	assert_str(dry).override_failure_message("a dry Carbine reads the same as a full one").is_not_equal(full)
