# The Unit Editor's live element-state toggles (#174): checkboxes over Elemental.State that write
# the transient Unit IMMEDIATELY (add/remove_element_state) -- the Down/Revive dev-write pattern,
# no staging, no Save. Each case drives the REAL CheckBox node found in the panel, because a
# handler that exists and a signal that fires are two different facts (#131).
#
# Fixture is tests/ui/test_game_scene_smoke.gd's -- see tests/README.md -> Testing the game scene.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

var _main: Node
var game: Node2D
var _editor: UnitEditorTool

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
	var overlay: DevOverlay = game.dev_overlay
	_editor = overlay.unit_editor
	await await_idle_frame()

func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()

func _spawn(cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), cell)
	assert_object(unit).is_not_null()
	return unit

# Re-fetched by text on every use, never cached -- the panel is rebuilt from scratch on repaint.
# Recursive since the sub-tab split (2026-08-11) moved the state toggles inside a page; "Wet" is
# unique among all checkbox texts (Wear/Equip/affinity/Alkahest), so text alone still identifies it.
func _checkbox(label: String) -> CheckBox:
	var container: Node = _editor.unit_editor_container
	for child in container.find_children("*", "CheckBox", true, false):
		if (child as CheckBox).text == label:
			return child as CheckBox
	return null

func test_the_wet_toggle_soaks_the_unit_immediately() -> void:
	var unit := _spawn(Vector2i(1, 0))
	_editor.edit_unit(unit)
	var box := _checkbox("Wet")
	assert_object(box).is_not_null()

	box.button_pressed = true   # the real control: the setter emits toggled

	assert_bool(unit.element_states.has(Elemental.State.WET)).is_true()

func test_untoggling_dries_the_unit() -> void:
	var unit := _spawn(Vector2i(1, 0))
	unit.add_element_state(Elemental.State.WET)
	_editor.edit_unit(unit)
	var box := _checkbox("Wet")
	assert_object(box).is_not_null()

	box.button_pressed = false

	assert_bool(unit.element_states.has(Elemental.State.WET)).is_false()

func test_the_panel_reflects_a_state_set_elsewhere() -> void:
	# The VIEW half of the ask: a WET applied by the game (or a reaction) shows checked on open.
	var unit := _spawn(Vector2i(1, 0))
	unit.add_element_state(Elemental.State.WET)

	_editor.edit_unit(unit)

	var box := _checkbox("Wet")
	assert_object(box).is_not_null()
	assert_bool(box.button_pressed).is_true()
