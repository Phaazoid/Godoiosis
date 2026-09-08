# Authored content has to be OBTAINABLE. #697 shipped four vials nothing in the project referenced:
# no catalog scanned Resources/Vials/, no roster listed one, and both dev editors built their item
# picker from a weapons+armor+runes union, so the only way to hold one was to hand-edit a .tres.
# Every test passed, the rule was correct end to end, and the feature was unplayable.
#
# What this law asks is the question the suite could not: can the dev GET one. It is deliberately
# about the ITEM CATALOGS rather than about vials -- the next content kind added without a catalog
# fails here rather than being noticed in play.
#
# WEAPONS joined it in #835, and they are the same fault wearing a second shape: their catalog
# existed and was scanned, but only the SAVED-variants folder ever fed a picker, so seven authored
# prototypes and a family base could not be granted to anyone while every test stayed green. A kind
# can be unreachable for want of a catalog, OR for want of a bridge from the layer it is authored in.
extends GdUnitTestSuite

const VIAL_DIR := "res://Resources/Vials/"


func _authored_vial_names() -> Array:
	return VialCatalog.get_variants().keys()


func test_the_authored_vials_are_actually_on_disk() -> void:
	assert_array(_authored_vial_names()).override_failure_message(
			"no vial resources under %s -- every case below would pass vacuously" % VIAL_DIR
			).is_not_empty()


# The catalog is what every editor and grant path reads. Without one the folder is invisible.
func test_every_authored_vial_is_in_the_catalog() -> void:
	var on_disk := ResourceDir.files_with_extension(VIAL_DIR, "tres")
	assert_int(_authored_vial_names().size()).override_failure_message(
			"%d vial files on disk, %d in the catalog -- one of them cannot be granted"
			% [on_disk.size(), _authored_vial_names().size()]).is_equal(on_disk.size())


func test_a_catalogued_vial_is_a_VialData_carrying_something() -> void:
	for name: String in _authored_vial_names():
		var vial := VialCatalog.get_variants()[name] as VialData
		assert_object(vial).override_failure_message(
				"'%s' is in the vial catalog but is not a VialData" % name).is_not_null()
		assert_array(vial.granted_elements()).override_failure_message(
				"'%s' grants no element at all -- using it would buy nothing" % name).is_not_empty()


# THE case the ticket's gap would have failed. A vial is an Item and never an EquippableData, so a
# picker built from equippables alone cannot offer one however many exist.
func test_the_editors_item_picker_offers_vials() -> void:
	var tool_node: UnitEditorTool = auto_free(UnitEditorTool.new())
	var offered: Array = tool_node._item_catalog().keys()

	assert_array(offered).is_not_empty()
	for name: String in _authored_vial_names():
		assert_bool(offered.has(name)).override_failure_message(
				"the dev editors cannot offer '%s' -- it exists and nobody can be given one" % name
				).is_true()


# A carried non-equippable must survive the pipeline it is authored into, or the stash entry below
# is a file that silently vanishes at deploy.
func test_a_vial_survives_a_grant_copy() -> void:
	for name: String in _authored_vial_names():
		var granted := (VialCatalog.get_variants()[name] as VialData).copy_for_grant() as VialData
		assert_object(granted).override_failure_message(
				"copying '%s' for a grant did not hand back a VialData" % name).is_not_null()
		assert_array(granted.granted_elements()).is_not_empty()


# The weapon half. A template is authored in MainVarieties/ or Prototypes/ and is not itself
# carryable, so the picker offers the DERIVED generic built on it (#835). Sweeps whatever is on
# disk and passes vacuously on an empty scan -- the claim is reachability, not which weapons exist.
func test_the_editors_item_picker_offers_every_weapon_template() -> void:
	var tool_node: UnitEditorTool = auto_free(UnitEditorTool.new())
	var offered: Array = tool_node._item_catalog().keys()

	for dir: String in [WeaponCatalog.MAIN_VARIETIES_DIR, WeaponCatalog.PROTOTYPE_DIR]:
		var templates := ResourceCatalog.by_file(dir, WeaponData)
		for file: String in templates:
			var template: WeaponData = templates[file]
			var name: String = template.display_name if template.display_name != "" else file
			assert_bool(offered.has(name)).override_failure_message(
					"the dev editors cannot offer '%s' -- it is authored and nobody can hold one"
					% name).is_true()


# THE LAST HOP, and the one every case above is blind to: a name in the catalog still has to become
# a ROW. #804 is the precedent and the warning -- a reflective editor row compared against the wrong
# thing, matched nothing, and left the attack stamp unauthorable for a whole ticket while its data
# layer tested clean. "Offered" is not "drawn", and only one of those is what the dev can click.
#
# Sweeps whatever the catalog offers, so it covers vials, armour, runes, weapons and the DERIVED
# generics (#835) in one claim, and passes vacuously on an empty catalog.
func test_every_offered_item_draws_a_row_in_the_inventory_picker() -> void:
	var tool_node: UnitEditorTool = auto_free(UnitEditorTool.new())
	tool_node._inventory.resize(Unit.MAX_INVENTORY_SIZE)
	var box: VBoxContainer = auto_free(VBoxContainer.new())
	tool_node._add_inventory_section(box)

	var picker := _first_option_button(box)
	assert_object(picker).override_failure_message(
			"the inventory section built no dropdown at all").is_not_null()

	var listed: Array[String] = []
	for i in range(picker.item_count):
		listed.append(picker.get_item_text(i))

	for name: String in tool_node._item_catalog():
		assert_bool(listed.has(name)).override_failure_message(
				"'%s' is offered by the catalog and no row draws it" % name).is_true()


func _first_option_button(node: Node) -> OptionButton:
	for child in node.get_children():
		if child is OptionButton:
			return child
		var found := _first_option_button(child)
		if found != null:
			return found
	return null
