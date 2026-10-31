extends Resource
class_name SubstanceMap

# What each thing the game already names is MADE of (docs/design/deep-alchemy.md) -- the one answer,
# in two declared halves:
#
#   ELEMENTS, CARRIED_AS_TOO   code. What a hit of each element IS, read backwards to say what a
#                              carving hits as. The element vocabulary, not a source.
#   grounds, tile_states,      AUTHORED (#1532), in Resources/SubstanceMap.tres. What each ground kind,
#   gases, unit_states         tile state, gas and unit state holds: what a carving beside it can draw
#                              on (CellSubstances). A row may name several substances (Burning is flame
#                              and heat, #1535); an empty row holds nothing (a hole, an entrenchment).
#
# A vial is per-file content, so it carries its own substance (VialData.substance) instead of a row.
# tests/law/test_substance_map.gd holds every member to a row and every id to a real file.

const PATH := "res://Resources/SubstanceMap.tres"

const ELEMENTS: Dictionary[Elemental.Element, String] = {
	Elemental.Element.FIRE: "flame",
	Elemental.Element.WATER: "water",
	Elemental.Element.SHOCK: "lightning",
	Elemental.Element.ICE: "atom_aether",  # free aether, which binds the first water it meets
	Elemental.Element.EARTH: "salt",
	Elemental.Element.AIR: "inert_air",
	Elemental.Element.AETHER: "essence",
	Elemental.Element.CORROSION: "vitriol",
	Elemental.Element.HEAT: "atom_fire",  # free heat: flame decays to it, and it melts ice
}

# What a hit carries when it delivers a substance -- ELEMENTS read backwards (flame is FIRE), plus
# the one product no ELEMENTS row names: ice, which a Freeze's free aether becomes once it binds water.
# A carving's hit element is derived from this (TransmutationData.get_elements).
const CARRIED_AS_TOO: Dictionary[String, Elemental.Element] = {
	"ice": Elemental.Element.ICE,
}

@export var grounds: Dictionary[Terrain.Kind, PackedStringArray] = {}
@export var tile_states: Dictionary[Terrain.TileState, PackedStringArray] = {}
@export var gases: Dictionary[Gas.Kind, PackedStringArray] = {}
@export var unit_states: Dictionary[Elemental.State, PackedStringArray] = {}

# The authored map, held so a reader per cell pays no path lookup. The dev tools edit and save this
# same object (DevWidgets.save_over writes through to the owner of the path), so a live edit reaches
# the next read.
static var _authored: SubstanceMap = null


static func authored() -> SubstanceMap:
	if _authored == null:
		_authored = load(PATH) as SubstanceMap
		if _authored == null:
			push_error("SubstanceMap: %s did not load, so nothing on the board is made of anything" % PATH)
			_authored = SubstanceMap.new()
	return _authored


static func refresh() -> void:
	_authored = null


func of_kind(kind: Terrain.Kind) -> Array[String]:
	return _ids(grounds.get(kind, PackedStringArray()))


func of_tile_state(state: Terrain.TileState) -> Array[String]:
	return _ids(tile_states.get(state, PackedStringArray()))


func of_gas(kind: Gas.Kind) -> Array[String]:
	return _ids(gases.get(kind, PackedStringArray()))


func of_state(state: Elemental.State) -> Array[String]:
	return _ids(unit_states.get(state, PackedStringArray()))


static func of_element(element: Elemental.Element) -> String:
	return ELEMENTS.get(element, "")


# The element a hit delivering this substance carries, or NONE.
static func element_carried_by(substance_id: String) -> Elemental.Element:
	for element: Elemental.Element in ELEMENTS:
		if ELEMENTS[element] == substance_id:
			return element
	return CARRIED_AS_TOO.get(substance_id, Elemental.Element.NONE)


static func _ids(row: PackedStringArray) -> Array[String]:
	var out: Array[String] = []
	out.assign(Array(row))
	return out
