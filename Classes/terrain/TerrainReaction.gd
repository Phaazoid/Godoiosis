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

@export var add_tile_states: Array[Terrain.TileState] = []
@export var remove_tile_states: Array[Terrain.TileState] = []   # omit to NOT consume

@export var popup: String = ""
@export var icon: Texture2D
