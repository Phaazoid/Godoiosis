# The ORDER an aim lands in (#1057 part 2, #1054 ruling 19): every tile of the wash carries the step
# the attack reaches it on, which the aim's travel-order flash plays. Asked through Conduction.sweep,
# the one answer to "what does this aim reach", so the timing cannot drift from the tiles it times.
#
#   true AoE           -- every tile step 0
#   swing from you     -- row by row moving away along the facing
#   swing at range     -- ring by ring outward from the impact
#   single-target path -- index along each path, cut at its victim, a revisit carrying two steps
#   the shock current  -- after the blow, one step per hop (ruling 29)
#
# Every attack and board is BUILT here (the content razor), with this folder's path-suite shapes.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")
const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const ORIGIN := Vector2i(0, 0)
const NO_UNITS: Array[Unit] = []


class _WaterBoard extends BoardContext:
	var water: Dictionary
	func _init(unit_list: Array[Unit], water_cells: Array[Vector2i]) -> void:
		super(null, unit_list, null)
		water = {}
		for cell in water_cells:
			water[cell] = true
	func terrain_kind_at(cell: Vector2i) -> Terrain.Kind:
		return Terrain.Kind.WATER if water.has(cell) else Terrain.Kind.GRASS


func _board(units: Array[Unit] = NO_UNITS) -> BoardContext:
	return BoardContext.new(null, units, null, null, null, BoardHeights.new())


func _cells(list: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(list)
	return out


func _sweep(attack: AttackData, target: Vector2i, board: BoardContext, actor: Unit = null) -> Conduction.Sweep:
	return Conduction.sweep(actor, ORIGIN, target, attack, board)


func _steps_of(reach: Conduction.Sweep, cell: Vector2i) -> Array:
	return reach.steps.get(cell, [])


# A painted shape, self-anchored unless a range is given.
func _painted(offsets: Array[Vector2i], max_range := 0, swing := true) -> WeaponAttackData:
	var attack := WeaponAttackData.new()
	P.stamped(attack, max_range, offsets, 1 if max_range > 0 else 0)
	attack.swing = swing
	return attack


func _pathed(paths: Array[Array]) -> WeaponAttackData:
	var attack := WeaponAttackData.new()
	attack.max_range = 0
	attack.attack_shape = P.pathed(paths)
	attack.swing = true
	return attack


# ==============================================================================
#  Area kinds (Reach.travel_steps)
# ==============================================================================

# A cleave lands row by row moving away: the near row first, then the far one.
func test_a_swing_from_you_lands_row_by_row() -> void:
	var cone := _cells([Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-2, -2), Vector2i(-1, -2), Vector2i(0, -2), Vector2i(1, -2), Vector2i(2, -2)])
	var reach := _sweep(_painted(cone), Vector2i(0, -1), _board())
	for cell in cone:
		var row := -cell.y - 1
		assert_array(_steps_of(reach, cell)).override_failure_message(
				"%s should land on step %d" % [cell, row]).contains_exactly([row])


# The row follows the FACING: the same line aimed east lands west to east.
func test_the_rows_turn_with_the_facing() -> void:
	var line := _cells([Vector2i(0, -1), Vector2i(0, -2), Vector2i(0, -3)])
	var reach := _sweep(_painted(line), Vector2i(1, 0), _board())
	assert_array(_steps_of(reach, Vector2i(1, 0))).contains_exactly([0])
	assert_array(_steps_of(reach, Vector2i(2, 0))).contains_exactly([1])
	assert_array(_steps_of(reach, Vector2i(3, 0))).contains_exactly([2])


# A swing placed at range spreads ring by ring from where it lands.
func test_a_swing_at_range_lands_ring_by_ring_from_the_impact() -> void:
	var plus := _cells([Vector2i(0, 0), Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
		Vector2i(0, -2), Vector2i(2, 0)])
	var impact := Vector2i(0, -3)
	var reach := _sweep(_painted(plus, 3), impact, _board())
	for offset in plus:
		var ring := absi(offset.x) + absi(offset.y)
		assert_array(_steps_of(reach, impact + offset)).override_failure_message(
				"%s should land on ring %d" % [impact + offset, ring]).contains_exactly([ring])


