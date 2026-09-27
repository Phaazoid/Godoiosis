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
		"strain": SquadLines2D.BREAK_STRAIN_SECONDS, "shatter": SquadLines2D.BREAK_SHATTER_SECONDS,
		"kick": SquadLines2D.BREAK_KICK, "turns": SquadLines2D.BREAK_TUMBLE_TURNS,
		"sparks": SquadLines2D.BREAK_SPARKS, "spark_speed": SquadLines2D.BREAK_SPARK_SPEED,
		"spark_secs": SquadLines2D.BREAK_SPARK_SECONDS,
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
	SquadLines2D.BREAK_STRAIN_SECONDS = _saved["strain"]
	SquadLines2D.BREAK_SHATTER_SECONDS = _saved["shatter"]
	SquadLines2D.BREAK_KICK = _saved["kick"]
	SquadLines2D.BREAK_TUMBLE_TURNS = _saved["turns"]
	SquadLines2D.BREAK_SPARKS = _saved["sparks"]
	SquadLines2D.BREAK_SPARK_SPEED = _saved["spark_speed"]
	SquadLines2D.BREAK_SPARK_SECONDS = _saved["spark_secs"]


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


# --- The break (#367 part 2B) --------------------------------------------------------------------

func _break_times(strain: float, shatter: float, sparks: int, spark_secs: float) -> void:
	SquadLines2D.TETHER_INSET = 0.25
	SquadLines2D.ARROW_LENGTH = 0.4
	SquadLines2D.DASHES_PER_TILE = 3
	SquadLines2D.DASH_FILL = 0.55
	SquadLines2D.SHAKE_AMPLITUDE = 0.12
	SquadLines2D.SHAKE_SWINGS = 3.0
	SquadLines2D.BREAK_STRAIN_SECONDS = strain
	SquadLines2D.BREAK_SHATTER_SECONDS = shatter
	SquadLines2D.BREAK_KICK = 0.8
	SquadLines2D.BREAK_TUMBLE_TURNS = 1.0
	SquadLines2D.BREAK_SPARKS = sparks
	SquadLines2D.BREAK_SPARK_SPEED = 2.5
	SquadLines2D.BREAK_SPARK_SECONDS = spark_secs


func _chord() -> PackedVector3Array:
	return PackedVector3Array([_CHORD_MEMBER, _CHORD_LEADER])


# The drawing a break makes `seconds` in, as moment_drawing hands it to both views.
func _break(seconds: float, flash := false) -> Dictionary:
	var entry := {"chord": _chord(), "moment": SquadLines2D.Moment.BREAK, "start_msec": 0, "standing": false}
	return SquadLines2D.moment_drawing(entry, roundi(seconds * 1000.0), flash)


func _middle(piece: Dictionary) -> Vector3:
	var points: PackedVector3Array = piece["points"]
	return (points[0] + points[1]) * 0.5


# Before it snaps a breaking tether is WHOLE and turns steadily toward the strain red, shivering; it
# has no pieces yet.
func test_a_break_strains_red_and_shivers_before_it_snaps() -> void:
	_break_times(0.4, 0.6, 0, 0.3)
	assert_bool(SquadLines2D.TETHER_COLOR.is_equal_approx(SquadLines2D.TETHER_STRAIN_COLOR)) \
			.override_failure_message("fixture: the tether and strain colours are one colour").is_false()
	var red := SquadLines2D.TETHER_STRAIN_COLOR
	var last := INF
	var shivered := false
	for i in 20:
		var drawing := _break(0.4 * float(i) / 20.0, true)
		assert_int((drawing["shaft"] as PackedVector3Array).size()).override_failure_message(
				"a straining tether was not whole").is_greater_equal(2)
		assert_bool((drawing["pieces"] as Array).is_empty()).override_failure_message(
				"the tether shattered before it snapped").is_true()
		var tint: Color = drawing["tint"]
		var to_red := Vector4(tint.r - red.r, tint.g - red.g, tint.b - red.b, tint.a - red.a).length()
		assert_bool(to_red <= last + 0.0001).override_failure_message(
				"the strain turned away from the red").is_true()
		last = to_red
		shivered = shivered or not is_zero_approx(float(drawing["bend"]))
	assert_bool(shivered).override_failure_message("the straining tether never shivered").is_true()


