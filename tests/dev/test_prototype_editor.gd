# The Item Editor's Prototype mode (#486) -- the tab that authors a weapon TEMPLATE rather than a
# carried item. Pins the four things that are decisions rather than plumbing: the blank prototype
# is authored instead of instantiated, a loaded template is handed out LIVE (not copied), the main
# attack auto-fills from the chosen family as a shared ref while a deliberate pick survives, and a
# template nobody could carry is refused at the save.
#
# No case writes to disk: the refusal case returns before any save, and the allowed direction is
# asserted at the refusal-predicate level rather than by pressing Save As on a tracked file.
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

# The dropdown index of a type-catalog key, so a case names what it picks rather than a number
# that moves whenever content is added.
func _type_index(key: String) -> int:
	return _tool()._base_catalog().keys().find(key)

func _new_prototype() -> WeaponData:
	var tool_ref := _tool()
	tool_ref._rebase_on_type(_type_index(ItemEditorTool.NEW_PROTOTYPE_KEY))
	return tool_ref.current_item as WeaponData

# ==============================================================================
#  The blank prototype is AUTHORED, not instantiated
# ==============================================================================

# A blank prototype is a WeaponData, and the type dropdown's other WeaponData entries mean "build
# an instance on this template". Without the key fork the blank one falls into that arm and the
# mode can never be entered at all -- WeaponInstance.make() would eat it (and, on an unset family,
# hand back null).
func test_the_blank_prototype_entry_authors_a_template_rather_than_an_instance() -> void:
	var tool_ref := _tool()
	tool_ref._rebase_on_type(_type_index(ItemEditorTool.NEW_PROTOTYPE_KEY))
	# Read the tool's own untyped field: a typed local would make the `is` check vacuous, and what
	# the fork writes there is the whole claim.
	var made: Resource = tool_ref.current_item
	assert_object(made).is_not_null()
	assert_bool(made is WeaponInstance).is_false()
	assert_bool(made is WeaponData).is_true()
	assert_bool((made as WeaponData).is_prototype).is_true()

# An established template picked from the SAME dropdown still instantiates -- the fork is on the
# blank entry only, not on "is this a WeaponData".
func test_an_established_template_still_builds_an_instance() -> void:
	var tool_ref := _tool()
	var family_key := ""
	for key in WeaponCatalog.get_family_bases():
		family_key = key
		break
	assert_str(family_key).is_not_empty()   # no family templates on disk: this case proves nothing
	tool_ref._rebase_on_type(_type_index(family_key))
	assert_bool(tool_ref.current_item is WeaponInstance).is_true()

# ==============================================================================
#  A loaded template is LIVE
# ==============================================================================

# Copying a template would fork it off every weapon built on it, and would let this panel and the
# Attack Editor's Weapon Families mode hold divergent copies of one file. Asserted by identity
# rather than by field equality, which a copy would also satisfy.
func test_loading_a_prototype_hands_back_the_catalog_object_itself() -> void:
	var prototypes := WeaponCatalog.get_prototypes()
	var name := ""
	for key in prototypes:
		name = key
		break
	assert_str(name).is_not_empty()   # nothing in Prototypes/: this case proves nothing
	var loaded := _tool()._editable_copy(prototypes[name])
	assert_object(loaded).is_same(prototypes[name])

# The other side of the fork, so the arm cannot be widened by accident: a carried weapon is still
# copied, because editing one must not edit the catalog's.
func test_loading_a_saved_instance_still_hands_back_a_copy() -> void:
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	var carried := WeaponInstance.make(template)
	var loaded := _tool()._editable_copy(carried)
	assert_object(loaded).is_not_same(carried)
	assert_object((loaded as WeaponInstance).template).is_same(template)   # ...but the template stays shared

# ==============================================================================
#  The main attack fills in from the family
# ==============================================================================

# The ask: "that family's main attack would fill in as the automatic main attack". A shared REF,
# so retuning the family main retunes an un-swapped prototype -- and so this mode never authors an
# attack file of its own.
func test_picking_a_family_fills_in_that_familys_main_as_a_shared_ref() -> void:
	var tool_ref := _tool()
	var made := _new_prototype()
	var family := _a_family_with_a_main()
	assert_int(family).is_not_equal(WeaponData.WeaponType.NONE)   # no family base has a main: proves nothing

	tool_ref._on_prototype_family_picked(made, WeaponData.WeaponType.keys()[family])
	assert_object(made.main_attack).is_same(tool_ref._family_main_for(family))

# A deliberate library pick is an authoring decision, so changing the family must not silently
# discard it -- only an auto-filled main follows.
func test_a_deliberately_picked_main_survives_a_family_change() -> void:
	var tool_ref := _tool()
	var made := _new_prototype()
	var chosen := WeaponAttackData.new()   # not in any catalog, so nothing can mistake it for a family main
	made.main_attack = chosen

	tool_ref._on_prototype_family_picked(made, WeaponData.WeaponType.keys()[_a_family_with_a_main()])
	assert_object(made.main_attack).is_same(chosen)

func _a_family_with_a_main() -> WeaponData.WeaponType:
	for base: WeaponData in WeaponCatalog.get_family_bases().values():
		if base.main_attack != null and base.weapon_type != WeaponData.WeaponType.NONE:
			return base.weapon_type
	return WeaponData.WeaponType.NONE

# ==============================================================================
#  Spaces are authorable, and a template nobody could carry is refused
# ==============================================================================

# A fresh prototype starts on the standard frame rather than empty, and the editor writes through
# to the array the model reads -- so adding a space adds a space a weapon actually has.
func test_a_new_prototype_starts_on_the_standard_frame_and_can_grow() -> void:
	var made := _new_prototype()
	assert_array(made.mod_spaces).is_equal(WeaponData.SPACE_CAPACITIES)
	made.mod_spaces.append(2)
	made.weapon_type = WeaponData.WeaponType.CHAINSWORD
	assert_int(WeaponInstance.make(made).space_count()).is_equal(4)

# BLOCKS refuses the write. An unset family is the fault that matters: make() returns null, so the
# file would load and list everywhere while producing nothing anyone can carry.
func test_saving_a_template_with_no_family_is_refused() -> void:
	var made := _new_prototype()
	assert_bool(_tool()._refuse_uncarryable(made)).is_true()

# DEGRADES does not. A main-less template is what the Attack Editor's Weapon Families mode already
# saves happily, and refusing here would give one rule two answers.
func test_saving_a_template_with_no_main_attack_is_allowed() -> void:
	var made := _new_prototype()
	made.weapon_type = WeaponData.WeaponType.CHAINSWORD
	made.main_attack = null
	assert_bool(_tool()._refuse_uncarryable(made)).is_false()

# The gate asks a question only a template has -- every other kind this tab authors passes through.
func test_the_refusal_ignores_the_other_kinds_this_tab_authors() -> void:
	assert_bool(_tool()._refuse_uncarryable(WeaponModData.new())).is_false()
	assert_bool(_tool()._refuse_uncarryable(RuneData.new())).is_false()

# A prototype is its own template, so it saves beside the other prototypes rather than into the
# saved-instances folder every other kind here writes to.
func test_a_prototype_saves_into_the_prototypes_folder() -> void:
	assert_str(_tool()._save_dir_for(_new_prototype())).is_equal(WeaponCatalog.PROTOTYPE_DIR)
