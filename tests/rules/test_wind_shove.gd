# THE WIND CARRIES A SHOVE (#1660): a shove going with the board's wind flies its WindRules.shove tiles
# further, one against it that much shorter, never below none; across it, unchanged. A diagonal wind
# counts for both of its sides. Weight then holds its tiles from the wind-changed length, and the outcome
# says what the wind did (`knockback_wind`), even when it cut the shove to nothing.
#
# Driven through the real resolve on test_shove_weight's fixture. The wind's rules are injected in
# memory (the WindRules cache, restored after), so retuning a file moves nothing here.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const TOUGH := {Stats.Stat.MHP: 60}
const WIND := Wind.Kind.STRONG_WIND

var _no_reactions: Array[ElementalReaction] = []
var _wind_cache: Dictionary


func before_test() -> void:
	_wind_cache = WindRules._rules_by_kind.duplicate()
	_shove_rule(1)


func after_test() -> void:
	WindRules._rules_by_kind = _wind_cache


func _shove_rule(tiles: int) -> void:
	var rules := WindRules.new()
	rules.shove = tiles
	WindRules._rules_by_kind[WIND] = rules


func _setup(knockback: int, a_cell: Vector2i, d_cell: Vector2i) -> Dictionary:
	var sm := H.make_manager(self)
	var a := H.spawn_solo(self, sm, PLAYER, a_cell)
	var d := H.spawn_solo(self, sm, ENEMY, d_cell, TOUGH)
	(a.get_equipped_weapon() as WeaponInstance).template.main_attack.knockback = knockback
	return {"sm": sm, "a": a, "d": d}


# One hit, resolved on the fixture's board with the wind blowing toward `direction` (`kind` CALM for none).
func _resolve(setup: Dictionary, direction: Wind.Direction, kind := WIND) -> ResolvedOutcome:
	var attack := H.stamped_attack(setup.a, setup.d)
	var plan := ResolvedPlan.new()
	var attacks: Array[AttackAction] = [attack]
	plan.attacks = attacks
	var sm: SquadManager = setup.sm
	var board: BoardContext = sm.board_source.call()
	board.wind = kind
	board.wind_direction = direction
	PlanResolver.resolve(plan, _no_reactions, board)
	return attack.resolved


func _tiles_moved(outcome: ResolvedOutcome) -> int:
	return maxi(0, outcome.knockback_path.size() - 1)


# Loads a unit to exactly a band threshold (test_shove_weight's helper).
func _weigh_to(unit: Unit, weight: int) -> void:
	var ballast := Item.new()
	ballast.weight = weight - unit.get_weight()
	assert_int(ballast.weight).override_failure_message(
		"the body alone is already past this threshold, so the case cannot set the band it needs") \
		.is_greater_equal(0)
	assert_bool(unit.add_item(ballast)).is_true()


# --- with, against, across ----------------------------------------------------------------------

func test_a_calm_board_shoves_the_authored_distance() -> void:
	var outcome := _resolve(_setup(2, Vector2i(1, 0), Vector2i(2, 0)), Wind.Direction.EAST, Wind.Kind.CALM)
	assert_int(_tiles_moved(outcome)).is_equal(2)
	assert_int(outcome.knockback_wind).is_equal(0)


func test_a_shove_with_the_wind_goes_further() -> void:
	var outcome := _resolve(_setup(1, Vector2i(1, 0), Vector2i(2, 0)), Wind.Direction.EAST)
	assert_int(_tiles_moved(outcome)).is_equal(2)
	assert_that(outcome.knockback_to).is_equal(Vector2i(4, 0))
	assert_int(outcome.knockback_wind).is_equal(1)


func test_a_shove_against_the_wind_falls_short() -> void:
	var outcome := _resolve(_setup(2, Vector2i(1, 0), Vector2i(2, 0)), Wind.Direction.WEST)
	assert_int(_tiles_moved(outcome)).is_equal(1)
	assert_int(outcome.knockback_wind).is_equal(-1)


func test_a_shove_across_the_wind_keeps_its_length() -> void:
	var outcome := _resolve(_setup(2, Vector2i(1, 0), Vector2i(2, 0)), Wind.Direction.NORTH)
	assert_int(_tiles_moved(outcome)).is_equal(2)
	assert_int(outcome.knockback_wind).is_equal(0)


# A north-east wind leans on both of its sides: a shove east and a shove north each go further.
func test_a_diagonal_wind_carries_a_shove_along_either_of_its_sides() -> void:
	var east := _resolve(_setup(1, Vector2i(1, 0), Vector2i(2, 0)), Wind.Direction.NORTH_EAST)
	assert_int(east.knockback_wind).is_equal(1)
	assert_int(_tiles_moved(east)).is_equal(2)
	var north := _resolve(_setup(1, Vector2i(2, 1), Vector2i(2, 0)), Wind.Direction.NORTH_EAST)
	assert_int(north.knockback_wind).is_equal(1)
	assert_that(north.knockback_to).is_equal(Vector2i(2, -2))


# --- the floor, weight, and what never shoves ---------------------------------------------------

# A wind stronger than the shove cuts it to nothing, never into a pull. The outcome still says why the
# target never moved, and reports only the tiles there were to take.
func test_a_shove_the_wind_cancels_moves_nothing_and_says_so() -> void:
	_shove_rule(3)
	var s := _setup(1, Vector2i(1, 0), Vector2i(2, 0))
	var outcome := _resolve(s, Wind.Direction.WEST)
	assert_bool(outcome.knockback_applied).is_false()
	assert_int(outcome.knockback_held).is_equal(0)
	assert_int(outcome.knockback_wind).is_equal(-1)
	assert_int(_tiles_moved(outcome)).is_equal(0)


func test_weight_holds_its_tiles_from_the_wind_changed_length() -> void:
	var s := _setup(1, Vector2i(1, 0), Vector2i(2, 0))
	_weigh_to(s.d as Unit, Stats.WEIGHT_BAND_1)
	var outcome := _resolve(s, Wind.Direction.EAST)
	assert_int(outcome.knockback_held).is_equal(1)
	assert_int(_tiles_moved(outcome)).override_failure_message(
		"weight read the authored length, not the wind's").is_equal(1)
	assert_int(outcome.knockback_wind).is_equal(1)


func test_a_hit_that_shoves_nothing_gains_no_shove_from_the_wind() -> void:
	var outcome := _resolve(_setup(0, Vector2i(1, 0), Vector2i(2, 0)), Wind.Direction.EAST)
	assert_bool(outcome.knockback_applied).is_false()
	assert_int(outcome.knockback_wind).is_equal(0)