# At the snap the whole shaft becomes PIECES, and they are exactly the dashes on screen then.
func test_at_the_snap_the_pieces_are_the_dashes_on_screen() -> void:
	_break_times(0.4, 0.6, 0, 0.3)
	var drawing := _break(0.4)
	assert_bool((drawing["shaft"] as PackedVector3Array).is_empty()).override_failure_message(
			"the shaft outlived the snap").is_true()
	var m := SquadLines2D.measure(_chord())
	var spans := SquadLines2D.dash_spans(float(m["shaft_end"]), 0.0)
	var pieces: Array = drawing["pieces"]
	assert_int(pieces.size()).override_failure_message("the pieces are not the dashes").is_equal(spans.size())
	for i in spans.size():
		var points: PackedVector3Array = (pieces[i] as Dictionary)["points"]
		assert_vector(points[0]).is_equal_approx(SquadLines2D.point_along(_chord(), spans[i].x),
				Vector3(0.001, 0.001, 0.001))
		assert_vector(points[1]).is_equal_approx(SquadLines2D.point_along(_chord(), spans[i].y),
				Vector3(0.001, 0.001, 0.001))


# The pieces and the arrowhead FALL: only ever downward, landing on the ground under the chord (its
# body-middle height taken back off) as the shatter ends, faded out -- and the moment ends there.
func test_the_pieces_and_the_arrowhead_fall_to_the_ground() -> void:
	_break_times(0.4, 0.6, 0, 0.3)
	var ground := _CHORD_MEMBER.y - SquadLines2D.body_middle_rule()
	var last: Array[float] = []
	var cone_last := INF
	for i in 21:
		var drawing := _break(0.4 + 0.6 * float(i) / 20.0)
		var pieces: Array = drawing["pieces"]
		for p in pieces.size():
			var y := _middle(pieces[p]).y
			if last.size() <= p:
				last.append(INF)
			assert_bool(y <= last[p] + 0.0001).override_failure_message("a piece rose").is_true()
			last[p] = y
		var cone: Dictionary = drawing["cone"]
		assert_bool(cone.is_empty()).override_failure_message(
				"the arrowhead did not fall with the pieces").is_false()
		var cone_y := ((cone["base"] as Vector3) + (cone["tip"] as Vector3)).y * 0.5
		assert_bool(cone_y <= cone_last + 0.0001).override_failure_message("the arrowhead rose").is_true()
		cone_last = cone_y
	var landed := _break(1.0)
	for piece: Dictionary in landed["pieces"]:
		assert_float(_middle(piece).y).override_failure_message("a piece did not land on the ground") \
				.is_equal_approx(ground, 0.001)
		assert_float((piece["tint"] as Color).a).override_failure_message("a landed piece had not faded") \
				.is_equal_approx(0.0, 0.001)
	assert_bool(bool(landed["done"])).override_failure_message("the break outlived its shatter").is_true()
	assert_bool(bool(_break(0.9)["done"])).is_false()


# The sparks start AT the snap and fly out of it; each streak is no longer than the way it has flown;
# and they are gone once their time is up.
func test_the_sparks_fly_out_of_the_snap() -> void:
	_break_times(0.4, 0.6, 6, 0.3)
	var m := SquadLines2D.measure(_chord())
	var snap := SquadLines2D.point_along(_chord(), float(m["shaft_end"]) * 0.5)
	var dashes := SquadLines2D.dash_spans(float(m["shaft_end"]), 0.0).size()
	var early: Array = _break(0.41)["pieces"]
	assert_int(early.size()).override_failure_message("the sparks did not fly").is_equal(dashes + 6)
	for i in range(dashes, early.size()):
		var points: PackedVector3Array = (early[i] as Dictionary)["points"]
		var flown := snap.distance_to(points[1])
		assert_float(flown).override_failure_message("a spark did not start at the snap").is_less(0.1)
		assert_bool(points[0].distance_to(points[1]) <= flown + 0.0001).override_failure_message(
				"a spark's streak was longer than the way it had flown").is_true()
	assert_int((_break(0.4 + 0.31)["pieces"] as Array).size()).override_failure_message(
			"the sparks outlived their time").is_equal(dashes)


# #217: the shiver is motion and the sparks' whitening a flash, so the setting stills both -- and
# nothing else. The tether still reddens, snaps and falls.
func test_the_photosensitivity_setting_stills_the_shiver_and_the_spark_flash_but_not_the_fall() -> void:
	_break_times(0.4, 0.6, 4, 0.3)
	var bent := 0.0
	for i in 20:
		bent = maxf(bent, absf(float(_break(0.4 * float(i) / 20.0, false)["bend"])))
	assert_float(bent).override_failure_message("the tether shivered with the setting on") \
			.is_equal_approx(0.0, 0.0001)
	var lit: Array = _break(0.45, true)["pieces"]
	var still: Array = _break(0.45, false)["pieces"]
	var spark_lit: Color = (lit[lit.size() - 1] as Dictionary)["tint"]
	var spark_still: Color = (still[still.size() - 1] as Dictionary)["tint"]
	assert_float(spark_lit.r + spark_lit.g + spark_lit.b).override_failure_message(
			"the sparks did not whiten without the setting").is_greater(spark_still.r + spark_still.g + spark_still.b)
	var fallen: Array = _break(0.9, false)["pieces"]
	var fresh: Array = _break(0.41, false)["pieces"]
	assert_float(_middle(fallen[0]).y).override_failure_message("the setting stopped the pieces falling") \
			.is_less(_middle(fresh[0]).y)


