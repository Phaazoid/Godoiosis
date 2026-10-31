extends RefCounted
class_name BoardSnapshot

# The board's CONTENT at one instant: the stores the Tile Brush can write, and nothing else (#391).
#
# ScenarioData is the whole saved battle -- units, whose turn it is, the mission layer, the look,
# the opening shot -- so putting one back rebuilds everything. A snapshot is the BOARD, which is
# what an authoring undo means when it says "put it back": restoring one never moves a unit, never
# rewinds a turn and never touches mission progress.
#
# Dumb data, with ScenarioManager.capture_board/restore_board as its writer and reader (the headless
# BoardBuilder restores through the same restore_into, #1365) -- the same
# split ScenarioData declares in its own header. RefCounted rather than Resource because a snapshot
# is never saved, never loaded and never referenced by a file; it lives as long as the undo stack.
#
# Field names match ScenarioData's deliberately. These ARE those fields, and from_scenario /
# write_into below are the ONE place that correspondence is written down -- before them, "which
# fields are the board" was spelled out separately at every capture and every load.
#
# A snapshot is also the board AS AUTHORED (#1507): the undo history keeps one beside each live step,
# moved by an authoring edit's own changes (edited, below) and never by play, and an authored save
# writes it. A new store needs nothing for that unless play writes it, when it joins PLAY_WRITTEN.

# The fields PLAY writes (#1507): a pass's landings and the round tick move tile states, their clocks
# and authored starts, and gas, and nothing else on the board. Each is keyed by cell, which is what
# lets an edit be told apart from play cell by cell.
const PLAY_WRITTEN: Array[StringName] = [&"terrain_states", &"terrain_state_turns",
		&"terrain_state_starts", &"gas"]
# The three of them that are tile states, which Clear Tile States wipes whole.
const TILE_STATE_FIELDS: Array[StringName] = [&"terrain_states", &"terrain_state_turns",
		&"terrain_state_starts"]

var tile_data: PackedByteArray       # BoardGrid.tile_map_data -- the whole layer as bytes
var terrain_states: Dictionary = {}  # TerrainStateManager.to_state_dict()
# The live clocks (#890). Its own field rather than a richer terrain_states, because that one is
# authored by hand in a mission .tres and read by the brush -- a countdown is a battle fact, not
# something an author sets. An empty one is the honest reading of a board that predates this.
var terrain_state_turns: Dictionary = {}  # TerrainStateManager.to_turns_dict()
# The AUTHORED starts (#1484): what an author chose a clock to begin at. Content, unlike the live
# clocks above, so an authoring save keeps this and drops those (#1483).
var terrain_state_starts: Dictionary = {}  # TerrainStateManager.to_starts_dict()
var corner_heights: Dictionary = {}  # BoardHeights.to_corner_dict()
var gas: Dictionary = {}             # GasField.to_dict() (#508)
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
		and terrain_state_turns == other.terrain_state_turns \
		and terrain_state_starts == other.terrain_state_starts \
		and corner_heights == other.corner_heights \
		and gas == other.gas \
		and zones == other.zones


# This board AS AUTHORED after one authoring edit took the LIVE board from `before` to `after` (#1507).
# What play did between edits sits in both, so it never reaches the result:
#   - a field play never writes is the edit's whole result, copied by reflection so a new store rides;
#   - a PLAY_WRITTEN field takes only what the edit changed, cell by cell (_merged_cell);
#   - a field in `whole` is the edit's whole result too: a wipe means "this store is now what you
#     see", which a per-cell change cannot say about a cell play had already emptied;
#   - a cell with no ground keeps nothing (#245), or erasing the ground under a fire play had put out
#     would leave that fire in the file.
func edited(before: BoardSnapshot, after: BoardSnapshot, has_ground: Callable,
		whole: Array[StringName] = []) -> BoardSnapshot:
	var result := BoardSnapshot.new()
	for property: Dictionary in get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			result.set(property.name, after.get(property.name))
	for field: StringName in PLAY_WRITTEN:
		if not whole.has(field):
			result.set(field, _merged(field, get(field), before.get(field), after.get(field), has_ground))
	return result


static func _merged(field: StringName, authored: Dictionary, before: Dictionary, after: Dictionary,
		has_ground: Callable) -> Dictionary:
	var result := authored.duplicate(true)
	var cells := before.duplicate()
	cells.merge(after)
	for cell: Vector2i in cells:
		var was: Variant = before.get(cell)
		var now: Variant = after.get(cell)
		if was == now:
			continue
		var merged: Variant = _merged_cell(field, result.get(cell), was, now)
		if _holds_nothing(merged):
			result.erase(cell)
		else:
			result[cell] = merged
	if has_ground.is_valid():
		for cell: Vector2i in result.keys():
			if not has_ground.call(cell):
				result.erase(cell)
	return result


