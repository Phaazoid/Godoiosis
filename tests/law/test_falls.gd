# Falls, shoves and tumbles (#259; canon docs/design/verticality.md -> Falls). The shove is
# AIRBORNE (dev, 2026-08-20): it flies its knockback distance at the starting elevation and the
# drop resolves where the travel ends -- so an ally can be blown OVER a hole to safety, a rise
# braces the flight, and a landing on a slope tumbles down it. Boards are hand-painted (never
# authored content); the two canon tumble examples are reproduced verbatim.
#
# Heights are in UNITS since #427 -- one level is 2 -- so every board below counts in twos. What a
# fall COSTS is still per whole level: FallRules.damage_for takes units and divides, and
# outcome.fall_levels reports levels, which is why those two numbers differ by a factor here.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

const HOLE_TILE := Vector2i(18, 2)   # the authored VOID tile ("hole") in TestTiles
# #116's two water tiles. ONE Terrain.Kind between them -- deep is the one that declares no
# `walkable` flag, which is exactly what "too deep to stand in" means, so every rule below asks
# RulesService.drowns_in rather than a second enum member.
const DEEP_WATER := Vector2i(5, 6)
const SHALLOW_WATER := Vector2i(6, 6)

const F := preload("res://tests/support/job_fixtures.gd")

var _no_reactions: Array[ElementalReaction] = []
var _scout: JobData
var _scout_snap: Dictionary


# Waterwalk has to come from somewhere and the fixtures carry no kit, so Scout's pool is forced to
# just WATERWALK for the duration -- test_movement_cost.gd's arrangement, for its reason: this stays
# correct whatever Scout's real authored kit becomes.
func before_test() -> void:
	_scout = JobCatalog.get_job("scout")
	_scout_snap = F.snapshot(_scout)
	var ability := AbilityData.new()
	ability.id = Abilities.Id.WATERWALK
	_scout.ability_pool = [ability]


func after_test() -> void:
	F.restore(_scout, _scout_snap)


# Shover at `a_cell` with a knockback-N main; victim at `d_cell`. The board's heights arrive
# painted; VOID cells are painted onto the fixture grid by the case itself.
func _setup(heights: BoardHeights, knockback: int, a_cell: Vector2i, d_cell: Vector2i) -> Dictionary:
	var sm := H.make_manager(self, heights)
	var a := H.spawn_solo(self, sm, PLAYER, a_cell)
	var d := H.spawn_solo(self, sm, ENEMY, d_cell)
	(a.get_equipped_weapon() as WeaponInstance).template.main_attack.knockback = knockback
	return {"sm": sm, "a": a, "d": d, "grid": sm.get_node("../Grid") as TileMapLayer}


func _resolve(setup: Dictionary) -> ResolvedOutcome:
	var attack := H.stamped_attack(setup.a, setup.d)
	var plan := ResolvedPlan.new()
	var attacks: Array[AttackAction] = [attack]
	plan.attacks = attacks
	var sm: SquadManager = setup.sm
	PlanResolver.resolve(plan, _no_reactions, sm.board_source.call())
	return attack.resolved


func _path_of(outcome: ResolvedOutcome) -> Array[Vector2i]:
	return outcome.knockback_path


# --- The brace: you cannot be pushed uphill --------------------------------------------------

func test_a_shove_toward_higher_ground_stops_dead() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(3, 0), 2)
	var s := _setup(heights, 2, Vector2i(1, 0), Vector2i(2, 0))
	assert_bool(_resolve(s).knockback_applied).is_false()


func test_the_brace_halts_a_flight_mid_way() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(4, 0), 2)
	var s := _setup(heights, 2, Vector2i(1, 0), Vector2i(2, 0))
	var outcome := _resolve(s)
	assert_bool(outcome.knockback_to == Vector2i(3, 0)).is_true()
	assert_int(outcome.fall_damage).is_equal(0)


