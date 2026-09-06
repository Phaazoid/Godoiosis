# Family extras in the Attack Editor (#473) -- the door that lets an authored attack reach a unit.
#
# Driven through the REAL built rows (find the Add button, press it), not by calling the handler:
# a list that fills a array nobody wired to a button is exactly #103's shape, and the assertion is
# on WeaponData.attacks() -- the visible consequence a unit's menu reads -- rather than on
# extra_attacks, which would pass against extras that never reach an attack list.
#
# NOTHING HERE TOUCHES SHIPPED CONTENT. current_template is a SYNTHETIC WeaponData, because
# WeaponCatalog serves the real families out of the resource cache to every suite in the run: a
# case that appended to Carbine.tres would leak an extra attack into whatever ran next (the same
# rule test_object_fields.gd keeps for TestTiles.tres). The library it picks FROM is real, since
# reading a catalog mutates nothing.
extends GdUnitTestSuite

# preload, never load(): a per-test load() reloads the 5 MB mesh library every case (#621).
const SCENE: PackedScene = preload("res://Scenes/Battle3D/Battle3D.tscn")

var _scene: Node3D
var _editor: AttackEditorTool


func before_test() -> void:
	var packed := SCENE
	_scene = packed.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	var dev_overlay := _scene.get_node("Main/DevOverlay") as DevOverlay
	_editor = dev_overlay.get_node("%Attack Editor") as AttackEditorTool


func after_test() -> void:
	# FALSE orphans, not a leak (tests/README.md #162): populate() tears its old rows down with
	# remove_child + queue_free, and a parentless-pending node is exactly what the orphan monitor
	# counts if the suite ends in the same frame. It reported 1017. The idle frame is the prescribed
	# teardown for any suite that clears or reloads a board. It is STILL needed on v6.2.1 (#482):
	# the upstream fix (GD-1291) drops only the queued row ROOT, not its descendants, and 6.2.1
	# samples in the same frame as after_test -- the row children count as orphans (gdUnit4#1320).
	await await_idle_frame()
	get_tree().root.remove_child(_scene)
	_scene.free()


# Put the editor in Family mode over a family nothing else shares.
func _open_synthetic_family(with_main: bool) -> WeaponData:
	var family := WeaponData.new()
	family.display_name = "Probe Family"
	if with_main:
		var main := WeaponAttackData.new()
		main.display_name = "Probe Main"
		family.main_attack = main
	_editor._mode = AttackEditorTool.Mode.FAMILY
	_editor.current_template = family
	_editor.current = family.main_attack
	_editor._loaded_name = "Probe Family"
	_editor.populate()
	return family


func _button(text: String) -> Button:
	return _find_button(_editor.editor_container, text)


func _find_button(node: Node, text: String) -> Button:
	for child in node.get_children():
		var button := child as Button
		if button != null and button.text == text:
			return button
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func test_the_library_is_not_empty_so_these_cases_mean_something() -> void:
	assert_bool(WeaponAttackCatalog.get_library().is_empty()).override_failure_message(
		"no saved attacks scanned -- the scan is broken, not the content").is_false()


func test_adding_an_extra_reaches_the_familys_attack_list() -> void:
	var family := _open_synthetic_family(true)
	var before: int = family.attacks().size()
	var add := _button("Add")
	assert_object(add).is_not_null()
	add.pressed.emit()
	assert_int(family.attacks().size()).is_equal(before + 1)
	# It is the library's own resource, not a copy: a copy would fork the file the Weapon Attack
	# mode edits, so every later edit there would stop reaching this family.
	var added: WeaponAttackData = family.extra_attacks[0]
	assert_str(added.resource_path).is_not_empty()


func test_removing_an_extra_takes_it_back_off() -> void:
	var family := _open_synthetic_family(true)
	_button("Add").pressed.emit()
	assert_int(family.extra_attacks.size()).is_equal(1)
	var remove := _button("Remove")
	assert_object(remove).is_not_null()
	remove.pressed.emit()
	assert_int(family.extra_attacks.size()).is_equal(0)
	assert_int(family.attacks().size()).is_equal(1)   # the main survives


