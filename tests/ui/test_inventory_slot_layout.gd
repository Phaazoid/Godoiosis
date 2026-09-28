extends GdUnitTestSuite

# The inspect panel's item slots LAY OUT their row (#966). Reported in play: the (E) on an equipped
# Heal Rune ran past the slot's border and every label sat above its slot's centre line. A slot was
# a plain Panel, which sizes and positions nothing, so its row sat at the top-left at its own width.
#
# The dev's ruling on the fix is ONE COLUMN of full-width rows, so nothing authored trims. The label
# still trims with an ellipsis, as a guard: an over-long name must not widen the panel (#685's edge).
#
# Every assertion compares one rect against another. None pins a pixel count, and the one width
# budget is priced against the panel's ANCHORED rect, never a sibling that grows in the same pass.

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const FIT := preload("res://tests/support/label_fit.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const PLAYER := Team.Faction.PLAYER

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(8):
		for y in range(5):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


func _frames(n: int) -> void:
	for i in range(n):
		await await_idle_frame()


# An equipped weapon, worn armour and empty slots: every kind of row the section draws.
func _inspect(weapon_name := "Test Blade") -> void:
	var data := H.make_unit_data({Stats.Stat.MHP: 80}, PLAYER)
	data.display_name = "Aldin"
	var unit: Unit = game.spawn_unit(data, Vector2i(2, 2))
	var weapon := H.make_weapon(4)
	weapon.display_name = weapon_name
	assert_bool(unit.add_item(weapon)).override_failure_message(
			"the fixture could not carry its weapon").is_true()
	assert_object(unit.get_equipped_weapon()).override_failure_message(
			"the fixture's weapon was not equipped, so no row carries (E)").is_same(weapon)
	var armor := ArmorData.new()
	armor.display_name = "Leather"
	unit.add_item(armor)
	unit.wear_armor(unit.inventory.find(armor))
	game.unit_info_panel.set_unit(unit, true, game._board())
	game.unit_info_panel.visible = true
	await _frames(2)


func _slots() -> Array[Control]:
	var out: Array[Control] = []
	for child: Node in game.unit_info_panel.inventory_panel.slots_container.get_children():
		out.append(child as Control)
	return out


func _centre_y(control: Control) -> float:
	return control.get_global_rect().get_center().y


func test_every_slot_centres_its_row() -> void:
	await _inspect()
	for slot: Control in _slots():
		var label := slot.get_node("SlotHBox/ItemName") as Label
		var icon := slot.get_node("SlotHBox/Icon") as Control
		assert_float(_centre_y(label)).override_failure_message(
				"'%s' sits %.1fpx off its slot's centre line" % [label.text,
					_centre_y(label) - _centre_y(slot)]).is_equal_approx(_centre_y(slot), 1.0)
		assert_float(_centre_y(icon)).override_failure_message(
				"the icon beside '%s' is off its slot's centre line" % label.text
				).is_equal_approx(_centre_y(slot), 1.0)


# The label's RECT is only its text's line when the label does not fill the row, and that is what
# keeps the text centred at any row height. Label's own default vertical flag is SHRINK_CENTER, so
# this pins that nobody sets FILL. At the shipped height the row is barely taller than one line, so
# the case makes the row tall enough for a label that filled it to show.
func test_the_name_stays_centred_in_a_taller_row() -> void:
	await _inspect()
	var slot: Control = _slots()[0]
	slot.custom_minimum_size.y = 60.0
	await _frames(2)
	var label := slot.get_node("SlotHBox/ItemName") as Label
	assert_float(label.size.y).override_failure_message(
			"the label fills a %dpx row, so its text draws at the top of it" % slot.size.y
			).is_equal_approx(label.get_combined_minimum_size().y, 0.5)
	assert_float(_centre_y(label)).is_equal_approx(_centre_y(slot), 1.0)


func test_every_row_stays_inside_its_slot() -> void:
	await _inspect()
	for slot: Control in _slots():
		var row := slot.get_node("SlotHBox") as Control
		var label := slot.get_node("SlotHBox/ItemName") as Label
		assert_bool(slot.get_global_rect().grow(0.5).encloses(row.get_global_rect())
				).override_failure_message("'%s' runs outside its slot: row %s, slot %s" % [
					label.text, row.get_global_rect(), slot.get_global_rect()]).is_true()


func test_one_column_of_slots_spans_the_section() -> void:
	await _inspect()
	var grid := game.unit_info_panel.inventory_panel.slots_container as Control
	for slot: Control in _slots():
		assert_float(slot.size.x).override_failure_message(
				"a slot is %dpx wide in a %dpx section" % [slot.size.x, grid.size.x]
				).is_equal_approx(grid.size.x, 0.5)
		assert_float(slot.global_position.x).is_equal_approx(grid.global_position.x, 0.5)


func test_an_over_long_name_trims_instead_of_widening_the_panel() -> void:
	await _inspect("W".repeat(60))
	var dock := game.unit_info_panel as Control
	var slot: Control = _slots()[0]
	var label := slot.get_node("SlotHBox/ItemName") as Label
	assert_bool(label.text.begins_with("WWW")).override_failure_message(
			"slot 0 is not the over-long weapon (reads '%s')" % label.text).is_true()
	assert_float(slot.get_global_rect().end.x).override_failure_message(
			"the slot ends at x=%d, past the panel's anchored edge at x=%d" % [
				slot.get_global_rect().end.x, dock.get_global_rect().end.x]
			).is_less_equal(dock.get_global_rect().end.x)
	assert_bool(FIT.draws_in_full(label)).override_failure_message(
			"the name fits after all, so this case proves nothing about trimming").is_false()


# The report's own complaint, (E) cut off, stated for names that fit. A trimming label declares
# almost no minimum width, so without SIZE_EXPAND it would draw as an ellipsis (the #1024 family).
func test_a_name_that_fits_draws_in_full() -> void:
	await _inspect()
	for slot: Control in _slots():
		var label := slot.get_node("SlotHBox/ItemName") as Label
		assert_bool(FIT.draws_in_full(label)).override_failure_message(
				"'%s' is drawn %dpx wide and needs %dpx" % [label.text, label.size.x,
					FIT.ink_width(label)]).is_true()