# --- The airborne flight over voids (the dev's own sentence) ---------------------------------

func test_you_can_blow_an_ally_over_a_hole_to_safety() -> void:
	var s := _setup(BoardHeights.new(), 2, Vector2i(1, 0), Vector2i(2, 0))
	(s.grid as TileMapLayer).set_cell(Vector2i(3, 0), 0, HOLE_TILE)
	var outcome := _resolve(s)
	assert_bool(outcome.removed).is_false()
	assert_bool(outcome.knockback_to == Vector2i(4, 0)).is_true()
	var expected: Array[Vector2i] = [Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]
	assert_that(_path_of(outcome)).is_equal(expected)


func test_a_flight_halted_over_the_hole_drops_in() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(4, 0), 2)   # the brace one past the hole
	var s := _setup(heights, 2, Vector2i(1, 0), Vector2i(2, 0))
	(s.grid as TileMapLayer).set_cell(Vector2i(3, 0), 0, HOLE_TILE)
	var outcome := _resolve(s)
	assert_bool(outcome.removed).is_true()
	assert_that(outcome.lethality).is_equal(ResolvedOutcome.Lethality.KILLED)


func test_a_shove_ending_on_the_hole_removes() -> void:
	var s := _setup(BoardHeights.new(), 1, Vector2i(1, 0), Vector2i(2, 0))
	(s.grid as TileMapLayer).set_cell(Vector2i(3, 0), 0, HOLE_TILE)
	var outcome := _resolve(s)
	assert_bool(outcome.removed).is_true()
	assert_that(outcome.lethality).is_equal(ResolvedOutcome.Lethality.KILLED)


# --- Drops: fall damage at the landing, DEF-blind, rung-moving -------------------------------

func test_a_drop_at_the_landing_deals_scaled_fall_damage() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 4)
	heights.set_cell(Vector2i(2, 0), 4)   # victim starts on the terrace; (3,0) is ground level
	var s := _setup(heights, 1, Vector2i(1, 0), Vector2i(2, 0))
	var flat := _setup(BoardHeights.new(), 1, Vector2i(1, 0), Vector2i(2, 0))
	var outcome := _resolve(s)
	var control := _resolve(flat)
	assert_int(outcome.fall_damage).is_equal(FallRules.damage_for(4, s.d))
	assert_int(outcome.damage).is_equal(control.damage + outcome.fall_damage)
	assert_bool(outcome.knockback_to == Vector2i(3, 0)).is_true()


func test_a_drop_can_change_the_rung() -> void:
	# Derive the hit's own damage from a probe (never assume the fixture's number), then give both
	# victims exactly one more HP than it: the flat twin survives, the dropped one does not.
	var hit := _resolve(_setup(BoardHeights.new(), 1, Vector2i(1, 0), Vector2i(2, 0))).damage
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 4)
	heights.set_cell(Vector2i(2, 0), 4)
	var s := _setup(heights, 1, Vector2i(1, 0), Vector2i(2, 0))
	var flat := _setup(BoardHeights.new(), 1, Vector2i(1, 0), Vector2i(2, 0))
	(s.d as Unit).set_current_hp(hit + 1)
	(flat.d as Unit).set_current_hp(hit + 1)
	assert_that(_resolve(flat).lethality).is_equal(ResolvedOutcome.Lethality.NONE)
	assert_bool(_resolve(s).lethality != ResolvedOutcome.Lethality.NONE).is_true()   # the fall tips it


func test_the_weight_hook_raises_fall_damage() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 4)
	heights.set_cell(Vector2i(2, 0), 4)
	var s := _setup(heights, 1, Vector2i(1, 0), Vector2i(2, 0))
	var ballast := H.make_weapon()
	ballast.weight = 2 * FallRules.WEIGHT_PER_BONUS_DAMAGE
	(s.d as Unit).add_item(ballast)
	# The scaling property, never the numbers: carried mass raises the same drop's cost, and the
	# resolver reads the loaded unit. Inert at weight 0 -- the #120 interlock's fall-damage wire.
	var laden := _resolve(s).fall_damage
	assert_int(laden).is_equal(FallRules.damage_for(4, s.d))
	assert_bool(laden > FallRules.damage_for(4, null)).is_true()