func test_the_same_attack_cannot_be_carried_twice() -> void:
	var family := _open_synthetic_family(true)
	_button("Add").pressed.emit()
	_button("Add").pressed.emit()
	assert_int(family.extra_attacks.size()).is_equal(1)
	assert_str(_editor.status_label.text).contains("already carries")


func test_a_family_with_no_main_can_still_gain_extras() -> void:
	# The door the old early return made unreachable: populate() returned before drawing anything
	# when a family had no main, so its extras could never be edited at all.
	var family := _open_synthetic_family(false)
	var add := _button("Add")
	assert_object(add).is_not_null()
	add.pressed.emit()
	assert_int(family.attacks().size()).is_equal(1)


# --- a new attack arrives with geometry (#804 follow-up, found in play) -----------------------

# The bug: New built a bare WeaponAttackData, and the ONLY way to give it geometry was the resource
# picker -- which could not do it (see test_stamp_grid.gd's dead-end cases). So a brand new attack
# could never be given a shape at all, and the stamp grid never appeared.
#
# Since #808 a new attack is fireable the moment it exists (range 1, no shape = the aimed cell), and
# the SHAPE row is the door to a footprint. Both halves are driven through the real controls, because
# "the row exists and does nothing" is the exact failure this whole arc keeps paying for.
func test_a_brand_new_attack_arrives_with_geometry_to_draw_on() -> void:
	_editor._on_weapon_attack_mode_selected()   # the MODE is setup, not the thing under test
	await await_idle_frame()
	_editor.new_button.emit_signal("pressed")
	await await_idle_frame()
	var made: AttackData = _editor.current
	assert_object(made).is_not_null()
	assert_int(made.max_range).override_failure_message(
		"New made an attack with no reach, so nothing can be aimed and no grid is worth drawing"
	).is_greater(0)
	assert_object(made.attack_shape).override_failure_message(
		"New should arrive SHAPELESS -- a single-target attack, which the shape row then adds to"
	).is_null()


func test_starting_a_new_shape_draws_the_grid() -> void:
	# A shape existing is not the same as the row appearing: #803 shipped a field nothing drew, and
	# #807 shipped a picker with no reachable row. So this presses the real one.
	_editor._on_weapon_attack_mode_selected()   # the MODE is setup, not the thing under test
	await await_idle_frame()
	_editor.new_button.emit_signal("pressed")
	await await_idle_frame()
	assert_object(_find_class(_editor, "GridContainer")).override_failure_message(
		"a shapeless attack drew a stamp grid over nothing"
	).is_null()

	var picker := _shape_picker()
	assert_object(picker).override_failure_message("no shape picker in the form").is_not_null()
	var row := -1
	for i in picker.item_count:
		if picker.get_item_text(i) == AttackEditorTool.NEW_SHAPE_KEY:
			row = i
	assert_int(row).override_failure_message("no (new shape) row to pick").is_greater(0)
	picker.item_selected.emit(row)
	await await_idle_frame()

	assert_object(_editor.current.attack_shape).override_failure_message(
		"picking (new shape) assigned nothing -- the control is a dead end again"
	).is_not_null()
	assert_object(_find_class(_editor, "GridContainer")).override_failure_message(
		"no stamp grid in the form after starting a shape"
	).is_not_null()


func _shape_picker() -> OptionButton:
	for node in _all_class(_editor, "OptionButton", []):
		var option := node as OptionButton
		for i in option.item_count:
			if option.get_item_text(i) == AttackEditorTool.NEW_SHAPE_KEY:
				return option
	return null


func _all_class(node: Node, klass: String, found: Array[Node]) -> Array[Node]:
	for child in node.get_children():
		if child.is_class(klass):
			found.append(child)
		_all_class(child, klass, found)
	return found


func _find_class(node: Node, klass: String) -> Node:
	for child in node.get_children():
		if child.is_class(klass):
			return child
		var deeper := _find_class(child, klass)
		if deeper != null:
			return deeper
	return null
