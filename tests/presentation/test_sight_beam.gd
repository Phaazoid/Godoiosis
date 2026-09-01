# The sight beam's RIBBON (#506): the geometry set_line emits and the wire from each shape knob to
# the shader that reads it. The beam replaced a 1-px ImmediateMesh line strip, which Godot draws at
# one screen pixel however close the camera gets -- so what is asserted here is the SHAPE of the
# mesh and the liveness of each knob, never a width, a colour or a glow, all of which are the dev's
# to tune (the no-pinning law).
#
# Fixture is a bare BoardOverlays rather than LookDev.tscn: none of this needs a board, and the
# scene costs a 5 MB mesh library per case (#621).
#
# What CANNOT be checked headless, stated rather than faked: the ribbon's camera-facing expansion
# happens in the vertex shader, so nothing here proves it looks right at any given camera angle.
# The shader is proven to PARSE (a deliberate syntax error reds this suite's load), and the mesh it
# is handed is proven correct; the picture is the dev's feel check.
extends GdUnitTestSuite

var _overlays: BoardOverlays


func before_test() -> void:
	_overlays = BoardOverlays.new()
	get_tree().root.add_child(_overlays)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_overlays)
	_overlays.free()
	# gdUnit4 reads a detached-then-freed node as an orphan without a flush frame (#93/#114).
	await await_idle_frame()


func _beam_node() -> MeshInstance3D:
	var pool: Array = _overlays._markers.get(BoardOverlays.Layer.SIGHT_TRACE, [])
	assert_int(pool.size()).override_failure_message("no beam was built").is_greater(0)
	return pool[0] as MeshInstance3D


func _beam_mesh() -> ImmediateMesh:
	return _beam_node().mesh as ImmediateMesh


func _beam_material() -> ShaderMaterial:
	return _beam_node().material_override as ShaderMaterial


# A straight three-point trace, the shape Reach.sight_trace emits for a flat shot.
func _draw_straight() -> void:
	_overlays.set_line(BoardOverlays.Layer.SIGHT_TRACE, PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0),
	]), Color(1, 1, 1, 0.9))


# --- The mesh -----------------------------------------------------------------------

func test_the_beam_is_a_triangle_strip_and_not_a_line_strip() -> void:
	# The whole point of the ticket: a LINE_STRIP is drawn at one screen pixel by the engine and no
	# amount of tuning widens it. ImmediateMesh has no surface_get_primitive_type (that is
	# ArrayMesh's), so the read goes through the RenderingServer, which does answer for one.
	_draw_straight()
	var surface: Dictionary = RenderingServer.mesh_get_surface(_beam_mesh().get_rid(), 0)
	assert_int(surface["primitive"]).is_equal(Mesh.PRIMITIVE_TRIANGLE_STRIP)


func test_every_centreline_point_is_emitted_twice_carrying_both_side_flags() -> void:
	# The ribbon's two edges are the SAME point twice, pushed apart by the shader -- so the mesh
	# stores 2N vertices for N centreline points, and each pair differs only in UV.y.
	var points := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)])
	_overlays.set_line(BoardOverlays.Layer.SIGHT_TRACE, points, Color.WHITE)

	var arrays: Array = _beam_mesh().surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_int(verts.size()).is_equal(points.size() * 2)
	assert_int(uvs.size()).is_equal(points.size() * 2)
	for i in points.size():
		assert_vector(verts[i * 2]).is_equal(points[i])
		assert_vector(verts[i * 2 + 1]).is_equal(points[i])
		assert_float(uvs[i * 2].y).is_equal(0.0)
		assert_float(uvs[i * 2 + 1].y).is_equal(1.0)


func test_a_bend_takes_the_average_of_its_two_segments_rather_than_either_one() -> void:
	# A lob's arc bends at every sample. Taking one segment's direction at a joint points the two
	# sides of the ribbon differently on either side of it, which splits the strip open; the
	# average is what closes it. Endpoints have one segment and use it unchanged.
	_overlays.set_line(BoardOverlays.Layer.SIGHT_TRACE, PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1),
	]), Color.WHITE)

	var normals: PackedVector3Array = _beam_mesh().surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var into := Vector3(1, 0, 0)
	var out_of := Vector3(0, 0, 1)
	assert_vector(normals[0]).is_equal_approx(into, Vector3.ONE * 0.001)
	assert_vector(normals[5]).is_equal_approx(out_of, Vector3.ONE * 0.001)
	# The joint, on both of its vertices.
	var averaged := (into + out_of).normalized()
	assert_vector(normals[2]).is_equal_approx(averaged, Vector3.ONE * 0.001)
	assert_vector(normals[3]).is_equal_approx(averaged, Vector3.ONE * 0.001)


func test_a_trace_with_no_points_hides_the_beam_and_does_not_reach_the_material() -> void:
	# The clear path (exiting an aim) runs through set_line with an empty array, which returns
	# before the material is touched -- so this also pins that clearing cannot fail on the cast.
	_draw_straight()
	assert_bool(_beam_node().visible).is_true()
	_overlays.clear(BoardOverlays.Layer.SIGHT_TRACE)
	assert_bool(_beam_node().visible).is_false()


