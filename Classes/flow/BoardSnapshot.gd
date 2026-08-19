extends RefCounted
class_name BoardSnapshot

# The board's CONTENT at one instant: the stores the Tile Brush can write, and nothing else (#391).
#
# ScenarioData is the whole saved battle -- units, whose turn it is, the mission layer, the look,
# the opening shot -- so putting one back rebuilds everything. A snapshot is the BOARD, which is
# what an authoring undo means when it says "put it back": restoring one never moves a unit, never
# rewinds a turn and never touches mission progress.
#
# Dumb data, with ScenarioManager.capture_board/restore_board as its writer and reader -- the same
# split ScenarioData declares in its own header. RefCounted rather than Resource because a snapshot
# is never saved, never loaded and never referenced by a file; it lives as long as the undo stack.
#
# Field names match ScenarioData's deliberately. These ARE those fields, and from_scenario /
# write_into below are the ONE place that correspondence is written down -- before them, "which
# fields are the board" was spelled out separately at every capture and every load.

var tile_data: PackedByteArray       # BoardGrid.tile_map_data -- the whole layer as bytes
var terrain_states: Dictionary = {}  # TerrainStateManager.to_state_dict()
var elevations: Dictionary = {}      # BoardHeights.to_elevation_dict()
var ramp_rises: Dictionary = {}      # BoardHeights.to_ramp_dict()
var zones: Dictionary = {}           # ZoneManager.to_dict()


# Did anything actually move? The undo stack asks before pushing a step, so a drag that repainted
# what was already there costs nothing -- without it the first Ctrl+Z after such a drag would
# appear to do nothing at all.
#
# A CONTENT compare on every field, not a hash: a hash would be cheaper and would silently swallow
# a real edit on a collision, and the asymmetry matters here -- a step wrongly KEPT is one extra
# press, a step wrongly DROPPED is the loss this feature exists to prevent.
func equals(other: BoardSnapshot) -> bool:
	return other != null \
		and tile_data == other.tile_data \
		and terrain_states == other.terrain_states \
		and elevations == other.elevations \
		and ramp_rises == other.ramp_rises \
		and zones == other.zones


# The ScenarioData bridge, both directions in one place: a saved scenario CONTAINS a board, and
# which fields those are is one question. capture_scenario and apply_scenario each used to answer
# it themselves, which is two lists to keep in step every time the board grows a store.
static func from_scenario(scenario: ScenarioData) -> BoardSnapshot:
	var snapshot := BoardSnapshot.new()
	snapshot.tile_data = scenario.tile_data
	snapshot.terrain_states = scenario.terrain_states
	snapshot.elevations = scenario.elevations
	snapshot.ramp_rises = scenario.ramp_rises
	snapshot.zones = scenario.zones
	return snapshot


func write_into(scenario: ScenarioData) -> void:
	scenario.tile_data = tile_data
	scenario.terrain_states = terrain_states
	scenario.elevations = elevations
	scenario.ramp_rises = ramp_rises
	scenario.zones = zones