# A HALF level is free (#427 ruling, dev 2026-08-23: "no fall damage for a half level fall") --
# newly expressible, so newly pinnable. The drop is real and the landing still happens.
func test_a_half_level_drop_costs_nothing() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 1)
	heights.set_cell(Vector2i(2, 0), 1)   # a half level above ground; (3,0) is 0
	var s := _setup(heights, 1, Vector2i(1, 0), Vector2i(2, 0))
	var outcome := _resolve(s)
	assert_bool(outcome.knockback_to == Vector2i(3, 0)).is_true()
	assert_int(outcome.fall_damage).is_equal(0)
	assert_int(outcome.fall_levels).is_equal(0)


# --- Tumbles: the two canon examples, verbatim -----------------------------------------------

# F3 R2 R1 R0 F0 -- one unbroken flight: tumbles to F0, no fall damage anywhere on a slope.
func test_canon_example_one_tumbles_the_whole_flight() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 6)                            # the shover stands level too
	heights.set_cell(Vector2i(2, 0), 6)                            # F3
	heights.set_cell(Vector2i(3, 0), 4, Terrain.RampRise.WEST)     # R2 (rises back toward F3)
	heights.set_cell(Vector2i(4, 0), 2, Terrain.RampRise.WEST)     # R1
	heights.set_cell(Vector2i(5, 0), 0, Terrain.RampRise.WEST)     # R0
	var s := _setup(heights, 1, Vector2i(1, 0), Vector2i(2, 0))    # (6,0) is F0
	var outcome := _resolve(s)
	assert_bool(outcome.knockback_to == Vector2i(6, 0)).is_true()
	assert_int(outcome.fall_damage).is_equal(0)
	var expected: Array[Vector2i] = [Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0)]
	assert_that(_path_of(outcome)).is_equal(expected)


# The same shape at half the pitch (#427 slice 2): a chain of GENTLE ramps, each dropping one unit.
# The tumble's continuation asks the next ramp's own climb now, so a chain that used to be spelled
# as "one level down" has to flow identically at half a level -- and the flight has to slide onto
# the first one for free, which only holds if the no-fall test reads that ramp's climb too.
func test_a_chain_of_gentle_ramps_tumbles_exactly_like_a_steep_one() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 3)                               # the shover stands level
	heights.set_cell(Vector2i(2, 0), 3)                               # the shelf
	heights.set_cell(Vector2i(3, 0), 2, Terrain.RampRise.WEST, 1)     # high edge meets the shelf
	heights.set_cell(Vector2i(4, 0), 1, Terrain.RampRise.WEST, 1)
	heights.set_cell(Vector2i(5, 0), 0, Terrain.RampRise.WEST, 1)
	var s := _setup(heights, 1, Vector2i(1, 0), Vector2i(2, 0))       # (6,0) is flat ground
	var outcome := _resolve(s)
	assert_bool(outcome.knockback_to == Vector2i(6, 0)) \
		.override_failure_message("the gentle chain stopped at %s" % outcome.knockback_to).is_true()
	assert_int(outcome.fall_damage).override_failure_message(
			"a slide down gentle slopes charged fall damage").is_equal(0)
	var expected: Array[Vector2i] = [Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0),
			Vector2i(6, 0)]
	assert_that(_path_of(outcome)).is_equal(expected)


