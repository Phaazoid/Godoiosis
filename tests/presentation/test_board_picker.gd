# BoardPicker (#205): pure ray-walk cases against synthetic column tops (the parallax
# skip, the cliff-side hit, misses), then the seam proven where it lives — the look-dev
# scene, via the unproject round-trip at all four yaw snaps, plus the occlusion case.
# Scene cases assert PROPERTIES (the blocker wins, the aimed cell comes back), never
# tuned camera values — pitch/FOV/zoom stay the dev's knobs and must not redden this.
#
# The PLANE (#231) is a second axis through most of this file: every call states its own
# fallback rect, and `Rect2i()` means columns-only. Cases that assert a MISS say WHY it
# still misses under a real plane — above the ceiling, or outside the apron — because
# "no column here" stopped being a reason on its own.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/LookDev/LookDev.tscn"

# The apron used by the plane cases. Any positive number works; the assertions derive
# their coordinates from the resulting rect rather than restating it.
const APRON := 4

# The synthetic fixtures are stated as rule HEIGHTS and converted through the seam (#427 slice 2).
# They used to be authored as raw tops, which baked "one row is one world unit" into every number —
# so the moment a row became half a level, every ray in this file was aimed somewhere else. The
# rays themselves are world-space and deliberately unchanged: what they cross has to stay put.
const SHORT_HEIGHT := 0
const TOWER_HEIGHT := 2 * Terrain.UNITS_PER_LEVEL
const DIP_HEIGHT := -Terrain.UNITS_PER_LEVEL


# What column_tops_from would report for a column of this height: the row above its top one.
func _top_for(height: int) -> int:
	return BoardSpace.top_row_of(height) + 1


# The cell a hit on such a column comes back as — _top_cell's answer, stated once.
func _cell_at(column: Vector2i, height: int) -> Vector3i:
	return BoardSpace.of_cell(column, BoardSpace.top_row_of(height))


# A short column, a tower two levels taller, a short column, all in row z=0.
var _tower_tops: Dictionary[Vector2i, int] = {
	Vector2i(0, 0): _top_for(SHORT_HEIGHT),
	Vector2i(1, 0): _top_for(TOWER_HEIGHT),
	Vector2i(2, 0): _top_for(SHORT_HEIGHT),
}

# The same strip with (1, 0) ERASED — the shape the dev brush makes in 3D.
var _holed_tops: Dictionary[Vector2i, int] = {
	Vector2i(0, 0): _top_for(SHORT_HEIGHT), Vector2i(2, 0): _top_for(SHORT_HEIGHT),
}

# The same strip with (1, 0) DIPPED one level deep — #260's negative elevation, and the shape a top
# of 0 could not describe while 0 also meant "nothing here". Note it is a different fixture
# from _holed_tops on purpose: a dip and a hole are the two answers the sentinel used to conflate.
var _dipped_tops: Dictionary[Vector2i, int] = {
	Vector2i(0, 0): _top_for(SHORT_HEIGHT),
	Vector2i(1, 0): _top_for(DIP_HEIGHT),
	Vector2i(2, 0): _top_for(SHORT_HEIGHT),
}


# Deeper than the plane by more than a whole level — the depth #582 was authored at, stated through
# the constant so a re-based UNITS_PER_LEVEL cannot quietly float this fixture back up to the floor.
const SUNKEN_HEIGHT := -Terrain.UNITS_PER_LEVEL - 1

# ONE column, sunk, with nothing around it: the lone block the dev painted into open ground. The
# void beside it is inside the apron, so the plane answers there and used to answer FIRST.
var _sunken_tops: Dictionary[Vector2i, int] = {
	Vector2i(0, 0): _top_for(SUNKEN_HEIGHT),
}

# _holed_tops with a sunken column added beyond the hole: the ray meets the HOLE, then solid ground
# at plane level, then the pit — the only order that can tell "held" apart from "deferred". Same
# hole at (1, 0), so the shallow ray the plane cases already use reaches it.
var _hole_then_pit_tops: Dictionary[Vector2i, int] = {
	Vector2i(0, 0): _top_for(SHORT_HEIGHT),
	Vector2i(2, 0): _top_for(SHORT_HEIGHT),
	Vector2i(3, 0): _top_for(SUNKEN_HEIGHT),
}