# One cell's authored value once an edit took it from `was` to `now`: the edit's own change, applied.
# A state list gains what the edit added and loses what it removed, in fold()'s remove-then-add order.
# Gas, one int a cell, copies the four-bit nibble of each kind the edit changed. A clock dict copies
# the entries the edit changed, and so does any later field until it names a rule of its own.
static func _merged_cell(field: StringName, authored: Variant, was: Variant, now: Variant) -> Variant:
	match field:
		&"terrain_states":
			var had: Array = was if was != null else []
			var has: Array = now if now != null else []
			var out: Array
			if authored != null:
				out = (authored as Array).duplicate()
			else:
				out = has.duplicate()   # for the live list's element type, so the cell saves as a painted one
				out.clear()
			for state in had:
				if not has.has(state):
					out.erase(state)
			for state in has:
				if not had.has(state) and not out.has(state):
					out.append(state)
			return out
		&"gas":
			var had: int = was if was != null else 0
			var has: int = now if now != null else 0
			var out: int = authored if authored != null else 0
			for kind: Gas.Kind in Gas.Kind.values():
				var mask := Gas.NIBBLE << (int(kind) * Gas.BITS)
				if (had & mask) != (has & mask):
					out = (out & ~mask) | (has & mask)
			return out
	var had: Dictionary = was if was != null else {}
	var has: Dictionary = now if now != null else {}
	var out: Dictionary = (authored as Dictionary).duplicate() if authored != null else {}
	for key: Variant in had:
		if not has.has(key):
			out.erase(key)
	for key: Variant in has:
		if not had.has(key) or had[key] != has[key]:
			out[key] = has[key]
	return out


static func _holds_nothing(value: Variant) -> bool:
	if value is Array or value is Dictionary:
		return value.is_empty()
	return value == null or value is int and value == 0


# How many cells' tile states or gas differ between this board and `other`: what play had moved that an
# authored save left out (#1507). Clocks are not counted, an authored save writing none (#1483). A
# state list is compared as a set: the live store keeps arrival order, so a state play took and gave
# back sits elsewhere in the list and is still not a change.
func cells_moved_from(other: BoardSnapshot) -> int:
	var moved: Dictionary[Vector2i, bool] = {}
	for field: StringName in [&"terrain_states", &"gas"]:
		var mine: Dictionary = get(field)
		var theirs: Dictionary = other.get(field)
		for cell: Vector2i in mine:
			if not _holds_the_same(mine[cell], theirs.get(cell)):
				moved[cell] = true
		for cell: Vector2i in theirs:
			if not mine.has(cell):
				moved[cell] = true
	return moved.size()


static func _holds_the_same(mine: Variant, theirs: Variant) -> bool:
	if mine is Array and theirs is Array:
		return mine.size() == theirs.size() and mine.all(func(state: Variant) -> bool: return theirs.has(state))
	return mine == theirs


# The ScenarioData bridge, both directions in one place: a saved scenario CONTAINS a board, and
# which fields those are is one question. capture_scenario and apply_scenario each used to answer
# it themselves, which is two lists to keep in step every time the board grows a store.
static func from_scenario(scenario: ScenarioData) -> BoardSnapshot:
	if scenario.predates_corner_heights():
		push_error("BoardSnapshot: '%s' predates #427's corner heights and would load FLAT — re-author it"
				% scenario.scenario_name)
	var snapshot := BoardSnapshot.new()
	snapshot.tile_data = scenario.tile_data
	snapshot.terrain_states = scenario.terrain_states
	snapshot.terrain_state_turns = scenario.terrain_state_turns
	snapshot.terrain_state_starts = scenario.terrain_state_starts
	snapshot.corner_heights = scenario.corner_heights
	snapshot.gas = scenario.gas
	snapshot.zones = scenario.zones
	return snapshot


# Put this board back into the stores that hold one: the ONE store list both loaders write through
# (#1365). ScenarioManager.restore_board adds its overlay redraws on top; the headless BoardBuilder has
# none to add, and used to hand-copy this list -- the second copy a new store would be missed by.
func restore_into(grid: BoardGrid, states: TerrainStateManager, heights: BoardHeights, gas_store: GasField,
		zone_store: ZoneManager) -> void:
	grid.restore(tile_data)
	states.load_state_dict(terrain_states, terrain_state_turns, terrain_state_starts)
	heights.load_corner_dict(corner_heights)
	gas_store.load_dict(gas)
	zone_store.load_dict(zones)


func write_into(scenario: ScenarioData) -> void:
	scenario.tile_data = tile_data
	scenario.terrain_states = terrain_states
	scenario.terrain_state_turns = terrain_state_turns
	scenario.terrain_state_starts = terrain_state_starts
	scenario.corner_heights = corner_heights
	scenario.gas = gas
	scenario.zones = zones
