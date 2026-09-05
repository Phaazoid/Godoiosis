extends RefCounted
class_name BoardContext

# The slice of world the rules read: terrain (grid), occupancy (units), and
# planned moves (squad_manager, for projected positions). game.gd builds this from
# its live nodes; the headless PlaySession (M2) builds it from its own — so
# RulesService runs identically in-game and headless. See docs/play-api.md.

var grid: TileMapLayer
var units: Array[Unit]
var squad_manager: SquadManager
var terrain_states: TerrainStateManager
var zones: ZoneManager
var heights: BoardHeights

# A unit whose death has RESOLVED is not on this board, and the filter lives HERE rather than in
# any one builder because there are three of them -- game.gd's _board(), play/board_builder.gd and
# tests/support/squad_fixtures.gd -- and a rule in one is a rule the other two disagree with, which
# is the two-implementations shape that hid #714 in the first place.
#
# It asks the DOMAIN fact, not the engine's: Unit.die() sets lifecycle DEAD and only then calls
# queue_free(), so between a death and the next frame the node is still a valid child of units_root.
# is_queued_for_deletion() would answer the same thing in a second vocabulary, which the persistence
# seam's three-way `dead` split explicitly warns against growing a fourth of. `present_factions`
# below has excluded the dead by this exact test since it was written; this is that belief applied
# to the list itself rather than re-stated per reader -- and `unit_at_cell` is what proves it was
# needed, since it never asked about lifecycle and so let a corpse go on blocking its own tile.
func _init(grid_layer: TileMapLayer, unit_list: Array[Unit], manager: SquadManager, states: TerrainStateManager = null, zone_manager: ZoneManager = null, board_heights: BoardHeights = null) -> void:
	grid = grid_layer
	units = []
	for unit in unit_list:
		if is_instance_valid(unit) and not unit.is_dead():
			units.append(unit)
	squad_manager = manager
	terrain_states = states
	zones = zone_manager
	heights = board_heights

func unit_at_cell(cell: Vector2i) -> Unit:
	for unit in units:
		if is_instance_valid(unit) and unit.movement.cell == cell:
			return unit
	return null

func is_walkable(cell: Vector2i) -> bool:
	# THE walkability answer for the whole game (#109) — three hand-rolled copies of this used to
	# live in HoverPresenter, game.spawn_unit and play_session, and none of them could see tile
	# STATE, so all three called a FROZEN water tile impassable while movement, pathing and
	# knockback walked across it.
	#
	# The FROZEN short-circuit deliberately runs BEFORE the tile lookup: the headless fixtures
	# carry a bare grid with no TileSet, and ice-over-water is the one thing they need to answer.
	if has_tile_state(cell, Terrain.TileState.FROZEN):
		return true
	# #109's rule (a tile that doesn't declare the flag is NOT walkable, and the guard that stops
	# get_custom_data raising) lives in GridUtils.walkable_of since #552, because the meshlib
	# generator asks the same question of a tileset with no board. The STATE half above is what
	# stays here: it is the half that needs a cell.
	return GridUtils.walkable_of(grid.get_cell_tile_data(cell))

# Which unit ends up here once the plan resolves — the inverse of Unit.get_projected_destination,
# derived from it (#105). Reads THIS board's own unit list, so the rules never resolve a cell
# against a different roster than the one they were handed.
func projected_unit_at_cell(cell: Vector2i) -> Unit:
	return Unit.projected_unit_at(units, cell)
	
# The rules' single read-point for a cell's static kind (#50): reads the tileset's
# "terrain_type" int layer as a Terrain.Kind. A method (not an inline grid read in the
# resolver) so tests can stub it — the headless fixture grid has no TileSet to paint.
func terrain_kind_at(cell: Vector2i) -> Terrain.Kind:
	return GridUtils.get_terrain_kind_at_cell(grid, cell)

# The rules' single read-point for a cell's terrain DEF (#84): a Burrow-dug COVER tile shelters
# whoever stands on it. Sibling of terrain_kind_at, same rationale — the resolver's mitigation
# stage and the inspect panel's DEF readout both come through here, so they can't drift.
func cover_def_at(cell: Vector2i) -> int:
	return Terrain.COVER_DEF if has_tile_state(cell, Terrain.TileState.COVER) else 0

