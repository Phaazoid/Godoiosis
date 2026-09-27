# The squad's LINES (#1070) as geometry: the stroke round the cohesion range, the tether from a member
# to its leader, the dashes both of them march, and the pluck a refused click gives. Pure statics --
# SquadLines2D and OverlayManager.outline_segments -- so no scene is built; the wire from the store to
# each view is test_overlay_mirror's, and the play that drives it is tests/ui/test_squad_lines_in_play.
#
# Every tuned value a case depends on is SET here and restored after, so these pin the rules and not
# the dev's tuning (tests/README.md #8).
extends GdUnitTestSuite

var _saved := {}


func before_test() -> void:
	_saved = {
		"dashes": SquadLines2D.DASHES_PER_TILE, "fill": SquadLines2D.DASH_FILL,
		"speed": SquadLines2D.DASH_SPEED, "inset": SquadLines2D.TETHER_INSET,
		"amp": SquadLines2D.SHAKE_AMPLITUDE, "secs": SquadLines2D.SHAKE_SECONDS,
		"swings": SquadLines2D.SHAKE_SWINGS, "cone": ThreatLines2D.CONE_LENGTH,
		"arrow": SquadLines2D.ARROW_LENGTH,
		"photo": PlayerSettings.is_on(PlayerSettings.Setting.PHOTOSENSITIVITY),
		"draw_in": SquadLines2D.DRAW_IN_SECONDS, "pop_scale": SquadLines2D.POP_SCALE,
		"pop_secs": SquadLines2D.POP_SECONDS, "hold": SquadLines2D.DRAWN_HOLD_SECONDS,
		"fade": SquadLines2D.DRAWN_FADE_SECONDS, "reel": SquadLines2D.REEL_IN_SECONDS,
		"brighten": SquadLines2D.POP_BRIGHTEN,
	}


func after_test() -> void:
	SquadLines2D.DASHES_PER_TILE = _saved["dashes"]
	SquadLines2D.DASH_FILL = _saved["fill"]
	SquadLines2D.DASH_SPEED = _saved["speed"]
	SquadLines2D.TETHER_INSET = _saved["inset"]
	SquadLines2D.SHAKE_AMPLITUDE = _saved["amp"]
	SquadLines2D.SHAKE_SECONDS = _saved["secs"]
	SquadLines2D.SHAKE_SWINGS = _saved["swings"]
	ThreatLines2D.CONE_LENGTH = _saved["cone"]
	SquadLines2D.ARROW_LENGTH = _saved["arrow"]
	PlayerSettings.set_on(PlayerSettings.Setting.PHOTOSENSITIVITY, _saved["photo"])
	SquadLines2D.DRAW_IN_SECONDS = _saved["draw_in"]
	SquadLines2D.POP_SCALE = _saved["pop_scale"]
	SquadLines2D.POP_SECONDS = _saved["pop_secs"]
	SquadLines2D.DRAWN_HOLD_SECONDS = _saved["hold"]
	SquadLines2D.DRAWN_FADE_SECONDS = _saved["fade"]
	SquadLines2D.REEL_IN_SECONDS = _saved["reel"]
	SquadLines2D.POP_BRIGHTEN = _saved["brighten"]


# --- The range's stroke -------------------------------------------------------------------------

# Every segment runs with its region on the RIGHT (screen y down), so the whole stroke goes round
# clockwise and a dash marching along each segment's own direction marches round the range one way.
# Before #1070 the LEFT and DOWN edges ran backwards, which a solid stroke could not show and a
# marching one shows as dashes running both ways at once. An L with a notch, so every edge direction
# and both a convex and a concave corner are present.
func test_the_range_stroke_is_wound_with_the_range_on_its_right() -> void:
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1),
		Vector2i(0, 2), Vector2i(1, 2)]
	var inside := {}
	for cell in cells:
		inside[cell] = true
	var segments := OverlayManager.outline_segments(cells, null)

	var outward := 0
	for cell in cells:
		for dir: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			if not inside.has(cell + dir):
				outward += 1
	assert_int(segments.size()).override_failure_message(
			"the stroke is not one segment per outward-facing edge").is_equal(outward)

	for segment in segments:
		var a := Vector2(segment[0].x, segment[0].z)
		var b := Vector2(segment[1].x, segment[1].z)
		var along := (b - a).normalized()
		var right := Vector2(-along.y, along.x)   # clockwise quarter turn, y down
		var middle := (a + b) * 0.5
		var right_cell := Vector2i((middle + right * 0.5).floor())
		var left_cell := Vector2i((middle - right * 0.5).floor())
		assert_bool(inside.has(right_cell) and not inside.has(left_cell)).override_failure_message(
				"the edge %s -> %s runs with the range on its LEFT" % [a, b]).is_true()


