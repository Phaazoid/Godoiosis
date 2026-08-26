# The Item Editor's mod-fitting picker (#74 slice 2). Two wires, and both are the #103 shape --
# `fits_family` and `fit_block_reason` are pinned at the model layer next door, and a rule can be
# correct at both ends while nothing connects them to the panel.
#
# The catalog is real authored content, so nothing here asserts WHAT it holds: every claim is
# derived from the same seam the panel reads, with a non-vacuity message where a claim needs the
# content to be a certain shape at all (the content razor).
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

# A weapon of a family that at least one authored mod is locked AWAY from, so the filter has real
# work to do. Null means the content cannot support the claim at all, which the caller says out loud
# rather than passing quietly.
func _weapon_the_catalog_can_refuse_something_for() -> WeaponInstance:
	var mods := WeaponModCatalog.get_mods()
	for base: WeaponData in WeaponCatalog.get_family_bases().values():
		if base.weapon_type == WeaponData.WeaponType.NONE or base.mod_spaces.is_empty():
			continue
		for name in mods:
			var mod: WeaponModData = mods[name]
			if not mod.fits_family(base.weapon_type):
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
#  The picker offers only what the family allows
# ==============================================================================

# The weapon is chosen so the catalog HAS something to refuse it. That is not fussiness: the first
# draft asked this of whatever family sorted first (the Carbine), and the only family-locked mod on
# disk is a Carbine one -- so nothing was refusable, `wrong` was empty by construction, and a
# mutant deleting the filter outright passed. The discriminating power is in which weapon we ask
# about (the #264 shape), so the pick derives it instead of assuming it.
func test_the_picker_offers_nothing_the_family_refuses() -> void:
	var weapon := _weapon_the_catalog_can_refuse_something_for()
	assert_object(weapon).is_not_null()   # no mod is family-locked away from any family: proves nothing
	var offered := _picker_entries(_show(weapon))

	var wrong: Array[String] = []
	var mods := WeaponModCatalog.get_mods()
	for name in mods:
		var mod: WeaponModData = mods[name]
		if not mod.fits_family(weapon.template.weapon_type) and offered.has(name):
			wrong.append(name)
	assert_array(wrong).is_empty()

# The other direction, or the case above passes against a picker that offers NOTHING. Derived from
# the catalog rather than naming a mod, so authoring a new one cannot break it.
func test_the_picker_offers_everything_the_family_allows() -> void:
	var weapon := _weapon()
	var offered := _picker_entries(_show(weapon))

	var missing: Array[String] = []
	var allowed := 0
	var mods := WeaponModCatalog.get_mods()
	for name in mods:
		var mod: WeaponModData = mods[name]
		if not mod.fits_family(weapon.template.weapon_type):
			continue
		allowed += 1
		if not offered.has(name):
			missing.append(name)
	assert_array(missing).is_empty()
	assert_int(allowed).is_greater(0)   # no mod fits this family: the case above is vacuous

# ==============================================================================
#  A refusal reaches the panel with its reason
# ==============================================================================

# Pressing Fit on a full space must SAY why, in the words fit_block_reason chose. Driven through
# the real button rather than by calling the handler, because the wire is what this pins -- the
# panel's own refusal string was a hardcoded "Not enough capacity" until this slice.
func test_a_refused_fit_puts_the_models_own_reason_on_the_panel() -> void:
	var weapon := _weapon()
	var mods := WeaponModCatalog.get_mods()
	var fitting: WeaponModData = null
	for name in mods:
		var mod: WeaponModData = mods[name]
		if mod.fits_family(weapon.template.weapon_type) and weapon.can_fit(0, mod):
			fitting = mod
			break
	assert_object(fitting).is_not_null()   # nothing the catalog holds fits space 0: proves nothing

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
