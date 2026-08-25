# THE law #427 slice 3 rests on: the cap a cell is DRAWN as and the surface the game QUERIES are the
# same surface.
#
# A quad with four independent corner heights is not planar, so a cap is two triangles and which
# diagonal splits them is real geometry rather than a tie-break. Terrain.height_at_uv picks the
# diagonal joining the two EQUAL corners, giving every legal form a flat half and a sloped half; take
# the other diagonal and an outer corner becomes a hip roof. BOTH triangulations meet all four
# corners, so nothing at a corner can tell them apart -- only a point INSIDE can.
#
# If the mesh and the query disagreed, a unit crossing a corner cell would float over or sink into it
# by up to a QUARTER of the climb, which is half a level on a steep corner. The generator therefore
# calls height_at_uv rather than reimplementing its rule, and this law is what keeps that true: it
# samples each drawn triangle at its own CENTROID, which is the one place a wrong diagonal shows.
#
# Read off the COMMITTED artifact, not a freshly built mesh -- what ships is what must agree.
extends GdUnitTestSuite

const MESHLIB_PATH := "res://Scenes/LookDev/lookdev_meshlib.tres"

# A cap sits on the row directly above its cell's surface, so its own floor is that row's floor --
# the generator's `lo`, and the zero every corner height is measured up from.
const FLOOR := -BoardSpace.ROW_HEIGHT * 0.5

var _library: MeshLibrary


func before_test() -> void:
	_library = load(MESHLIB_PATH) as MeshLibrary


func _item_named(name: String) -> int:
	for id: int in _library.get_item_list():
		if _library.get_item_name(id) == name:
			return id
	return -1


func _generic_cap(climb: int, form: Terrain.Form) -> Mesh:
	var stem: String = BoardMirror.RAMP_ITEM_NAMES[climb]
	var item_name := stem if form == Terrain.Form.WEDGE \
			else "%s_%s" % [stem, BoardMirror.form_suffix(form)]
	var id := _item_named(item_name)
	assert_int(id).override_failure_message(
			"the meshlib has no item called '%s' -- the generator and the mirror disagree about "
			% item_name + "how a cap is named, so every cell of this shape draws the fallback"
			).is_not_equal(-1)
	return _library.get_item_mesh(id)


# The cap's TOP surface, as triangles. Surface 0 is the one the generator commits with the ground
# material and surface 1 is the walls plus the floor, so the split is structural rather than guessed
# from geometry -- which matters, because the floor quad's own winding computes to an UPWARD normal
# and a "which way does this triangle face" filter silently sampled it.
func _surface_triangles(mesh: Mesh) -> Array:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# An unindexed surface stores NIL in that slot rather than an empty array, so the typed local
	# cannot take it straight.
	var index_slot: Variant = arrays[Mesh.ARRAY_INDEX]
	var indices := PackedInt32Array() if index_slot == null else index_slot as PackedInt32Array
	var triangles := []
	if indices.is_empty():
		for i in range(0, verts.size(), 3):
			triangles.append([verts[i], verts[i + 1], verts[i + 2]])
		return triangles
	for i in range(0, indices.size(), 3):
		triangles.append([verts[indices[i]], verts[indices[i + 1]], verts[indices[i + 2]]])
	return triangles


func test_every_generic_cap_is_the_surface_the_rules_query() -> void:
	for climb in [1, Terrain.UNITS_PER_LEVEL]:
		for form: Terrain.Form in [Terrain.Form.WEDGE, Terrain.Form.OUTER, Terrain.Form.INNER]:
			var corners := Terrain.corners_of_form(0, Terrain.CANONICAL_MASKS[form], climb)
			var sampled := 0
			for triangle in _surface_triangles(_generic_cap(climb, form)):
				var a: Vector3 = triangle[0]
				var b: Vector3 = triangle[1]
				var c: Vector3 = triangle[2]
				sampled += 1
				# The triangle's OWN centre, which is the point a wrong diagonal misplaces. A cap
				# built on the other diagonal still meets all four corners, so sampling those would
				# pass either way.
				var centre := (a + b + c) / 3.0
				var want := FLOOR + Terrain.height_at_uv(corners, centre.x + 0.5, centre.z + 0.5) \
						* BoardSpace.ROW_HEIGHT
				assert_float(centre.y).override_failure_message(
						"%s at climb %d: the drawn cap is %s high at the centre of one of its own "
						% [BoardMirror.form_suffix(form), climb, centre.y]
						+ "triangles and Terrain.height_at_uv says %s -- the mesh and the query are "
						% want + "split on different diagonals, so a unit crossing this cell floats"
						).is_equal_approx(want, 0.001)
			# TWO triangles for a wedge and an inner corner, ONE for an outer. A cap draws only what
			# rises ABOVE the block it caps, and an outer corner is the single form with a triangle
			# lying entirely on the floor -- that half of its surface is the block's own top face,
			# and drawing it as well is the z-fight this count exists to keep fixed.
			var drawn := 1 if form == Terrain.Form.OUTER else 2
			assert_int(sampled).override_failure_message(
					"%s at climb %d drew %d surface triangles, not %d, so this case sampled the "
					% [BoardMirror.form_suffix(form), climb, sampled, drawn]
					+ "wrong amount of the cap").is_equal(drawn)


