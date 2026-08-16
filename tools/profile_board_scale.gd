extends SceneTree

# Headless profiler for how the 3D authoring poll scales with BOARD SIZE (#319).
# See docs/performance.md for the recorded numbers and what they were used to decide.
#
#   godot --headless --path <repo> --script res://tools/profile_board_scale.gd
#
# Lives outside tests/ for the same reason profile_group_move.gd does: it extends SceneTree, not
# GdUnitTestSuite, and the suite runner scans res://tests recursively. Shape copied from that file
# per its own header -- boot the REAL scene, load a REAL mission, wrap the REAL call in
# Time.get_ticks_usec().
#
# WHAT IS BEING MEASURED, and why these three calls. battle3d._sync_terrain_while_authoring runs
# every frame while game_state == DEV_MODE and performs three full-board walks with no change
# detection: BoardMirror.sync's walk over grid.get_used_cells(), sync's erase sweep over
# board.get_used_cells(), and _refresh_tops()'s third get_used_cells() inside
# BoardPicker.column_tops_from + used_rect. All three are O(board), so the poll's cost is set by
# map size alone.
#
# FIRST vs STEADY is the split that matters, and they answer different questions:
#   first  -- the one-off cost of the sync that actually writes the new board (the resize hitch).
#   steady -- what the same walk costs on an UNCHANGED board, i.e. the per-frame tax you pay for
#             every frame you sit in dev mode. This is the number the cap decision rests on.
#
# The figures are a FLOOR: headless skips the draw a real frame also pays.

const MISSION := "res://Scenarios/missions/Prolog.tres"

# Ascending on purpose: each resize GROWS the board, so no measurement is polluted by erasing the
# previous size's leftover columns.
const SIZES := [
	Vector2i(20, 12),    # ~Prolog scale, the size every design assumption is written against
	Vector2i(40, 40),
	Vector2i(60, 60),
	Vector2i(80, 80),
	Vector2i(100, 100),
	Vector2i(150, 150),
	Vector2i(200, 200),  # what the SpinBox currently allows, and what the dev hit in play
]

const STEADY_SAMPLES := 4
const PROP_SIZE := Vector2i(100, 100)
# Smaller than PROP_SIZE deliberately: a tuft is one sprite PER DRAWN CLUSTER rather than one per
# cell (#280), so a 10k-cell tuft fill is tens of thousands of nodes. 3600 is enough to read the
# per-cell cost off, and the curve above is linear enough to scale it.
const TUFT_SIZE := Vector2i(60, 60)

var _scene: Node3D
var _game: Node2D
var _mirror: BoardMirror
var _board: GridMap


func _init() -> void:
	_run.call_deferred()


func _stamp(label: String, usec: int) -> void:
	print("  %-44s %8.2f ms" % [label, usec / 1000.0])


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


# A tile to fill with, found in the TILESET rather than on the loaded board: whether Prolog happens
# to paint a prop is authored content, and this must not depend on it (the content razor). `want` is
# the PropShape to match, or -1 for "any flat ground". Returns {} when the sheet carries no such
# tile, which the caller reports rather than guesses at.
func _find_tile(want: int) -> Dictionary:
	var tiles: TileSet = _game.grid.tile_set
	for s in tiles.get_source_count():
		var source_id := tiles.get_source_id(s)
		var atlas := tiles.get_source(source_id) as TileSetAtlasSource
		if atlas == null:
			continue
		for i in atlas.get_tiles_count():
			var coords := atlas.get_tile_id(i)
			var data := atlas.get_tile_data(coords, 0)
			if data == null:
				continue
			if want == -1:
				# A flat fill must be real ground, or the board is a field of unnamed decoration.
				if GridUtils.stands_up_of(data) or GridUtils.terrain_kind_of(data) == Terrain.Kind.NONE:
					continue
			elif GridUtils.prop_shape_of(data) != want:
				continue
			return {"source": source_id, "coords": coords, "name": GridUtils.authored_tile_display_name(data)}
	return {}


