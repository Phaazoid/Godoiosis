# Can the player READ the Inspect dock and the info card under either palette (#1105)? Both joined
# QueueStyle in #1105 -- the dock's frame, its paper boxes and inks, and the card's two faces -- so
# this is test_pre_mission_contrast's law asked of them, through the same walker
# (tests/support/palette_contrast.gd), plus the WIRE that puts a palette picked in Settings on them.
#
# One case per property, many findings each: a failing case truncates the rest of its suite file, so
# a sweep reports everything it found rather than the first.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const PC := preload("res://tests/support/palette_contrast.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const BUSY := Vector2i(5, 3)

# What the dock and card are drawn over is the board, which varies; both frames are near-opaque, so
# the pre-mission suite's dark base is as honest a floor as any.
const SCREEN_BASE := Color(0.06, 0.06, 0.09)

var _main: Node
var game: Node2D


func before_test() -> void:
	PlayerSettings.reset_for_test()
	QueueStyle._cache.clear()
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
	PlayerSettings.reset_for_test()
	QueueStyle._cache.clear()


func _frames(n: int) -> void:
	for i in range(n):
		await await_idle_frame()


# A unit whose dock shows every ink the dock has: an equipped weapon, worn armour, empty slots and a
# squadmate.
func _inspected_unit() -> Unit:
	var data := H.make_unit_data({Stats.Stat.MHP: 80}, PLAYER)
	data.display_name = "Aldin"
	var unit: Unit = game.spawn_unit(data, Vector2i(2, 2))
	unit.add_item(H.make_weapon(4))
	var armor := ArmorData.new()
	armor.display_name = "Leather"
	armor.def_power = 1
	unit.add_item(armor)
	unit.wear_armor(unit.inventory.find(armor))
	var mate_data := H.make_unit_data({}, PLAYER)
	mate_data.display_name = "Aster"
	var mate: Unit = game.spawn_unit(mate_data, Vector2i(3, 2))
	game.squad_manager.join_squad(mate, unit.squad)
	assert_object(unit.get_equipped_weapon()).override_failure_message(
			"fixture: nothing equipped, so the highlight ink is never drawn").is_not_null()
	assert_object(unit.worn_armor).override_failure_message("fixture: no armour worn").is_same(armor)
	return unit


# Three watches, two zones and a fire -- the busiest tile card, every section and ink it draws.
func _build_busy_tile() -> void:
	var effect := ResolvedCellEffect.new()
	effect.cell = BUSY
	effect.states_added = [Terrain.TileState.BURNING]
	game.terrain_states.apply(effect)
	for i in range(3):
		var data := H.make_unit_data({Stats.Stat.MHP: 80}, ENEMY if i != 1 else PLAYER)
		data.display_name = "Watcher %d" % i
		var watcher: Unit = game.spawn_unit(data, Vector2i(i, 0))
		watcher.equipped_weapon = H.make_weapon(4)
		var footprint: Array[Vector2i] = [BUSY]
		watcher.arm_watch(watcher.movement.cell, BUSY, footprint, watcher.get_default_attack())
	game.refresh_watch_markers()
	game.zone_manager.paint_cell("The Far Ground", ZoneManager.Kind.CAPTURE, BUSY)
	game.zone_manager.paint_cell("The Landing Field", ZoneManager.Kind.DEPLOYMENT, BUSY)


func _equipped_slot_label() -> Label:
	var slots: Node = game.unit_info_panel.inventory_panel.slots_container
	for slot in slots.get_children():
		var label := slot.get_node("SlotHBox/ItemName") as Label
		if label.text.ends_with("(E)"):
			return label
	return null


