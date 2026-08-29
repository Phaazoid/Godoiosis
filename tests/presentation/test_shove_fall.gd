# The shove's own FALL (#472; canon docs/design/verticality.md -> Falls, shoves and tumbles).
#
# A shove flies at its launch height and then drops, and #431 already ruled WHERE: a trail cell
# drops when the two surfaces meeting at the EDGE it was entered by are not at the same height.
# The preview obeyed that rule; the playback asked a looser one -- UnitMirror began ground contact
# on ANY ramp landing, where the resolver only calls a landing a slide-on at a drop of exactly 1
# down a matching slope. Every other ramp landing therefore snapped by the difference, in a single
# frame, halfway through the final flight segment. The dev reported it as a midair teleport.
#
# These two boards are HIS, from the pair of reports that isolated it (2026-08-22, both on main
# @ 5bbef65), transposed to small coordinates and otherwise reproduced cell for cell: same
# elevations, same ramp directions, same knockback, same shove direction relative to the slope.
# One fell wrong and one was always correct, and the ONLY term that differs is the size of the drop.
#
# What is pinned is the DECISION and the sequence that reaches it, never the animation: _fall is
# instant headless exactly as plummet() is, so a rate or a duration is unobservable here -- and a
# feel knob does not belong in an assertion anyway. What survives is the depth it recorded, which
# is the thing the bug got wrong.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _no_reactions: Array[ElementalReaction] = []


# Shover at `a_cell` with a knockback-N main, victim at `d_cell`, on a painted-height board. The
# victim gets the grid and the heights the live game hands it (game.spawn_unit), because the slide
# is what is under test and it reads both.
func _setup(heights: BoardHeights, knockback: int, a_cell: Vector2i, d_cell: Vector2i) -> Dictionary:
	var sm := H.make_manager(self, heights)
	var a := H.spawn_solo(self, sm, PLAYER, a_cell)
	var d := H.spawn_solo(self, sm, ENEMY, d_cell)
	(a.get_equipped_weapon() as WeaponInstance).template.main_attack.knockback = knockback
	var grid := sm.get_node("../Grid") as TileMapLayer
	d.movement.set_grid(grid)
	d.movement.set_heights(heights)
	d.movement.set_cell(d_cell)
	return {"sm": sm, "a": a, "d": d, "grid": grid}


# The resolver's own answer -- the path and the flight/tumble split the slide is handed (Law #2,
# never re-derived here, which is why this drives the real resolver instead of hand-writing a path).
func _resolve(setup: Dictionary) -> ResolvedOutcome:
	var attack := H.stamped_attack(setup.a, setup.d)
	var plan := ResolvedPlan.new()
	var attacks: Array[AttackAction] = [attack]
	plan.attacks = attacks
	var sm: SquadManager = setup.sm
	PlanResolver.resolve(plan, _no_reactions, sm.board_source.call())
	return attack.resolved


# Run the REAL slide to completion. Bounded rather than signal-awaited, so a slide that never
# finishes fails the case instead of hanging the suite.
func _slide(unit: Unit, outcome: ResolvedOutcome) -> void:
	unit.movement.slide_along_path(outcome.knockback_path, outcome.knockback_landing_index)
	for _frame in range(600):
		if not unit.movement.sliding:
			return
		await await_idle_frame()
	fail("the slide never finished -- 600 frames elapsed with sliding still true")


