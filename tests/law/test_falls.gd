# Falls, shoves and tumbles (#259; canon docs/design/verticality.md -> Falls). The shove is
# AIRBORNE (dev, 2026-08-20): it flies its knockback distance at the starting elevation and the
# drop resolves where the travel ends -- so an ally can be blown OVER a hole to safety, a rise
# braces the flight, and a landing on a slope tumbles down it. Boards are hand-painted (never
# authored content); the two canon tumble examples are reproduced verbatim.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

const HOLE_TILE := Vector2i(18, 2)   # the authored VOID tile ("hole") in TestTiles

var _no_reactions: Array[ElementalReaction] = []


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
	heights.set_cell(Vector2i(3, 0), 1)
	var s := _setup(heights, 2, Vector2i(1, 0), Vector2i(2, 0))
	assert_bool(_resolve(s).knockback_applied).is_false()


func test_the_brace_halts_a_flight_mid_way() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(4, 0), 1)
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
	heights.set_cell(Vector2i(4, 0), 1)   # the brace one past the hole
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
	heights.set_cell(Vector2i(1, 0), 2)
	heights.set_cell(Vector2i(2, 0), 2)   # victim starts on the terrace; (3,0) is ground level
	var s := _setup(heights, 1, Vector2i(1, 0), Vector2i(2, 0))
	var flat := _setup(BoardHeights.new(), 1, Vector2i(1, 0), Vector2i(2, 0))
	var outcome := _resolve(s)
	var control := _resolve(flat)
	assert_int(outcome.fall_damage).is_equal(FallRules.damage_for(2, s.d))
	assert_int(outcome.damage).is_equal(control.damage + outcome.fall_damage)
	assert_bool(outcome.knockback_to == Vector2i(3, 0)).is_true()


func test_a_drop_can_change_the_rung() -> void:
	# Derive the hit's own damage from a probe (never assume the fixture's number), then give both
	# victims exactly one more HP than it: the flat twin survives, the dropped one does not.
	var hit := _resolve(_setup(BoardHeights.new(), 1, Vector2i(1, 0), Vector2i(2, 0))).damage
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 2)
	heights.set_cell(Vector2i(2, 0), 2)
	var s := _setup(heights, 1, Vector2i(1, 0), Vector2i(2, 0))
	var flat := _setup(BoardHeights.new(), 1, Vector2i(1, 0), Vector2i(2, 0))
	(s.d as Unit).set_current_hp(hit + 1)
	(flat.d as Unit).set_current_hp(hit + 1)
	assert_that(_resolve(flat).lethality).is_equal(ResolvedOutcome.Lethality.NONE)
	assert_bool(_resolve(s).lethality != ResolvedOutcome.Lethality.NONE).is_true()   # the fall tips it


func test_the_weight_hook_raises_fall_damage() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 2)
	heights.set_cell(Vector2i(2, 0), 2)
	var s := _setup(heights, 1, Vector2i(1, 0), Vector2i(2, 0))
	var ballast := H.make_weapon()
	ballast.weight = 2 * FallRules.WEIGHT_PER_BONUS_DAMAGE
	(s.d as Unit).add_item(ballast)
	# The scaling property, never the numbers: carried mass raises the same drop's cost, and the
	# resolver reads the loaded unit. Inert at weight 0 -- the #120 interlock's fall-damage wire.
	var laden := _resolve(s).fall_damage
	assert_int(laden).is_equal(FallRules.damage_for(2, s.d))
	assert_bool(laden > FallRules.damage_for(2, null)).is_true()


# --- Tumbles: the two canon examples, verbatim -----------------------------------------------

# F3 R2 R1 R0 F0 -- one unbroken flight: tumbles to F0, no fall damage anywhere on a slope.
func test_canon_example_one_tumbles_the_whole_flight() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 3)                            # the shover stands level too
	heights.set_cell(Vector2i(2, 0), 3)                            # F3
	heights.set_cell(Vector2i(3, 0), 2, Terrain.RampRise.WEST)     # R2 (rises back toward F3)
	heights.set_cell(Vector2i(4, 0), 1, Terrain.RampRise.WEST)     # R1
	heights.set_cell(Vector2i(5, 0), 0, Terrain.RampRise.WEST)     # R0
	var s := _setup(heights, 1, Vector2i(1, 0), Vector2i(2, 0))    # (6,0) is F0
	var outcome := _resolve(s)
	assert_bool(outcome.knockback_to == Vector2i(6, 0)).is_true()
	assert_int(outcome.fall_damage).is_equal(0)
	var expected: Array[Vector2i] = [Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0)]
	assert_that(_path_of(outcome)).is_equal(expected)


