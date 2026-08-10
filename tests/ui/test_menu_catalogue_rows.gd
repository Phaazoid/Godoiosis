# #166: a menu LISTS what the unit owns and greys what it can't use, with a reason on every
# greyed row and a readout on every row.
#
# This suite asserts on the RENDERED BUTTONS, not on the lists behind them, and that is the whole
# point of it existing. `get_transmutation_choices()` returning three carvings tells you nothing
# about whether the menu drew three rows, disabled two, or attached a single word of explanation —
# and the row-building path (MainActionMenu._entry -> ActionMenuController.populate) is where every
# one of those decisions actually happens. Same lesson as #114, #126 and #131: a test that stops
# short of the thing the player looks at is blind to bugs in the thing the player looks at.
#
# Fixture is tests/squad/test_downed_ejection.gd's real game scene — see tests/README.md ->
# Testing the game scene.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

const FIRE := Elemental.Element.FIRE

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
		game.grid.set_cell(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), cell)
	assert_object(unit).is_not_null()
	return unit


func _carving(sigils: Array[Elemental.Element], name: String) -> TransmutationData:
	var t: TransmutationData = TransmutationData.new()
	t.display_name = name
	t.power = 5
	t.sigils.assign(sigils)
	return t


# An alchemist wielding a three-carving rune with a mixed verdict — #157's partial case, which is
# precisely why this readout is owed: the rune equips legally and the dead carving still needs to
# explain itself. At fire-1 under the wildcard model (2026-08-10): Ember covered, Pyre channels
# via the universal +1, Inferno's deficit of 2 is past any pool.
func _alchemist_with_a_partial_rune() -> Unit:
	var alch := _spawn(Vector2i(1, 0))
	alch.unit_instance.aura = { FIRE: 1 }
	alch.unit_instance.affinity = [FIRE]

	var rune := RuneData.new()
	rune.size = RuneData.Size.LARGE
	rune.display_name = "Test Rune"
	assert_bool(rune.inscribe(_carving([FIRE], "Ember"))).is_true()              # deficit 0
	assert_bool(rune.inscribe(_carving([FIRE, FIRE], "Pyre"))).is_true()         # deficit 1 — wildcarded
	assert_bool(rune.inscribe(_carving([FIRE, FIRE, FIRE], "Inferno"))).is_true()# deficit 2 — dead
	alch.add_item(rune)
	assert_object(alch.get_equipped_weapon()).override_failure_message("fixture failed to equip the rune").is_same(rune)
	return alch


# The live menu's rendered rows. MainActionMenu._open_menu parents its controller to Game, so the
# most recently opened one is the submenu under test.
func _open_rows() -> Array[Button]:
	var rows: Array[Button] = []
	var controller: ActionMenuController = null
	for child in game.get_children():
		if child is ActionMenuController:
			controller = child
	assert_object(controller).override_failure_message("no menu was opened at all").is_not_null()
	for node in controller._button_box.get_children():
		if node is Button:
			rows.append(node)
	return rows


func _row_named(rows: Array[Button], text: String) -> Button:
	for row in rows:
		if row.text == text:
			return row
	return null


# ==============================================================================

# THE readout, as one sequence: open the category, and every carving the rune holds has a row —
# the two that can't be paid for greyed rather than missing.
func test_the_submenu_lists_every_carving_and_greys_the_unaffordable_ones() -> void:
	var alch := _alchemist_with_a_partial_rune()

	game.main_action_menu.on_pressed(MainActionMenu.TRANSMUTATION, alch)
	await await_idle_frame()
	var rows := _open_rows()

	assert_int(rows.size()).override_failure_message("the catalogue did not list all three carvings").is_equal(3)
	assert_bool(_row_named(rows, "Ember").disabled) \
		.override_failure_message("the covered carving was greyed").is_false()
	assert_bool(_row_named(rows, "Pyre").disabled) \
		.override_failure_message("a wildcard-covered carving was greyed").is_false()
	assert_bool(_row_named(rows, "Inferno").disabled) \
		.override_failure_message("an unchannelable carving was left pickable").is_true()


