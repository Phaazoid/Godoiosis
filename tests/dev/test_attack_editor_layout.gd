# The Attack Editor's sectioned form (#825) -- headings, and rows that hide when the attack they
# describe cannot use them.
#
# What is worth pinning here is what a glance at the panel cannot confirm. That every exported field
# lands in exactly one section is a LAW, and it is what replaced the two skip lists: a field is drawn
# because its resource declares a home for it, so a field in no section is a field nobody can edit
# and nothing else would say so (#803 shipped exactly that and it went unnoticed for a whole ticket).
# That hiding is LIVE is a WIRE -- the rows react to `changed` rather than to a rebuild, so the cases
# hold a node across the edit and assert on that same node, which is the only way to tell a redraw
# from a reflow.
#
# Everything builds its own attack (dev: tests never read authored content). What a headless suite
# cannot see is whether the sections READ well -- the PR says so out loud.
extends GdUnitTestSuite

# preload, never load(): a per-test load() reloads the 5 MB mesh library every case (#621).
const SCENE: PackedScene = preload("res://Scenes/Battle3D/Battle3D.tscn")

var _scene: Node3D
var _editor: AttackEditorTool


func before_test() -> void:
	_scene = SCENE.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	var dev_overlay := _scene.get_node("Main/DevOverlay") as DevOverlay
	_editor = dev_overlay.get_node("%Attack Editor") as AttackEditorTool


func after_test() -> void:
	# FALSE orphans, not a leak (tests/README.md #162): populate() tears its rows down with
	# remove_child + queue_free, and a parentless-pending node is what the orphan monitor counts if
	# the suite ends in the same frame.
	await await_idle_frame()
	get_tree().root.remove_child(_scene)
	_scene.free()


# --- helpers -------------------------------------------------------------------------------

# Open the editor on an attack of our own, in the mode that draws the fullest form.
func _open(attack: AttackData) -> void:
	_editor._mode = AttackEditorTool.Mode.WEAPON_ATTACK
	_editor.current = attack
	_editor._loaded_name = ""
	_editor._stage_fields()
	_editor.populate()


func _all_of(node: Node, klass: String, found: Array[Node]) -> Array[Node]:
	for child in node.get_children():
		if child.is_class(klass):
			found.append(child)
		_all_of(child, klass, found)
	return found


func _label_texts() -> PackedStringArray:
	var texts: PackedStringArray = []
	for node in _all_of(_editor.editor_container, "Label", []):
		texts.append((node as Label).text)
	return texts


# The ROW a control sits in -- the direct child of the form, so its visibility IS the row's. A
# labelled row is the Label's parent; a checkbox is its own row, add_checkbox putting the text on
# the button rather than beside it.
func _row(label_text: String) -> Control:
	for node in _all_of(_editor.editor_container, "Label", []):
		if (node as Label).text == label_text:
			return node.get_parent() as Control
	return _checkbox(label_text)


# The dropdown beside a label, for the rows built as label + OptionButton.
func _option(label_text: String) -> OptionButton:
	var row := _row(label_text)
	return null if row == null else row.get_child(1) as OptionButton


func _checkbox(text: String) -> CheckBox:
	for node in _all_of(_editor.editor_container, "CheckBox", []):
		if (node as CheckBox).text == text:
			return node as CheckBox
	return null


# Where a label sits in the form, top to bottom, for comparing the order of the headings.
func _index_of(text: String) -> int:
	var texts := _label_texts()
	for i in texts.size():
		if texts[i] == text:
			return i
	return -1


func _exported_names(resource: Resource) -> PackedStringArray:
	var names: PackedStringArray = []
	for prop in resource.get_property_list():
		if DevWidgets.is_exported(prop):
			names.append(prop.name)
	return names


func _section_fields(resource: Resource) -> PackedStringArray:
	var fields: PackedStringArray = []
	for section: Dictionary in resource.call("property_sections"):
		fields.append_array(section["fields"] as PackedStringArray)
	return fields


# --- the law: every field has exactly one home ----------------------------------------------

# What the skip lists used to be, inverted. A field in NO section is unreachable in the editor, and
# nothing else in the suite would notice -- the tips law reads the property TABLE, and every case
# below drives a field it already knows the name of.
func test_every_exported_field_sits_in_exactly_one_section() -> void:
	var offenders: Array[String] = []
	for resource: Resource in [WeaponAttackData.new(), TransmutationData.new()]:
		var fields := _section_fields(resource)
		for name in _exported_names(resource):
			var seen := 0
			for field in fields:
				if field == name:
					seen += 1
			if seen != 1:
				offenders.append("%s.%s in %d sections" % [resource.get_script().get_global_name(), name, seen])
	assert_array(offenders).override_failure_message(
		"a field in no section is a field the Attack Editor cannot draw: %s" % str(offenders)
	).is_empty()


