extends Object
class_name SubstanceMap

# What each thing the game already names is MADE of (docs/design/deep-alchemy.md) -- the one answer,
# for the five enum vocabularies. A vial is per-file content, so it carries its own substance
# (VialData.substance) instead of a row here.
#
# An entry is a substance id, or a NONE / PENDING line saying why there is none. PENDING lines are
# open design questions; c3potheds owns them. tests/law/test_substance_map.gd holds every member to
# an entry and every id to a real file.

const NONE := "none: "
const PENDING := "pending: "

const ELEMENTS: Dictionary[Elemental.Element, String] = {
	Elemental.Element.FIRE: "flame",
	Elemental.Element.WATER: "water",
	Elemental.Element.SHOCK: "lightning",
	Elemental.Element.ICE: PENDING + "what ice is made of is open",
	Elemental.Element.EARTH: "salt",
	Elemental.Element.AIR: "inert_air",
	Elemental.Element.AETHER: "essence",
	Elemental.Element.CORROSION: PENDING + "vitriol has no formula yet",
}

const STATES: Dictionary[Elemental.State, String] = {
	Elemental.State.WET: "water",
	Elemental.State.CHILLED: PENDING + "cold is open",
}

const TILE_STATES: Dictionary[Terrain.TileState, String] = {
	Terrain.TileState.BURNING: "flame",
	Terrain.TileState.FROZEN: PENDING + "what ice is made of is open",
	Terrain.TileState.COVER: NONE + "an entrenchment is a shape dug in the ground",
	Terrain.TileState.SCORCHED: "ash",
}

const KINDS: Dictionary[Terrain.Kind, String] = {
	Terrain.Kind.GRASS: PENDING + "organic matter's proportions are open",
	Terrain.Kind.MUD: PENDING + "mud has no formula yet",
	Terrain.Kind.ROCK: PENDING + "stone has no formula yet",
	Terrain.Kind.TREE: PENDING + "organic matter's proportions are open",
	Terrain.Kind.WATER: "water",
	Terrain.Kind.DIRT: PENDING + "dirt has no formula yet",
	Terrain.Kind.VOID: NONE + "a hole holds nothing",
	Terrain.Kind.TALL_GRASS: PENDING + "organic matter's proportions are open",
}

const GASES: Dictionary[Gas.Kind, String] = {
	Gas.Kind.STEAM: "steam",
	Gas.Kind.SMOKE: "smoke",
	Gas.Kind.POISON: "chlorine",
	Gas.Kind.FROST: PENDING + "frost cloud is ice in air, and ice is open",
	Gas.Kind.THUNDER: "thunder",
	Gas.Kind.SULFUR: "sulfur_gas",
}


# The substance id an entry names, or "" for a NONE or PENDING line (or no entry).
static func id_of(entry: String) -> String:
	if entry == "" or entry.begins_with(NONE) or entry.begins_with(PENDING):
		return ""
	return entry


static func of_element(element: Elemental.Element) -> String:
	return id_of(ELEMENTS.get(element, ""))


static func of_state(state: Elemental.State) -> String:
	return id_of(STATES.get(state, ""))


static func of_tile_state(state: Terrain.TileState) -> String:
	return id_of(TILE_STATES.get(state, ""))


static func of_kind(kind: Terrain.Kind) -> String:
	return id_of(KINDS.get(kind, ""))


static func of_gas(kind: Gas.Kind) -> String:
	return id_of(GASES.get(kind, ""))
