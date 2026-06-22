# The inspect panel's bottom states bar (#6) reads a unit's live element_states through
# StateIcons. This pins the bar end-to-end: a unit with no states shows an empty bar, a
# held state shows one icon, and a null unit clears it.
#
# queue_free() is deferred, so count only after an idle frame.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const PLAYER := Team.Faction.PLAYER

func test_bar_shows_one_icon_per_held_state() -> void:
	var bar: UnitStatesBar = auto_free(UnitStatesBar.new())
	add_child(bar)
	var unit: Unit = H.spawn_unit(self, PLAYER, Vector2i(0, 0))

	# No states -> empty bar.
	bar.set_unit(unit)
	await get_tree().process_frame
	assert_int(bar.get_child_count()).is_equal(0)

	# One held state -> one icon.
	unit.add_element_state(Elemental.State.WET)
	bar.set_unit(unit)
	await get_tree().process_frame
	assert_int(bar.get_child_count()).is_equal(1)

func test_bar_clears_on_null_unit() -> void:
	var bar: UnitStatesBar = auto_free(UnitStatesBar.new())
	add_child(bar)
	var unit: Unit = H.spawn_unit(self, PLAYER, Vector2i(0, 0))
	unit.add_element_state(Elemental.State.WET)

	bar.set_unit(unit)
	await get_tree().process_frame
	assert_int(bar.get_child_count()).is_equal(1)

	bar.set_unit(null)
	await get_tree().process_frame
	assert_int(bar.get_child_count()).is_equal(0)