# The other direction: a section naming a field that does not exist draws nothing at all, silently.
func test_every_section_entry_names_a_real_exported_field() -> void:
	var offenders: Array[String] = []
	for resource: Resource in [WeaponAttackData.new(), TransmutationData.new()]:
		var exported := _exported_names(resource)
		for field in _section_fields(resource):
			if not exported.has(field):
				offenders.append("%s.%s" % [resource.get_script().get_global_name(), field])
	assert_array(offenders).is_empty()


func test_the_headings_are_drawn_in_the_order_the_resource_declares() -> void:
	_open(WeaponAttackData.new())
	var previous := -1
	for section: Dictionary in WeaponAttackData.property_sections():
		var at := _index_of(section["title"])
		assert_int(at).override_failure_message(
			"no heading drawn for section '%s'" % section["title"]
		).is_greater(previous)
		previous = at


func test_a_carving_gets_its_sigils_section_between_identity_and_the_geometry() -> void:
	_editor._mode = AttackEditorTool.Mode.TRANSMUTATION
	_editor.current = TransmutationData.new()
	_editor._stage_fields()
	_editor.populate()
	var identity := _index_of("Identity")
	var sigils := _index_of("Sigils and flourishes")
	var geometry := _index_of("Range and shape")
	assert_int(sigils).override_failure_message("no sigils heading in the carving form").is_greater(identity)
	assert_int(geometry).is_greater(sigils)


# --- hiding is live, and it reflows rather than rebuilding -----------------------------------

# THE WIRE. Deleting bind_hidden_fields' `changed` connection leaves every case that only checks the
# opening state green, because the form is built with the rule already applied -- so this drives the
# real dropdown and asserts on the node it was holding BEFORE the edit. A rebuild would free that
# node, and a dead connection would leave it visible.
func test_a_row_hides_the_moment_the_rule_changes_and_the_same_node_survives() -> void:
	var attack := WeaponAttackData.new()
	attack.vertical_rule = AttackData.VerticalRule.RANGED
	_open(attack)
	var up_row := _row("Up Tolerance")
	assert_object(up_row).override_failure_message("no Up Tolerance row in the form").is_not_null()
	assert_bool(up_row.visible).is_true()

	_option("Vertical Rule").item_selected.emit(AttackData.VerticalRule.MELEE)
	assert_bool(is_instance_valid(up_row)).override_failure_message(
		"the form REBUILT instead of reflowing -- that frees the control being edited (#741)"
	).is_true()
	assert_bool(up_row.visible).override_failure_message(
		"a MELEE attack still offers Up Tolerance, which its rule never reads"
	).is_false()

	_option("Vertical Rule").item_selected.emit(AttackData.VerticalRule.RANGED)
	assert_bool(up_row.visible).override_failure_message("the row never came back").is_true()


# The reach of that rule, which is the half a mutant gets wrong: arc_clearance is read by the lane
# trace whatever the vertical rule says, so it must SURVIVE the melee hide.
func test_melee_hides_both_tolerances_and_keeps_arc_clearance() -> void:
	var attack := WeaponAttackData.new()
	attack.vertical_rule = AttackData.VerticalRule.MELEE
	_open(attack)
	assert_bool(_row("Up Tolerance").visible).is_false()
	assert_bool(_row("Down Tolerance").visible).is_false()
	assert_bool(_row("Arc Clearance").visible).override_failure_message(
		"arc clearance is traced whatever the vertical rule -- hiding it makes a lob unauthorable in melee"
	).is_true()


# --- the effect choice ------------------------------------------------------------------------

func test_the_effect_choice_writes_the_pair_and_never_both() -> void:
	var attack := WeaponAttackData.new()
	_open(attack)
	var effect := _option("Effect")
	assert_object(effect).override_failure_message("no Effect row in the form").is_not_null()

	effect.item_selected.emit(2)   # No damage
	assert_bool(attack.heals).is_false()
	assert_bool(attack.deals_no_damage).is_true()

	effect.item_selected.emit(1)   # Heal
	assert_bool(attack.heals).is_true()
	assert_bool(attack.deals_no_damage).override_failure_message(
		"heal and no-damage were both set -- the pair must never be true together"
	).is_false()

	effect.item_selected.emit(0)   # Damage
	assert_bool(attack.heals).is_false()
	assert_bool(attack.deals_no_damage).is_false()


func test_a_no_damage_attack_stops_offering_power_and_the_kind_picker() -> void:
	var attack := WeaponAttackData.new()
	_open(attack)
	var power_row := _row("Power")
	var kind_row := _row("Damage kind")
	_option("Effect").item_selected.emit(2)   # No damage
	assert_bool(power_row.visible).override_failure_message(
		"scaling is suppressed on a no-damage attack, so its power number reaches nothing"
	).is_false()
	assert_bool(kind_row.visible).is_false()


# A heal keeps its POWER -- that number is the HP restored -- and only loses the kind.
func test_a_heal_keeps_its_power_and_loses_only_the_kind() -> void:
	var attack := WeaponAttackData.new()
	_open(attack)
	var power_row := _row("Power")
	var kind_row := _row("Damage kind")
	_option("Effect").item_selected.emit(1)   # Heal
	assert_bool(power_row.visible).is_true()
	assert_bool(kind_row.visible).is_false()