# The refusal that keeps the case above honest: a flight arriving a FULL level over a gentle ramp's
# high edge is a drop, not a slide-on. Reading the constant instead of the ramp's climb makes this
# free.
func test_a_flight_landing_above_a_gentle_ramps_shoulder_still_falls() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), Terrain.UNITS_PER_LEVEL)
	heights.set_cell(Vector2i(2, 0), Terrain.UNITS_PER_LEVEL)         # the shelf, a level up
	heights.set_cell(Vector2i(3, 0), 0, Terrain.RampRise.WEST, 1)     # its shoulder is only 1 up
	var s := _setup(heights, 1, Vector2i(1, 0), Vector2i(2, 0))
	var outcome := _resolve(s)
	assert_int(outcome.fall_damage).override_failure_message(
			"the flight slid onto a shoulder it was above").is_greater(0)


# F3 R2 F2 ... -- the landing at F2 catches it: ends on F2, never reaches R1.
func test_canon_example_two_is_caught_by_the_landing() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 6)
	heights.set_cell(Vector2i(2, 0), 6)                            # F3
	heights.set_cell(Vector2i(3, 0), 4, Terrain.RampRise.WEST)     # R2
	heights.set_cell(Vector2i(4, 0), 4)                            # F2 -- the catch
	heights.set_cell(Vector2i(5, 0), 2, Terrain.RampRise.WEST)     # R1, never reached
	var s := _setup(heights, 1, Vector2i(1, 0), Vector2i(2, 0))
	var outcome := _resolve(s)
	assert_bool(outcome.knockback_to == Vector2i(4, 0)).is_true()
	assert_int(outcome.fall_damage).is_equal(0)


# The airborne model's distinguishing case: a STRONGER shove on example two's board flies OVER
# the ramp and drops onto F2 -- one level of genuine fall, where the knockback-1 tumble was free.
func test_a_longer_flight_overflies_the_ramp_and_falls() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 6)
	heights.set_cell(Vector2i(2, 0), 6)
	heights.set_cell(Vector2i(3, 0), 4, Terrain.RampRise.WEST)
	heights.set_cell(Vector2i(4, 0), 4)
	var s := _setup(heights, 2, Vector2i(1, 0), Vector2i(2, 0))
	var outcome := _resolve(s)
	assert_bool(outcome.knockback_to == Vector2i(4, 0)).is_true()
	assert_int(outcome.fall_damage).is_equal(FallRules.damage_for(2, s.d))
	# No tumble here, so flight runs the whole path: the drop happens on its last cell.
	assert_int(outcome.knockback_landing_index).is_equal(outcome.knockback_path.size() - 1)


# "When a unit lands, if they land on a slope, they tumble down that too" (dev) -- a sideways
# ramp bends the path once, down the slope's OWN downhill.
func test_a_perpendicular_ramp_landing_bends_the_tumble() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(3, 0), 0, Terrain.RampRise.NORTH)    # slopes up to the north
	var s := _setup(heights, 1, Vector2i(1, 0), Vector2i(2, 0))
	var outcome := _resolve(s)
	assert_bool(outcome.knockback_to == Vector2i(3, 1)).is_true()  # slid south, downhill
	var expected: Array[Vector2i] = [Vector2i(2, 0), Vector2i(3, 0), Vector2i(3, 1)]
	assert_that(_path_of(outcome)).is_equal(expected)
	# The flight/tumble split (#259 rework): flight ends on the ramp at index 1, the bend after it
	# is tumble -- what the shove animation and the 3D trail's air/ground fork read.
	assert_int(outcome.knockback_landing_index).is_equal(1)


# Tumble-then-plummet (the deferred later addition): the tumble no longer stops at a lip -- it
# falls the drop, pays fall damage for it, and keeps whatever descent waits below.
func test_the_tumble_plummets_past_a_lip() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 6)
	heights.set_cell(Vector2i(2, 0), 6)
	heights.set_cell(Vector2i(3, 0), 4, Terrain.RampRise.WEST)     # R2, then a sheer 2-drop to (4,0)
	var s := _setup(heights, 1, Vector2i(1, 0), Vector2i(2, 0))
	var outcome := _resolve(s)
	assert_bool(outcome.knockback_to == Vector2i(4, 0)).is_true()  # falls the drop, not stopped
	assert_int(outcome.fall_damage).is_equal(FallRules.damage_for(4, s.d))
	assert_int(outcome.fall_levels).is_equal(2)


