# Every thing the game names says what it is made of (SubstanceMap, Deep Alchemy phase 1).
#
# The element vocabulary (ELEMENTS) is code; the tile states, gases and unit states are AUTHORED rows in
# Resources/SubstanceMap.tres (#1532), and a ground's makeup is its tile's made_of column (#1315). A new
# Element, State, TileState or gas Kind reds here until it gets a row. A row or tile may be EMPTY (a hole
# holds nothing), but every id it names must be a real substance file. Vials carry their own field, so
# they are held here too, with the vials that have no substance yet declared.
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


# A ground's makeup is its tile's made_of column (#1315). A tile may hold nothing (a hole), but every
# id it names is a substance file, named once.
func test_every_tile_names_real_substances() -> void:
	var tiles := load(GridUtils.TILESET_PATH) as TileSet
	assert_int(tiles.get_custom_data_layer_by_name(GridUtils.MADE_OF)).override_failure_message(
			"%s has no '%s' column" % [GridUtils.TILESET_PATH, GridUtils.MADE_OF]).is_not_equal(-1)
	var catalog := SubstanceCatalog.get_all()
	var faults: Array[String] = []
	for s in tiles.get_source_count():
		var source := tiles.get_source(tiles.get_source_id(s)) as TileSetAtlasSource
		if source == null:
			continue
		for i in source.get_tiles_count():
			var coords := source.get_tile_id(i)
			for alt in source.get_alternative_tiles_count(coords):
				var ids := GridUtils.made_of(source.get_tile_data(coords, source.get_alternative_tile_id(coords, alt)))
				for id: String in ids:
					if not catalog.has(id):
						faults.append("tile %s names '%s', which is not a substance file" % [coords, id])
					elif ids.count(id) > 1:
						faults.append("tile %s names '%s' twice" % [coords, id])
	assert_array(faults).is_empty()


# Walkable ground with a kind is somewhere a unit stands and casts from, so it must say what it is
# made of (#1315): an empty makeup makes every carving fizzle there, silently.
func test_every_walkable_ground_names_its_makeup() -> void:
	var tiles := load(GridUtils.TILESET_PATH) as TileSet
	var grounds := 0
	var faults: Array[String] = []
	for s in tiles.get_source_count():
		var source_id := tiles.get_source_id(s)
		var source := tiles.get_source(source_id) as TileSetAtlasSource
		if source == null:
			continue
		for i in source.get_tiles_count():
			var coords := source.get_tile_id(i)
			for alt in source.get_alternative_tiles_count(coords):
				var data := source.get_tile_data(coords, source.get_alternative_tile_id(coords, alt))
				if not GridUtils.walkable_of(data) or GridUtils.terrain_kind_of(data) == Terrain.Kind.NONE:
					continue
				grounds += 1
				if GridUtils.made_of(data).is_empty():
					faults.append("tile %d/%s (%s) is walkable ground with no Made of"
							% [source_id, coords, Terrain.Kind.keys()[GridUtils.terrain_kind_of(data)]])
	assert_int(grounds).override_failure_message(
			"no walkable ground tile in %s: this law checked nothing" % GridUtils.TILESET_PATH).is_greater(0)
	assert_array(faults).is_empty()


# What only an Extract draws out of a compound must be a real substance (#1315).
func test_every_extract_only_part_is_a_substance() -> void:
	var catalog := SubstanceCatalog.get_all()
	var faults: Array[String] = []
	for key: String in catalog:
		for id: String in (catalog[key] as Substance).extract_only_ids():
			if not catalog.has(id):
				faults.append("%s holds '%s' for an Extract, which is not a substance file" % [key, id])
	assert_array(faults).is_empty()


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