# F3 R2 F2 ... -- the landing at F2 catches it: ends on F2, never reaches R1.
func test_canon_example_two_is_caught_by_the_landing() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 3)
	heights.set_cell(Vector2i(2, 0), 3)                            # F3
	heights.set_cell(Vector2i(3, 0), 2, Terrain.RampRise.WEST)     # R2
	heights.set_cell(Vector2i(4, 0), 2)                            # F2 -- the catch
	heights.set_cell(Vector2i(5, 0), 1, Terrain.RampRise.WEST)     # R1, never reached
	var s := _setup(heights, 1, Vector2i(1, 0), Vector2i(2, 0))
	var outcome := _resolve(s)
	assert_bool(outcome.knockback_to == Vector2i(4, 0)).is_true()
	assert_int(outcome.fall_damage).is_equal(0)


# The airborne model's distinguishing case: a STRONGER shove on example two's board flies OVER
# the ramp and drops onto F2 -- one level of genuine fall, where the knockback-1 tumble was free.
func test_a_longer_flight_overflies_the_ramp_and_falls() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 3)
	heights.set_cell(Vector2i(2, 0), 3)
	heights.set_cell(Vector2i(3, 0), 2, Terrain.RampRise.WEST)
	heights.set_cell(Vector2i(4, 0), 2)
	var s := _setup(heights, 2, Vector2i(1, 0), Vector2i(2, 0))
	var outcome := _resolve(s)
	assert_bool(outcome.knockback_to == Vector2i(4, 0)).is_true()
	assert_int(outcome.fall_damage).is_equal(FallRules.damage_for(1, s.d))
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
	heights.set_cell(Vector2i(1, 0), 3)
	heights.set_cell(Vector2i(2, 0), 3)
	heights.set_cell(Vector2i(3, 0), 2, Terrain.RampRise.WEST)     # R2, then a sheer 2-drop to (4,0)
	var s := _setup(heights, 1, Vector2i(1, 0), Vector2i(2, 0))
	var outcome := _resolve(s)
	assert_bool(outcome.knockback_to == Vector2i(4, 0)).is_true()  # falls the drop, not stopped
	assert_int(outcome.fall_damage).is_equal(FallRules.damage_for(2, s.d))
	assert_int(outcome.fall_levels).is_equal(2)


# A plummet that lands on another ramp keeps tumbling down that one too (dev: "continue whatever
# descent awaits them").
func test_a_plummet_landing_on_a_ramp_tumbles_again() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 3)
	heights.set_cell(Vector2i(2, 0), 3)
	heights.set_cell(Vector2i(3, 0), 2, Terrain.RampRise.WEST)     # R2, then a 2-drop
	heights.set_cell(Vector2i(4, 0), 0, Terrain.RampRise.WEST)     # lands on R0, tumbles again
	var s := _setup(heights, 1, Vector2i(1, 0), Vector2i(2, 0))    # (5,0) is F0, the catch
	var outcome := _resolve(s)
	assert_bool(outcome.knockback_to == Vector2i(5, 0)).is_true()
	assert_int(outcome.fall_levels).is_equal(2)
	var expected: Array[Vector2i] = [Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0)]
	assert_that(_path_of(outcome)).is_equal(expected)


func test_the_tumble_stops_at_an_occupied_cell() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 3)
	heights.set_cell(Vector2i(2, 0), 3)
	heights.set_cell(Vector2i(3, 0), 2, Terrain.RampRise.WEST)
	var s := _setup(heights, 1, Vector2i(1, 0), Vector2i(2, 0))
	H.spawn_solo(self, s.sm, ENEMY, Vector2i(4, 0))                # a body on the catch cell
	var outcome := _resolve(s)
	assert_bool(outcome.knockback_to == Vector2i(3, 0)).is_true()


# --- The two rules #259 deliberately does NOT change -----------------------------------------

# Water keeps its shoreline stop verbatim -- what a shove INTO water does is #116's open fork.
func test_water_still_stops_the_shove_at_the_shoreline() -> void:
	var s := _setup(BoardHeights.new(), 2, Vector2i(1, 0), Vector2i(2, 0))
	(s.grid as TileMapLayer).set_cell(Vector2i(3, 0), 0, Vector2i(5, 6))   # water_basic
	assert_bool(_resolve(s).knockback_applied).is_false()


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