func _apron_of(tops: Dictionary[Vector2i, int]) -> Rect2i:
	return BoardPicker.used_rect(tops).grow(APRON)


# --- Pure cases (no scene, authored rays) -------------------------------------

func test_straight_down_hits_the_top_face() -> void:
	var cell := BoardPicker.pick_cell(Vector3(0.5, 10.0, 0.5), Vector3.DOWN, _tower_tops, Rect2i())
	assert_that(cell).is_equal(_cell_at(Vector2i(0, 0), SHORT_HEIGHT))


func test_parallax_ray_skips_the_short_column_and_hits_the_tower() -> void:
	# Passes 2.75+ units above the short column, crosses the tower's top plane inside it.
	var cell := BoardPicker.pick_cell(Vector3(-2.5, 5.0, 0.5), Vector3(4.0, -2.0, 0.0), _tower_tops, Rect2i())
	assert_that(cell).is_equal(_cell_at(Vector2i(1, 0), TOWER_HEIGHT))


func test_cliff_side_hit_returns_the_column_top_cell() -> void:
	# Enters the tower's footprint at y 2.2 — below its top at 3 — striking the wall.
	var cell := BoardPicker.pick_cell(Vector3(-0.5, 2.5, 0.5), Vector3(1.0, -0.2, 0.0), _tower_tops, Rect2i())
	assert_that(cell).is_equal(_cell_at(Vector2i(1, 0), TOWER_HEIGHT))


func test_shallow_approach_from_outside_the_board_hits_the_first_column() -> void:
	var cell := BoardPicker.pick_cell(Vector3(-3.5, 1.5, 0.5), Vector3(1.0, -0.15, 0.0), _tower_tops, Rect2i())
	assert_that(cell).is_equal(_cell_at(Vector2i(0, 0), SHORT_HEIGHT))


func test_level_ray_above_everything_misses() -> void:
	# Misses for a GEOMETRIC reason, not for want of a plane: it is level and already
	# above the tallest thing there is. So it must still miss with the apron live.
	var ray_from := Vector3(-1.0, 5.0, 0.5)
	var along := Vector3(1.0, 0.0, 0.0)
	assert_that(BoardPicker.pick_cell(ray_from, along, _tower_tops, Rect2i())).is_equal(BoardSpace.NO_CELL)
	assert_that(BoardPicker.pick_cell(ray_from, along, _tower_tops, _apron_of(_tower_tops))) \
		.override_failure_message("a level ray over the board resolved once a plane existed") \
		.is_equal(BoardSpace.NO_CELL)


func test_descending_ray_beyond_the_board_walks_off_and_misses() -> void:
	var cell := BoardPicker.pick_cell(Vector3(5.0, 2.0, 0.5), Vector3(1.0, -1.0, 0.0), _tower_tops, Rect2i())
	assert_that(cell).is_equal(BoardSpace.NO_CELL)


func test_the_apron_catches_a_ray_that_walks_off_the_board() -> void:
	# The SAME ray as the case above, one input different. Two answers from one
	# difference is the sharpest form this pin comes in.
	var cell := BoardPicker.pick_cell(Vector3(5.0, 2.0, 0.5), Vector3(1.0, -1.0, 0.0),
			_tower_tops, _apron_of(_tower_tops))
	assert_that(cell).is_not_equal(BoardSpace.NO_CELL)
	assert_that(BoardSpace.flat(cell)).is_equal(Vector2i(5, 0))


func test_a_vertical_ray_outside_the_apron_still_misses() -> void:
	# The apron BOUNDS the plane — it is not an infinite floor.
	var plane := _apron_of(_tower_tops)
	assert_bool(plane.has_point(Vector2i(10, 10))) \
		.override_failure_message("the fixture's far cell drifted inside the apron").is_false()
	var cell := BoardPicker.pick_cell(Vector3(10.5, 5.0, 10.5), Vector3.DOWN, _tower_tops, plane)
	assert_that(cell).is_equal(BoardSpace.NO_CELL)


# --- The plane fallback (#231) -------------------------------------------------