# The times are the knobs', as ratios: doubling the strain doubles when it snaps, and the break lasts
# its strain plus the longer of its shatter and its sparks.
func test_a_breaks_timing_follows_its_knobs() -> void:
	_break_times(0.4, 0.6, 0, 0.3)
	var first := _snap_time()
	SquadLines2D.BREAK_STRAIN_SECONDS = 0.8
	assert_float(_snap_time()).override_failure_message("the strain ignored its time knob") \
			.is_equal_approx(first * 2.0, 0.02)
	assert_float(SquadLines2D.moment_seconds(SquadLines2D.Moment.BREAK)).is_equal_approx(0.8 + 0.6, 0.0001)
	SquadLines2D.BREAK_SPARK_SECONDS = 1.0
	assert_float(SquadLines2D.moment_seconds(SquadLines2D.Moment.BREAK)).is_equal_approx(0.8 + 1.0, 0.0001)


func _snap_time() -> float:
	for i in 400:
		var t := 2.0 * float(i) / 400.0
		if not (_break(t)["pieces"] as Array).is_empty():
			return t
	return -1.0


# --- An enemy squad's colour (#1109) --------------------------------------------------------------

# An enemy's moment wears the enemy colour: a draw-in starts in it, a break starts in it and still
# strains toward the ONE strain red, and its sparks fly in it. Its standing tether is the same colour,
# and the ghost and strain states do not change with the side. Compared to the statics, never values.
func test_an_enemy_squads_lines_and_moments_wear_the_enemy_colour() -> void:
	_break_times(0.4, 0.6, 4, 0.3)
	var enemy := SquadLines2D.ENEMY_TETHER_COLOR
	var red := SquadLines2D.TETHER_STRAIN_COLOR
	assert_bool(enemy.is_equal_approx(SquadLines2D.TETHER_COLOR) or enemy.is_equal_approx(red)) \
			.override_failure_message("fixture: the enemy colour matches a colour it is told apart from") \
			.is_false()

	var draw_in := SquadLines2D.moment_at(SquadLines2D.Moment.DRAW_IN, _chord(), 0.1, false, false, true)
	assert_bool((draw_in["tint"] as Color).is_equal_approx(enemy)).override_failure_message(
			"an enemy's draw-in did not wear the enemy colour").is_true()

	var entry := {"chord": _chord(), "moment": SquadLines2D.Moment.BREAK, "start_msec": 0,
			"standing": false, "hostile": true}
	var opening: Color = SquadLines2D.moment_drawing(entry, 0, false)["tint"]
	assert_bool(opening.is_equal_approx(enemy)).override_failure_message(
			"an enemy's break did not start in the enemy colour -- moment_drawing lost its side").is_true()
	var late: Color = SquadLines2D.moment_drawing(entry, 390, false)["tint"]
	var to_red := Vector4(late.r - red.r, late.g - red.g, late.b - red.b, late.a - red.a).length()
	var to_enemy := Vector4(late.r - enemy.r, late.g - enemy.g, late.b - enemy.b, late.a - enemy.a).length()
	assert_bool(to_red < to_enemy).override_failure_message(
			"an enemy's break did not strain toward the shared strain red").is_true()
	var spark_in_enemy := false
	for piece: Dictionary in SquadLines2D.moment_drawing(entry, 450, false)["pieces"]:
		var tint: Color = piece["tint"]
		spark_in_enemy = spark_in_enemy or Color(tint, 1.0).is_equal_approx(Color(enemy, 1.0))
	assert_bool(spark_in_enemy).override_failure_message(
			"an enemy's break threw no spark in the enemy colour").is_true()

	assert_bool(SquadLines2D.color_of(SquadLines2D.Strain.SOLID, true).is_equal_approx(enemy)) \
			.override_failure_message("an enemy's standing tether is not the enemy colour").is_true()
	assert_bool(SquadLines2D.color_of(SquadLines2D.Strain.GHOST, true)
			.is_equal_approx(SquadLines2D.TETHER_GHOST_COLOR)).is_true()
	assert_bool(SquadLines2D.color_of(SquadLines2D.Strain.STRAIN, true).is_equal_approx(red)).is_true()
