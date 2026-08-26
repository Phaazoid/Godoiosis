# THE claim that lets a cap stay an OPEN shell, now that back faces are culled (#559).
#
# #496 deleted the cap's bottom quad: it sat in the block-top plane, which already belongs to the
# block _write_column writes underneath, so the pair fought -- and being down-facing it lost to
# nothing and won as a hole. What replaced it was an argument rather than geometry: *the cap's
# opening is exactly the footprint that block's top face covers, so there is no angle the inside can
# be seen from.*
#
# That argument was written while _mat() drew both sides of everything, so an exposed opening would
# merely have shown the cap's own inside surface. With CULL_BACK it would show the SKY THROUGH THE
# BOARD instead. The claim went from true-and-comfortable to load-bearing, so it gets a law.
#
# The law is the argument, stated geometrically: every BOUNDARY edge -- an edge with only one
# triangle on it, i.e. the rim of the opening -- lies in the block-top plane and inside the cell.
# Both halves matter. Off that plane, the opening looks somewhere the block below does not cover;
# outside the footprint, it overhangs the block that is supposed to close it.
#
# It also asserts the cap IS open. Without that the case passes vacuously the moment someone puts
# the bottom quad back -- a mesh with no boundary trivially has no boundary off-plane -- and putting
# it back is precisely the #496 regression. A law that cannot fail on the change it exists to catch
# is not a law.
#
# A skipped wall is not a hole: _form_mesh declines a wall whose two corners both sit ON the floor,
# and the top-surface edge left exposed there is already at the floor, so it lands on this same
# plane. One rule covers both.
extends GdUnitTestSuite

const MESHLIB_PATH := "res://Scenes/LookDev/lookdev_meshlib.tres"

# A cap sits on the row above its cell's surface, so its own floor is that row's floor -- the
# generator's `lo`, and the plane the block below tops out at.
const FLOOR := -BoardSpace.ROW_HEIGHT * 0.5

# Slack for a float that has been through a mesh save. Far tighter than any real feature.
const EPSILON := 0.0005

var _library: MeshLibrary


func before_test() -> void:
	_library = load(MESHLIB_PATH) as MeshLibrary
	assert_object(_library).override_failure_message(
			"the meshlib is missing or unreadable at %s" % MESHLIB_PATH).is_not_null()


# Everything _form_mesh built: caps, wedges and their per-tile variants. Named as the COMPLEMENT of
# the families that are not caps, so a new cap shape joins the law by existing rather than by
# somebody remembering to add its prefix here.
func _caps() -> Array[int]:
	var out: Array[int] = []
	for id: int in _library.get_item_list():
		var item_name := _library.get_item_name(id)
		if item_name.begins_with("tile_") or item_name.begins_with("prop_"):
			continue
		if item_name.ends_with("_block") or item_name == BoardMirror.RAMP_FILL_ITEM_NAME:
			continue
		out.append(id)
	return out


func _point_key(v: Vector3) -> String:
	return "%.4f|%.4f|%.4f" % [v.x, v.y, v.z]


func _edge_key(a: Vector3, b: Vector3) -> String:
	var first := _point_key(a)
	var second := _point_key(b)
	if first < second:
		return first + ">" + second
	return second + ">" + first


func _triangles(mesh: Mesh, surface: int) -> Array:
	var arrays := mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
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


func test_every_cap_opens_only_onto_the_block_beneath_it() -> void:
	var checked := 0
	for id: int in _caps():
		var item_name := _library.get_item_name(id)
		var mesh := _library.get_item_mesh(id)
		if mesh == null or mesh.get_surface_count() == 0:
			continue   # ramp_fill and its kin draw nothing; there is no shell to reason about
		var counts: Dictionary[String, int] = {}
		var ends: Dictionary[String, Array] = {}
		for surface in mesh.get_surface_count():
			for tri: Array in _triangles(mesh, surface):
				for k in 3:
					var a: Vector3 = tri[k]
					var b: Vector3 = tri[(k + 1) % 3]
					var key := _edge_key(a, b)
					counts[key] = counts.get(key, 0) + 1
					ends[key] = [a, b]
		var boundary := 0
		var stray := 0
		for key: String in counts:
			if counts[key] != 1:
				continue
			boundary += 1
			for v: Vector3 in ends[key]:
				if absf(v.y - FLOOR) > EPSILON or absf(v.x) > 0.5 + EPSILON \
						or absf(v.z) > 0.5 + EPSILON:
					stray += 1
					break
		assert_int(boundary).override_failure_message(
				"'%s' is a CLOSED shell. A cap draws nothing in its own floor plane -- that plane " \
				% item_name + "belongs to the block underneath, and #496 deleted the bottom quad " \
				+ "because the two fought. Closing it again brings that back").is_greater(0)
		assert_int(stray).override_failure_message(
				"'%s' has %d of %d boundary edge(s) off the block-top plane or outside the cell. " \
				% [item_name, stray, boundary] + "The cap is an open shell, and the only thing " \
				+ "closing it is the block below -- an opening it does not cover is a hole " \
				+ "straight through the board now that back faces are culled").is_equal(0)
		checked += 1
	assert_int(checked).override_failure_message(
			"no caps in the meshlib; the case is vacuous").is_greater(0)
