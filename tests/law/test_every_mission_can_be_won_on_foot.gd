# The check the board lint is structurally BLIND to, and the one The Terraces cost to learn: a
# board can be clean, load every unit, and still be unwinnable because the player cannot WALK to
# what the mission asks for. The lint reads each cell's own declarations; reachability is a
# property of the whole board and only a traversal search can answer it.
#
# It became worth committing when The Ford was authored (2026-09-10). That map's entire question is
# that exactly two crossings exist, so a single tile repainted from shallow to deep water leaves a
# green lint, seven units placed correctly, and a capture zone on the far side of an uncrossable
# river. Terraces failed the same way from the other direction -- terraces numbered a half-level
# apart put every ramp's high side short of the ground above it, and its whole upper half, enemies
# included, was unreachable behind a passing lint.
#
# Deliberately NOT folded into BoardLint. The lint answers per cell for a LIVE board while the dev
# paints and must stay cheap enough to run on every press; this is a flood fill over the whole map
# per mission, which is CI's shape rather than the panel's.
#
# The probe is a plain roster character with no Waterwalk, i.e. the WEAKEST traversal any deployed
# unit can have -- so a pass here is a pass for every unit the player could bring. Asking with a
# waterwalker would answer a question no mission is played under.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const PROBE := "res://Resources/Units/Torv.tres"

const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


# Guards both laws below against passing vacuously if the mission scan ever breaks -- the shape
# test_board_lint's own law block opens with, and for the same reason.
func test_scan_finds_shipped_missions() -> void:
	assert_array(game.scenario_manager.get_missions()).is_not_empty()


func test_every_objective_zone_is_reachable_from_the_deployment_zone() -> void:
	var problems: Array[String] = []
	for path: String in game.scenario_manager.get_missions():
		game.scenario_manager.load_scenario(path)
		await await_idle_frame()
		var start: Array[Vector2i] = _deployment_cells()
		if start.is_empty():
			continue   # nowhere authored to deploy: #736 has nothing to say about this board yet
		var reached := _flood(start)
		if reached.is_empty():
			# NOT a skip: _flood only comes back empty when no cell of the authored deployment
			# zone would take a unit, which is a broken board and not a board with nothing to say.
			problems.append("%s: no cell of the deployment zone will take a unit" % path.get_file())
			continue
		for kind in [ZoneManager.Kind.CAPTURE, ZoneManager.Kind.EXTRACTION]:
			for cell: Vector2i in game.zone_manager.cells_of_kind(kind):
				if not reached.has(cell):
					problems.append("%s: %s cell %s cannot be walked to from the deployment zone"
						% [path.get_file(), ZoneManager.Kind.keys()[kind], cell])
	assert_array(problems).is_empty()


func test_every_enemy_can_be_walked_up_to_from_the_deployment_zone() -> void:
	# A ROUT map's objective has no geometry to probe -- the enemies ARE the objective -- so the
	# question becomes whether each of them can be stood NEXT to. Adjacency rather than the cell
	# itself: an occupied cell is never walkable, and reach beyond 1 is a weapon's business.
	var problems: Array[String] = []
	for path: String in game.scenario_manager.get_missions():
		game.scenario_manager.load_scenario(path)
		await await_idle_frame()
		var start: Array[Vector2i] = _deployment_cells()
		if start.is_empty():
			continue
		var reached := _flood(start)
		if reached.is_empty():
			problems.append("%s: no cell of the deployment zone will take a unit" % path.get_file())
			continue
		for unit: Unit in _hostiles():
			var cell: Vector2i = unit.movement.cell
			var touched := false
			for d: Vector2i in DIRS:
				if reached.has(cell + d):
					touched = true
					break
			if not touched:
				problems.append("%s: %s at %s cannot be walked up to from the deployment zone"
					% [path.get_file(), unit.get_unit_name(), cell])
	assert_array(problems).is_empty()


# --- helpers -------------------------------------------------------------------------------------

func _deployment_cells() -> Array[Vector2i]:
	return game.zone_manager.cells_of_kind(ZoneManager.Kind.DEPLOYMENT)


func _hostiles() -> Array[Unit]:
	var found: Array[Unit] = []
	for unit: Unit in game.units_root.get_children():
		if Team.is_enemy(Team.Faction.PLAYER, unit.get_faction()):
			found.append(unit)
	return found


# Flood fill over RulesService.can_step -- the EDGE rule movement itself asks (traversal AND the
# height step), never the tile's own walkable flag. It was can_traverse until The Quarry (2026-09-11),
# and a mutant that erased both of that board's flank ramps PASSED: can_traverse is per-CELL, so the
# flood walked straight up the cliff. That is the defect class Terraces first shipped -- an upper
# band no ramp reaches -- and this law had been blind to it on every board with a height in it.
# The tile flag and the rule also disagree wherever tile STATE does (a frozen water cell is solid
# ground), and it is the rule that disagrees which the player actually plays under.
#
# Returns {} rather than a partial answer when the probe cannot be placed, so a caller reports
# nothing instead of reporting everything.
func _flood(start: Array[Vector2i]) -> Dictionary:
	var probe: Unit = null
	for cell: Vector2i in start:
		probe = game.spawn_unit(load(PROBE), cell)
		if probe != null:
			break
	if probe == null:
		return {}

	var board: BoardContext = game._board()
	var rect: Rect2i = game.grid.get_used_rect()
	var seen := {}
	var frontier: Array[Vector2i] = []
	for cell: Vector2i in start:
		if RulesService.can_traverse(cell, probe, board):
			seen[cell] = true
			frontier.append(cell)
	while frontier.size() > 0:
		var at: Vector2i = frontier.pop_front()
		for d: Vector2i in DIRS:
			var next: Vector2i = at + d
			if seen.has(next) or not rect.has_point(next):
				continue
			if not RulesService.can_step(at, next, probe, board):
				continue
			seen[next] = true
			frontier.append(next)
	return seen
