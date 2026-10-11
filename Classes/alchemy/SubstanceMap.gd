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
	Elemental.Element.ICE: "atom_aether",  # free aether, which binds the first water it meets
	Elemental.Element.EARTH: "salt",
	Elemental.Element.AIR: "inert_air",
	Elemental.Element.AETHER: "essence",
	Elemental.Element.CORROSION: "vitriol",
}

const STATES: Dictionary[Elemental.State, String] = {
	Elemental.State.WET: "water",
	Elemental.State.CHILLED: "ice",
}

const TILE_STATES: Dictionary[Terrain.TileState, String] = {
	Terrain.TileState.BURNING: "flame",
	Terrain.TileState.FROZEN: "ice",
	Terrain.TileState.COVER: NONE + "an entrenchment is a shape dug in the ground",
	Terrain.TileState.SCORCHED: "ash",
}

const KINDS: Dictionary[Terrain.Kind, String] = {
	Terrain.Kind.GRASS: "green_plant",
	Terrain.Kind.MUD: "mud",
	Terrain.Kind.ROCK: "stone",
	Terrain.Kind.TREE: "green_plant",
	Terrain.Kind.WATER: "water",
	Terrain.Kind.DIRT: "dirt",
	Terrain.Kind.VOID: NONE + "a hole holds nothing",
	Terrain.Kind.TALL_GRASS: "dry_plant",
}

const GASES: Dictionary[Gas.Kind, String] = {
	Gas.Kind.STEAM: "steam",
	Gas.Kind.SMOKE: "smoke",
	Gas.Kind.POISON: "chlorine",
	Gas.Kind.FROST: "frost",
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