# --- The dev's failing board: a cliff onto a staircase ---------------------------------------
#
# F5 F5 F5 R3 R2 R1 R4, shoved EAST off the flat top. Knockback 2 lands on the R3 ramp, which
# descends the way the shove travels -- but from three levels up rather than one, so the resolver
# calls it a fall of 2 and the tumble carries on down the slope behind it.
func test_a_cliff_onto_a_slope_falls_at_the_edge_it_lands_over() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(0, 0), 10)
	heights.set_cell(Vector2i(1, 0), 10)
	heights.set_cell(Vector2i(2, 0), 10)
	heights.set_cell(Vector2i(3, 0), 6, Terrain.RampRise.WEST)   # descends east, two levels down
	heights.set_cell(Vector2i(4, 0), 4, Terrain.RampRise.WEST)
	heights.set_cell(Vector2i(5, 0), 2, Terrain.RampRise.WEST)
	heights.set_cell(Vector2i(6, 0), 8, Terrain.RampRise.WEST)   # a rise: stops the tumble
	var s := _setup(heights, 2, Vector2i(0, 0), Vector2i(1, 0))
	var outcome := _resolve(s)
	# The premise, asserted rather than assumed: flight ends on the ramp with the tumble behind it.
	assert_bool(outcome.knockback_to == Vector2i(5, 0)).override_failure_message(
			"the board is not the one this case is about -- the tumble did not run").is_true()
	assert_int(outcome.knockback_landing_index).is_equal(2)

	var victim: Unit = s.d
	await _slide(victim, outcome)

	# The fall HAPPENED, from the flight level, and was exactly the gap between the flight and the
	# ramp's high shoulder: surface_y(5) = 6.0 above, surface_y(3 + 1) = 5.0 at the edge it enters.
	# Before the fix that gap was crossed in one frame with no beat at all -- the reported teleport.
	assert_float(victim.movement.landing_fall_top).override_failure_message(
			"the fall did not start from the flight level").is_equal_approx(6.0, 0.001)
	assert_float(victim.movement.landing_fall_depth).override_failure_message(
			"the landing did not fall the gap between the flight and the ramp's high edge") \
			.is_equal_approx(1.0, 0.001)
	# And the horizontal still finished: a fall is a BEAT of the slide, never a truncation of it.
	assert_bool(victim.movement.cell == Vector2i(5, 0)).override_failure_message(
			"the slide did not carry the unit all the way to its resolved landing").is_true()


# --- The dev's working board: a drop of exactly one onto a matching slope ---------------------
#
# F2 F2 R1 with a rise behind it, shoved WEST. Knockback 2 lands on R1, whose high shoulder meets
# the flight level exactly -- the one geometry the resolver zeroes ("slopes never deal fall
# damage"), and the one that was always correct. It is here because a fix that makes the broken
# case fall is worthless if it also makes this one stutter.
func test_a_one_level_slide_onto_a_matching_slope_never_falls() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(2, 0), 4)
	heights.set_cell(Vector2i(1, 0), 4)
	heights.set_cell(Vector2i(0, 0), 4)
	heights.set_cell(Vector2i(-1, 0), 2, Terrain.RampRise.EAST)  # descends west, one level down
	heights.set_cell(Vector2i(-2, 0), 6)                         # a rise: stops the tumble
	var s := _setup(heights, 2, Vector2i(2, 0), Vector2i(1, 0))
	var outcome := _resolve(s)
	assert_bool(outcome.knockback_to == Vector2i(-1, 0)).override_failure_message(
			"the board is not the one this case is about").is_true()
	assert_int(outcome.fall_levels).override_failure_message(
			"this landing is supposed to be a free slide-on, not a fall").is_equal(0)

	var victim: Unit = s.d
	await _slide(victim, outcome)

	# Two reads, because one of them is weak on its own: a depth of zero is also what an
	# un-run fall leaves behind, whereas landing_fall_top is published ONLY when a drop is real,
	# so an untouched top is positive evidence that no fall was ever taken at any edge here.
	assert_float(victim.movement.landing_fall_top).override_failure_message(
			"a clean slide-on published a fall -- no edge on this board should break") \
			.is_equal(0.0)
	assert_float(victim.movement.landing_fall_depth).override_failure_message(
			"a clean slide-on fell -- the surfaces meet at that edge and nothing should drop") \
			.is_equal(0.0)
	assert_bool(victim.movement.cell == Vector2i(-1, 0)).is_true()


# --- The seam itself --------------------------------------------------------------------------