# A plummet that lands on another ramp keeps tumbling down that one too (dev: "continue whatever
# descent awaits them").
func test_a_plummet_landing_on_a_ramp_tumbles_again() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 6)
	heights.set_cell(Vector2i(2, 0), 6)
	heights.set_cell(Vector2i(3, 0), 4, Terrain.RampRise.WEST)     # R2, then a 2-drop
	heights.set_cell(Vector2i(4, 0), 0, Terrain.RampRise.WEST)     # lands on R0, tumbles again
	var s := _setup(heights, 1, Vector2i(1, 0), Vector2i(2, 0))    # (5,0) is F0, the catch
	var outcome := _resolve(s)
	assert_bool(outcome.knockback_to == Vector2i(5, 0)).is_true()
	assert_int(outcome.fall_levels).is_equal(2)
	var expected: Array[Vector2i] = [Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0)]
	assert_that(_path_of(outcome)).is_equal(expected)


func test_the_tumble_stops_at_an_occupied_cell() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 6)
	heights.set_cell(Vector2i(2, 0), 6)
	heights.set_cell(Vector2i(3, 0), 4, Terrain.RampRise.WEST)
	var s := _setup(heights, 1, Vector2i(1, 0), Vector2i(2, 0))
	H.spawn_solo(self, s.sm, ENEMY, Vector2i(4, 0))                # a body on the catch cell
	var outcome := _resolve(s)
	assert_bool(outcome.knockback_to == Vector2i(3, 0)).is_true()


# --- The two rules #259 deliberately does NOT change -----------------------------------------

# --- Water (#116) -----------------------------------------------------------------------------
#
# The shoreline stop is GONE, and its replacement is the ticket: water CATCHES a shove instead of
# bracing it. "Water stops the shove" is still true -- one cell later, in the drink.
#
# What the drown COSTS is asserted as a property, never as a number: the water takes whatever the
# blow left, so the fixture's own HP is the expectation and nothing here pins a tuning value. The
# rung is read through lifecycle_for so a fixture whose Will cannot pay (a MAIM) still passes -- a
# maim IS a down, and what this ticket rules on is that the unit goes DOWN rather than which flavour.

func _lifecycle(outcome: ResolvedOutcome) -> Unit.LifecycleState:
	return LethalityRules.lifecycle_for(outcome.lethality)


func test_a_shove_into_deep_water_takes_everything_the_blow_left() -> void:
	var s := _setup(BoardHeights.new(), 1, Vector2i(1, 0), Vector2i(2, 0))
	(s.grid as TileMapLayer).set_cell(Vector2i(3, 0), 0, DEEP_WATER)
	var outcome := _resolve(s)
	assert_bool(outcome.knockback_to == Vector2i(3, 0)) \
		.override_failure_message("the shove should end IN the water, not dry on the bank").is_true()
	assert_that(_lifecycle(outcome)).is_equal(Unit.LifecycleState.DOWNED)
	# "Losing all one's health", stated as the arithmetic rather than as a number: total damage IS
	# what the unit had, so no tuning value is pinned here.
	assert_int(outcome.damage).is_equal(outcome.hp_before)
	assert_int(outcome.target_hp_after).is_equal(0)
	assert_int(outcome.drown_damage).is_greater(0)


