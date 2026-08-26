# THE law that makes back-face culling safe on a ground block (#559): the shell has no holes.
#
# _mat() draws BACK faces no longer. Under the old CULL_DISABLED an opening in a mesh merely showed
# its own inside surface -- opaque, slightly odd, harmless. With culling on, a ray entering an
# opening passes the far wall from behind, gets culled, and leaves: you see THROUGH the board. So
# "is this mesh closed" stopped being a tidiness question and became a rendering guarantee.
#
# It also guards the rim specifically. The rim exists to cover the band left when the side faces
# dropped out of the top plane, and a rim that covered three edges of four would look perfect from
# most angles and open a hairline hole on the fourth -- the exact failure mode that is hardest to
# catch by looking. An edge count is blind to how convincing the render is.
#
# Counted by POSITION rather than by vertex index: SurfaceTool commits these unindexed, so the two
# triangles either side of a seam hold distinct vertices that happen to sit at the same point. The
# quantisation is coarse enough to weld those and far finer than any real feature -- the rim itself
# is 0.004 and the grid is 1.0.
extends GdUnitTestSuite

const MESHLIB_PATH := "res://Scenes/LookDev/lookdev_meshlib.tres"

var _library: MeshLibrary


func before_test() -> void:
	_library = load(MESHLIB_PATH) as MeshLibrary
	assert_object(_library).override_failure_message(
			"the meshlib is missing or unreadable at %s" % MESHLIB_PATH).is_not_null()


func _ground_blocks() -> Array[int]:
	var out: Array[int] = []
	for id: int in _library.get_item_list():
		var item_name := _library.get_item_name(id)
		if item_name.begins_with("tile_") or item_name.ends_with("_block"):
			out.append(id)
	return out


func _point_key(v: Vector3) -> String:
	return "%.4f|%.4f|%.4f" % [v.x, v.y, v.z]


# An edge, named the same from either triangle that owns it.
func _edge_key(a: Vector3, b: Vector3) -> String:
	var first := _point_key(a)
	var second := _point_key(b)
	if first < second:
		return first + ">" + second
	return second + ">" + first


func _triangles(mesh: Mesh, surface: int) -> Array:
	var arrays := mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# An unindexed surface stores NIL in that slot rather than an empty array.
	var index_slot: Variant = arrays[Mesh.ARRAY_INDEX]
	var indices := PackedInt32Array() if index_slot == null else index_slot as PackedInt32Array
	var out := []
	if indices.is_empty():
		for i in range(0, verts.size(), 3):
			out.append([verts[i], verts[i + 1], verts[i + 2]])
		return out
	for i in range(0, indices.size(), 3):
		out.append([verts[indices[i]], verts[indices[i + 1]], verts[indices[i + 2]]])
	return out


func test_every_ground_block_encloses_a_solid() -> void:
	var checked := 0
	for id: int in _ground_blocks():
		var item_name := _library.get_item_name(id)
		var mesh := _library.get_item_mesh(id)
		var counts: Dictionary[String, int] = {}
		# Both surfaces together: the shell is only closed where the rim's lower edge meets the
		# side's upper one, and those live on opposite surfaces.
		for surface in mesh.get_surface_count():
			for tri: Array in _triangles(mesh, surface):
				for k in 3:
					var key := _edge_key(tri[k], tri[(k + 1) % 3])
					counts[key] = counts.get(key, 0) + 1
		var open_edges := 0
		for key: String in counts:
			if counts[key] != 2:
				open_edges += 1
		assert_int(open_edges).override_failure_message(
				"'%s' has %d edge(s) not shared by exactly two triangles -- an open shell, which " \
				% [item_name, open_edges] + "with CULL_BACK renders as a hole straight through " \
				+ "the board rather than as its own inside face").is_equal(0)
		checked += 1
	assert_int(checked).override_failure_message(
			"no ground blocks in the meshlib; the case is vacuous").is_greater(0)
