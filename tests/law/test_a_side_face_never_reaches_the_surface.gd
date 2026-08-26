# THE law #559 rests on: a ground block's SIDE material never reaches the plane its TOP face draws.
#
# A side quad used to run from `up`, the top face's own plane. Adjacent cells' top faces abut there
# exactly, so at every cell border four surfaces met along ONE line -- both neighbours' top faces and
# both blocks' buried sides -- and a pixel centre landing on it could be won by a side. Off-axis
# those wins stagger across scanlines and read as noise; at an axis-aligned yaw a whole row of
# borders lands on one scanline and the noise becomes a brown hairline drawn across the board. The
# camera SNAPS to those yaws (CameraRig3D.align_to_detent, called on the enemy phase), so it is the
# pose the game reaches on its own rather than one you have to go looking for.
#
# What this measures is the PROPERTY, not BoardSpace.SIDE_RIM's value: the rim is free to grow to a
# full texel or shrink toward zero without touching this case, and only a rim of ZERO -- the bug
# itself -- can red it. Pinning the number instead would have locked a tuning decision into a law.
#
# Surface 0 is the ground face plus its rim and surface 1 is the sides plus the bottom, a split the
# generator commits deliberately rather than one inferred from geometry -- so "the side material"
# is a surface index here, not a guess about which triangles point outward.
#
# Read off the COMMITTED meshlib: what ships is what has to hold.
extends GdUnitTestSuite

const MESHLIB_PATH := "res://Scenes/LookDev/lookdev_meshlib.tres"

var _library: MeshLibrary


func before_test() -> void:
	_library = load(MESHLIB_PATH) as MeshLibrary
	assert_object(_library).override_failure_message(
			"the meshlib is missing or unreadable at %s" % MESHLIB_PATH).is_not_null()


# Every GROUND block: the hand-picked Kind blocks and one per tileset tile. Exactly the items
# _block_mesh builds WITH a rim -- a cap is a _form_mesh and a prop passes rim 0, and neither of
# those tiles against a neighbour, which is the whole reason the border tie exists.
func _ground_blocks() -> Array[int]:
	var out: Array[int] = []
	for id: int in _library.get_item_list():
		var item_name := _library.get_item_name(id)
		if item_name.begins_with("tile_") or item_name.ends_with("_block"):
			out.append(id)
	return out


func _max_y(mesh: Mesh, surface: int) -> float:
	var verts: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
	var top := -INF
	for v: Vector3 in verts:
		top = maxf(top, v.y)
	return top


func test_no_ground_block_draws_its_side_material_at_the_surface() -> void:
	var checked := 0
	for id: int in _ground_blocks():
		var item_name := _library.get_item_name(id)
		var mesh := _library.get_item_mesh(id)
		assert_object(mesh).override_failure_message(
				"'%s' has no mesh" % item_name).is_not_null()
		assert_int(mesh.get_surface_count()).override_failure_message(
				"'%s' should carry a top surface and a side surface" % item_name).is_equal(2)
		var surface := _max_y(mesh, 0)
		var side := _max_y(mesh, 1)
		assert_float(side).override_failure_message(
				"'%s' draws its side material up to y=%f, and its surface is at y=%f -- a side " \
				% [item_name, side, surface] + "that reaches the top plane ties with the " \
				+ "NEIGHBOUR's top face along the shared cell border, which is the brown hairline " \
				+ "of #559. It must stop BoardSpace.SIDE_RIM short, with the rim covering the gap"
				).is_less(surface)
		checked += 1
	assert_int(checked).override_failure_message(
			"no ground blocks in the meshlib; the case is vacuous").is_greater(0)