func test_an_erased_cell_inside_the_board_is_still_pickable() -> void:
	# The headline: erase a tile in the 3D view and it must not become unreachable.
	var straight_down := Vector3.DOWN
	var over_the_hole := Vector3(1.5, 5.0, 0.5)
	assert_that(BoardPicker.pick_cell(over_the_hole, straight_down, _holed_tops, Rect2i())) \
		.override_failure_message("the fixture's hole is not actually a hole").is_equal(BoardSpace.NO_CELL)
	var cell := BoardPicker.pick_cell(over_the_hole, straight_down, _holed_tops, _apron_of(_holed_tops))
	assert_that(cell).is_equal(_cell_at(Vector2i(1, 0), SHORT_HEIGHT))


func test_the_ground_plane_sits_on_the_top_face_not_the_slab_bottom() -> void:
	# A shallow ray across the hole. At FLAT_TOP_ROW the plane is the face the
	# neighbouring blocks present, so the ray lands IN the hole; at the slab's bottom it
	# would travel a further cell and come down on the far column instead.
	var cell := BoardPicker.pick_cell(Vector3(-1.5, 3.0, 0.5), Vector3(3.0, -2.0, 0.0),
			_holed_tops, _apron_of(_holed_tops))
	assert_that(cell).is_equal(_cell_at(Vector2i(1, 0), SHORT_HEIGHT))
	assert_int(cell.y).override_failure_message("the plane cell came back at the wrong row") \
		.is_equal(BoardSpace.top_row_of(SHORT_HEIGHT))


func test_a_real_column_beats_the_plane_at_the_same_ray() -> void:
	# Ray order, not a hand-written comparison: resolving the plane before the walk
	# would let a hole in front of the tower answer instead of the tower.
	var ray_from := Vector3(-2.5, 5.0, 0.5)
	var along := Vector3(4.0, -2.0, 0.0)
	var columns_only := BoardPicker.pick_cell(ray_from, along, _tower_tops, Rect2i())
	assert_that(columns_only).override_failure_message("the case proves nothing — the ray misses").is_not_equal(BoardSpace.NO_CELL)
	assert_that(BoardPicker.pick_cell(ray_from, along, _tower_tops, _apron_of(_tower_tops))) \
		.override_failure_message("the plane stole a ray that strikes a real column") \
		.is_equal(columns_only)


func test_the_apron_bounds_where_the_plane_ends() -> void:
	# Derived from the rect, never from numbers — the apron is a knob.
	var plane := _apron_of(_tower_tops)
	var inside := plane.end - Vector2i.ONE
	var outside := plane.end
	var hit := BoardPicker.pick_cell(Vector3(inside.x + 0.5, 5.0, inside.y + 0.5), Vector3.DOWN, _tower_tops, plane)
	assert_that(hit).is_equal(_cell_at(inside, SHORT_HEIGHT))
	var miss := BoardPicker.pick_cell(Vector3(outside.x + 0.5, 5.0, outside.y + 0.5), Vector3.DOWN, _tower_tops, plane)
	assert_that(miss).is_equal(BoardSpace.NO_CELL)


func test_an_empty_board_is_still_pickable_under_a_plane() -> void:
	# Erase everything and you must be able to paint it back — so "no columns at all"
	# cannot short-circuit while a plane exists.
	var empty: Dictionary[Vector2i, int] = {}
	var plane := Rect2i(0, 0, 4, 4)
	var cell := BoardPicker.pick_cell(Vector3(1.5, 5.0, 1.5), Vector3.DOWN, empty, plane)
	assert_that(cell).is_equal(_cell_at(Vector2i(1, 1), SHORT_HEIGHT))
	assert_that(BoardPicker.pick_cell(Vector3(1.5, 5.0, 1.5), Vector3.DOWN, empty, Rect2i())) \
		.is_equal(BoardSpace.NO_CELL)