# One edge, named from either side, is ONE height. That is what lets "do these two surfaces meet?"
# be a single question -- the drop pointer asks it from the arriving cell and the slide asks it
# from the leaving one -- and a fix that let the two sides disagree would hang the preview's arrow
# somewhere the sprite does not fall.
func test_an_edge_reads_the_same_height_from_both_of_its_sides() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(3, 0), 6, Terrain.RampRise.WEST)
	heights.set_cell(Vector2i(4, 0), 4, Terrain.RampRise.WEST)
	var east_side := BoardSpace.surface_height_at_edge(Vector2i(3, 0), Vector2i(1, 0), heights)
	var west_side := BoardSpace.surface_height_at_edge(Vector2i(4, 0), Vector2i(-1, 0), heights)
	assert_float(east_side).override_failure_message(
			"two ramps continuing one slope do not meet at their shared edge") \
			.is_equal_approx(west_side, 0.001)


# --- the depth the CAMERA rides (#602) ----------------------------------------------------------
#
# UnitMirror.fall_depth is UnitMirror.stand_height read from the other end, and the cliff follow
# takes the camera down by it. Both cases below drive the state DIRECTLY, which is forced rather
# than lazy: plummet() and _fall both return before raising their flag when DisplayServer is
# headless, so no run of the real path can ever reach the state these describe -- which is exactly
# why the SIGN is worth a case. The camera floors this at zero, and only a case can say whether
# that floor is guarding against something or is dead code.

func test_a_falling_body_reports_the_depth_its_own_sprite_is_placed_by() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(0, 0), 4)
	heights.set_cell(Vector2i(1, 0), 4)
	var s := _setup(heights, 1, Vector2i(0, 0), Vector2i(1, 0))
	var victim: Unit = s.d
	var surface := BoardSpace.surface_point(Vector2i(1, 0), heights).y
	victim.movement.plummeting = true
	victim.movement.plummet_depth = 3.0

	assert_float(UnitMirror.fall_depth(victim, heights)).override_failure_message(
			"a body three cells down a hole does not report three cells of fall") \
			.is_equal_approx(3.0 * BoardSpace.CELL_SIZE, 0.001)
	# ...and the complement holds, which is what makes the shot and the sprite one answer: the
	# camera drops by the depth, the sprite is placed at the height, and both come off this pair.
	assert_float(UnitMirror.stand_height(victim, heights)).override_failure_message(
			"the depth and the stand height disagree about where the body is") \
			.is_equal_approx(surface - UnitMirror.fall_depth(victim, heights), 0.001)


func test_a_body_still_in_the_AIR_over_a_hole_reports_a_negative_depth() -> void:
	# The third vertical animation: an airborne shove holds the body at its LAUNCH height while it
	# flies over lower ground, so the same subtraction comes out the other way. The sign is
	# LOAD-BEARING since #602 round 4 -- the trained shot rides it UP, holding the camera level
	# with the flying body instead of dipping to the ground it crosses (the old channel floored
	# this at zero and watched every fall from the lip, the rule the round repealed).
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(0, 0), 8)
	heights.set_cell(Vector2i(1, 0), 8)
	heights.set_cell(Vector2i(2, 0), 2)   # the low ground it is flying over
	var s := _setup(heights, 2, Vector2i(0, 0), Vector2i(1, 0))
	var victim: Unit = s.d
	victim.movement.set_cell(Vector2i(2, 0))
	victim.movement.sliding = true
	victim.movement.airborne = true
	victim.movement.slide_origin = Vector2i(1, 0)

	assert_float(UnitMirror.fall_depth(victim, heights)).override_failure_message(
			"a body flying above the ground beneath it did not report a negative depth") \
			.is_less(0.0)


# --- the body steps CLEAR of the edge before it drops (dev, 2026-08-29) -------------------------