# Swing OFF is a true AoE: the whole footprint at once, self-anchored or placed.
func test_a_true_aoe_lands_all_at_once() -> void:
	var line := _cells([Vector2i(0, -1), Vector2i(0, -2), Vector2i(0, -3)])
	var reach := _sweep(_painted(line, 0, false), Vector2i(0, -1), _board())
	assert_int(reach.steps.size()).is_equal(3)
	for cell: Vector2i in reach.steps:
		assert_array(reach.steps[cell]).contains_exactly([0])
	var placed := _sweep(_painted(line, 3, false), Vector2i(0, -3), _board())
	for cell: Vector2i in placed.steps:
		assert_array(placed.steps[cell]).contains_exactly([0])


# ==============================================================================
#  Paths (the gather's cut)
# ==============================================================================

# A path's step is its index, and an out-and-back tile carries BOTH visits.
func test_a_path_steps_along_its_tiles_and_a_revisit_carries_two() -> void:
	var there_and_back := _cells([Vector2i(0, -1), Vector2i(0, -2), Vector2i(0, -3), Vector2i(0, -2)])
	var reach := _sweep(_pathed([there_and_back] as Array[Array]), Vector2i(0, -1), _board())
	assert_array(_steps_of(reach, Vector2i(0, -1))).contains_exactly([0])
	assert_array(_steps_of(reach, Vector2i(0, -2))).contains_exactly_in_any_order([1, 3])
	assert_array(_steps_of(reach, Vector2i(0, -3))).contains_exactly([2])


# The flash stops where the swing does: a tile past the victim was never reached, so it has no step.
func test_nothing_past_the_victim_has_a_step() -> void:
	var attacker: Unit = H.spawn_unit(self, PLAYER, ORIGIN)
	var victim: Unit = H.spawn_unit(self, ENEMY, Vector2i(0, -2))
	var three := _cells([Vector2i(0, -1), Vector2i(0, -2), Vector2i(0, -3)])
	var board := _board([attacker, victim] as Array[Unit])
	var reach := _sweep(_pathed([three] as Array[Array]), Vector2i(0, -1), board, attacker)
	assert_array(_steps_of(reach, Vector2i(0, -2))).contains_exactly([1])
	assert_bool(reach.steps.has(Vector2i(0, -3))).override_failure_message(
			"a tile past the victim was given a step, so the flash runs on past the hit").is_false()


# Several paths travel at once: step 1 of every path lands together.
func test_paths_travel_together() -> void:
	var left := _cells([Vector2i(-1, -1), Vector2i(-1, -2)])
	var right := _cells([Vector2i(1, -1), Vector2i(1, -2)])
	var reach := _sweep(_pathed([left, right] as Array[Array]), Vector2i(0, -1), _board())
	assert_array(_steps_of(reach, Vector2i(-1, -2))).contains_exactly([1])
	assert_array(_steps_of(reach, Vector2i(1, -2))).contains_exactly([1])


# ==============================================================================
#  The current (ruling 29): after the blow, one step per hop
# ==============================================================================

func test_the_current_flashes_after_the_blow_one_hop_at_a_time() -> void:
	var swing := _pathed([_cells([Vector2i(0, -1), Vector2i(0, -2), Vector2i(0, -3)])] as Array[Array])
	swing.elemental_damage_type = Elemental.Element.SHOCK
	var attacker: Unit = H.spawn_unit(self, PLAYER, ORIGIN)
	(attacker.get_equipped_weapon() as WeaponInstance).template.main_attack = swing
	var victim: Unit = H.spawn_unit(self, ENEMY, Vector2i(0, -2))
	var units: Array[Unit] = [attacker, victim]
	# The swing crosses water on its first tile; the lake runs two cells off to the side.
	var board := _WaterBoard.new(units, _cells([Vector2i(0, -1), Vector2i(1, -1), Vector2i(2, -1)]))
	var reach := Conduction.sweep(attacker, ORIGIN, Vector2i(0, -1), swing, board)
	var last := 1   # the victim's step: the swing's own last
	assert_array(_steps_of(reach, Vector2i(0, -1))).contains_exactly([0])   # a struck tile keeps its own
	assert_array(_steps_of(reach, Vector2i(1, -1))).contains_exactly([last + 1])
	assert_array(_steps_of(reach, Vector2i(2, -1))).contains_exactly([last + 2])