func test_the_dock_and_both_cards_can_be_read_in_both_palettes() -> void:
	var unit := _inspected_unit()
	_build_busy_tile()
	var found: Array[String] = []
	for palette: int in [PlayerSettings.QueuePalette.DEFAULT, PlayerSettings.QueuePalette.PARCHMENT]:
		PlayerSettings.set_choice(PlayerSettings.Setting.QUEUE_PALETTE, palette)
		game.unit_info_panel.restyle()
		game.hover_info_panel.restyle()
		game.unit_info_panel.set_unit(unit, true, game._board())
		await _frames(2)
		found.append_array(PC.findings(game.unit_info_panel, SCREEN_BASE, "palette %d / dock" % palette))

		game.hover_info_panel.show_unit(unit, unit.global_position)
		await _frames(2)
		found.append_array(PC.findings(game.hover_info_panel.hover_panel, SCREEN_BASE,
				"palette %d / unit card" % palette))

		game.hover_info_panel.show_tile(BUSY, GridUtils.cell_world(game.grid, BUSY))
		await _frames(3)
		assert_int(game.hover_info_panel.tile_texts().size()).override_failure_message(
				"precondition: the tile card drew nothing to read").is_greater(8)
		found.append_array(PC.findings(game.hover_info_panel._tile_panel, SCREEN_BASE,
				"palette %d / tile card" % palette))
		game.unit_info_panel.clear()
		game.hover_info_panel.clear()

	assert_array(found).override_failure_message(
			"unreadable text on the dock or the info card:\n  %s" % "\n  ".join(found)).is_empty()


# The equipped item is marked by ONE colour in both palettes (dev, 2026-09-27: "we don't want to
# communicate things differently in the slate than in the parchment") -- the EMPHASIS role, read as
# the label will draw it rather than as a modulate the contrast walker cannot see.
func test_an_equipped_item_wears_the_emphasis_ink_in_both_palettes() -> void:
	var unit := _inspected_unit()
	for palette: int in [PlayerSettings.QueuePalette.DEFAULT, PlayerSettings.QueuePalette.PARCHMENT]:
		PlayerSettings.set_choice(PlayerSettings.Setting.QUEUE_PALETTE, palette)
		game.unit_info_panel.restyle()
		game.unit_info_panel.set_unit(unit, true, game._board())
		await _frames(1)
		var label := _equipped_slot_label()
		assert_object(label).override_failure_message("no slot reads as equipped").is_not_null()
		assert_that(label.get_theme_color("font_color")).override_failure_message(
				"palette %d: the equipped slot is not in the emphasis ink" % palette).is_equal(
				QueueStyle.ink(QueueStyle.Role.EMPHASIS_TEXT))
		game.unit_info_panel.clear()


# THE WIRE. Nothing is pushed on a palette switch, so a dock or card already on screen keeps the old
# palette unless SettingsScreen restyles it on close -- driven through the real page and its real
# Close button, with both surfaces up behind it.
func test_a_palette_picked_in_settings_reaches_the_dock_and_the_card() -> void:
	var unit := _inspected_unit()
	game.inspect_unit(unit)
	await _frames(2)
	assert_bool(game.hover_info_panel.is_showing_tile()).override_failure_message(
			"precondition: Inspect put up no tile card").is_true()

	SettingsScreen.show_screen(game)
	await _frames(3)
	var screen: SettingsScreen = null
	for child in game.card_layer.get_children():
		if child is SettingsScreen:
			screen = child
	assert_object(screen).override_failure_message("the settings page did not open").is_not_null()
	PlayerSettings.set_choice(PlayerSettings.Setting.QUEUE_PALETTE, PlayerSettings.QueuePalette.PARCHMENT)
	var close: Button = null
	for node in PC.walk(screen):
		if node is Button and (node as Button).text == "Close":
			close = node
	close.pressed.emit()
	await _frames(4)

	var frame := QueueStyle.ink(QueueStyle.Role.PANEL_BG)
	var dock_box := (game.unit_info_panel.get_node("UnitInfoPanel") as Control).get_theme_stylebox("panel") as StyleBoxFlat
	assert_that(dock_box.bg_color).override_failure_message(
			"the dock kept the old palette after Settings closed").is_equal(frame)
	var card_box := game.hover_info_panel._tile_panel.get_theme_stylebox("panel") as StyleBoxFlat
	assert_that(card_box.bg_color).override_failure_message(
			"the tile card kept the old palette after Settings closed").is_equal(frame)
	assert_that(_equipped_slot_label().get_theme_color("font_color")).override_failure_message(
			"the dock's slots kept the old palette's ink").is_equal(QueueStyle.ink(QueueStyle.Role.EMPHASIS_TEXT))