# It used to slide to the MIDPOINT of the shared edge and fall from there, which puts the sprite
# exactly in the boundary plane -- half inside the wall for the whole descent. Invisible on the
# one-cell drops this suite was written for; down a ten-level pillar the dev watched a body sink
# through the rock for two and a half seconds and then snap sideways to the cell centre, that snap
# being the leftover half-step running in a sixteenth of a second after the fall had played.
#
# The FALL is headless-escaped, as everything in this neighbourhood is -- but the STEP is a real
# tween in every run, so the ordering between them is observable even though the descent is not.
# That is why _step_off does the step first in both branches.
func test_a_body_finishes_its_step_before_it_starts_to_drop() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(0, 0), 10)
	heights.set_cell(Vector2i(1, 0), 10)
	heights.set_cell(Vector2i(2, 0), 10)
	heights.set_cell(Vector2i(3, 0), 0)   # a sheer drop of five levels off the lip
	heights.set_cell(Vector2i(4, 0), 0)
	var s := _setup(heights, 2, Vector2i(0, 0), Vector2i(1, 0))
	var outcome := _resolve(s)
	assert_bool(outcome.knockback_landing_index > 0).override_failure_message(
			"the board is not the one this case is about -- nothing flew").is_true()

	var victim: Unit = s.d
	var caught := await _slide_watching_the_drop(victim, outcome)
	assert_bool(caught.has("at")).override_failure_message(
			"no fall was recorded at all -- this shove never left the lip").is_true()

	var grid: TileMapLayer = s.grid
	var at: Vector2 = caught["at"]
	var centre: Vector2 = grid.map_to_local(caught["cell"])
	assert_float(at.distance_to(centre)).override_failure_message(
			"the body began to drop %.1f px from the centre of the cell it was entering -- it is "
			% at.distance_to(centre) + "falling in the boundary plane, half inside the wall it left"
	).is_less(0.5)


# Run the real slide, recording where the body stood the first frame its fall was recorded.
func _slide_watching_the_drop(unit: Unit, outcome: ResolvedOutcome) -> Dictionary:
	var caught: Dictionary = {}
	unit.movement.slide_along_path(outcome.knockback_path, outcome.knockback_landing_index)
	for _frame in range(600):
		if not caught.has("at") and unit.movement.landing_fall_depth > 0.0:
			caught["at"] = unit.position
			caught["cell"] = unit.movement.cell
		if not unit.movement.sliding:
			return caught
		await await_idle_frame()
	fail("the slide never finished -- 600 frames elapsed with sliding still true")
	return caught


# --- and where its bricks burst once it has fallen out of frame (dev, 2026-08-29) ---------------

# REWRITTEN in #602 round 4: the round-2 spelling here re-derived the camera's stop from the
# body's own fall (Pacing.followed_fall of the depth), which is a second BASE as well as a second
# spelling -- the shot hangs off the STAGE's height and the body off the void's lip, and on a
# fight staged above a pit those differ by the whole cliff, so the cubes were below the frame at
# every slider setting (the pillar board, found in play). The burst is now raised to the frame the
# camera actually holds: UnitMirror.burst_lift takes the host's own frame-floor anchor, and the
# property worth pinning is unchanged -- the show lands in the same place however deep the pit is.
func test_a_deeper_plummet_does_not_burst_further_from_the_camera() -> void:
	var anchor := 2.5   # where the bottom of the shot happens to be, in world y

	# Two bodies, one five times deeper than the other: the burst LANDS at the anchor either way.
	var deep := -8.0 + UnitMirror.burst_lift(anchor, -8.0)
	var deeper := -40.0 + UnitMirror.burst_lift(anchor, -40.0)
	assert_float(deeper).override_failure_message(
			"a body that fell five times as far burst five times further from the camera -- the "
			+ "cubes are launching somewhere nobody is looking").is_equal_approx(deep, 0.001)
	assert_float(deep).override_failure_message(
			"the bricks did not come up to the frame the camera is holding") \
			.is_equal_approx(anchor, 0.001)

	# A burst already inside the frame is never LOWERED: nothing else in the game bursts anywhere
	# but the body, and a shallow fall whose readout is still on screen keeps it there.
	assert_float(UnitMirror.burst_lift(anchor, anchor + 1.0)).override_failure_message(
			"a burst already above the frame floor was dragged down to it").is_equal(0.0)