# The poll's cost on the board exactly as the mission authored it -- no resize, no synthetic fill.
# The most directly useful number here: it says what sitting in dev mode costs on real content
# today, which is the thing any cap has to be judged against.
func _measure_as_loaded() -> void:
	print("\nAS AUTHORED (%s, no resize)" % MISSION.get_file())
	var lo := 1 << 62
	var hi := 0
	for i in range(STEADY_SAMPLES):
		var t := Time.get_ticks_usec()
		_mirror.sync(_game.grid, _game.board_heights)
		var spent := Time.get_ticks_usec() - t
		lo = mini(lo, spent)
		hi = maxi(hi, spent)
	var t2 := Time.get_ticks_usec()
	var tops := BoardPicker.column_tops_from(_board)
	BoardPicker.used_rect(tops)
	var tops_usec := Time.get_ticks_usec() - t2
	print("  %-44s %8.2f - %.2f ms" % ["FULL-BOARD primitives (sync + tops + rect)",
		(lo + tops_usec) / 1000.0, (hi + tops_usec) / 1000.0])
	var first: Vector2i = _game.grid.get_used_cells()[0]
	_measure_poll({"source": _game.grid.get_cell_source_id(first),
		"coords": _game.grid.get_cell_atlas_coords(first)})
	print("    2D cells = %d   3D cells = %d   props = %d" % [
		_game.grid.get_used_cells().size(), _board.get_used_cells().size(), _mirror.prop_count()])


# One board size, end to end. Returns nothing -- everything it learns it prints, because the whole
# artifact of this tool is its transcript.
func _measure(size: Vector2i, fill: Dictionary, label: String) -> void:
	print("\n%s  %d x %d  (%d cells)" % [label, size.x, size.y, size.x * size.y])

	var t := Time.get_ticks_usec()
	_game.dev_controller.resize_map(size.x, size.y, fill.source, fill.coords)
	_stamp("resize_map (the 2D store)", Time.get_ticks_usec() - t)

	t = Time.get_ticks_usec()
	_mirror.sync(_game.grid, _game.board_heights)
	_stamp("sync -- FIRST (writes the new board)", Time.get_ticks_usec() - t)

	var lo := 1 << 62
	var hi := 0
	for i in range(STEADY_SAMPLES):
		t = Time.get_ticks_usec()
		_mirror.sync(_game.grid, _game.board_heights)
		var spent := Time.get_ticks_usec() - t
		lo = mini(lo, spent)
		hi = maxi(hi, spent)
	print("  %-44s %8.2f - %.2f ms" % ["sync -- STEADY (per frame, unchanged board)", lo / 1000.0, hi / 1000.0])

	# _refresh_tops split into its two halves, so the third walk is attributed rather than lumped
	# in with the two inside sync().
	t = Time.get_ticks_usec()
	var tops := BoardPicker.column_tops_from(_board)
	var tops_usec := Time.get_ticks_usec() - t
	_stamp("column_tops_from (the third walk)", tops_usec)

	t = Time.get_ticks_usec()
	BoardPicker.used_rect(tops)
	var rect_usec := Time.get_ticks_usec() - t
	_stamp("used_rect", rect_usec)

	print("  %-44s %8.2f - %.2f ms" % ["FULL-BOARD primitives (sync + tops + rect)",
		(lo + tops_usec + rect_usec) / 1000.0, (hi + tops_usec + rect_usec) / 1000.0])
	_measure_poll(fill)
	print("    2D cells = %d   3D cells = %d   props = %d" % [
		_game.grid.get_used_cells().size(), _board.get_used_cells().size(), _mirror.prop_count()])


