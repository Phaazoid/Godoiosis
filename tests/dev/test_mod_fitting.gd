# The Item Editor's mod-fitting picker (#74 slice 2). Two wires, and both are the #103 shape --
# `fits_family` and `fit_block_reason` are pinned at the model layer next door, and a rule can be
# correct at both ends while nothing connects them to the panel.
#
# The catalog is real authored content, so nothing here asserts WHAT it holds: every claim is
# derived from the same seam the panel reads. Nor may a claim REQUIRE the content to be a certain
# shape -- deleting a mod is authoring, not a regression (dev ruling, 2026-08-27: "a lack of
# authored content shouldn't cause tests to fail", after #596 reddened this suite over a rename).
# Where a case cannot be driven at all without content it warns and returns rather than failing,
# which keeps the absence audible without calling it a fault.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

var _main: Node
var game: Node2D
var overlay: DevOverlay

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
	overlay = game.dev_overlay
	await await_idle_frame()

func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()

func _tool() -> ItemEditorTool:
	return overlay.get_node("%Item Editor")

# A carried weapon off a real family base, which is what the fitting UI is drawn for.
func _weapon() -> WeaponInstance:
	for base: WeaponData in WeaponCatalog.get_family_bases().values():
		if base.weapon_type != WeaponData.WeaponType.NONE and not base.mod_spaces.is_empty():
			return WeaponInstance.make(base)
	return null

func _show(weapon: WeaponInstance) -> ItemEditorTool:
	var tool_ref := _tool()
	tool_ref.current_item = weapon
	tool_ref.populate()
	return tool_ref

func _controls(node: Node, type_name: String, found: Array) -> Array:
	for child in node.get_children():
		if child.is_class(type_name):
			found.append(child)
		_controls(child, type_name, found)
	return found

func _picker_entries(tool_ref: ItemEditorTool) -> Array[String]:
	var names: Array[String] = []
	for picker in _controls(tool_ref.editor_container, "OptionButton", []):
		var option := picker as OptionButton
		for i in option.item_count:
			names.append(option.get_item_text(i))
	return names

# ==============================================================================
#  The picker offers exactly what the family allows
# ==============================================================================

# One equality rather than two half-claims, because either half alone is passable by a broken
# picker: "offers nothing it refuses" is satisfied by a picker that offers NOTHING, and "offers
# everything it allows" by one that offers EVERYTHING. Derived from the same seam the panel reads,
# so authoring a new mod cannot break it.
#
# What this can no longer do is guarantee its own teeth. The refusal half bites only while some
# shipped mod is family-locked -- the first draft asked this of whatever family sorted first, the
# only family-locked mod on disk was a Carbine one, and a mutant deleting the filter outright
# passed. The old case answered that by hunting for a weapon the catalog could refuse something
# for and FAILING when it found none, which made deleting that one mod a test failure (#596), and
# a lack of authored content is not a failure. Teeth without the content dependency need a fixture
# mod this case owns; that is filed, not faked here.
func test_the_picker_offers_exactly_what_the_family_allows() -> void:
	var weapon := _weapon()
	if weapon == null:
		push_warning("no family base carries a mod space, so the picker cannot be drawn at all")
		return
	var offered := _picker_entries(_show(weapon))

	var wrong: Array[String] = []
	var missing: Array[String] = []
	var mods := WeaponModCatalog.get_mods()
	for name in mods:
		var mod: WeaponModData = mods[name]
		var allowed := mod.fits_family(weapon.template.weapon_type)
		if allowed and not offered.has(name):
			missing.append(name)
		elif not allowed and offered.has(name):
			wrong.append(name)
	assert_array(missing).is_empty()
	assert_array(wrong).is_empty()

# ==============================================================================
#  A refusal reaches the panel with its reason
# ==============================================================================

# Pressing Fit on a full space must SAY why, in the words fit_block_reason chose. Driven through
# the real button rather than by calling the handler, because the wire is what this pins -- the
# panel's own refusal string was a hardcoded "Not enough capacity" until this slice.
func test_a_refused_fit_puts_the_models_own_reason_on_the_panel() -> void:
	var weapon := _weapon()
	if weapon == null:
		push_warning("no family base carries a mod space, so there is no panel to refuse on")
		return
	var mods := WeaponModCatalog.get_mods()
	var fitting: WeaponModData = null
	for name in mods:
		var mod: WeaponModData = mods[name]
		if mod.fits_family(weapon.template.weapon_type) and weapon.can_fit(0, mod):
			fitting = mod
			break
	if fitting == null:
		push_warning("no mod in the catalog fits space 0, so nothing here can be refused a fit")
		return

	# Fill space 0 to its capacity, so the next fit of the same mod is refused.
	while weapon.can_fit(0, fitting):
		weapon.fit(0, fitting)
	var tool_ref := _show(weapon)
	var expected := weapon.fit_block_reason(0, fitting)
	assert_str(expected).is_not_empty()

	var buttons := _controls(tool_ref.editor_container, "Button", [])
	var fit_button: Button = null
	for control in buttons:
		var button := control as Button
		if button.text == "Fit":
			fit_button = button
			break
	assert_object(fit_button).is_not_null()

	# The picker defaults to entry 0; aim it at the mod we know is refused.
	var picker: OptionButton = _controls(tool_ref.editor_container, "OptionButton", [])[0]
	for i in picker.item_count:
		if picker.get_item_text(i) == _catalog_name_of(mods, fitting):
			picker.selected = i
			break

	tool_ref.status_label.text = ""
	fit_button.pressed.emit()
	assert_str(tool_ref.status_label.text).is_equal(expected)

func _catalog_name_of(mods: Dictionary, wanted: WeaponModData) -> String:
	for name in mods:
		if mods[name] == wanted:
			return name
	return ""