func test_used_rect_and_max_top_describe_the_tops_table() -> void:
	# The bbox battle3d._board_volume used to derive for itself.
	assert_that(BoardPicker.used_rect(_tower_tops)).is_equal(Rect2i(0, 0, 3, 1))
	assert_bool(BoardPicker.used_rect(_tower_tops).has_point(Vector2i(2, 0))) \
		.override_failure_message("used_rect excluded its own highest column").is_true()
	assert_int(BoardPicker.max_top(_tower_tops)).is_equal(_top_for(TOWER_HEIGHT))
	var empty: Dictionary[Vector2i, int] = {}
	assert_that(BoardPicker.used_rect(empty)).is_equal(Rect2i())
	assert_int(BoardPicker.max_top(empty)).is_equal(0)


# --- A dip is a column, not a miss (#294) --------------------------------------
#
# Level 0 used to be BOTH a legitimate top (a cell one deep: it occupies [-1..0], so its surface
# sits at 0) and the "no column here" answer, which made a dip unrepresentable by construction.
# NO_COLUMN is the separation; these are the cases that can tell the two apart.

func test_a_one_deep_dip_is_a_column_and_not_a_hole() -> void:
	# Columns only, so no plane can answer on the dip's behalf — a top of 0 has to stand alone.
	var cell := BoardPicker.pick_cell(Vector3(1.5, 10.0, 0.5), Vector3.DOWN, _dipped_tops, Rect2i())
	assert_that(cell).is_equal(_cell_at(Vector2i(1, 0), DIP_HEIGHT))


func test_a_dip_inside_the_plane_reads_as_the_dip_and_not_as_flat() -> void:
	# The dev-authoring case, and the one that fails PLAUSIBLY rather than loudly: with the column
	# missing from the table, _top_level falls through to the plane's FLAT_TOP_ROW and the click
	# resolves one level too high. A wrong cell, not a miss — so the brush paints the wrong thing.
	var cell := BoardPicker.pick_cell(Vector3(1.5, 10.0, 0.5), Vector3.DOWN, _dipped_tops,
			_apron_of(_dipped_tops))
	assert_that(cell).is_equal(_cell_at(Vector2i(1, 0), DIP_HEIGHT))
	assert_int(cell.y).override_failure_message(
			"the dip resolved at its flat neighbours' level") \
		.is_equal(BoardSpace.top_row_of(DIP_HEIGHT))
	assert_int(BoardSpace.top_row_of(DIP_HEIGHT)).override_failure_message(
			"the dip fixture stopped being below its neighbours; the case is vacuous") \
		.is_less(BoardSpace.top_row_of(SHORT_HEIGHT))


# --- The plane is a FLOOR, not a lid (#582) ------------------------------------

func test_a_column_below_the_plane_is_visible_through_it() -> void:
	# The headline. The apron's floor is INVISIBLE, so it must not hide a block that is drawn:
	# a cell painted more than a level down used to pick as the void in front of it, which made it
	# unpaintable, unerasable and unselectable at once.
	var surface := BoardSpace.surface_y(BoardSpace.top_row_of(SUNKEN_HEIGHT))
	var aim := Vector3(0.5, surface, 0.5)
	var along := Vector3(2.0, -2.0, 0.0)
	var plane := _apron_of(_sunken_tops)
	var origin := aim - along.normalized() * 10.0

	# Non-vacuity, and the whole mechanism in one line: the ray crosses the plane's own height
	# SOMEWHERE ELSE, so under the old rule that column answered and this one never got asked.
	assert_that(BoardSpace.flat(BoardPicker.pick_on_plane(origin, along, BoardSpace.FLAT_TOP_ROW, plane))) \
		.override_failure_message("the ray meets the plane inside the sunken column; nothing occludes") \
		.is_not_equal(Vector2i(0, 0))

	assert_that(BoardPicker.pick_cell(origin, along, _sunken_tops, plane)) \
		.override_failure_message("the invisible floor answered in front of a block you can see") \
		.is_equal(_cell_at(Vector2i(0, 0), SUNKEN_HEIGHT))