# --- The dashes ----------------------------------------------------------------------------------

# A dash period is a whole fraction of a tile, so the pattern on one tile is the pattern on the next:
# that is what lets the range's stroke stay one pattern while it is drawn as one segment per edge.
func test_the_dash_pattern_repeats_exactly_once_per_tile() -> void:
	SquadLines2D.DASHES_PER_TILE = 3
	SquadLines2D.DASH_FILL = 0.5
	var spans := SquadLines2D.dash_spans(3.0, 0.37)
	var starts := {}
	for span in spans:
		starts[snappedf(span.x, 0.0001)] = true
	var checked := 0
	for span in spans:
		if span.x > 0.0 and span.y < 2.0:
			assert_bool(starts.has(snappedf(span.x + 1.0, 0.0001))).override_failure_message(
					"a dash at %.3f has no twin one tile on -- the pattern restarts at a tile edge"
					% span.x).is_true()
			checked += 1
	assert_int(checked).override_failure_message("fixture drew no whole dashes to compare").is_greater(0)


# The pattern MARCHES: advancing the clock slides every dash forward by the same distance, which is
# what "the dashes slowly moving" is, and toward the stroke's END, which on a tether is the leader.
func test_the_dashes_march_toward_the_end_of_the_stroke() -> void:
	SquadLines2D.DASHES_PER_TILE = 2
	SquadLines2D.DASH_FILL = 0.4
	var before := SquadLines2D.dash_spans(4.0, 0.0)
	var after := SquadLines2D.dash_spans(4.0, 0.1)
	var moved := 0
	for span in before:
		if span.x <= 0.0 or span.y >= 3.8:
			continue
		var found := false
		for other in after:
			if is_equal_approx(other.x, span.x + 0.1) and is_equal_approx(other.y, span.y + 0.1):
				found = true
		assert_bool(found).override_failure_message(
				"the dash at %.2f did not move 0.1 toward the end" % span.x).is_true()
		moved += 1
	assert_int(moved).override_failure_message("fixture drew no whole dashes to follow").is_greater(0)


# --- The tether ---------------------------------------------------------------------------------

# From the member's middle to just short of the leader's, ending in the reach mark's own cone -- with
# the arrowhead at the LEADER's end, because every tether points at its leader (dev). The shaft is
# sampled rather than two points, or the pluck (a bend pinned at both ends) would have nothing to bend.
func test_a_tether_runs_from_the_member_to_the_leader_and_points_at_the_leader() -> void:
	SquadLines2D.TETHER_INSET = 0.25
	SquadLines2D.ARROW_LENGTH = 0.4
	var member := Vector3(0.5, 1.0, 0.5)
	var leader := Vector3(3.5, 1.0, 0.5)
	var strokes := SquadLines2D.tether(PackedVector3Array([member, leader]))

	assert_int(strokes.size()).override_failure_message("the tether has no arrowhead").is_equal(2)
	assert_that(strokes[0][0]).override_failure_message(
			"the tether does not start at the member").is_equal(member)
	var cone := ThreatLines2D.cone_of(strokes, SquadLines2D.ARROW_WIDTH_SCALE)
	assert_bool(cone.is_empty()).override_failure_message("the arrowhead is not a cone").is_false()
	var tip: Vector3 = cone["tip"]
	var base: Vector3 = cone["base"]
	assert_float(tip.distance_to(leader)).override_failure_message(
			"the arrowhead's tip is not inset from the leader").is_equal_approx(0.25, 0.0001)
	assert_bool(tip.distance_to(leader) < base.distance_to(leader)).override_failure_message(
			"the arrowhead points at the MEMBER").is_true()
	assert_int(strokes[0].size()).override_failure_message(
			"the shaft is two points, so the pluck cannot bend it").is_greater(2)