func test_the_beam_is_lifted_out_of_its_own_frustum_cull() -> void:
	# The mesh's AABB is the CENTRELINE; the shader draws outside it. Without a cull margin a beam
	# whose centreline leaves the frustum pops out while its visible width is still on screen.
	_draw_straight()
	assert_float(_beam_node().extra_cull_margin).is_greater(0.0)


# --- The knobs ----------------------------------------------------------------------

func test_the_beam_takes_the_verdict_colour_it_is_handed() -> void:
	# The colour is per DRAW, not per layer -- OverlayMirror passes the clear/blocked tint it copied
	# from SightTrace2D. Asserted as "what was handed over arrived", never against a value.
	var verdict := Color(0.25, 0.5, 0.75, 0.8)
	_overlays.set_line(BoardOverlays.Layer.SIGHT_TRACE, PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0),
	]), verdict)
	assert_that(_beam_material().get_shader_parameter("beam_color")).is_equal(verdict)


func test_a_shape_knob_reaches_the_shader_and_not_merely_the_export() -> void:
	# The wire, not the two ends. Reading the export back would pass against a setter that never
	# pushed anything, which is exactly the born-dead slider the knob rule exists to prevent.
	_draw_straight()
	var material := _beam_material()
	_overlays.beam_width = 0.25
	_overlays.beam_softness = 3.0
	_overlays.beam_intensity = 4.0
	assert_float(material.get_shader_parameter("beam_width")).is_equal(0.25)
	assert_float(material.get_shader_parameter("beam_softness")).is_equal(3.0)
	assert_float(material.get_shader_parameter("beam_intensity")).is_equal(4.0)


func test_width_is_the_only_thing_the_offset_is_made_of() -> void:
	# The beam shipped once as huge flaring wedges no knob could shrink, because the offset also
	# carried a screen-pixel FLOOR derived from view depth over PROJECTION_MATRIX * VIEWPORT_SIZE --
	# builtins this suite has no way to read, in a stage it has no way to run. That term dominated
	# the max() at every setting the panel could reach.
	#
	# What a headless test CAN hold is that the shader takes no such input any more: the offset is
	# beam_width and nothing else, so no camera, projection or viewport value can widen it. A
	# uniform this suite does not know about is exactly how the floor got back in last time.
	# COMMENTS ARE STRIPPED FIRST, and that is not fussiness: the shader's own note explains this
	# bug by NAMING the builtins it must not use, so a raw scan reds on the explanation of why it
	# is correct. A law over source text has to read the code and not the prose about it.
	var code := _shader_code_without_comments()
	for banned in ["VIEWPORT_SIZE", "beam_min_pixels"]:
		assert_bool(code.contains(banned)).override_failure_message(
			("sight_beam.gdshader names %s again -- the beam's width must not depend on a "
			+ "screen-space builtin, see the render_mode note") % banned).is_false()
	# The one legitimate PROJECTION_MATRIX use is the final clip transform, never a width term.
	assert_int(code.count("PROJECTION_MATRIX")).override_failure_message(
		"PROJECTION_MATRIX should appear once, projecting POSITION").is_equal(1)


func _shader_code_without_comments() -> String:
	var kept := PackedStringArray()
	for line in (load(BoardOverlays.SIGHT_BEAM_SHADER_PATH) as Shader).code.split("\n"):
		var body: String = line.split("//")[0]
		if not body.strip_edges().is_empty():
			kept.append(body)
	return "\n".join(kept)


func test_a_knob_written_before_any_beam_exists_still_reaches_the_first_one() -> void:
	# The ordering hole: the LINE pool is built lazily by the first set_line, so a knob written
	# before an aim was ever hovered has no material to push to. _make_line must apply the current
	# values as it builds, or the first beam comes up wearing the shader's defaults instead.
	_overlays.beam_width = 0.31
	_draw_straight()
	assert_float(_beam_material().get_shader_parameter("beam_width")).is_equal(0.31)


func test_the_verdict_colours_are_writable_so_a_knob_has_something_to_write() -> void:
	# They were `const` before #506, which a GameKnobs CLASS_KNOBS row cannot write at all. Both
	# views read these two, which is what keeps the flat line and the diorama's beam agreeing about
	# what "blocked" looks like.
	var clear_before := SightTrace2D.CLEAR_COLOR
	var blocked_before := SightTrace2D.BLOCKED_COLOR
	SightTrace2D.CLEAR_COLOR = Color(0.1, 0.2, 0.3, 0.4)
	SightTrace2D.BLOCKED_COLOR = Color(0.5, 0.6, 0.7, 0.8)
	assert_that(SightTrace2D.CLEAR_COLOR).is_equal(Color(0.1, 0.2, 0.3, 0.4))
	assert_that(SightTrace2D.BLOCKED_COLOR).is_equal(Color(0.5, 0.6, 0.7, 0.8))
	SightTrace2D.CLEAR_COLOR = clear_before
	SightTrace2D.BLOCKED_COLOR = blocked_before