func test_ground_at_plane_level_blocks_and_the_held_hole_stands() -> void:
	# The other side of the same rule, and the one that keeps #231: a held plane hit may only be
	# beaten by a column BELOW the floor. Solid ground at floor level really does block, so the
	# hole the ray entered first is the answer — never a pit further down the same ray.
	var plane := _apron_of(_hole_then_pit_tops)
	var cell := BoardPicker.pick_cell(Vector3(-1.5, 3.0, 0.5), Vector3(3.0, -2.0, 0.0),
			_hole_then_pit_tops, plane)
	assert_that(cell).override_failure_message(
			"the hole lost its ray — to the ground that blocks, or to the pit past it") \
		.is_equal(_cell_at(Vector2i(1, 0), SHORT_HEIGHT))
	assert_bool(_hole_then_pit_tops.has(Vector2i(1, 0))).override_failure_message(
			"the fixture's hole stopped being a hole; the case is vacuous").is_false()
	assert_bool(_hole_then_pit_tops.has(Vector2i(2, 0))).override_failure_message(
			"nothing blocks between the hole and the pit; the case is vacuous").is_true()


func test_pick_on_plane_answers_the_crossing_column_and_not_the_blocker() -> void:
	# The brush's aim (#582). Nothing can hide behind a plane — pick_on_plane takes no `tops` at
	# all — so the tower this very ray strikes cannot change the answer. That is what lets the brush
	# author a one-cell well the camera has no line into.
	var origin := Vector3(-2.5, 5.0, 0.5)
	var along := Vector3(4.0, -2.0, 0.0)
	var row := BoardSpace.top_row_of(SUNKEN_HEIGHT) + 1
	# The case states its own rect rather than borrowing the board's apron: a ray travels while it
	# descends, so a crossing this far down lands well outside a board-sized one — which is the
	# neighbouring case's point, not this one's.
	var reach := _apron_of(_tower_tops).grow(APRON * 4)

	var aimed := BoardPicker.pick_on_plane(origin, along, row, reach)
	assert_that(aimed).override_failure_message("the aim fell outside its own rect") \
		.is_not_equal(BoardSpace.NO_CELL)
	assert_int(aimed.y).override_failure_message("the aimed cell came back at the wrong row") \
		.is_equal(BoardSpace.top_row_of(SUNKEN_HEIGHT))

	var struck := BoardPicker.pick_cell(origin, along, _tower_tops, reach)
	assert_that(struck).override_failure_message("the ray strikes nothing; the case is vacuous") \
		.is_not_equal(BoardSpace.NO_CELL)
	assert_that(aimed).override_failure_message("the aim came back as the blocker the walk found") \
		.is_not_equal(struck)


func test_pick_on_plane_misses_outside_the_authoring_rect_and_behind_the_camera() -> void:
	# The rect stays the caller's policy, exactly as pick_cell has it — and a plane the ray is
	# travelling AWAY from is a miss, not a hit at a negative distance.
	var plane := _apron_of(_tower_tops)
	var outside := plane.end
	assert_that(BoardPicker.pick_on_plane(Vector3(outside.x + 0.5, 5.0, outside.y + 0.5),
			Vector3.DOWN, BoardSpace.FLAT_TOP_ROW, plane)).is_equal(BoardSpace.NO_CELL)
	assert_that(BoardPicker.pick_on_plane(Vector3(0.5, 5.0, 0.5), Vector3.UP,
			BoardSpace.FLAT_TOP_ROW, plane)).is_equal(BoardSpace.NO_CELL)
	assert_that(BoardPicker.pick_on_plane(Vector3(0.5, 5.0, 0.5), Vector3(1.0, 0.0, 0.0),
			BoardSpace.FLAT_TOP_ROW, plane)).is_equal(BoardSpace.NO_CELL)


func test_a_ray_clearing_the_rim_strikes_the_dips_own_cell() -> void:
	# The walk's hit test at h == 0, reached the way a real camera reaches it: over the near rim
	# (both ends above the neighbours' top, so they do not answer) and down through the dip's
	# surface. Skipping the column entirely walks the ray on to the FAR rim, which is a wrong
	# answer rather than a miss.
	var cell := BoardPicker.pick_cell(Vector3(0.0, 3.2, 0.5), Vector3(1.0, -2.0, 0.0),
			_dipped_tops, Rect2i())
	assert_that(cell).is_equal(_cell_at(Vector2i(1, 0), DIP_HEIGHT))


# --- The seam where it lives: the look-dev scene -------------------------------

