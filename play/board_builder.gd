extends RefCounted
# Headless board construction for the Play API (docs/play-api.md, #46 M2).
# Builds the minimal node graph the real managers expect — Grid (+ the game's TileSet),
# Units, OverlayManager (+ its nine overlays), SquadManager, TurnManager — so PlaySession
# drives the REAL SquadManager / TurnManager / PlanResolver / RulesService headless.
# No visuals run; the one overlay call on the order path (redraw_planned_paths) no-ops
# while no planned paths are registered.

const TILESET_PATH := "res://Resources/TestTiles.tres"
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)   # walkable=true, move_cost=1, terrain_type=GRASS in TestTiles.tres
const WATER_ATLAS := Vector2i(5, 6)   # walkable=false (Waterwalk-only), move_cost=1, terrain_type=WATER in TestTiles.tres

# OverlayManager's @onready child overlays — supplied as bare Node2Ds so its _ready
# (which only sets each one's modulate/visibility) runs without error.
const OVERLAY_CHILD_NAMES := [
	"MoveOverlay", "AttackOverlay", "HoverOverlay", "SquadOverlay", "IconOverlay",
	"ArrowIconOverlay", "ProjectedUnitOverlay", "SquadRangeOverlay", "InvalidMoveOverlay",
	"ZoneOverlay",
]

# Build the node graph under `parent` (a node already in the SceneTree). Returns refs by name.
static func build(parent: Node, root_name := "PlayRoot") -> Dictionary:
	var root := Node2D.new()
	root.name = root_name
	parent.add_child(root)

	var grid := TileMapLayer.new()
	grid.name = "Grid"
	grid.tile_set = load(TILESET_PATH)
	root.add_child(grid)

	var units_root := Node2D.new()
	units_root.name = "Units"
	root.add_child(units_root)

	var overlay := OverlayManager.new()
	overlay.name = "OverlayManager"
	for child_name in OVERLAY_CHILD_NAMES:
		var c := Node2D.new()
		c.name = child_name
		overlay.add_child(c)
	root.add_child(overlay)              # enters tree -> @onready (children + ../Grid) resolve

	var squad_manager := SquadManager.new()
	squad_manager.name = "SquadManager"
	root.add_child(squad_manager)

	var turn_manager := TurnManager.new()
	turn_manager.name = "TurnManager"
	root.add_child(turn_manager)

	return {
		"root": root,
		"grid": grid,
		"units_root": units_root,
		"overlay_manager": overlay,
		"squad_manager": squad_manager,
		"turn_manager": turn_manager,
	}

static func paint_rect(grid: TileMapLayer, rect: Rect2i) -> void:
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)

static func paint_cell(grid: TileMapLayer, cell: Vector2i, atlas: Vector2i) -> void:
	grid.set_cell(cell, GRASS_SOURCE, atlas)

# Spawn a unit onto the board in its own solo squad (mirrors game.spawn_unit's contract).
static func spawn(board: Dictionary, data: UnitData, cell: Vector2i) -> Unit:
	var unit := UnitFactory.create_unit(data, board.grid, cell)
	board.units_root.add_child(unit)     # triggers _ready -> unit_instance + movement wired to grid
	board.squad_manager.create_squad(unit)
	return unit

# Load a saved scenario (.tres) onto an already-built board. COROUTINE — await it.
static func load_scenario(board: Dictionary, path: String) -> Array[Unit]:
	var scenario: ScenarioData = load(path)
	if scenario == null:
		push_error("Play: could not load scenario at %s" % path)
		return []
	return await apply_scenario(board, scenario)

# Apply a ScenarioData (terrain + units + squads + turn) to a built board. Mirrors
# ScenarioManager.load_scenario minus the game/visual wiring. Awaits one frame after
# spawning so each unit's _ready runs (unit_instance + inventory) before weapons and
# squad rebuilds read them.
static func apply_scenario(board: Dictionary, scenario: ScenarioData) -> Array[Unit]:
	board.grid.tile_map_data = scenario.tile_data

	var spawned: Array[Unit] = []
	var entry_by_unit := {}            # Unit -> ScenarioUnitEntry
	var leaders := {}                  # squad_id -> Unit
	var members := {}                  # squad_id -> Array[Unit]

	for entry in scenario.unit_entries:
		if entry.unit_data == null:
			push_warning("Play: scenario entry with null unit_data; skipping")
			continue
		var unit := spawn(board, entry.unit_data.duplicate(true), entry.cell)
		spawned.append(unit)
		entry_by_unit[unit] = entry
		if entry.squad_id != -1:
			if entry.is_leader:
				leaders[entry.squad_id] = unit
			elif members.has(entry.squad_id):
				members[entry.squad_id].append(unit)
			else:
				members[entry.squad_id] = [unit]

	# Nodes added this frame haven't run _ready yet; wait one so unit_instance/inventory exist.
	await board.root.get_tree().process_frame

	for unit in spawned:
		var entry: ScenarioUnitEntry = entry_by_unit[unit]
		if entry.equipped_weapon != null:
			# copy_equippable, never duplicate(true) — a WeaponInstance must keep its template
			# shared (#59); mirrors ScenarioManager.load_scenario.
			unit.add_item(entry.equipped_weapon.copy_equippable())

	for squad_id in members.keys():
		var leader: Unit = leaders.get(squad_id)
		if leader == null:
			continue                   # group saved without a leader -> leave them solo
		for member in members[squad_id]:
			board.squad_manager.join_squad(member, leader.squad)

	board.turn_manager.set_active_faction(scenario.active_faction)
	return spawned