# The arrowhead is the tether's OWN (dev, 2026-09-22): its length is ARROW_LENGTH, and the reach mark's
# CONE_LENGTH -- the enemy intent's knob -- does not reach it. Set apart, so a tether still reading
# the reach knob draws the wrong length.
func test_a_tethers_arrow_is_its_own_length_not_the_reach_marks() -> void:
	SquadLines2D.TETHER_INSET = 0.25
	SquadLines2D.ARROW_LENGTH = 0.6
	ThreatLines2D.CONE_LENGTH = 0.2
	var strokes := SquadLines2D.tether(PackedVector3Array([Vector3(0.5, 1.0, 0.5), Vector3(4.5, 1.0, 0.5)]))
	assert_int(strokes.size()).override_failure_message("the tether has no arrowhead").is_equal(2)
	var head := strokes[1]
	assert_float(head[0].distance_to(head[head.size() - 1])).override_failure_message(
			"the tether's arrow is not ARROW_LENGTH long -- it is reading the reach mark's cone") 		.is_equal_approx(0.6, 0.0001)


# The tether hangs at the MIDDLE of the bodies -- the dev's "connect the middle of the sprites" -- which
# is the art's own measure, between the feet and the top of the ink, whatever the density is tuned to.
func test_a_tether_hangs_between_the_feet_and_the_top_of_the_body() -> void:
	var chord := SquadLines2D.chord(Vector2i(0, 0), Vector2i(2, 0), null)
	var middle_world := chord[0].y * BoardSpace.ROW_HEIGHT
	var body_top := float(MapSpriteInk.INK_RECT.size.y) / UnitSprite3D.texels_per_unit
	assert_float(middle_world).override_failure_message("the tether lies on the ground").is_greater(0.0)
	assert_float(middle_world).override_failure_message(
			"the tether hangs above the body's head").is_less(body_top)
	assert_float(chord[1].y).override_failure_message(
			"the two ends hang at different heights on flat ground").is_equal_approx(chord[0].y, 0.0001)


# --- The pluck ----------------------------------------------------------------------------------

# A refused click rings the strained tether and lets it settle: still at the moment of the click,
# swinging while it rings, still again once it has -- and never before it was plucked.
func test_the_pluck_starts_still_swings_and_settles() -> void:
	SquadLines2D.SHAKE_AMPLITUDE = 0.2
	SquadLines2D.SHAKE_SECONDS = 0.4
	SquadLines2D.SHAKE_SWINGS = 3.0
	assert_float(SquadLines2D.shake_offset(-0.1)).is_equal_approx(0.0, 0.0001)
	assert_float(SquadLines2D.shake_offset(0.0)).is_equal_approx(0.0, 0.0001)
	assert_float(SquadLines2D.shake_offset(0.4)).is_equal_approx(0.0, 0.0001)
	assert_float(SquadLines2D.shake_offset(1.0)).is_equal_approx(0.0, 0.0001)
	var peak := 0.0
	for i in 40:
		peak = maxf(peak, absf(SquadLines2D.shake_offset(0.4 * float(i) / 40.0)))
	assert_float(peak).override_failure_message("the pluck never swung").is_greater(0.0)


# #217: a shake is motion, so the photosensitivity setting stills it -- the RED still says why.
func test_the_photosensitivity_setting_stills_the_pluck() -> void:
	SquadLines2D.SHAKE_AMPLITUDE = 0.2
	SquadLines2D.SHAKE_SECONDS = 10.0
	SquadLines2D.SHAKE_SWINGS = 3.0
	var stamp := Time.get_ticks_msec() - 400
	PlayerSettings.set_on(PlayerSettings.Setting.PHOTOSENSITIVITY, false)
	assert_float(absf(SquadLines2D.shake_now(stamp))).override_failure_message(
			"fixture: the pluck is still at this moment, so the setting cannot be seen").is_greater(0.0)
	PlayerSettings.set_on(PlayerSettings.Setting.PHOTOSENSITIVITY, true)
	assert_float(SquadLines2D.shake_now(stamp)).override_failure_message(
			"the tether shook with the photosensitivity setting on").is_equal_approx(0.0, 0.0001)


# --- Membership moments (#367) -------------------------------------------------------------------

const _CHORD_MEMBER := Vector3(0.5, 1.0, 0.5)
const _CHORD_LEADER := Vector3(4.5, 1.0, 0.5)


