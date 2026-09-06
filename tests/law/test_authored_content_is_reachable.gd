# Authored content has to be OBTAINABLE. #697 shipped four vials nothing in the project referenced:
# no catalog scanned Resources/Vials/, no roster listed one, and both dev editors built their item
# picker from a weapons+armor+runes union, so the only way to hold one was to hand-edit a .tres.
# Every test passed, the rule was correct end to end, and the feature was unplayable.
#
# What this law asks is the question the suite could not: can the dev GET one. It is deliberately
# about the ITEM CATALOGS rather than about vials -- the next content kind added without a catalog
# fails here rather than being noticed in play.
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
