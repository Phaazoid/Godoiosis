# Shared fixtures for the Tier-2 node-dependent suites (squad / counter / volley / law).
#
# PRELOADED, not class_name'd:  const H := preload("res://tests/support/squad_fixtures.gd")
# Using preload (instead of a global class_name) means adding this file never
# requires a one-time `--import` pass — gdUnit4 rescans tests/ at run time.
#
# Design notes that make node fixtures tractable (learned from reading the code):
#   * Unit is a scene (Scenes/unit.tscn). It must have `unit_data` set BEFORE it
#     enters the tree, or _ready() push_errors and skips building unit_instance.
#   * Unit._ready() only wires movement to a grid if setup() was called first, so
#     we DON'T call setup() — we set `movement.cell` directly (a plain field).
#     No TileMapLayer / grid node is needed anywhere in these tests.
#   * A pattern-less weapon makes CombatComponent fall back to Manhattan range 1,
#     so counter reach is trivial and grid-free: distance <= 1 can hit, >= 2 cannot.
#   * SquadManager is stood up IN the SceneTree (see make_manager) so the Squad
#     nodes it creates are tree nodes, not orphans — that keeps gdUnit4's orphan
#     monitor clean (orphans = nodes not in the tree, sampled before teardown).
#     The manager's @onready siblings (a Grid + an OverlayManager) are supplied as
#     lightweight reals. No test here calls into overlay/grid; the player-facing
#     queue_action / cancel_* wrappers (which redraw overlays) stay out of scope.
extends RefCounted

const UNIT_SCENE := preload("res://Scenes/unit.tscn")

# OverlayManager's nine @onready child overlays. Supplied as bare Node2Ds so its
# _ready (which only sets each one's modulate) runs without error.
const OVERLAY_CHILD_NAMES := [
	"MoveOverlay", "AttackOverlay", "HoverOverlay", "SquadOverlay", "IconOverlay",
	"ArrowIconOverlay", "ProjectedUnitOverlay", "SquadRangeOverlay", "InvalidMoveOverlay",
]

# Sensible defaults so a bare unit has HP (MHP), can deal damage (STR) and can
# lead a small squad (LDR). Individual tests override only what they care about.
const BASELINE_STATS := {"MHP": 10, "STR": 5, "LDR": 3, "WIL": 5, "SPD": 5}

# Build a UnitData with baseline stats patched by `overrides`.
static func make_unit_data(overrides: Dictionary, faction: Team.Faction) -> UnitData:
	var data := UnitData.new()
	var stats: Dictionary[String, int] = {}
	for key in BASELINE_STATS:
		stats[key] = BASELINE_STATS[key]
	for key in overrides:
		stats[key] = overrides[key]
	data.base_stats = stats
	data.faction = faction
	return data

# A pattern-less weapon: CombatComponent.get_attack_cells_from falls back to
# Manhattan range 1 when attack_pattern is null. Keeps counter geometry simple.
static func make_weapon(power: int = 3) -> WeaponData:
	var weapon := WeaponData.new()
	weapon.power = power
	return weapon

# Instance a real Unit, register it for cleanup, add it to the tree (so _ready
# builds unit_instance and resolves the @onready components), then place it.
# We set equipped_weapon directly: has_equipped_weapon()/get_equipped_weapon()
# read that field, so this is faithful to what the counter path actually checks.
static func spawn_unit(
		suite: GdUnitTestSuite,
		faction: Team.Faction,
		cell: Vector2i,
		overrides: Dictionary = {},
		give_weapon: bool = true,
		weapon_power: int = 3) -> Unit:
	var unit: Unit = suite.auto_free(UNIT_SCENE.instantiate())
	unit.unit_data = make_unit_data(overrides, faction)
	suite.add_child(unit)              # triggers _ready -> unit_instance built
	unit.movement.cell = cell          # plain field; no grid needed
	if give_weapon:
		unit.equipped_weapon = make_weapon(weapon_power)
	return unit

# Spawn a unit already wrapped in its own solo squad (the spawn_unit -> create_squad
# contract from invariant I7).
static func spawn_solo(
		suite: GdUnitTestSuite,
		manager: SquadManager,
		faction: Team.Faction,
		cell: Vector2i,
		overrides: Dictionary = {},
		give_weapon: bool = true,
		weapon_power: int = 3) -> Unit:
	var unit := spawn_unit(suite, faction, cell, overrides, give_weapon, weapon_power)
	manager.create_squad(unit)
	return unit

# Build the minimal in-tree node graph the SquadManager expects and return the
# manager. The whole graph is rooted under a single GameRoot that is auto_free'd
# AND added to the suite's tree, so:
#   * the manager and the Squads it parents are real tree nodes -> not orphans,
#   * queue_free (used by destroy_empty_squad) works,
#   * gdUnit4 frees the entire subtree at teardown via the GameRoot registration.
# Siblings are named to match the manager's @onready paths ($"../OverlayManager",
# $"../Grid"); the OverlayManager also resolves its own children + $"../Grid".
static func make_manager(suite: GdUnitTestSuite) -> SquadManager:
	var root := Node.new()
	root.name = "GameRoot"

	var grid := TileMapLayer.new()
	grid.name = "Grid"
	root.add_child(grid)

	var overlay := OverlayManager.new()
	overlay.name = "OverlayManager"
	for child_name in OVERLAY_CHILD_NAMES:
		var child := Node2D.new()
		child.name = child_name
		overlay.add_child(child)
	root.add_child(overlay)

	var manager := SquadManager.new()
	manager.name = "SquadManager"
	root.add_child(manager)

	suite.auto_free(root)
	suite.add_child(root)   # enters tree -> every @onready resolves cleanly
	return manager
