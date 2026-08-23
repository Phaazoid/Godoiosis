# Field tooltips on the dev tools' reflective editor (#473).
#
# The editor draws its rows from get_property_list() and carried no text on any of them, which is
# how a range edit landed in the wrong box of two adjacent lookalike spinboxes with nothing to say
# so. The text lives in an overridable static property_tips() beside the @export it describes,
# each class merging its parent's -- so the things worth pinning are that the merge actually
# carries a base class's entries, and that the text reaches the CONTROL rather than the lookup.
#
# The nested case is the trap this was designed around: apply_tooltip recurses, so tipping an
# object row after its nested block was built would overwrite every tip inside it with the parent's.
extends GdUnitTestSuite

var _box: VBoxContainer


func before_test() -> void:
	_box = VBoxContainer.new()
	add_child(_box)


func after_test() -> void:
	remove_child(_box)
	_box.free()


func _attack() -> WeaponAttackData:
	var attack := WeaponAttackData.new()
	attack.attack_pattern = ManhattanRangePattern.new()
	return attack


# Every Label the editor built, by its text -- the row's tooltip is set on every control in it, so
# the label answers for the row.
func _labels(node: Node, found: Dictionary) -> Dictionary:
	for child in node.get_children():
		var label := child as Label
		if label != null:
			found[label.text] = label
		_labels(child, found)
	return found


func test_a_tip_comes_off_the_resources_own_table() -> void:
	var tip := DevWidgets.property_tip(ManhattanRangePattern.new(), "min_range")
	assert_str(tip).contains("CLOSEST")


func test_a_tip_is_found_on_a_base_class_table() -> void:
	# vertical_rule is declared on AttackData; the resource being drawn is a WeaponAttackData.
	var tip := DevWidgets.property_tip(WeaponAttackData.new(), "vertical_rule")
	assert_str(tip).contains("MELEE")


func test_a_field_with_no_entry_answers_empty_rather_than_failing() -> void:
	assert_str(DevWidgets.property_tip(WeaponAttackData.new(), "not_a_field")).is_equal("")
	assert_str(DevWidgets.property_tip(AttackPattern.new(), "anything")).is_equal("")


func test_the_text_reaches_the_built_control() -> void:
	DevWidgets.build_resource_editor(_box, _attack(), func(): pass, ["display_name"])
	var labels := _labels(_box, {})
	assert_bool(labels.has("Vertical Rule")).is_true()
	assert_str((labels["Vertical Rule"] as Label).tooltip_text).contains("beads")


func test_a_nested_patterns_rows_keep_their_own_tips() -> void:
	DevWidgets.build_resource_editor(_box, _attack(), func(): pass, ["display_name"])
	var labels := _labels(_box, {})
	assert_bool(labels.has("Min Range")).is_true()
	var nested := (labels["Min Range"] as Label).tooltip_text
	assert_str(nested).contains("CLOSEST")
	# The parent row's own text must not have been painted over it.
	assert_str(nested).not_contains("indented underneath")


# Mirrors build_resource_editor's own filter, so a field this reports is exactly a field that gets
# drawn. The skip lists come from AttackEditorTool rather than being restated here -- a field
# skipped in one and not the other is a field that silently loses its text or fails a law that
# never draws it.
func _untipped(resource: Resource, skip: Array, missing: Array[String]) -> void:
	for prop in resource.get_property_list():
		if prop.name in skip:
			continue
		var exported: bool = (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and (prop.usage & PROPERTY_USAGE_EDITOR) != 0
		if not exported:
			continue
		if DevWidgets.property_tip(resource, prop.name) == "":
			missing.append("%s.%s" % [resource.get_script().get_global_name(), prop.name])


# The coverage law: a field the Attack Editor draws must say what it is. Scoped to that editor's
# own resources on purpose -- the Item Editor's reflective branch only fires for an equippable that
# is neither a rune nor a weapon, which is ArmorData and its own ticket's business.
func test_every_field_the_attack_editor_draws_carries_text() -> void:
	var missing: Array[String] = []
	_untipped(WeaponAttackData.new(), AttackEditorTool.POOL_SKIP, missing)
	_untipped(TransmutationData.new(), AttackEditorTool.CARVING_SKIP, missing)
	_untipped(ManhattanRangePattern.new(), [], missing)
	_untipped(ForwardLinePattern.new(), [], missing)
	_untipped(ForwardWidePattern.new(), [], missing)
	assert_array(missing).is_empty()


# The Item Editor's mod mode (#74) -- and it skips only display_name, which has its own LineEdit
# above the form. That is stricter than the Attack Editor's lists above, deliberately: the four
# fields build_resource_editor cannot draw (two Arrays, two Dictionaries) get bespoke UI that is
# handed DevWidgets.property_tip explicitly, so every one of them reaches a control and owes text.
func test_every_field_the_mod_editor_draws_carries_text() -> void:
	var missing: Array[String] = []
	_untipped(WeaponModData.new(), ["display_name"], missing)
	assert_array(missing).is_empty()


func test_a_subclass_keeps_its_parents_entries_as_well_as_its_own() -> void:
	# The merge is hand-written per class, so forgetting it is the live footgun. Both halves in one
	# case, because the failure mode is exactly "one of these two answers went missing".
	var weapon_attack := WeaponAttackData.new()
	assert_str(DevWidgets.property_tip(weapon_attack, "requires_readiness")).is_not_empty()   # its own
	assert_str(DevWidgets.property_tip(weapon_attack, "arc_clearance")).is_not_empty()        # AttackData's
