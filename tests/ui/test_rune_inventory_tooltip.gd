# #167: a rune sitting in inventory tells the player what it actually is -- temper, capacity, and
# a line per inscribed carving, greyed with a reason when it can't currently channel.
#
# Sibling of tests/ui/test_menu_catalogue_rows.gd (#166), which proved the identical readout on
# the Transmutation submenu's rows. This is the SAME data (RuneData.attack_detail/
# attack_block_reason) reaching the OTHER surface that used to show nothing but a name -- so the
# fixture (a partial rune: one clean carving, one wildcard-covered, one dead) is copied verbatim.
# Reads the RENDERED slot tooltip, not the private _tooltip_for() function in isolation -- the
# project's own "test the wire" precedent (#114/#126/#131/#166): a builder that returns the right
# string proves nothing about whether _refresh() ever attaches it to the slot the player hovers.
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


# Same fixture as test_menu_catalogue_rows.gd: fire-1 aura, LARGE rune (capacity 6), fully used —
# Ember channels clean, Pyre via the universal +1 wildcard, Inferno's deficit of 2 is past any pool.
func _alchemist_with_a_partial_rune() -> Unit:
	var alch := _spawn(Vector2i(1, 0))
	alch.unit_instance.aura = { FIRE: 1 }
	alch.unit_instance.affinity = [FIRE]

	var rune := RuneData.new()
	rune.size = RuneData.Size.LARGE
	rune.display_name = "Test Rune"
	assert_bool(rune.inscribe(_carving([FIRE], "Ember"))).is_true()               # deficit 0
	assert_bool(rune.inscribe(_carving([FIRE, FIRE], "Pyre"))).is_true()          # deficit 1 — wildcarded
	assert_bool(rune.inscribe(_carving([FIRE, FIRE, FIRE], "Inferno"))).is_true() # deficit 2 — dead
	alch.add_item(rune)
	assert_object(alch.get_equipped_weapon()).override_failure_message("fixture failed to equip the rune").is_same(rune)
	return alch


func _rendered_rune_tooltip(alch: Unit, rune: RuneData) -> String:
	game.unit_info_panel.set_unit(alch, true, game._board())
	var idx := alch.inventory.find(rune)
	assert_int(idx).override_failure_message("the rune is not in the unit's inventory").is_greater_equal(0)
	var inv = game.unit_info_panel.inventory_panel
	var slot: Panel = inv.slots_container.get_child(idx)
	return slot.tooltip_text


# ==============================================================================

func test_the_tooltip_names_temper_and_capacity() -> void:
	var alch := _alchemist_with_a_partial_rune()
	var rune: RuneData = alch.get_equipped_weapon() as RuneData
	await await_idle_frame()

	var tip := _rendered_rune_tooltip(alch, rune)
	assert_str(tip).override_failure_message("tooltip does not name the temper element:\n%s" % tip) \
		.contains("Fire")
	assert_str(tip).override_failure_message("tooltip does not show used/total capacity:\n%s" % tip) \
		.contains("6/6 capacity")


func test_the_tooltip_lists_every_carving_and_the_dead_ones_reason() -> void:
	var alch := _alchemist_with_a_partial_rune()
	var rune: RuneData = alch.get_equipped_weapon() as RuneData
	await await_idle_frame()

	var tip := _rendered_rune_tooltip(alch, rune)
	assert_str(tip).override_failure_message("carving list is missing an inscription:\n%s" % tip) \
		.contains("Ember")
	assert_str(tip).contains("Pyre")
	assert_str(tip).contains("Inferno")
	assert_str(tip).override_failure_message("the dead carving's reason never reached the tooltip:\n%s" % tip) \
		.contains("wildcard")


func test_the_rendered_tooltip_is_wrapped() -> void:
	var alch := _alchemist_with_a_partial_rune()
	var rune: RuneData = alch.get_equipped_weapon() as RuneData
	await await_idle_frame()

	var tip := _rendered_rune_tooltip(alch, rune)
	assert_str(tip).override_failure_message("rune tooltip is not in wrapped form: %s" % tip) \
		.is_equal(UiText.wrap(tip))
