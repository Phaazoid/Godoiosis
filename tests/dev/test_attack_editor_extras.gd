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
