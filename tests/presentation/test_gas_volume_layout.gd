# GasVolumeEffect (#508): the half of the gas volume a headless run CAN check. The compute passes need
# a RenderingDevice the suite does not have, so nothing here proves the volume draws; what it pins is
# the CPU's side of the contract with gas_volume.glsl -- that the uniform block is laid out the way
# the shader declares it, and which pixels a frame dispatches over.
extends GdUnitTestSuite

const SHADER := "res://Classes/presentation/gas_volume.glsl"


# The Frame block's size as the SHADER spells it: every member of `uniform Frame { ... } frame;`,
# a mat4 sixteen floats, a vec4 four, an array N of them. Read off the source so the two sides of
# the contract are counted independently.
func _shader_frame_floats() -> int:
	var f := FileAccess.open(SHADER, FileAccess.READ)
	assert_object(f).override_failure_message("could not read %s" % SHADER).is_not_null()
	var text := f.get_as_text()
	f.close()
	var start := text.find("uniform Frame {")
	var end := text.find("} frame;")
	assert_bool(start >= 0 and end > start).override_failure_message(
		"no Frame block in %s -- this law would count nothing" % SHADER).is_true()
	var total := 0
	var member := RegEx.create_from_string("^\\s*(mat4|vec4)\\s+\\w+(?:\\[(\\d+)\\])?\\s*;")
	for line in text.substr(start, end - start).split("\n"):
		var m := member.search(line)
		if m == null:
			continue
		var each := 16 if m.get_string(1) == "mat4" else 4
		total += each * (int(m.get_string(2)) if m.get_string(2) != "" else 1)
	return total


func _params() -> GasVolumeEffect.Params:
	var p := GasVolumeEffect.Params.new()
	p.board_rect = Vector4(1, 2, 3, 4)
	p.kind_count = 6
	p.region_count = 5
	p.march3 = Vector4(10, 1.7, 0.03, 0.25)
	p.stage = Vector4(0, 40, 0, 1)
	p.lamps = [Vector4(7, 8, 9, 3)]
	p.lamp_colors = [Vector4(0.5, 0.25, 0.125, 0)]
	p.flashes = [Vector4(11, 12, 13, 0.75)]
	return p


func _floats(bytes: PackedByteArray) -> PackedFloat32Array:
	return bytes.to_float32_array()


func test_the_frame_block_is_the_size_the_shader_declares() -> void:
	var declared := _shader_frame_floats()
	assert_int(GasVolumeEffect.FRAME_FLOATS).override_failure_message(
		"GasVolumeEffect.FRAME_FLOATS says %d floats, gas_volume.glsl's Frame block holds %d"
			% [GasVolumeEffect.FRAME_FLOATS, declared]).is_equal(declared)
	var bytes := GasVolumeEffect.frame_bytes(Projection.IDENTITY, Transform3D.IDENTITY, Vector2i(1920, 1080), 2,
		Vector2i.ZERO, Vector2i.ZERO, _params())
	assert_int(bytes.size()).is_equal(declared * 4)


func test_every_member_lands_where_the_shader_reads_it() -> void:
	var cam := Transform3D(Basis.IDENTITY, Vector3(5, 6, 7))
	var f := _floats(GasVolumeEffect.frame_bytes(Projection.IDENTITY, cam, Vector2i(1920, 1080), 2,
		Vector2i(100, 200), Vector2i(49, 99), _params()))
	# camera_to_world's origin column is the second matrix's last.
	assert_array([f[28], f[29], f[30], f[31]]).is_equal([5.0, 6.0, 7.0, 1.0])
	assert_array([f[32], f[33], f[34], f[35]]).is_equal([1920.0, 1080.0, 2.0, 0.0])     # raster
	assert_array([f[36], f[37], f[38], f[39]]).is_equal([100.0, 200.0, 49.0, 99.0])     # screen_rect
	assert_array([f[40], f[41], f[42], f[43]]).is_equal([1.0, 2.0, 3.0, 4.0])           # board_rect
	assert_float(f[55]).is_equal(5.0)                                                    # ambient.w: regions
	assert_float(f[71]).is_equal(0.25)                                                   # march3.w: cloud strength
	assert_array([f[76], f[77], f[78]]).is_equal([1.0, 1.0, 6.0])                       # counts
	assert_array([f[80], f[81], f[82], f[83]]).is_equal([0.0, 40.0, 0.0, 1.0])          # stage
	assert_array([f[84], f[85], f[86], f[87]]).is_equal([7.0, 8.0, 9.0, 3.0])           # lamps[0]
	assert_array([f[116], f[117], f[118]]).is_equal([0.5, 0.25, 0.125])                # lamp_colors[0]
	assert_array([f[148], f[149], f[150], f[151]]).is_equal([11.0, 12.0, 13.0, 0.75])   # flashes[0]


func test_more_lamps_than_the_shader_holds_are_dropped_not_overflowed() -> void:
	var p := _params()
	for i in GasVolumeEffect.MAX_LAMPS + 3:
		p.lamps.append(Vector4(i, i, i, 1))
		p.lamp_colors.append(Vector4.ONE)
	var bytes := GasVolumeEffect.frame_bytes(Projection.IDENTITY, Transform3D.IDENTITY, Vector2i(64, 64), 1,
		Vector2i.ZERO, Vector2i.ZERO, p)
	assert_int(bytes.size()).is_equal(GasVolumeEffect.FRAME_FLOATS * 4)
	assert_float(_floats(bytes)[76]).is_equal(float(GasVolumeEffect.MAX_LAMPS))


func test_a_whole_screen_dispatches_every_pixel_and_every_texel() -> void:
	var rects := GasVolumeEffect.dispatch_rects(Rect2(0, 0, 1, 1), Vector2i(1920, 1080), 2)
	assert_that(rects[0]).is_equal(Rect2i(0, 0, 1920, 1080))
	assert_that(rects[1]).is_equal(Rect2i(0, 0, 960, 540))


func test_the_march_rect_is_grown_a_texel_past_the_pixels_it_feeds() -> void:
	# The upsample reads the four texels around a pixel, so a texel this frame did not write must
	# never be one of them.
	var rects := GasVolumeEffect.dispatch_rects(Rect2(0.25, 0.25, 0.5, 0.5), Vector2i(1920, 1080), 4)
	var pixels: Rect2i = rects[0]
	var texels: Rect2i = rects[1]
	assert_that(pixels).is_equal(Rect2i(480, 270, 960, 540))
	for corner: Vector2i in [pixels.position, pixels.end - Vector2i.ONE]:
		var tap := Vector2i(((Vector2(corner) + Vector2(0.5, 0.5)) / 4.0 - Vector2(0.5, 0.5)).floor())
		for o: Vector2i in [Vector2i(0, 0), Vector2i(1, 1)]:
			assert_bool(texels.has_point(tap + o)).override_failure_message(
				"pixel %s reads texel %s, outside the march rect %s" % [corner, tap + o, texels]).is_true()


func test_gas_off_screen_dispatches_nothing() -> void:
	assert_array(GasVolumeEffect.dispatch_rects(Rect2(), Vector2i(1920, 1080), 2)).is_empty()
