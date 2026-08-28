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

# A family-locked mod this suite AUTHORS, because none is shipped and #597 forbids demanding one
# (see #604). It lands in the real scanned directory so the catalog finds it the way it finds
# content; the name is gitignored, so a run that dies before after_test still cannot dirty the tree.
const FIXTURE_NAME := "__test Family Locked"
const FIXTURE_PATH := "res://Resources/WeaponMods/__test_family_locked.tres"

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
	if FileAccess.file_exists(FIXTURE_PATH):
		DirAccess.remove_absolute(FIXTURE_PATH)

func _tool() -> ItemEditorTool:
	return overlay.get_node("%Item Editor")

# A carried weapon off a real family base, which is what the fitting UI is drawn for.
func _weapon() -> WeaponInstance:
	for base: WeaponData in WeaponCatalog.get_family_bases().values():
		if base.weapon_type != WeaponData.WeaponType.NONE and not base.mod_spaces.is_empty():
			return WeaponInstance.make(base)
	return null

# A weapon of a NAMED family, so the case can ask the picker about both sides of a lock.
func _weapon_of(family: WeaponData.WeaponType) -> WeaponInstance:
	for base: WeaponData in WeaponCatalog.get_family_bases().values():
		if base.weapon_type == family and not base.mod_spaces.is_empty():
			return WeaponInstance.make(base)
	return null


# Any moddable family that is not this one. NONE means the shipped set has only one, which the
# caller says out loud rather than failing.
func _a_family_other_than(family: WeaponData.WeaponType) -> WeaponData.WeaponType:
	for base: WeaponData in WeaponCatalog.get_family_bases().values():
		if base.weapon_type == WeaponData.WeaponType.NONE or base.mod_spaces.is_empty():
			continue
		if base.weapon_type != family:
			return base.weapon_type
	return WeaponData.WeaponType.NONE


# Built and saved through the REAL writer rather than hand-authored text: the catalog then loads it
# exactly as it loads shipped content, and nothing here pins the .tres format.
func _write_family_locked_fixture(family: WeaponData.WeaponType) -> void:
	var mod := WeaponModData.new()
	mod.display_name = FIXTURE_NAME
	mod.family = family
	assert_int(ResourceSaver.save(mod, FIXTURE_PATH)).is_equal(OK)

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
# What this cannot do is supply its own teeth. The refusal half bites only while some shipped mod is
# family-locked, and none is; the case BELOW owns that job now, authoring the lock it needs (#604)
# rather than demanding the dev ship one -- which is what made deleting a mod redden this suite
# (#596/#597), and a lack of authored content is not a failure.
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

# The TEETH the equality above cannot supply on its own (#604). Its refusal direction bites only
# while some shipped mod is family-locked, and none is -- deleting `Super Scope.tres` (#596) took
# the last one, and a mutant deleting the family filter outright would sail through. The first draft
# of that case was measured doing exactly this and PASSING.
#
# The old answer was to hunt the catalog for a weapon it could refuse something for and FAIL when it
# found none, which is what made deleting one mod redden this suite (#597). So the case authors the
# lock it needs instead of demanding the dev ship one, and asserts BOTH sides of it: refused for the
# family it is locked away from, offered for the family it names. One without the other passes on a
# picker that offers nothing, or on one that ignores the lock entirely.
func test_the_picker_refuses_a_mod_locked_to_another_family() -> void:
	var mine := _weapon()
	if mine == null:   # content-absent: warn, never fail (tests/README.md rule 9)
		push_warning("no family base carries a mod space, so the picker cannot be drawn at all")
		return
	var other := _a_family_other_than(mine.template.weapon_type)
	if other == WeaponData.WeaponType.NONE:
		push_warning("only one weapon family has mod spaces, so nothing can be locked away from it")
		return

	_write_family_locked_fixture(other)

	# Refused where it does not belong...
	assert_bool(_picker_entries(_show(mine)).has(FIXTURE_NAME)).override_failure_message(
		"the picker offered a mod locked to %s on a %s weapon, so the family filter is not running"
		% [WeaponData.WeaponType.keys()[other], WeaponData.WeaponType.keys()[mine.template.weapon_type]]
	).is_false()

	# ...and offered where it does, or the line above passes on a picker that offers NOTHING.
	var theirs := _weapon_of(other)
	assert_object(theirs).is_not_null()
	assert_bool(_picker_entries(_show(theirs)).has(FIXTURE_NAME)).override_failure_message(
		"the picker withheld a mod locked to the very family it was asked about"
	).is_true()

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