func test_a_cap_reaches_exactly_the_corner_heights_it_names() -> void:
	# The other half, and the one the centroid check cannot make: a mesh split on the right diagonal
	# but built to the wrong heights would agree with the query at every centroid of ITS OWN
	# triangles while sitting at the wrong altitude entirely.
	for climb in [1, Terrain.UNITS_PER_LEVEL]:
		for form: Terrain.Form in [Terrain.Form.WEDGE, Terrain.Form.OUTER, Terrain.Form.INNER]:
			var mesh := _generic_cap(climb, form)
			var lowest := INF
			var highest := -INF
			for vertex in mesh.get_faces():
				lowest = minf(lowest, vertex.y)
				highest = maxf(highest, vertex.y)
			assert_float(lowest).override_failure_message(
					"%s at climb %d does not reach its row's floor, so the column shows a gap under "
					% [BoardMirror.form_suffix(form), climb] + "the cap").is_equal_approx(FLOOR, 0.001)
			assert_float(highest).override_failure_message(
					"%s at climb %d tops out at %s, not the %d units it climbs"
					% [BoardMirror.form_suffix(form), climb, highest, climb]).is_equal_approx(
					FLOOR + float(climb) * BoardSpace.ROW_HEIGHT, 0.001)


func test_no_cap_draws_ground_on_its_own_floor() -> void:
	# The z-fight, as a law. A cap sits on a column whose top BLOCK reaches exactly the cell's
	# surface, so the cap's floor plane already has an upward-facing, grass-textured face on it. An
	# OUTER corner is the one form whose surface has a whole triangle down there -- three corners at
	# the low height -- and drawing it made two coplanar textures fight for every such cell. He
	# reported it as z-fighting "on the ground half of half corner tiles", which is exactly that
	# triangle.
	#
	# Read off the SHIPPED library, so a generator fixed without regenerating still reds.
	for climb in [1, Terrain.UNITS_PER_LEVEL]:
		for form: Terrain.Form in [Terrain.Form.WEDGE, Terrain.Form.OUTER, Terrain.Form.INNER]:
			for triangle in _surface_triangles(_generic_cap(climb, form)):
				var lowest: float = minf(minf(triangle[0].y, triangle[1].y), triangle[2].y)
				var highest: float = maxf(maxf(triangle[0].y, triangle[1].y), triangle[2].y)
				assert_bool(is_equal_approx(lowest, FLOOR) and is_equal_approx(highest, FLOOR)) \
					.override_failure_message(
						"%s at climb %d draws a ground triangle flat on its own floor, coplanar "
						% [BoardMirror.form_suffix(form), climb]
						+ "with the top face of the block underneath it").is_false()


func test_an_inner_corner_keeps_the_flat_triangle_it_carries_up_top() -> void:
	# The other side of the rule above, and the reason it is written as "on its own FLOOR" rather
	# than "flat": an inner corner's flat half is at its HIGH plane, where nothing else is drawn, so
	# it must survive. A guard widened to skip every horizontal triangle would punch a hole through
	# three quarters of every inner corner and pass the case above.
	for climb in [1, Terrain.UNITS_PER_LEVEL]:
		var top := FLOOR + float(climb) * BoardSpace.ROW_HEIGHT
		var flat := 0
		for triangle in _surface_triangles(_generic_cap(climb, Terrain.Form.INNER)):
			if is_equal_approx(triangle[0].y, top) and is_equal_approx(triangle[1].y, top) \
					and is_equal_approx(triangle[2].y, top):
				flat += 1
		assert_int(flat).override_failure_message(
				"the inner corner at climb %d lost the flat triangle at its high side, so its "
				% climb + "raised quarter is now a hole").is_equal(1)


func test_the_two_corner_families_are_complements_at_the_same_orientation() -> void:
	# Why eight corner forms cost two meshes: the GridMap's yaw supplies each shape's four rotations,
	# and BoardMirror measures that yaw from the AUTHORED orientation. Outer and inner must therefore
	# be cut facing the same way, or one family lands rotated by a quarter turn everywhere.
	#
	# Their uphills point the same way exactly when their raised sets are complements -- which is what
	# CANONICAL_MASKS declares and this reads back.
	var outer: int = Terrain.CANONICAL_MASKS[Terrain.Form.OUTER]
	var inner: int = Terrain.CANONICAL_MASKS[Terrain.Form.INNER]
	assert_int(outer & inner).override_failure_message(
			"the authored outer and inner caps share a raised corner, so they are not complements"
			).is_equal(outer)

	var outer_uphill := Terrain.gradient_of_corners(Terrain.corners_of_form(0, outer)).normalized()
	var inner_uphill := Terrain.gradient_of_corners(Terrain.corners_of_form(0, inner)).normalized()
	assert_float(outer_uphill.dot(inner_uphill)).override_failure_message(
			"the authored outer and inner caps climb in different directions, so one family will be "
			+ "yawed a quarter turn wrong on every cell").is_equal_approx(1.0, 0.001)