var _scene: Node3D


func before_test() -> void:
	_scene = (load(SCENE_PATH) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(_scene)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_scene)
	_scene.free()


func test_column_tops_read_the_painted_board() -> void:
	var board := _scene.get_node("Board") as GridMap
	var tops := BoardPicker.column_tops_from(board)
	assert_int(tops[Vector2i(0, 0)]).is_equal(1)   # plain
	assert_int(tops[Vector2i(8, 3)]).is_equal(3)   # plateau
	assert_int(tops[Vector2i(3, 10)]).is_equal(2)  # stone platform
	assert_int(tops[Vector2i(5, 3)]).is_equal(2)   # ramp counts as a full block (stage-1 approximation)


func test_used_rect_spans_the_painted_boards_own_footprint() -> void:
	# Independent spelling: derive the expected rect from the GridMap's cells directly.
	var board := _scene.get_node("Board") as GridMap
	var lo := Vector2i(2147483647, 2147483647)
	var hi := Vector2i(-2147483648, -2147483648)
	for cell: Vector3i in board.get_used_cells():
		lo = lo.min(BoardSpace.flat(cell))
		hi = hi.max(BoardSpace.flat(cell))
	assert_bool(lo.x <= hi.x).override_failure_message("the look-dev board is empty").is_true()
	assert_that(BoardPicker.used_rect(BoardPicker.column_tops_from(board))) \
		.is_equal(Rect2i(lo, hi - lo + Vector2i.ONE))


func test_unproject_round_trip_finds_the_cell_at_every_yaw_snap() -> void:
	var board := _scene.get_node("Board") as GridMap
	var rig := _scene.get_node("CameraRig") as Node3D
	var camera := _scene.get_node("CameraRig/Pitch/Camera") as Camera3D
	var tops := BoardPicker.column_tops_from(board)
	# A plain cell clear of the hill, and the plateau's own top: both visible from all sides.
	var cells: Array[Vector3i] = [Vector3i(2, 0, 6), Vector3i(8, 2, 3)]
	for yaw: float in [0.0, 90.0, 180.0, 270.0]:
		rig.rotation_degrees = Vector3(0.0, yaw, 0.0)
		rig._target_yaw_degrees = yaw  # keep the rig's smoothing from fighting the pose
		await await_idle_frame()
		for cell in cells:
			var aim := BoardSpace.standing_point(cell) + Vector3(0.0, -0.02, 0.0)
			var screen := camera.unproject_position(aim)
			var picked := BoardPicker.pick_cell(
					camera.project_ray_origin(screen), camera.project_ray_normal(screen), tops, Rect2i())
			assert_that(picked).is_equal(cell)


func test_pick_at_is_the_ray_pair_spelled_once() -> void:
	# Delegation equality against a live camera — and not vacuously, on a real hit.
	# Both sides pass Rect2i(), so the plane cannot make this pass for a new reason.
	var board := _scene.get_node("Board") as GridMap
	var camera := _scene.get_node("CameraRig/Pitch/Camera") as Camera3D
	var tops := BoardPicker.column_tops_from(board)
	var screen := camera.unproject_position(BoardSpace.standing_point(Vector3i(8, 2, 3)) + Vector3(0.0, -0.02, 0.0))
	var direct := BoardPicker.pick_cell(
			camera.project_ray_origin(screen), camera.project_ray_normal(screen), tops, Rect2i())
	assert_that(direct).is_not_equal(BoardSpace.NO_CELL)
	assert_that(BoardPicker.pick_at(camera, screen, tops, Rect2i())).is_equal(direct)


func test_pick_at_height_is_the_ray_pair_spelled_once() -> void:
	# pick_at's twin, and the same reason it exists (#222): a caller building the origin/normal
	# pair by hand is the copy these convenience wrappers are here to stop.
	var board := _scene.get_node("Board") as GridMap
	var camera := _scene.get_node("CameraRig/Pitch/Camera") as Camera3D
	var plane := BoardPicker.used_rect(BoardPicker.column_tops_from(board)).grow(APRON)
	var screen := camera.unproject_position(BoardSpace.standing_point(Vector3i(8, 2, 3)))
	var direct := BoardPicker.pick_on_plane(camera.project_ray_origin(screen),
			camera.project_ray_normal(screen), BoardSpace.FLAT_TOP_ROW, plane)
	assert_that(direct).is_not_equal(BoardSpace.NO_CELL)
	assert_that(BoardPicker.pick_at_height(camera, screen, BoardSpace.FLAT_TOP_ROW, plane)) \
		.is_equal(direct)


