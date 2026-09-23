# A single-target swing's paths on the SHAPE PLATE (#1057 part 2, #1054 ruling 30): one line per path
# over the yellow tiles, a ring where it starts, a BEAD on every tile it stops on, the arrowhead on the
# last, and each path in its own DARK colour. PathLines.lines() is the whole model, so every case here
# asserts the drawing's geometry rather than a pixel; the last block drives the real plate.
#
# Centres are handed in on a plain square lattice (PITCH apart), which is what the plate's grid lays
# out -- the model reads centres, never the grid, so it is asserted on its own.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")

const PITCH := 20.0
const PALETTE := PlayerSettings.Setting.AIM_PALETTE


func before_test() -> void:
	PlayerSettings.reset_for_test()


func after_test() -> void:
	PlayerSettings.reset_for_test()


func _centres(half := 4) -> Dictionary:
	var out: Dictionary = {}
	for y in range(-half, half + 1):
		for x in range(-half, half + 1):
			out[Vector2i(x, y)] = Vector2(x, y) * PITCH
	return out


func _path(cells: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(cells)
	return out


func _lines(paths: Array[Array], centres := _centres()) -> Array[PathLines.Line]:
	return PathLines.lines(paths, centres, PITCH, OverlayManager.aim_fill_color())


# Is any of `points` within half a pitch of `cell`'s centre?
func _near(points: PackedVector2Array, cell: Vector2i) -> bool:
	for point in points:
		if point.distance_to(Vector2(cell) * PITCH) < PITCH * 0.5:
			return true
	return false


# ==============================================================================
#  The model
# ==============================================================================

# A straight path: a ring on its first tile, a bead on every tile between, the head past the last.
func test_a_path_has_a_ring_a_bead_per_stop_and_a_head_on_the_last() -> void:
	var four := _path([Vector2i(0, -1), Vector2i(0, -2), Vector2i(0, -3), Vector2i(0, -4)])
	var lines := _lines([four] as Array[Array])
	assert_int(lines.size()).is_equal(1)
	var line := lines[0]
	assert_bool(line.ring.distance_to(Vector2(0, -1) * PITCH) < PITCH * 0.5).is_true()
	assert_int(line.beads.size()).is_equal(2)
	assert_bool(_near(line.beads, Vector2i(0, -2))).is_true()
	assert_bool(_near(line.beads, Vector2i(0, -3))).is_true()
	assert_int(line.head.size()).is_equal(3)
	assert_float(line.head[0].y).is_less(Vector2(0, -4).y * PITCH)   # the tip runs on past the last stop


# THE point of a bead per stop (dev: "some way to indicate that a line is stopping on each tile"): a
# tile the path JUMPS over gets none, so the jump shows where one straight line would not.
func test_a_jumped_tile_gets_no_bead() -> void:
	var jump := _path([Vector2i(0, -1), Vector2i(0, -3), Vector2i(1, -3)])
	var line := _lines([jump] as Array[Array])[0]
	assert_int(line.beads.size()).is_equal(1)
	assert_bool(_near(line.beads, Vector2i(0, -3))).is_true()
	assert_bool(_near(line.beads, Vector2i(0, -2))).override_failure_message(
			"the jumped tile wears a bead, so the plate says the path stops there").is_false()


# An out-and-back swings round its far tile, so it reads as a line going and a line coming back.
func test_an_out_and_back_reads_as_two_lines() -> void:
	var back := _path([Vector2i(0, -1), Vector2i(0, -2), Vector2i(0, -1)])
	var line := _lines([back] as Array[Array])[0]
	assert_int(line.beads.size()).is_equal(1)
	var sides: Dictionary = {}
	for point in line.shaft:
		if absf(point.y - (-1 * PITCH)) < PITCH * 0.5:
			sides[signf(point.x)] = true
	assert_bool(sides.has(1.0) and sides.has(-1.0)).override_failure_message(
			"the way out and the way back share one lane, so the return is invisible").is_true()


# A one-tile path is its ring alone -- there is no travel to point a head along.
func test_a_one_tile_path_is_a_ring() -> void:
	var line := _lines([_path([Vector2i(0, -1)])] as Array[Array])[0]
	assert_int(line.head.size()).is_equal(0)
	assert_int(line.beads.size()).is_equal(0)


# A path that runs off the plate is drawn as far as its tiles are on it.
func test_a_path_is_drawn_only_as_far_as_the_plate_reaches() -> void:
	var long := _path([Vector2i(0, -1), Vector2i(0, -2), Vector2i(0, -3)])
	var line := _lines([long] as Array[Array], _centres(2))[0]
	assert_int(line.beads.size()).is_equal(0)   # (0,-2) is now the LAST stop drawn, so it carries the head
	assert_int(line.head.size()).is_equal(3)


# ==============================================================================
#  The colours
# ==============================================================================

# Each path its own colour, from the dark palette -- the editor's hue pushed dark enough to read on
# the tiles it is drawn over.
func test_each_path_wears_its_own_dark_colour() -> void:
	var footprint := OverlayManager.aim_fill_color()
	var paths: Array[Array] = []
	for i in PathPalette.HUES.size():
		paths.append(_path([Vector2i(i - 3, -1), Vector2i(i - 3, -2)]))
	var lines := PathLines.lines(paths, _centres(), PITCH, footprint)
	var seen: Dictionary = {}
	for i in lines.size():
		assert_that(lines[i].colour).is_equal(PathPalette.dark(i, footprint))
		seen[lines[i].colour] = true
	assert_int(seen.size()).override_failure_message(
			"two paths share a colour, so the plate cannot tell them apart").is_equal(PathPalette.HUES.size())


# The floor holds against the footprint the plate is ACTUALLY painted, under every aim palette -- the
# colour-blind palette's footprint is not the default yellow.
func test_every_dark_colour_reads_on_the_footprint_under_every_palette() -> void:
	for palette: int in PlayerSettings.AimPalette.values():
		PlayerSettings.set_choice(PALETTE, palette)
		var footprint := OverlayManager.aim_fill_color()
		for i in PathPalette.HUES.size():
			var ratio := PathPalette.contrast(PathPalette.dark(i, footprint), footprint)
			assert_float(ratio).override_failure_message(
					"path %d is too faint on the %s footprint (%.1f:1)" % [
						i + 1, PlayerSettings.AimPalette.keys()[palette], ratio]
					).is_greater_equal(PathPalette.MIN_CONTRAST)


# Derived, not authored: a dark colour keeps its editor hue's family, so path 2 is teal on both.
func test_a_dark_colour_keeps_its_hue() -> void:
	var footprint := OverlayManager.aim_fill_color()
	for i in PathPalette.HUES.size():
		var hue_gap := absf(PathPalette.dark(i, footprint).ok_hsl_h - PathPalette.hue(i).ok_hsl_h)
		assert_float(minf(hue_gap, 1.0 - hue_gap)).is_less(0.05)


# ==============================================================================
#  The plate
# ==============================================================================

func _swing(paths: Array[Array], swing := true) -> WeaponAttackData:
	var attack := WeaponAttackData.new()
	attack.max_range = 0
	attack.attack_shape = P.pathed(paths)
	attack.swing = swing
	return attack


# THE WIRE: the plate hands its lines the attack's own paths, and every cell names its offset.
func test_the_plate_draws_a_path_swings_paths() -> void:
	var plate: ShapePlate = auto_free(ShapePlate.new())
	var ahead := _path([Vector2i(0, -1), Vector2i(0, -2)])
	plate.show_attack(_swing([ahead] as Array[Array]))
	assert_bool(plate._lines.visible).is_true()
	assert_array(plate._lines.drawn_paths).is_equal([ahead])
	for cell in plate.grid().get_children():
		assert_bool(cell.has_meta(PathLines.CELL_META)).is_true()


# A painted shape draws no lines, and neither does a path shape with Swing OFF, which lands all at
# once (ruling 21) -- there is no order for lines to claim.
func test_a_painted_shape_or_a_swing_off_path_shape_draws_no_lines() -> void:
	var plate: ShapePlate = auto_free(ShapePlate.new())
	plate.show_attack(P.line(WeaponAttackData.new(), 2))
	assert_bool(plate._lines.visible).is_false()
	var ahead := _path([Vector2i(0, -1), Vector2i(0, -2)])
	plate.show_attack(_swing([ahead] as Array[Array], false))
	assert_bool(plate._lines.visible).is_false()
	plate.show_attack(null)
	assert_bool(plate._lines.visible).is_false()
