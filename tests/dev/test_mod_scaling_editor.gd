# The mod editor's scaling surface (#74 slice 3): ABSOLUTE in, DELTA at rest.
#
# You author the percentages the weapon should scale off; what is stored is the difference from the
# family main attack's blend, so every attack that weapon fires shifts by the same amount and keeps
# its own character. These cases pin the conversion in both directions plus the two rules that fall
# out of it -- the delta sums to zero, and drift moves the absolutes rather than the stored shift.
#
# The reference is built HERE rather than read off the catalog, so nothing asserts what any shipped
# family scales off (the content razor). One case reads the real catalog and says so.
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

func _mod(family: WeaponData.WeaponType, change: Dictionary[Stats.Stat, int] = {}) -> WeaponModData:
	var m := WeaponModData.new()
	m.family = family
	m.scaling_change = change
	return m

func _sliders(node: Node, found: Array[HSlider]) -> Array[HSlider]:
	for child in node.get_children():
		var slider := child as HSlider
		if slider != null:
			found.append(slider)
		_sliders(child, found)
	return found

func _show(mod: WeaponModData) -> ItemEditorTool:
	var tool_ref := _tool()
	tool_ref.current_item = mod
	tool_ref.populate()
	return tool_ref

# ==============================================================================
#  The conversion, both directions
# ==============================================================================

const REFERENCE: Dictionary[Stats.Stat, int] = {Stats.Stat.DEX: 40, Stats.Stat.PER: 60}

func test_the_absolute_is_the_reference_plus_the_stored_shift() -> void:
	var absolute := _tool()._absolute_blend(REFERENCE, {Stats.Stat.DEX: 5, Stats.Stat.PER: -5})
	assert_int(absolute.get(Stats.Stat.DEX, 0)).is_equal(45)
	assert_int(absolute.get(Stats.Stat.PER, 0)).is_equal(55)

func test_authoring_an_absolute_stores_the_shift_not_the_absolute() -> void:
	var mod := _mod(WeaponData.WeaponType.CARBINE)
	var absolute: Dictionary[Stats.Stat, int] = {Stats.Stat.DEX: 45, Stats.Stat.PER: 55}
	_tool()._store_scaling_change(mod, REFERENCE, absolute)
	assert_int(mod.scaling_change.get(Stats.Stat.DEX, 0)).is_equal(5)
	assert_int(mod.scaling_change.get(Stats.Stat.PER, 0)).is_equal(-5)

# The round trip is the claim the whole design rests on: reopening a saved mod must put the sliders
# back where they were left, or every edit silently re-authors the last one.
func test_a_stored_shift_round_trips_through_the_sliders_unchanged() -> void:
	var tool_ref := _tool()
	var original: Dictionary[Stats.Stat, int] = {Stats.Stat.DEX: 15, Stats.Stat.PER: -15}
	var mod := _mod(WeaponData.WeaponType.CARBINE, original.duplicate())

	var absolute := tool_ref._absolute_blend(REFERENCE, mod.scaling_change)
	tool_ref._store_scaling_change(mod, REFERENCE, absolute)
	assert_int(mod.scaling_change.get(Stats.Stat.DEX, 0)).is_equal(original[Stats.Stat.DEX])
	assert_int(mod.scaling_change.get(Stats.Stat.PER, 0)).is_equal(original[Stats.Stat.PER])

# A stat the mod does not move is not an entry worth storing -- the same sparse rule the sliders
# and add_stat_dict keep. Storing it would grow every saved mod four keys wide with stats nobody
# touched, which only the .tres would ever show.
func test_a_stat_the_mod_does_not_move_is_erased_rather_than_stored_as_zero() -> void:
	var mod := _mod(WeaponData.WeaponType.CARBINE, {Stats.Stat.DEX: 5, Stats.Stat.PER: -5})
	_tool()._store_scaling_change(mod, REFERENCE, REFERENCE)   # authored back onto the reference
	assert_bool(mod.scaling_change.is_empty()).is_true()

# The invariant that keeps the absolutes summing to BLEND_TOTAL after any retune: the sliders pin
# their total, the reference sums to the same, so the difference sums to nothing.
func test_a_shift_authored_off_a_full_blend_sums_to_zero() -> void:
	var mod := _mod(WeaponData.WeaponType.CARBINE)
	var absolute: Dictionary[Stats.Stat, int] = {Stats.Stat.STR: 25, Stats.Stat.DEX: 25, Stats.Stat.PER: 50}
	_tool()._store_scaling_change(mod, REFERENCE, absolute)

	var sum := 0
	for stat: Stats.Stat in mod.scaling_change:
		sum += mod.scaling_change[stat]
	assert_int(sum).is_equal(0)

# Dev ruling: keep the drift, make it visible. A mod stores a SHIFT, so retuning the family main
# moves what the mod ends up at -- it follows the family, which is what a shift means.
func test_retuning_the_family_moves_the_absolutes_and_leaves_the_shift_alone() -> void:
	var tool_ref := _tool()
	var mod := _mod(WeaponData.WeaponType.CARBINE, {Stats.Stat.DEX: 10, Stats.Stat.PER: -10})
	var retuned: Dictionary[Stats.Stat, int] = {Stats.Stat.DEX: 80, Stats.Stat.PER: 20}

	var absolute := tool_ref._absolute_blend(retuned, mod.scaling_change)
	assert_int(absolute.get(Stats.Stat.DEX, 0)).is_equal(90)
	assert_int(absolute.get(Stats.Stat.PER, 0)).is_equal(10)
	assert_int(mod.scaling_change.get(Stats.Stat.DEX, 0)).is_equal(10)   # untouched

