# Every gas has a look (#508). GasLook.for_kind falls back to a blank look with a push_error when a
# kind's file is missing, so a seventh Gas.Kind added without its .tres would draw as steam-white and
# pass every other test. This is where that reds instead.
extends GdUnitTestSuite


func test_every_kind_has_its_own_look_file() -> void:
	for kind: Gas.Kind in Gas.Kind.values():
		var path := GasLook.FOLDER + Gas.name_of(kind) + ".tres"
		assert_bool(ResourceLoader.exists(path)).override_failure_message(
			"Gas.Kind.%s has no look at %s" % [Gas.name_of(kind), path]).is_true()
		assert_object(load(path) as GasLook).override_failure_message(
			"%s is not a GasLook" % path).is_not_null()


func test_every_look_carries_a_four_tone_palette_and_a_known_shape() -> void:
	for kind: Gas.Kind in Gas.Kind.values():
		var look := GasLook.for_kind(kind)
		assert_int(look.palette().size()).is_equal(4)
		assert_bool(GasPuffArt.SIZES.has(look.puff_shape)).override_failure_message(
			"%s's puff shape has no sizes to draw at" % Gas.name_of(kind)).is_true()
		var frames := GasPuffArt.extra_frames(look.extra, look.palette())
		assert_int(frames.size()).override_failure_message(
			"%s's extra draws no frames" % Gas.name_of(kind)).is_greater(0)
		assert_int(GasPuffArt.EXTRA_BASE + frames.size()).override_failure_message(
			"%s's extra has more frames than its stride holds" % Gas.name_of(kind)).is_less_equal(GasPuffArt.STRIDE)


func test_every_drawing_fits_the_shared_canvas() -> void:
	for kind: Gas.Kind in Gas.Kind.values():
		var look := GasLook.for_kind(kind)
		for size: Vector2i in GasPuffArt.SIZES[look.puff_shape]:
			assert_bool(size.x <= GasPuffArt.LAYER_SIZE.x and size.y <= GasPuffArt.LAYER_SIZE.y) \
				.override_failure_message("a %s puff of %s overflows the %s canvas"
					% [Gas.name_of(kind), size, GasPuffArt.LAYER_SIZE]).is_true()
		for frame in GasPuffArt.extra_frames(look.extra, look.palette()):
			assert_bool(frame.get_width() <= GasPuffArt.LAYER_SIZE.x and frame.get_height() <= GasPuffArt.LAYER_SIZE.y) \
				.is_true()
