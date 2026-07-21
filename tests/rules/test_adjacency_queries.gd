# Adjacency targeting queries (RulesService.adjacent_downed_allies/adjacent_enemies),
# extracted from game.gd so the game and the headless PlaySession share ONE implementation
# (mirrors test_rules_service.gd's parity-guard framing). Both read off the unit's PROJECTED
# destination, not its current cell (Law #2 — "move next to X, then act" sequencing).
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

func _board() -> BoardContext:
	var units: Array[Unit] = []
	for squad in _sm.squads:
		for member in squad.get_members():
			if not units.has(member):
				units.append(member)
	return BoardContext.new(_sm.grid, units, _sm)

# ---- adjacent_downed_allies ----

func test_downed_ally_adjacent_is_included() -> void:
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	ally.lifecycle_state = Unit.LifecycleState.DOWNED

	var result := RulesService.adjacent_downed_allies(unit, _board())

	assert_array(result).contains([ally])

func test_active_ally_is_excluded_from_downed_allies() -> void:
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))   # stays ACTIVE

	var result := RulesService.adjacent_downed_allies(unit, _board())

	assert_array(result).is_empty()

func test_downed_enemy_is_excluded_from_downed_allies() -> void:
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var enemy := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	enemy.lifecycle_state = Unit.LifecycleState.DOWNED

	var result := RulesService.adjacent_downed_allies(unit, _board())

	assert_array(result).is_empty()

func test_diagonal_downed_ally_is_excluded() -> void:
	# Manhattan range 1 is orthogonal only -- a diagonal neighbor is distance 2.
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 1))
	ally.lifecycle_state = Unit.LifecycleState.DOWNED

	var result := RulesService.adjacent_downed_allies(unit, _board())

	assert_array(result).is_empty()

func test_downed_allies_read_off_projected_destination() -> void:
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := H.spawn_solo(self, _sm, PLAYER, Vector2i(5, 0))
	ally.lifecycle_state = Unit.LifecycleState.DOWNED

	# Not adjacent from the current cell -- only becomes adjacent after a queued move.
	assert_array(RulesService.adjacent_downed_allies(unit, _board())).is_empty()

	var move := MoveAction.new()
	move.init(unit, [Vector2i(0, 0), Vector2i(4, 0)], null)
	unit.squad._queue_action(move)

	var result := RulesService.adjacent_downed_allies(unit, _board())
	assert_array(result).contains([ally])

# ---- adjacent_enemies ----

func test_active_enemy_adjacent_is_included() -> void:
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var enemy := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))

	var result := RulesService.adjacent_enemies(unit, _board())

	assert_array(result).contains([enemy])

func test_downed_enemy_is_a_legal_intimidate_target() -> void:
	# Downed enemies stay legal on purpose -- draining a body's Will can be worth a main action.
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var enemy := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	enemy.lifecycle_state = Unit.LifecycleState.DOWNED

	var result := RulesService.adjacent_enemies(unit, _board())

	assert_array(result).contains([enemy])

func test_dead_enemy_is_excluded_from_adjacent_enemies() -> void:
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var enemy := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	enemy.lifecycle_state = Unit.LifecycleState.DEAD

	var result := RulesService.adjacent_enemies(unit, _board())

	assert_array(result).is_empty()

func test_ally_is_excluded_from_adjacent_enemies() -> void:
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))

	var result := RulesService.adjacent_enemies(unit, _board())

	assert_array(result).is_empty()

func test_diagonal_enemy_is_excluded() -> void:
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 1))

	var result := RulesService.adjacent_enemies(unit, _board())

	assert_array(result).is_empty()

func test_adjacent_enemies_read_off_projected_destination() -> void:
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var enemy := H.spawn_solo(self, _sm, ENEMY, Vector2i(5, 0))

	assert_array(RulesService.adjacent_enemies(unit, _board())).is_empty()

	var move := MoveAction.new()
	move.init(unit, [Vector2i(0, 0), Vector2i(4, 0)], null)
	unit.squad._queue_action(move)

	var result := RulesService.adjacent_enemies(unit, _board())
	assert_array(result).contains([enemy])