func test_the_flight_stops_in_the_FIRST_water_cell() -> void:
	var s := _setup(BoardHeights.new(), 3, Vector2i(1, 0), Vector2i(2, 0))
	for x in [3, 4, 5]:
		(s.grid as TileMapLayer).set_cell(Vector2i(x, 0), 0, DEEP_WATER)
	var outcome := _resolve(s)
	# NOT the void's fly-over: a hole cannot catch you and a lake can, and stopping at the water's
	# EDGE is what keeps the body inside a rescuer's reach.
	assert_bool(outcome.knockback_to == Vector2i(3, 0)).is_true()
	var expected: Array[Vector2i] = [Vector2i(2, 0), Vector2i(3, 0)]
	assert_that(_path_of(outcome)).is_equal(expected)


func test_a_shove_into_shallow_water_is_only_a_shove() -> void:
	var s := _setup(BoardHeights.new(), 1, Vector2i(1, 0), Vector2i(2, 0))
	(s.grid as TileMapLayer).set_cell(Vector2i(3, 0), 0, SHALLOW_WATER)
	var outcome := _resolve(s)
	assert_bool(outcome.knockback_to == Vector2i(3, 0)).is_true()
	assert_int(outcome.drown_damage).is_equal(0)
	assert_that(_lifecycle(outcome)).is_equal(Unit.LifecycleState.ACTIVE)


func test_a_waterwalker_is_shoved_onto_the_water_and_stands() -> void:
	var s := _setup(BoardHeights.new(), 1, Vector2i(1, 0), Vector2i(2, 0))
	(s.d as Unit).unit_instance.add_job("scout")
	(s.grid as TileMapLayer).set_cell(Vector2i(3, 0), 0, DEEP_WATER)
	var outcome := _resolve(s)
	assert_bool(outcome.knockback_to == Vector2i(3, 0)) \
		.override_failure_message("water it can stand on must not brace the shove").is_true()
	assert_int(outcome.drown_damage).is_equal(0)
	assert_that(_lifecycle(outcome)).is_equal(Unit.LifecycleState.ACTIVE)


func test_frozen_water_catches_the_shove_without_drowning_anyone() -> void:
	var s := _setup(BoardHeights.new(), 1, Vector2i(1, 0), Vector2i(2, 0))
	var grid := s.grid as TileMapLayer
	grid.set_cell(Vector2i(3, 0), 0, DEEP_WATER)
	# The shared fixture board carries no state store, so this case supplies one -- the ONLY thing
	# it changes about the board, so the ice is genuinely what the assertions below are reading.
	var sm: SquadManager = s.sm
	var states: TerrainStateManager = auto_free(TerrainStateManager.new())
	var freeze := ResolvedCellEffect.new()
	freeze.cell = Vector2i(3, 0)
	freeze.states_added.append(Terrain.TileState.FROZEN)
	states.apply(freeze)
	sm.board_source = func() -> BoardContext:
		return BoardContext.new(grid, sm._all_units(), sm, states, null, BoardHeights.new())
	var outcome := _resolve(s)
	# The ice is solid ground (#109's whole point), and drowns_in asks can_traverse, which reads tile
	# STATE -- so this comes out right with no ice clause anywhere in the shove.
	assert_bool(outcome.knockback_to == Vector2i(3, 0)).is_true()
	assert_int(outcome.drown_damage).is_equal(0)
	assert_that(_lifecycle(outcome)).is_equal(Unit.LifecycleState.ACTIVE)


func test_a_body_already_down_is_finished_by_the_water() -> void:
	# A 0-damage shove, because that is the only kind a downed body ever takes: a damaging hit
	# finishes it where it lies (#126), and the resolver's provisional rung then leaves nothing to
	# shove. So this is the REPOSITION case, and the water is what turns it lethal.
	var sm := H.make_manager(self)
	var a := H.spawn_solo(self, sm, PLAYER, Vector2i(1, 0))
	var d := H.spawn_solo(self, sm, ENEMY, Vector2i(2, 0))
	var main := (a.get_equipped_weapon() as WeaponInstance).template.main_attack
	main.knockback = 1
	# `deals_no_damage`, not power 0: power is only one term, and the family's stat blend puts the
	# wielder's own numbers on top -- a 0-power swing still lands damage, which would finish the body
	# where it lies and leave nothing to shove.
	main.deals_no_damage = true
	(sm.get_node("../Grid") as TileMapLayer).set_cell(Vector2i(3, 0), 0, DEEP_WATER)
	d.force_down()
	var outcome := _resolve({"sm": sm, "a": a, "d": d})
	assert_bool(outcome.knockback_to == Vector2i(3, 0)) \
		.override_failure_message("the body should be pushed into the water, not left on the bank") \
		.is_true()
	assert_that(_lifecycle(outcome)).is_equal(Unit.LifecycleState.DEAD)