# THE REAL CLAIM (#319). Everything above times the full-board primitives by hand, which is the
# BEFORE shape and is what the poll used to run unconditionally. This times the poll ITSELF, in the
# two states that actually occur in play:
#
#   IDLE     nothing was announced -- what sitting in dev mode costs.
#   PAINTING one cell announced through the door -- what a brush drag costs, one cell per frame.
#
# The painting figure is the one that matters, and the one a dirty FLAG could never have fixed: at
# 200x200 the full walk costs the same whether or not anything changed, so a flag would leave a
# drag exactly as slow as before.
func _measure_poll(fill: Dictionary) -> void:
	_scene._sync_terrain_while_authoring()   # drain anything the resize announced

	var idle_lo := 1 << 62
	var idle_hi := 0
	for i in range(STEADY_SAMPLES):
		var t := Time.get_ticks_usec()
		_scene._sync_terrain_while_authoring()
		var spent := Time.get_ticks_usec() - t
		idle_lo = mini(idle_lo, spent)
		idle_hi = maxi(idle_hi, spent)

	# Repaint an existing cell with the tile it already has: it announces exactly as a drag does,
	# while leaving the board identical so repeated samples measure the same work.
	var cells: Array[Vector2i] = _game.grid.get_used_cells()
	var paint_lo := 1 << 62
	var paint_hi := 0
	for i in range(STEADY_SAMPLES):
		_game.grid.paint(cells[i % cells.size()], fill.source, fill.coords)
		var t := Time.get_ticks_usec()
		_scene._sync_terrain_while_authoring()
		var spent := Time.get_ticks_usec() - t
		paint_lo = mini(paint_lo, spent)
		paint_hi = maxi(paint_hi, spent)

	print("  %-44s %8.3f - %.3f ms" % ["POLL, idle", idle_lo / 1000.0, idle_hi / 1000.0])
	print("  %-44s %8.3f - %.3f ms" % ["POLL, painting one cell", paint_lo / 1000.0, paint_hi / 1000.0])


func _run() -> void:
	var packed := load("res://Scenes/Battle3D/Battle3D.tscn") as PackedScene
	_scene = packed.instantiate() as Node3D
	_scene.auto_play = false   # no AI churning mid-measure (the tests/presentation fixture's setting)
	root.add_child(_scene)
	await _frames(5)

	_game = _scene.game
	_scene.load_mission(MISSION)
	await _frames(5)

	_mirror = _scene.get_node("BoardMirror") as BoardMirror
	_board = _scene.get_node("Board") as GridMap

	# The gate the poll itself checks. Without it nothing below would ever run in the real game.
	_game.game_state = _game.GameState.DEV_MODE

	var flat := _find_tile(-1)
	var prop := _find_tile(GridUtils.PropShape.PLANE)
	var tuft := _find_tile(GridUtils.PropShape.TUFT)
	if flat.is_empty():
		print("ABORT: the tileset offers no flat ground tile to fill with")
		quit(1)
		return

	print("mission   = ", MISSION)
	print("fill      = %s (source %d, %s)" % [flat.name if flat.name != "" else "unnamed",
		flat.source, flat.coords])
	print("build     = ", Build.version())
	print("\nAll figures are a FLOOR: headless does no drawing, a real frame also pays that.")

	await _measure_as_loaded()

	for size: Vector2i in SIZES:
		await _measure(size, flat, "FLAT")
		await process_frame

	# The worse case the cap has to survive, if it exists. The dev's zoom-in test already argues
	# props were not his cause, but a cap set against the cheap fill would be set too high.
	if prop.is_empty():
		print("\nPROP RUN SKIPPED: the tileset carries no PLANE-prop tile")
	else:
		print("\n--- solid prop fill: %s ---" % [prop.name if prop.name != "" else "unnamed"])
		await _measure(PROP_SIZE, prop, "PROP")

	# The expensive prop shape, and the reason #311 exists: one sprite per drawn cluster, not one
	# per cell. Measured separately because a cap set against the fence would be set too high.
	if tuft.is_empty():
		print("\nTUFT RUN SKIPPED: the tileset carries no TUFT tile")
	else:
		print("\n--- tuft fill: %s ---" % [tuft.name if tuft.name != "" else "unnamed"])
		await _measure(TUFT_SIZE, tuft, "TUFT")

	print("\nPROFILE DONE")
	quit(0)
