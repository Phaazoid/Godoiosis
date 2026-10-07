# Every thing the game names says what it is made of (SubstanceMap, Deep Alchemy phase 1).
#
# A new Element, State, TileState, terrain Kind or gas Kind reds here until it gets a row: a substance
# id, or a NONE / PENDING line saying why not. Every id must be a real substance file. Vials carry
# their own field, so they are held here too, with the vials that have no substance yet declared.
extends GdUnitTestSuite

const VIALS_WITHOUT_SUBSTANCE := {
	"res://Resources/Vials/NitreVial.tres": "nitre has no formula yet (codev)",
	"res://Resources/Vials/IchorVial.tres": "ichor has no formula yet (codev)",
	"res://Resources/Vials/VitriolVial.tres": "vitriol has no formula yet (codev)",
	"res://Resources/Vials/AlkahestVial.tres": "alkahest is the prima materia, not a formula",
}


func _check_table(table: Dictionary, members: Array, names: Array, label: String) -> Array[String]:
	var catalog := SubstanceCatalog.get_all()
	var faults: Array[String] = []
	for member: int in members:
		var name: String = names[member]
		if not table.has(member):
			faults.append("%s.%s has no SubstanceMap row" % [label, name])
			continue
		var entry: String = table[member]
		var id := SubstanceMap.id_of(entry)
		if id == "":
			var reason := entry.trim_prefix(SubstanceMap.NONE).trim_prefix(SubstanceMap.PENDING).strip_edges()
			if reason == "" or reason == entry.strip_edges():
				faults.append("%s.%s: '%s' is neither a substance id nor a reasoned NONE/PENDING" % [label, name, entry])
		elif not catalog.has(id):
			faults.append("%s.%s names '%s', which is not a substance file" % [label, name, id])
	return faults


func _members_except(values: Array, skip: Array) -> Array:
	var out := []
	for v: int in values:
		if not skip.has(v):
			out.append(v)
	return out


func test_every_element_says_what_it_is() -> void:
	var members := _members_except(Elemental.Element.values(), [Elemental.Element.NONE])
	assert_array(_check_table(SubstanceMap.ELEMENTS, members, Elemental.Element.keys(), "Element")).is_empty()


func test_every_unit_state_says_what_it_is() -> void:
	var members := _members_except(Elemental.State.values(), [Elemental.State.NONE])
	assert_array(_check_table(SubstanceMap.STATES, members, Elemental.State.keys(), "State")).is_empty()


func test_every_tile_state_says_what_it_is() -> void:
	var skip: Array = [Terrain.TileState.NONE]
	skip.append_array(Terrain.RETIRED_STATES)
	var members := _members_except(Terrain.TileState.values(), skip)
	assert_array(_check_table(SubstanceMap.TILE_STATES, members, Terrain.TileState.keys(), "TileState")).is_empty()


func test_every_ground_says_what_it_is() -> void:
	var members := _members_except(Terrain.Kind.values(), [Terrain.Kind.NONE])
	assert_array(_check_table(SubstanceMap.KINDS, members, Terrain.Kind.keys(), "Kind")).is_empty()


func test_every_gas_says_what_it_is() -> void:
	# The six gas looks hang on this answer (#508): a gas with no substance has no chemistry to draw.
	assert_array(_check_table(SubstanceMap.GASES, Gas.Kind.values(), Gas.Kind.keys(), "Gas")).is_empty()


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
