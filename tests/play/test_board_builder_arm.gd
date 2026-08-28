# Guards BoardBuilder.arm — the ONE way a play fixture gives a unit a working weapon (#617).
#
# It used to be three byte-similar copies (play_bridge, play_host, tests/play), and the two
# PRODUCTION ones never set weapon_type: WeaponInstance.make() refuses the unmapped NONE family
# (#82), returns null, and the bridge's own `new` board therefore spawned both units unarmed.
#
# Note which way the drift ran. Law #4's usual warning is that a duplicate propagates INTO
# fixtures; here the fixture was the only copy anyone repaired, so the suite stayed permanently
# green about a helper that did not work anywhere it shipped. It could not have caught the bug:
# it built its own units with its own correct copy and never touched either host.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")

const PLAYER := Team.Faction.PLAYER

var _board: Dictionary


func before_test() -> void:
	_board = BoardBuilder.build(self)
	auto_free(_board.root)
	BoardBuilder.paint_rect(_board.grid, Rect2i(-2, -2, 8, 8))


func _spawn() -> Unit:
	var data := UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), "Fixture", PLAYER)
	return BoardBuilder.spawn(_board, data, Vector2i(0, 0))


func test_arm_leaves_the_unit_actually_holding_a_weapon() -> void:
	var unit := _spawn()
	# Non-vacuity: a bare fixture unit starts with nothing, so the assertion below is about arm()
	# and not about whatever a UnitData happened to seed.
	assert_bool(unit.has_equipped_weapon()) \
		.override_failure_message("fixture: a fresh unit should start unarmed") \
		.is_false()

	BoardBuilder.arm(unit, 6)

	assert_bool(unit.has_equipped_weapon()) \
		.override_failure_message("arm() granted nothing — make() refused the family and returned null") \
		.is_true()


func test_the_armed_weapon_is_a_real_family_carrying_the_requested_power() -> void:
	var unit := _spawn()
	BoardBuilder.arm(unit, 6)

	var weapon := unit.get_equipped_weapon() as WeaponInstance
	assert_object(weapon).is_not_null()
	# An unmapped weapon_type is what broke this, so pin that it resolved to a real family class
	# rather than merely that something got equipped.
	assert_int(weapon.template.weapon_type).is_not_equal(WeaponData.WeaponType.NONE)
	assert_int(weapon.template.main_attack.power).is_equal(6)