func _moment_times(draw_in: float, pop: float, hold: float, fade: float, reel: float) -> void:
	SquadLines2D.TETHER_INSET = 0.25
	SquadLines2D.ARROW_LENGTH = 0.4
	SquadLines2D.DRAW_IN_SECONDS = draw_in
	SquadLines2D.POP_SCALE = 1.8
	SquadLines2D.POP_SECONDS = pop
	SquadLines2D.DRAWN_HOLD_SECONDS = hold
	SquadLines2D.DRAWN_FADE_SECONDS = fade
	SquadLines2D.REEL_IN_SECONDS = reel


func _at(moment: int, elapsed: float, standing := false) -> Dictionary:
	return SquadLines2D.moment_at(moment, PackedVector3Array([_CHORD_MEMBER, _CHORD_LEADER]), elapsed,
			standing)


# A draw-in GROWS from the member: the shaft's far end only ever advances, it never passes where the
# cone begins, and the cone appears only once the shaft has reached it -- then grows to the full tip.
func test_a_draw_in_grows_from_the_member_and_the_cone_follows_the_shaft() -> void:
	_moment_times(0.4, 0.2, 0.5, 0.3, 0.4)
	var m := SquadLines2D.measure(PackedVector3Array([_CHORD_MEMBER, _CHORD_LEADER]))
	var last := -1.0
	var cone_seen := false
	for i in 41:
		var drawn := _at(SquadLines2D.Moment.DRAW_IN, 0.4 * float(i) / 40.0)
		var u1: float = drawn["u1"]
		assert_float(float(drawn["u0"])).override_failure_message("a draw-in did not start at the member") \
				.is_equal_approx(0.0, 0.0001)
		assert_bool(u1 >= last).override_failure_message("the draw-in's front went backwards").is_true()
		assert_bool(u1 <= float(m["shaft_end"]) + 0.0001).override_failure_message(
				"the shaft ran into the cone").is_true()
		if float(drawn["cone_grow"]) > 0.0:
			cone_seen = true
			assert_float(u1).override_failure_message("the cone appeared before the shaft reached it") \
					.is_equal_approx(float(m["shaft_end"]), 0.0001)
		last = u1
	assert_bool(cone_seen).override_failure_message("the cone never appeared").is_true()
	assert_float(float(_at(SquadLines2D.Moment.DRAW_IN, 0.4)["cone_grow"])).override_failure_message(
			"the cone never reached the full tip").is_equal_approx(1.0, 0.0001)
	assert_float(float(_at(SquadLines2D.Moment.DRAW_IN, -0.1)["u1"])).override_failure_message(
			"a draw-in waiting its turn drew something").is_equal_approx(0.0, 0.0001)


# The pop: the cone swells past its own size the moment the tether arrives, then settles back.
func test_the_pop_swells_the_cone_then_settles_it() -> void:
	_moment_times(0.4, 0.2, 0.5, 0.3, 0.4)
	var at_arrival := float(_at(SquadLines2D.Moment.DRAW_IN, 0.4)["cone_scale"])
	var settled := float(_at(SquadLines2D.Moment.DRAW_IN, 0.4 + 0.2)["cone_scale"])
	var before := float(_at(SquadLines2D.Moment.DRAW_IN, 0.3)["cone_scale"])
	assert_float(at_arrival).override_failure_message("the cone did not pop").is_greater(1.0)
	assert_float(settled).override_failure_message("the pop never settled").is_equal_approx(1.0, 0.0001)
	assert_float(before).override_failure_message("the cone popped before the tether arrived") \
			.is_equal_approx(1.0, 0.0001)