func test_a_tumble_that_bottoms_out_in_a_lake_ends_in_the_lake() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 2)
	heights.set_cell(Vector2i(2, 0), 2)
	heights.set_cell(Vector2i(3, 0), 0, Terrain.RampRise.WEST)   # a ramp down toward the water
	var s := _setup(heights, 1, Vector2i(1, 0), Vector2i(2, 0))
	(s.grid as TileMapLayer).set_cell(Vector2i(4, 0), 0, DEEP_WATER)
	var outcome := _resolve(s)
	assert_bool(outcome.knockback_to == Vector2i(4, 0)) \
		.override_failure_message("the slide should carry on into the water, not stop dry above it") \
		.is_true()
	assert_that(_lifecycle(outcome)).is_equal(Unit.LifecycleState.DOWNED)
	assert_int(outcome.target_hp_after).is_equal(0)


func test_a_fall_into_water_pays_the_fall_and_the_water_takes_the_rest() -> void:
	# ONE level, off the constant rather than a number. The victim is given HEADROOM rather than the
	# drop being tuned down: the baseline fixture unit is felled by the swing plus a single level, so
	# without it there is nothing left for the water and the case tests only the fall.
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), Terrain.UNITS_PER_LEVEL)
	heights.set_cell(Vector2i(2, 0), Terrain.UNITS_PER_LEVEL)
	var sm := H.make_manager(self, heights)
	var a := H.spawn_solo(self, sm, PLAYER, Vector2i(1, 0))
	var d := H.spawn_solo(self, sm, ENEMY, Vector2i(2, 0), {Stats.Stat.MHP: 200})
	(a.get_equipped_weapon() as WeaponInstance).template.main_attack.knockback = 1
	var grid := sm.get_node("../Grid") as TileMapLayer
	grid.set_cell(Vector2i(3, 0), 0, DEEP_WATER)   # at the board floor
	var outcome := _resolve({"sm": sm, "a": a, "d": d, "grid": grid})
	assert_int(outcome.fall_damage) \
		.override_failure_message("a drop into water is still a drop").is_greater(0)
	assert_int(outcome.drown_damage) \
		.override_failure_message("fixture assumption broke: the fall alone finished the unit, so "
			+ "there was nothing left for the water to take -- lower the drop").is_greater(0)
	# THE property, and it is tuning-proof: however the blow and the fall are priced, the water takes
	# the remainder, so the total is exactly what the unit had.
	assert_int(outcome.damage).is_equal(outcome.hp_before)
	assert_int(outcome.target_hp_after).is_equal(0)


# A hit that alone kills leaves nothing to shove (the pre-#259 rule, judged provisionally).
func test_a_killing_hit_still_never_shoves() -> void:
	var sm := H.make_manager(self)
	var a := H.spawn_solo(self, sm, PLAYER, Vector2i(1, 0), {}, true, 25)   # overkill past the ceiling
	var d := H.spawn_solo(self, sm, ENEMY, Vector2i(2, 0))
	(a.get_equipped_weapon() as WeaponInstance).template.main_attack.knockback = 2
	var s := {"sm": sm, "a": a, "d": d}
	var outcome := _resolve(s)
	assert_that(outcome.lethality).is_equal(ResolvedOutcome.Lethality.KILLED)
	assert_bool(outcome.knockback_applied).is_false()
