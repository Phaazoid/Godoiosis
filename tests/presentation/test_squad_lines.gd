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
		"photo": PlayerSettings.is_on(PlayerSettings.Setting.PHOTOSENSITIVITY),
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
	PlayerSettings.set_on(PlayerSettings.Setting.PHOTOSENSITIVITY, _saved["photo"])


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
	ThreatLines2D.CONE_LENGTH = 0.4
	var member := Vector3(0.5, 1.0, 0.5)
	var leader := Vector3(3.5, 1.0, 0.5)
	var strokes := SquadLines2D.tether(PackedVector3Array([member, leader]))

	assert_int(strokes.size()).override_failure_message("the tether has no arrowhead").is_equal(2)
	assert_that(strokes[0][0]).override_failure_message(
			"the tether does not start at the member").is_equal(member)
	var cone := ThreatLines2D.cone_of(strokes)
	assert_bool(cone.is_empty()).override_failure_message("the arrowhead is not a cone").is_false()
	var tip: Vector3 = cone["tip"]
	var base: Vector3 = cone["base"]
	assert_float(tip.distance_to(leader)).override_failure_message(
			"the arrowhead's tip is not inset from the leader").is_equal_approx(0.25, 0.0001)
	assert_bool(tip.distance_to(leader) < base.distance_to(leader)).override_failure_message(
			"the arrowhead points at the MEMBER").is_true()
	assert_int(strokes[0].size()).override_failure_message(
			"the shaft is two points, so the pluck cannot bend it").is_greater(2)


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
