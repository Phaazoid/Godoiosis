# Every thing the game names says what it is made of (SubstanceMap, Deep Alchemy phase 1).
#
# The element vocabulary (ELEMENTS) is code; the grounds, tile states, gases and unit states are AUTHORED
# rows in Resources/SubstanceMap.tres (#1532). A new Element, State, TileState, terrain Kind or gas Kind
# reds here until it gets a row. An authored row may be EMPTY (a hole holds nothing), but every id it
# names must be a real substance file. Vials carry their own field, so they are held here too, with the
# vials that have no substance yet declared.
extends GdUnitTestSuite

const VIALS_WITHOUT_SUBSTANCE := {
	"res://Resources/Vials/IchorVial.tres": "ichor has no formula yet (codev)",
	"res://Resources/Vials/AlkahestVial.tres": "alkahest is the prima materia, not a formula",
}


func _members_except(values: Array, skip: Array) -> Array:
	var out := []
	for v: int in values:
		if not skip.has(v):
			out.append(v)
	return out


# Every member has a row, and every id a row names is a substance file.
func _check_rows(table: Dictionary, members: Array, names: Array, label: String) -> Array[String]:
	var catalog := SubstanceCatalog.get_all()
	var faults: Array[String] = []
	for member: int in members:
		var name: String = names[member]
		if not table.has(member):
			faults.append("%s.%s has no row in %s" % [label, name, SubstanceMap.PATH])
			continue
		for id: String in table[member]:
			if not catalog.has(id):
				faults.append("%s.%s names '%s', which is not a substance file" % [label, name, id])
	return faults


func test_the_authored_map_loads() -> void:
	SubstanceMap.refresh()
	assert_object(load(SubstanceMap.PATH) as SubstanceMap).override_failure_message(
			"%s is not a SubstanceMap" % SubstanceMap.PATH).is_not_null()


func test_every_element_says_what_it_is() -> void:
	var catalog := SubstanceCatalog.get_all()
	var faults: Array[String] = []
	for element: int in _members_except(Elemental.Element.values(), [Elemental.Element.NONE]):
		var id := SubstanceMap.of_element(element as Elemental.Element)
		var name: String = Elemental.Element.keys()[element]
		if id == "":
			faults.append("Element.%s has no SubstanceMap.ELEMENTS row" % name)
		elif not catalog.has(id):
			faults.append("Element.%s names '%s', which is not a substance file" % [name, id])
	assert_array(faults).is_empty()


func test_every_unit_state_says_what_it_is() -> void:
	var members := _members_except(Elemental.State.values(), [Elemental.State.NONE])
	assert_array(_check_rows(SubstanceMap.authored().unit_states, members, Elemental.State.keys(), "State")).is_empty()


func test_every_tile_state_says_what_it_is() -> void:
	var skip: Array = [Terrain.TileState.NONE]
	skip.append_array(Terrain.RETIRED_STATES)
	var members := _members_except(Terrain.TileState.values(), skip)
	assert_array(_check_rows(SubstanceMap.authored().tile_states, members, Terrain.TileState.keys(), "TileState")).is_empty()


func test_every_ground_says_what_it_is() -> void:
	var members := _members_except(Terrain.Kind.values(), [Terrain.Kind.NONE])
	assert_array(_check_rows(SubstanceMap.authored().grounds, members, Terrain.Kind.keys(), "Kind")).is_empty()


func test_every_gas_says_what_it_is() -> void:
	# The gas looks hang on this answer (#508): a gas with no substance has no chemistry to draw.
	assert_array(_check_rows(SubstanceMap.authored().gases, Gas.Kind.values(), Gas.Kind.keys(), "Gas")).is_empty()


func test_every_vial_names_its_substance_or_says_why_not() -> void:
	var vials := VialCatalog.get_variants()
	assert_bool(vials.is_empty()).override_failure_message("no vials scanned").is_false()
	var faults: Array[String] = []
	for key: String in vials:
		var vial := vials[key] as VialData
		var path := vial.resource_path
		var declared := VIALS_WITHOUT_SUBSTANCE.has(path)
		if vial.substance == null and not declared:
			faults.append("%s has no substance and no line in VIALS_WITHOUT_SUBSTANCE" % path)
		elif vial.substance != null and declared:
			faults.append("%s now has a substance: take it off VIALS_WITHOUT_SUBSTANCE" % path)
	assert_array(faults).is_empty()


# A conduit (#1312) exists only to supply its substance, so one holding nothing is a file that does
# nothing. Every one is authored with one; an empty catalog passes (rule 9).
func test_every_conduit_names_its_substance() -> void:
	var conduits := ConduitCatalog.get_variants()
	var faults: Array[String] = []
	for key: String in conduits:
		var conduit := conduits[key] as ConduitData
		if conduit.substance == null:
			faults.append("%s holds no substance, so it supplies nothing" % conduit.resource_path)
	assert_array(faults).is_empty()
