# Field tooltips on the dev tools' reflective editor (#473).
#
# The editor draws its rows from get_property_list() and carried no text on any of them, which is
# how a range edit landed in the wrong box of two adjacent lookalike spinboxes with nothing to say
# so. The text lives in a PROPERTY_TIPS const beside the @export it describes, and DevWidgets walks
# the base chain to find it -- so the two things worth pinning are that the walk actually reaches a
# base class's table, and that the text reaches the CONTROL rather than stopping at the lookup.
#
# The nested case is the trap this was designed around: apply_tooltip recurses, so tipping an
# object row after its nested block was built would overwrite every tip inside it with the parent's.
extends GdUnitTestSuite

var _box: VBoxContainer


func before_test() -> void:
	_box = VBoxContainer.new()
	add_child(_box)


func after_test() -> void:
	_box.queue_free()


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