# Clamped exactly as WeaponInstance.effective_blend clamps, so the panel shows what the weapon
# would really scale off rather than a negative weight no rule can honour.
func test_a_shift_that_would_drive_a_weight_below_zero_shows_as_zero() -> void:
	var absolute := _tool()._absolute_blend(REFERENCE, {Stats.Stat.DEX: -70})
	assert_bool(absolute.has(Stats.Stat.DEX)).is_false()

# ==============================================================================
#  The panel
# ==============================================================================

# No family, no sliders: a change is measured against one family's main and means nothing without
# it, so the door is not there rather than authoring a number with nothing behind it.
func test_a_mod_with_no_family_gets_no_scaling_sliders() -> void:
	var without := _show(_mod(WeaponData.WeaponType.NONE))
	assert_array(_sliders(without.editor_container, [])).is_empty()

	# ...and picking one opens it, against a family the catalog really has a main for.
	var family := _a_family_with_a_blend()
	if family == WeaponData.WeaponType.NONE:   # content-absent: warn, never fail (tests/README.md rule 9)
		push_warning("no family base authors a main with a scaling blend, so there is nothing to measure against")
		return
	var with_family := _show(_mod(family))
	assert_int(_sliders(with_family.editor_container, []).size()).is_equal(Stats.SCALING_STATS.size())

func _a_family_with_a_blend() -> WeaponData.WeaponType:
	for base: WeaponData in WeaponCatalog.get_family_bases().values():
		if base.weapon_type == WeaponData.WeaponType.NONE:
			continue
		var main := WeaponCatalog.family_main(base.weapon_type)
		if main != null and not main.scaling_blend.is_empty():
			return base.weapon_type
	return WeaponData.WeaponType.NONE

# The WIRE, not the math. Both halves above are correct in isolation and would stay correct with
# nothing connecting them to the panel -- #103's shape, and the reason this drives a real slider
# instead of calling _store_scaling_change directly.
func test_dragging_a_slider_writes_the_shift_onto_the_mod() -> void:
	var family := _a_family_with_a_blend()
	if family == WeaponData.WeaponType.NONE:   # content-absent: warn, never fail (tests/README.md rule 9)
		push_warning("no family base authors a main with a scaling blend, so there is nothing to measure against")
		return
	var mod := _mod(family)
	var tool_ref := _show(mod)
	var reference := tool_ref._reference_blend(family)

	# A stat the family leans on NOT AT ALL, so the drag cannot be mistaken for a no-op.
	var untouched := Stats.SCALING_STATS.filter(func(s): return not reference.has(s))
	if untouched.is_empty():   # content-absent: warn, never fail (tests/README.md rule 9)
		push_warning("this family leans on every scaling stat, so no drag can be told from a no-op")
		return
	var target: Stats.Stat = untouched[0]

	var sliders := _sliders(tool_ref.editor_container, [])
	sliders[Stats.SCALING_STATS.find(target)].value = 25
	assert_bool(mod.scaling_change.is_empty()).is_false()

	# Every stat, not just the dragged one: the stored shift IS what the sliders show minus the
	# reference, which is the whole contract between the panel and the file.
	for i in Stats.SCALING_STATS.size():
		var stat: Stats.Stat = Stats.SCALING_STATS[i]
		var shown := int(sliders[i].value)
		assert_int(mod.scaling_change.get(stat, 0)).is_equal(shown - int(reference.get(stat, 0)))

# ==============================================================================
#  The save gate
# ==============================================================================

# The derived restriction, enforced where it can actually be caught. A shift with no family is
# measured against nothing -- the file would load, list, and fit anywhere, quietly meaning nothing.
func test_saving_a_mod_that_changes_scaling_with_no_family_is_refused() -> void:
	var mod := _mod(WeaponData.WeaponType.NONE, {Stats.Stat.DEX: 5})
	assert_bool(_tool()._refuse_unusable(mod)).is_true()

# Both legal shapes: a shift WITH its family, and a mod that changes no scaling at all -- which is
# the majority of the bank, and is exactly why the restriction is derived rather than blanket.
func test_a_mod_with_a_family_or_with_no_scaling_saves_fine() -> void:
	var tool_ref := _tool()
	assert_bool(tool_ref._refuse_unusable(_mod(WeaponData.WeaponType.CARBINE, {Stats.Stat.DEX: 5}))).is_false()
	assert_bool(tool_ref._refuse_unusable(_mod(WeaponData.WeaponType.NONE))).is_false()

# One door for every kind this tab authors, so widening it for mods must not have narrowed it for
# anything else -- the template arm is the one that was already there.
func test_the_gate_still_refuses_a_template_with_no_family() -> void:
	var template := WeaponData.new()          # weapon_type NONE: make() could never build it
	assert_bool(_tool()._refuse_unusable(template)).is_true()
