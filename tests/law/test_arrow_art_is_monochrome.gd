extends GdUnitTestSuite

# THE TRAIL ART MUST STAY GREYSCALE, or every arrow colour knob silently lies (2026-08-21).
#
# `modulate` MULTIPLIES. The 14 path segments shipped cyan (112-136 red against 208-248 green/blue),
# so dialling the shove knob to yellow zeroed the blue channel and drew GREEN -- found in play, not
# by any test. The same fact meant a "white" planned move had always rendered cyan, and the knob's
# RGB never matched what the board showed.
#
# Desaturating the art is what makes OverlayManager's four arrow tints mean what they say, so this
# is a law rather than a one-off fix: re-colour these PNGs and the tuning surface breaks again, the
# same way, invisibly. It asserts the PROPERTY (r == g == b) and never a specific grey -- the shading
# ramp is art, and pinning its values would be the content razor's exact mistake.
#
# ERROR.png is deliberately NOT here. It has a second consumer, GridUtils.ERROR_ICON, which draws it
# UNTINTED as the unknown-terrain marker -- greyscaling it would turn a red diagnostic into a white
# square. Same for nomove.png, a queue-row icon that never lands on a trail.
#
# Delete this suite when real (coloured) arrow art arrives -- at that point the tints stop being
# tunable and that is a design decision, not a regression.

# Reached through OverlayManager's own consts, never by re-typing res:// paths: it is the one answer
# to "which textures does a trail draw", so a renamed file breaks the build rather than this test.
func _trail_textures() -> Dictionary:
	return {
		"horizontal": OverlayManager.PATH_HORIZONTAL,
		"vertical": OverlayManager.PATH_VERTICAL,
		"up_right": OverlayManager.PATH_UP_RIGHT,
		"up_left": OverlayManager.PATH_UP_LEFT,
		"down_right": OverlayManager.PATH_DOWN_RIGHT,
		"down_left": OverlayManager.PATH_DOWN_LEFT,
		"start_right": OverlayManager.PATH_START_RIGHT,
		"start_left": OverlayManager.PATH_START_LEFT,
		"start_up": OverlayManager.PATH_START_UP,
		"start_down": OverlayManager.PATH_START_DOWN,
		"arrow_right": OverlayManager.PATH_ARROW_RIGHT,
		"arrow_left": OverlayManager.PATH_ARROW_LEFT,
		"arrow_up": OverlayManager.PATH_ARROW_UP,
		"arrow_down": OverlayManager.PATH_ARROW_DOWN,
	}


func test_every_trail_segment_is_greyscale() -> void:
	var checked := 0
	for name: String in _trail_textures():
		var texture: Texture2D = _trail_textures()[name]
		assert_object(texture).override_failure_message(
				"%s did not load at all" % name).is_not_null()
		var image := texture.get_image()
		assert_object(image).override_failure_message(
				"%s has no readable Image -- if this is an import-format problem rather than a real "
				% name + "regression, delete this suite rather than weakening it").is_not_null()
		# ONE assertion per texture, not per pixel: a re-coloured 16x16 sprite has ~200 offending
		# pixels and gdUnit4 reports every failed assertion, so the per-pixel form buried the answer
		# under thousands of identical lines. The worst offender carries the report.
		var worst := 0.0
		var worst_at := ""
		for y in image.get_height():
			for x in image.get_width():
				var p := image.get_pixel(x, y)
				if p.a <= 0.0:
					continue
				checked += 1
				# A tolerance, not equality: an imported texture round-trips through 8-bit, so an
				# exact float compare would trip on the last bit.
				var spread: float = maxf(p.r, maxf(p.g, p.b)) - minf(p.r, minf(p.g, p.b))
				if spread > worst:
					worst = spread
					worst_at = "(%d,%d) rgb %.3f/%.3f/%.3f" % [x, y, p.r, p.g, p.b]
		assert_float(worst).override_failure_message(
				"%s is not greyscale -- worst pixel %s. Every arrow colour knob multiplies against "
				% [name, worst_at]
				+ "this art, so a hue here silently rewrites the colour the dev dialled in."
				).is_less(0.01)

	# Non-vacuity: get_image() returning a blank or zero-sized Image would pass every loop above
	# without executing one comparison.
	assert_bool(checked > 0).override_failure_message(
			"read zero opaque pixels across 14 textures -- the assertion never ran").is_true()


func test_the_brightest_segment_pixel_is_full_white() -> void:
	# The tool's real promise: what you dial is what you get. That only holds if the art peaks at
	# white, since anything darker scales the knob's colour down before it reaches the screen.
	var peak := 0.0
	for name: String in _trail_textures():
		var image: Image = (_trail_textures()[name] as Texture2D).get_image()
		for y in image.get_height():
			for x in image.get_width():
				var p := image.get_pixel(x, y)
				if p.a > 0.0:
					peak = maxf(peak, p.r)
	assert_float(peak).override_failure_message(
			"the brightest trail pixel is %.3f, not 1.0 -- an arrow tint can never reach the "
			% peak + "colour the knob names").is_equal_approx(1.0, 0.01)