func test_occluded_cell_yields_the_blocker_not_the_hidden_cell() -> void:
	# From the default camera (south, pitched down), ground cell (8, 0, 0) hides behind
	# the 3-tall hill. Aiming at its standing point must pick a hill cell instead —
	# asserted as a property (the blocker wins), not an exact cell, so camera tuning
	# can't redden it. The Rect2i() pass keeps the not-a-miss clause non-vacuous.
	var board := _scene.get_node("Board") as GridMap
	var camera := _scene.get_node("CameraRig/Pitch/Camera") as Camera3D
	var tops := BoardPicker.column_tops_from(board)
	var hidden := Vector3i(8, 0, 0)
	var screen := camera.unproject_position(BoardSpace.standing_point(hidden))
	var picked := BoardPicker.pick_cell(
			camera.project_ray_origin(screen), camera.project_ray_normal(screen), tops, Rect2i())
	assert_that(picked).is_not_equal(hidden)
	assert_that(picked).is_not_equal(BoardSpace.NO_CELL)
	assert_bool(picked.y >= 1).is_true()                      # a raised cell took the ray
	assert_bool(picked.x >= 6 and picked.x <= 10).is_true()   # inside the hill's footprint
	assert_bool(picked.z >= 1 and picked.z <= 5).is_true()
	# And the blocker still wins with the apron live — the case a plane-first walk fails.
	assert_that(BoardPicker.pick_cell(
			camera.project_ray_origin(screen), camera.project_ray_normal(screen), tops,
			BoardPicker.used_rect(tops).grow(APRON))).is_equal(picked)


# --- The two adapters, against a real GridMap (#294) ---------------------------

# One cell written at `level` in a column clear of everything the board already holds. The
# column is DERIVED from the board's own footprint and the item id read off a real cell, so
# nothing authored is named or asserted — and the scene is instantiated per test and freed
# after, so nothing authored is mutated either.
func _dip_a_fresh_column(board: GridMap, level: int) -> Vector2i:
	var used := board.get_used_cells()
	assert_bool(used.is_empty()).override_failure_message(
			"the look-dev board is empty, so writing beside it proves nothing").is_false()
	var column := BoardPicker.used_rect(BoardPicker.column_tops_from(board)).end + Vector2i(2, 2)
	board.set_cell_item(BoardSpace.of_cell(column, level), board.get_cell_item(used[0]))
	return column


func test_column_tops_from_reads_a_column_that_dips_below_zero() -> void:
	# A cell at y = -1 tops out at 0, which is a real surface. The accumulator seeded at 0 and
	# compared with `>` dropped exactly the columns whose top IS 0, and only those.
	var board := _scene.get_node("Board") as GridMap
	var column := _dip_a_fresh_column(board, -1)
	var tops := BoardPicker.column_tops_from(board)
	assert_bool(tops.has(column)).override_failure_message(
			"the dipped column is missing from the tops table").is_true()
	assert_int(tops[column]).is_equal(0)


func test_top_of_answers_a_dip_and_keeps_no_column_a_separate_answer() -> void:
	# The incremental twin (#319) carried the same sentinel, and its caller ERASES on it — so a
	# dip painted onto an already-dipped board was actively removed, not merely never added.
	# The pair is the claim: a real top of 0 and "nothing here" must not be the same int.
	var board := _scene.get_node("Board") as GridMap
	var column := _dip_a_fresh_column(board, -1)
	assert_int(BoardPicker.top_of(board, column, -1)).override_failure_message(
			"a column one cell deep read as no column at all").is_equal(0)
	assert_int(BoardPicker.top_of(board, column + Vector2i(1, 0), -1)).override_failure_message(
			"an empty column stopped saying it was empty").is_equal(BoardPicker.NO_COLUMN)