# A greyed row that doesn't say why is the bug this ticket exists to fix — the reported symptom was
# a menu that silently showed nothing, and silently showing a dead row instead is no better.
func test_every_greyed_row_says_what_it_needs() -> void:
	var alch := _alchemist_with_a_partial_rune()

	game.main_action_menu.on_pressed(MainActionMenu.TRANSMUTATION, alch)
	await await_idle_frame()
	var rows := _open_rows()

	var inferno := _row_named(rows, "Inferno")
	assert_str(inferno.tooltip_text).override_failure_message("a greyed row explained nothing").is_not_empty()
	assert_str(inferno.tooltip_text).contains("wildcard")   # names the shortfall in the model's currency
	assert_str(inferno.tooltip_text).contains("2")


# The descriptions half of #166: a row you CAN pick still says what it does. Blocked by the old
# controller, which attached a tooltip only when a row was disabled.
func test_an_enabled_row_still_carries_its_readout() -> void:
	var alch := _alchemist_with_a_partial_rune()

	game.main_action_menu.on_pressed(MainActionMenu.TRANSMUTATION, alch)
	await await_idle_frame()
	var rows := _open_rows()

	var ember := _row_named(rows, "Ember")
	assert_bool(ember.disabled).is_false()
	assert_str(ember.tooltip_text) \
		.override_failure_message("an enabled row has no hover readout").is_not_empty()
	assert_str(ember.tooltip_text).contains("Damage")


# The tooltip law (visual-clarity #1): Godot tooltips don't autowrap, so every rendered one must
# already be in wrapped form. Valid as an equality check because UiText.wrap is idempotent.
func test_every_rendered_tooltip_is_wrapped() -> void:
	var alch := _alchemist_with_a_partial_rune()

	game.main_action_menu.on_pressed(MainActionMenu.TRANSMUTATION, alch)
	await await_idle_frame()

	for row in _open_rows():
		if row.tooltip_text != "":
			assert_str(row.tooltip_text) \
				.override_failure_message("an unwrapped tooltip reached the screen: '%s'" % row.tooltip_text) \
				.is_equal(UiText.wrap(row.tooltip_text))


# The generalization, proven on the OTHER kind: the reason a weapon row gives is now the family's
# own words rather than one string the menu kept for every weapon in the game.
func test_a_weapon_row_greys_with_its_familys_own_words() -> void:
	var unit := _spawn(Vector2i(2, 0))
	var spear := _sprung_springspear()
	unit.add_item(spear)
	assert_object(unit.get_equipped_weapon()).is_same(spear)

	game.main_action_menu.on_pressed(MainActionMenu.WEAPON_ACTION, unit)
	await await_idle_frame()
	var rows := _open_rows()

	var stab := _row_named(rows, "Spring Stab")
	assert_object(stab).override_failure_message("the secondary attack was not listed").is_not_null()
	assert_bool(stab.disabled).is_true()
	assert_str(stab.tooltip_text) \
		.override_failure_message("the row fell back to the generic reason instead of the family's") \
		.contains("Spring Load")


# A Springspear whose secondary requires readiness, already spent.
func _sprung_springspear() -> WeaponInstance:
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.SPRINGSPEAR
	template.display_name = "Springspear"
	template.main_attack = WeaponAttackData.new()
	template.main_attack.display_name = "Jab"
	template.main_attack.power = 3
	var lunge := WeaponAttackData.new()
	lunge.display_name = "Spring Stab"
	lunge.power = 6
	lunge.requires_readiness = true
	template.extra_attacks = [lunge]

	var spear := WeaponInstance.make(template) as SpringspearWeaponInstance
	spear.ready = false   # spent: the secondary is gated, the family has words for it
	return spear
