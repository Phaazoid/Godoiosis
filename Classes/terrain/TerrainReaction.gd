extends Resource
class_name TerrainReaction

# A data rule for the MAP, parallel to ElementalReaction for units (docs/design/terrain.md +
# elemental-interactions.md "attack the map"). When an attack carrying `incoming_element` lands
# on a cell of `required_kind` (and/or already holding `required_tile_state`), it changes the
# tile's states. Authored as .tres later; injected directly in tests for now.
#
# NONE on either gate = "don't care": required_kind NONE matches any tile; required_tile_state
# NONE needs no pre-existing state (the setup half — e.g. WATER -> WET tile).

@export var incoming_element: Elemental.Element = Elemental.Element.NONE
@export var required_kind: Terrain.Kind = Terrain.Kind.NONE
@export var required_tile_state: Terrain.TileState = Terrain.TileState.NONE

# A state that REFUSES this reaction (#890) -- required_tile_state's negative, and NONE means
# nothing refuses it. The ignition reactions name SCORCHED, so ground whose fuel is spent cannot
# catch again, from a neighbour or from a fireball: one clause, both paths, no second rule about
# what spreading may take. It is also where a firebreak would be spelled if ice ever became one.
@export var forbidden_tile_state: Terrain.TileState = Terrain.TileState.NONE

@export var add_tile_states: Array[Terrain.TileState] = []
@export var remove_tile_states: Array[Terrain.TileState] = []   # omit to NOT consume

# How long each added state lasts, in turn cycles (#890). ElementalReaction.add_state_turns' exact
# grammar applied to the map: ABSENT = no clock = permanent, which is already how COVER and FROZEN
# spell it. There is no sentinel for "forever" because omission is the sentinel.
#
# For fire this dictionary IS the ground's fuel. Grass carries 3; a ground with no ignition
# reaction at all carries nothing, so a fire on stone is consuming nothing and never runs out --
# which is what the authored braziers on Prolog's flagstones have always meant.
@export var add_state_turns: Dictionary[Terrain.TileState, int] = {}

# How FAR fire reaches out of this ground (#891), the twin of the duration above: add_state_turns
# says how long the fire lasts, this says how wide it throws while it burns. False = the four sides;
# true = the corners too, which is the dev's "1.5 tiles per turn" and therefore spelled with
# AttackData.max_and_a_half's word rather than a new one -- GridUtils.cells_within_blended_range is
# the one answer to "sides, or sides and corners", and aiming already asks it.
#
# It is read off the ground that is ALIGHT, never off the ground catching: tall flames throw sparks
# further, so a fire IN tall grass reaches diagonally into whatever is beside it, while a fire in
# ordinary grass does not reach a corner however flammable that corner is. Reach belongs to the
# flame, not to what it is reaching for.
@export var spread_and_a_half: bool = false

@export var popup: String = ""
@export var icon: Texture2D

# The tile gate as ONE predicate (#135 round 2): the resolver's deposit filter and the hover
# card's "what can touch this tile" list read the same clauses, so they can never drift.
func applies_to_tile(kind: Terrain.Kind, held_states: Array[Terrain.TileState]) -> bool:
	if required_kind != Terrain.Kind.NONE and required_kind != kind:
		return false
	if not admits(held_states):
		return false
	return required_tile_state == Terrain.TileState.NONE or held_states.has(required_tile_state)


# The state REFUSAL alone, split out because the spread step asks it separately: the KIND half is
# already settled there (the store holds this cell's fuel reaction, found by kind), so asking the
# whole predicate again would mean handing it a kind it just looked up. One clause, one home --
# applies_to_tile composes it rather than restating it.
func admits(held_states: Array[Terrain.TileState]) -> bool:
	return forbidden_tile_state == Terrain.TileState.NONE \
			or not held_states.has(forbidden_tile_state)
