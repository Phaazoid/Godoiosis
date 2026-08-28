# Exercises SharedBoard through its own four hooks (#622, leaves A and D), because machinery with no
# consumer is the born-dead wire this project keeps paying for (#103, #264): it would compile, ship,
# and be wrong in a way nothing could report.
#
# It is deliberately its own suite rather than a conversion of an existing one. What is under test
# here is the FIXTURE -- that the scene is genuinely shared, that a case which dirties the board
# hands the next one a clean board, and that check() is reached at all. Converting a real suite is
# the next leaf and a separate question: it asks whether THAT suite's cases stay green, which is a
# different claim and a different blast radius.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const PROLOG := "res://Scenarios/missions/Prolog.tres"

var _board := SharedBoard.new(SCENE_PATH, PROLOG)
var _opened_id := 0


func before() -> void:
	await _board.open(self)
	_opened_id = _board.scene.get_instance_id() if _board.scene != null else 0


func before_test() -> void:
	await _board.reset(self)


func after_test() -> void:
	await _board.check(self)


func after() -> void:
	_board.close()


func _units() -> Array[Unit]:
	var units: Array[Unit] = []
	for child in _board.game.units_root.get_children():
		if child is Unit:
			units.append(child as Unit)
	return units


# ==============================================================================
#  The sharing itself
# ==============================================================================

func test_the_board_is_loaded_and_usable() -> void:
	assert_object(_board.scene).is_not_null()
	assert_object(_board.game).is_not_null()
	assert_int(_units().size()).override_failure_message(
		"the shared board came up with no units, so every case below proves nothing").is_greater(0)


func test_every_case_gets_the_same_scene_instance_rather_than_a_rebuild() -> void:
	# THE claim: one Battle3D for the whole suite. Compared against the id recorded in before(),
	# not against another case, so this does not depend on execution order.
	#
	# In fresh mode the id legitimately differs -- that is the mode doing its job -- so the
	# assertion states which branch it is in rather than being skipped silently (#449's lesson
	# that a settings-driven surface must say which branch it asserts on).
	if SharedBoard.fresh_mode():
		assert_int(_board.scene.get_instance_id()).override_failure_message(
			"fresh mode should rebuild, so this case should NOT match before()'s scene"
			).is_not_equal(_opened_id)
		return
	assert_int(_board.scene.get_instance_id()).override_failure_message(
		"the scene was rebuilt between before() and this case -- nothing is being shared"
		).is_equal(_opened_id)


# ==============================================================================
#  A dirty case does not contaminate the next one
# ==============================================================================

func test_a_case_may_dirty_the_board_freely() -> void:
	# after_test resets before it diffs, so ordinary mutation is not a leak -- it is the case doing
	# its job. If this reddens, the reset door cannot undo a plain HP change and sharing is off.
	var units := _units()
	assert_int(units.size()).is_greater(0)
	units[0].set_current_hp(maxi(1, units[0].get_current_hp() - 5))


func test_and_the_next_case_still_sees_full_health() -> void:
	# The payoff of the case above, and the only one here that is deliberately order-dependent:
	# gdUnit4 runs cases in declaration order, and what it asserts is precisely that the previous
	# case's damage did not survive.
	for unit: Unit in _units():
		assert_int(unit.get_current_hp()).override_failure_message(
			"%s arrived damaged -- the previous case leaked through the reset" % unit.get_unit_name()
			).is_equal(unit.get_max_hp())