# With a standing tether for the pair (mid-Squad Up) the draw-in hands over as soon as it has popped;
# with none (Join Squad just closed) it holds, fades to nothing, and only then is done.
func test_a_draw_in_hands_over_to_a_standing_tether_or_holds_and_fades() -> void:
	_moment_times(0.4, 0.2, 0.5, 0.3, 0.4)
	var popped := 0.4 + 0.2 + 0.01
	assert_bool(bool(_at(SquadLines2D.Moment.DRAW_IN, popped, true)["done"])).override_failure_message(
			"a draw-in did not hand over to the standing tether").is_true()
	assert_bool(bool(_at(SquadLines2D.Moment.DRAW_IN, popped, false)["done"])).override_failure_message(
			"a draw-in with nothing to hand to ended instead of holding").is_false()
	var held: Color = _at(SquadLines2D.Moment.DRAW_IN, 0.4 + 0.2 + 0.4, false)["tint"]
	assert_float(held.a).override_failure_message("the held tether had already started fading") \
			.is_equal_approx(SquadLines2D.TETHER_COLOR.a, 0.0001)
	var fading: Color = _at(SquadLines2D.Moment.DRAW_IN, 0.4 + 0.2 + 0.5 + 0.15, false)["tint"]
	assert_bool(fading.a < SquadLines2D.TETHER_COLOR.a and fading.a > 0.0).override_failure_message(
			"the held tether was not fading halfway through its fade").is_true()
	var gone := _at(SquadLines2D.Moment.DRAW_IN, 0.4 + 0.2 + 0.5 + 0.3 + 0.01, false)
	assert_bool(bool(gone["done"])).override_failure_message("the faded tether never finished").is_true()


# A reel-in is pulled INTO the leader: the member end only ever advances, the shaft is gone before the
# cone starts to shrink, and the moment is over when the reel is.
func test_a_reel_in_pulls_the_tether_into_the_leader() -> void:
	_moment_times(0.4, 0.2, 0.5, 0.3, 0.4)
	var last := -1.0
	var shaft_gone_at := -1.0
	var shrink_at := -1.0
	for i in 41:
		var t := 0.4 * float(i) / 40.0
		var drawn := _at(SquadLines2D.Moment.REEL_IN, t)
		var u0: float = drawn["u0"]
		assert_bool(u0 >= last).override_failure_message("the reel-in's member end went backwards").is_true()
		last = u0
		if shaft_gone_at < 0.0 and u0 >= float(drawn["u1"]):
			shaft_gone_at = t
		if shrink_at < 0.0 and float(drawn["cone_scale"]) < 1.0:
			shrink_at = t
	assert_bool(shrink_at >= shaft_gone_at and shaft_gone_at >= 0.0).override_failure_message(
			"the cone shrank while the shaft was still there").is_true()
	assert_bool(bool(_at(SquadLines2D.Moment.REEL_IN, 0.4)["done"])).override_failure_message(
			"the reel-in did not end with the reel").is_true()
	assert_bool(bool(_at(SquadLines2D.Moment.REEL_IN, 0.3)["done"])).is_false()


# The times are the knobs', as RATIOS: doubling the draw-in time doubles when the cone first shows.
func test_a_moments_timing_follows_its_knob() -> void:
	_moment_times(0.4, 0.2, 0.5, 0.3, 0.4)
	var first := _first_cone_time()
	SquadLines2D.DRAW_IN_SECONDS = 0.8
	var doubled := _first_cone_time()
	assert_float(doubled).override_failure_message("the draw-in ignored its time knob") \
			.is_equal_approx(first * 2.0, 0.02)


func _first_cone_time() -> float:
	for i in 400:
		var t := 2.0 * float(i) / 400.0
		if float(_at(SquadLines2D.Moment.DRAW_IN, t)["cone_grow"]) > 0.0:
			return t
	return -1.0


# #217: the pop's whitening is a flash, so the setting drops it -- and nothing else. The swell stays.
func test_the_photosensitivity_setting_drops_the_pop_flash_but_not_the_swell() -> void:
	_moment_times(0.4, 0.2, 0.5, 0.3, 0.4)
	SquadLines2D.POP_BRIGHTEN = 0.8
	var chord := PackedVector3Array([_CHORD_MEMBER, _CHORD_LEADER])
	var lit := SquadLines2D.moment_at(SquadLines2D.Moment.DRAW_IN, chord, 0.4, false, true)
	var still := SquadLines2D.moment_at(SquadLines2D.Moment.DRAW_IN, chord, 0.4, false, false)
	assert_bool((lit["cone_tint"] as Color).is_equal_approx(SquadLines2D.TETHER_COLOR)) \
			.override_failure_message("fixture: the pop did not flash").is_false()
	assert_bool((still["cone_tint"] as Color).is_equal_approx(SquadLines2D.TETHER_COLOR)) \
			.override_failure_message("the pop flashed with the photosensitivity setting on").is_true()
	assert_float(float(still["cone_scale"])).override_failure_message(
			"the setting stilled the swell as well as the flash").is_greater(1.0)