# --- the range toggle -------------------------------------------------------------------------

func test_untucking_placed_at_range_writes_zero_and_says_what_that_means() -> void:
	var attack := WeaponAttackData.new()
	attack.max_range = 3
	_open(attack)
	var placed := _checkbox("Placed at range")
	assert_object(placed).override_failure_message("no range toggle in the form").is_not_null()
	assert_bool(placed.button_pressed).is_true()

	placed.button_pressed = false
	assert_int(attack.max_range).override_failure_message(
		"the toggle stores nothing of its own -- off IS max range 0"
	).is_equal(0)
	assert_bool(_row("Max range").visible).is_false()
	assert_int(_index_of("Fires from the attacker: the aim is a FACING, and the whole shape turns to it.")) \
		.override_failure_message("nothing on screen says what range 0 means").is_greater(-1)


func test_ticking_it_back_on_makes_the_attack_placed_again() -> void:
	var attack := WeaponAttackData.new()
	attack.max_range = 0
	_open(attack)
	var placed := _checkbox("Placed at range")
	assert_bool(placed.button_pressed).is_false()
	assert_bool(_row("Max range").visible).is_false()

	placed.button_pressed = true
	assert_int(attack.max_range).is_greater(0)
	assert_bool(_row("Max range").visible).is_true()
	assert_bool(_row("Max and a half").visible).is_true()


# The minimum is behind its own tick because nearly every attack wants the ordinary 1 -- but an
# attack that already carries something else must OPEN with the box ticked, or its authored value is
# invisible and the next save quietly keeps it.
func test_an_attack_with_an_authored_minimum_opens_with_the_box_ticked() -> void:
	var attack := WeaponAttackData.new()
	attack.max_range = 4
	attack.min_range = 2
	_open(attack)
	var custom := _checkbox("Custom minimum range")
	assert_object(custom).is_not_null()
	assert_bool(custom.button_pressed).is_true()
	assert_bool(_row("Min range").visible).is_true()


func test_an_ordinary_attack_hides_the_minimum_until_it_is_asked_for() -> void:
	var attack := WeaponAttackData.new()
	attack.max_range = 2
	attack.min_range = 1
	_open(attack)
	var custom := _checkbox("Custom minimum range")
	assert_bool(custom.button_pressed).is_false()
	assert_bool(_row("Min range").visible).is_false()

	custom.button_pressed = true
	assert_bool(_row("Min range").visible).override_failure_message(
		"ticking the box revealed nothing to edit"
	).is_true()


func test_unticking_the_minimum_puts_it_back_to_adjacent() -> void:
	var attack := WeaponAttackData.new()
	attack.max_range = 4
	attack.min_range = 3
	_open(attack)
	_checkbox("Custom minimum range").button_pressed = false
	assert_int(attack.min_range).override_failure_message(
		"unticking left the dead zone in place, so the attack still cannot hit what closed on it"
	).is_equal(1)
	assert_bool(_row("Min range").visible).is_false()


# A self-anchored attack has no ring, so neither the minimum nor the bevel reaches anything.
func test_a_self_anchored_attack_offers_no_ring_rows_at_all() -> void:
	var attack := WeaponAttackData.new()
	attack.max_range = 0
	_open(attack)
	assert_bool(_row("Min range").visible).is_false()
	assert_bool(_row("Max and a half").visible).is_false()


# --- the Swing modifier's row (#1055) ---------------------------------------------------------

# It reads nothing without a shape: Reach._place answers the anchor cell alone, and one cell has
# nothing to stop at. An inert tick on every single-target attack in the game is what this avoids.
func test_the_swing_box_is_absent_until_the_attack_names_a_shape() -> void:
	var attack := WeaponAttackData.new()
	attack.attack_shape = null
	_open(attack)
	var row := _row("Swing")
	assert_object(row).override_failure_message("no Swing row in the form at all").is_not_null()
	assert_bool(row.visible).override_failure_message(
		"a shapeless attack offers a Swing tick that reaches nothing"
	).is_false()


func test_giving_an_attack_a_shape_brings_the_swing_box_back_live() -> void:
	# THE WIRE, and it rides the same door the form's own controls write through -- DevWidgets.write
	# sets and then emits `changed`, which is what bind_hidden_fields listens to. Asserting on the
	# node held from BEFORE the edit is what separates a reflow from a rebuild (#741).
	var attack := WeaponAttackData.new()
	attack.attack_shape = null
	_open(attack)
	var row := _row("Swing")
	assert_bool(row.visible).is_false()

	DevWidgets.write(attack, "attack_shape", AttackShape.new())
	assert_bool(is_instance_valid(row)).override_failure_message(
		"the form REBUILT instead of reflowing -- that frees the control being edited (#741)"
	).is_true()
	assert_bool(row.visible).override_failure_message(
		"picking a shape left the Swing tick hidden, so the modifier is unauthorable"
	).is_true()

	DevWidgets.write(attack, "attack_shape", null)
	assert_bool(row.visible).override_failure_message("the row never went away again").is_false()
