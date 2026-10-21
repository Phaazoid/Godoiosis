# Every gas has a look (#508), and room in the shaders that draw it (#1324). GasLook.for_kind falls back
# to a blank look with a push_error when a kind's file is missing, so a new Gas.Kind added without its
# .tres would draw as steam-white and pass every other test. This is where that reds instead.
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


# Every per-kind uniform array holds every kind (#1324): GasMirror fills them from Gas.Kind.size(), and
# an array shorter than that is a fault no headless run can see -- nothing here renders. Read off the
# shader source, entries per kind declared beside each name.
const PER_KIND_UNIFORMS := {
	"res://Classes/presentation/gas_puff.gdshader": {"boil_seconds": 1, "bob": 1, "sway": 1},
	"res://Classes/presentation/gas_floor.gdshader": {"palettes": 4, "patterns": 1},
}


func test_every_per_kind_shader_array_holds_every_kind() -> void:
	var sized := RegEx.create_from_string("uniform\\s+\\w+\\s+(\\w+)\\[(\\d+)\\]")
	for path: String in PER_KIND_UNIFORMS:
		var source := FileAccess.get_file_as_string(path)
		var found := {}
		for m: RegExMatch in sized.search_all(source):
			found[m.get_string(1)] = int(m.get_string(2))
		var wanted: Dictionary = PER_KIND_UNIFORMS[path]
		for uniform: String in wanted:
			assert_bool(found.has(uniform)).override_failure_message(
				"%s no longer declares %s as a sized array" % [path, uniform]).is_true()
			var need: int = Gas.Kind.size() * int(wanted[uniform])
			assert_int(int(found.get(uniform, 0))).override_failure_message("%s's %s holds %d, and %d kinds need %d"
				% [path, uniform, int(found.get(uniform, 0)), Gas.Kind.size(), need]).is_greater_equal(need)


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