# The rules' read-points for a cell's dynamic tile STATE — the null-safe forms of the store's own
# two accessors, siblings of terrain_kind_at for the same two reasons: a board built without a
# state store reads empty rather than crashing, and a fixture can stub them.
#
# `is_walkable` and `cover_def_at` each carried their own `terrain_states != null` guard before
# #694 wanted a third; one guard, one place (Law #4). Both spellings are here because the callers
# genuinely differ — a caller naming ONE state wants has_tile_state, while a caller asking a
# question OVER the states (Terrain.is_burning, which owns which members count as fire) needs the
# array and must not enumerate FIRE_STATES itself.
func tile_states_at(cell: Vector2i) -> Array[Terrain.TileState]:
	if terrain_states == null:
		return []
	return terrain_states.states_at(cell)

func has_tile_state(cell: Vector2i, state: Terrain.TileState) -> bool:
	if terrain_states == null:
		return false
	return terrain_states.has_state(cell, state)

# Is the prop standing on this cell ALIGHT (#272's prop_lit column)? Sibling of terrain_kind_at,
# and null-safe on the GRID as well as the tile, because a stub board carries no TileMapLayer.
func prop_lit_at(cell: Vector2i) -> bool:
	if grid == null:
		return false
	return GridUtils.prop_lit_of(grid.get_cell_tile_data(cell))

# The rules' read-points for elevation (#257), siblings of terrain_kind_at / cover_def_at and there
# for the same reason: methods rather than inline store reads, so a fixture board can stub them.
#
# A board built WITHOUT a heights store reads perfectly flat — every existing caller, test fixture
# and headless board therefore behaves exactly as it did before elevation existed, which is what
# lets can_step ship without touching a single one of them.
func elevation_at(cell: Vector2i) -> int:
	if heights == null:
		return 0
	return heights.elevation_at(cell)

# The cell's four corner heights — the SHAPE, not a reading of it (#427 slice 3). The rules ask this
# rather than an (elevation, rise, climb) triple now: a corner form is not describable that way, and
# the edge question height_step_ok asks needs the corners themselves. Vector4i.ZERO on a board with
# no heights, which is flat ground at 0 — the same "behaves as it did before elevation existed"
# contract every accessor here keeps.
func corners_at(cell: Vector2i) -> Vector4i:
	if heights == null:
		return Vector4i.ZERO
	return heights.corners_at(cell)

func ramp_rise_at(cell: Vector2i) -> Terrain.RampRise:
	if heights == null:
		return Terrain.RampRise.NONE
	return heights.ramp_rise_at(cell)

# How far this cell climbs (#427 slice 2). Flat on a board with no heights, which is what keeps the
# height rules reading "a flat cell climbs 0" rather than needing a null branch of their own.
func ramp_climb_at(cell: Vector2i) -> int:
	if heights == null:
		return 0
	return heights.ramp_climb_at(cell)

# How tall the PROP standing on this cell reaches above its surface (#660), in the same height units
# elevation_at answers in. The rules' read-point for the tile-authored column, sibling of
# terrain_kind_at and there for the same reason: a fixture board stubs the method rather than
# painting a TileSet it does not have.
#
# A board with no grid reads 0, which is "nothing stands here" -- the same "behaves exactly as it did
# before this existed" contract every accessor above keeps, and what lets every existing sight-trace
# fixture (BoardContext.new(null, ...)) go on answering as it always did.
func prop_rule_height_at(cell: Vector2i) -> int:
	if grid == null:
		return 0
	return GridUtils.prop_rule_height_at_cell(grid, cell)

# Census over this board's units — shared by game.gd and the headless PlaySession so the
# turn cycle's membership/auto-skip reads have ONE implementation.
func present_factions() -> Array[Team.Faction]:
	# Factions with at least one living unit (active OR downed) — downed units keep their
	# faction in the cycle so its downed clocks keep ticking; dead units are excluded.
	var seen: Dictionary = {}
	var result: Array[Team.Faction] = []
	for unit in units:
		if not is_instance_valid(unit) or unit.is_dead():
			continue
		var f := unit.get_faction()
		if not seen.has(f):
			seen[f] = true
			result.append(f)
	return result

func faction_has_active_units(faction: Team.Faction) -> bool:
	for unit in units:
		if is_instance_valid(unit) and unit.get_faction() == faction and unit.is_active():
			return true
	return false

func has_active_units() -> bool:
	for unit in units:
		if is_instance_valid(unit) and unit.is_active():
			return true
	return false
