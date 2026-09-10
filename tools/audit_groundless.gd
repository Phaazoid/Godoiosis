extends SceneTree

# Every GROUNDLESS cell that sits INSIDE a shipped board's used_rect -- the audit #1's rules change
# owes before it lands. Once "no ground, inside the rect" resolves as VOID, each of these stops
# bracing a shove and starts removing whoever lands on it, so this is the blast radius stated as a
# list rather than assumed to be empty.
#
#   godot --headless --path <repo> --script res://tools/audit_groundless.gd
#
# NOT a test and nothing here asserts: it reports what the shipped content actually contains, and
# the answer is read by a person deciding whether a map needs re-authoring. Lives outside tests/
# for replay_battle.gd's reason (extends SceneTree, and the suite runner scans res://tests).
#
# The rect is get_used_rect(), which is what RulesService.movement_cost and compute_move_range
# already mean by "on the map" -- so a notch erased mid-edge counts as inside, and only a corner
# bite shrinks the rect. That asymmetry is the whole reason this walks the rect rather than
# eyeballing the maps.

const TILESET := "res://Resources/TestTiles.tres"


func _init() -> void:
	var tileset: TileSet = load(TILESET)
	var paths := _scenarios("res://Scenarios")
	paths.sort()
	var total_groundless := 0
	var total_void := 0
	print("Auditing %d scenarios\n" % paths.size())
	for path in paths:
		var bytes := _tile_bytes(path)
		if bytes.is_empty():
			print("%-44s -- no tile_data" % path.get_file())
			continue
		var grid := TileMapLayer.new()
		grid.tile_set = tileset
		grid.tile_map_data = bytes
		var rect := grid.get_used_rect()
		var groundless: Array[Vector2i] = []
		var voids: Array[Vector2i] = []
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var cell := Vector2i(x, y)
				if grid.get_cell_source_id(cell) == -1:
					groundless.append(cell)
				elif GridUtils.get_terrain_kind_at_cell(grid, cell) == Terrain.Kind.VOID:
					voids.append(cell)
		total_groundless += groundless.size()
		total_void += voids.size()
		var cells := rect.size.x * rect.size.y
		print("%-44s rect %s = %d cells" % [path.get_file(), rect.size, cells])
		if not voids.is_empty():
			print("    painted VOID  : %d  %s" % [voids.size(), _brief(voids)])
		if groundless.is_empty():
			print("    groundless    : none -- the rect is solid")
		else:
			print("    GROUNDLESS    : %d (%.1f%% of the rect)  %s"
					% [groundless.size(), 100.0 * groundless.size() / cells, _brief(groundless)])
			print("    -> %s" % _shape(groundless, rect))
		grid.free()
	print("\nTOTAL: %d groundless-inside-rect cells, %d painted VOID cells" % [total_groundless, total_void])
	quit()


# Does the groundless set hug the rect's border, or is it genuinely interior? The distinction the
# plan leaned on, measured rather than asserted: a border-hugging set is a non-rectangular outline
# (a notch or an L), an interior one is a hole somebody dug on purpose.
func _shape(cells: Array[Vector2i], rect: Rect2i) -> String:
	var edge := 0
	for cell in cells:
		if cell.x == rect.position.x or cell.x == rect.end.x - 1 \
				or cell.y == rect.position.y or cell.y == rect.end.y - 1:
			edge += 1
	var interior := cells.size() - edge
	if interior == 0:
		return "all %d touch the rect border: a non-rectangular OUTLINE, not dug holes" % edge
	if edge == 0:
		return "all %d are INTERIOR: holes dug inside a solid outline" % interior
	return "%d on the border, %d INTERIOR" % [edge, interior]


# The board's bytes, straight out of the .tres TEXT rather than through load(). Deliberately not a
# resource load: Prolog references .dtl dialog resources whose loader is only registered by the
# editor plugin, so a bare --script run fails to parse the whole file and would silently skip the
# one shipped mission with a tutorial. The board is a plain byte array in the text either way.
func _tile_bytes(path: String) -> PackedByteArray:
	var text := FileAccess.get_file_as_string(path)
	var head := text.find("tile_data = PackedByteArray(")
	if head < 0:
		return PackedByteArray()
	# BASE64 in a quoted string, not a comma list -- 4.7 writes byte arrays that way, and a
	# comma parser reads every board as empty rather than failing, which is a wrong answer
	# wearing a right one's clothes.
	var start := text.find("\"", head) + 1
	var stop := text.find("\"", start)
	if start <= 0 or stop <= start:
		return PackedByteArray()
	return Marshalls.base64_to_raw(text.substr(start, stop - start))


func _brief(cells: Array[Vector2i]) -> String:
	if cells.size() <= 8:
		return str(cells)
	return "%s ... (+%d more)" % [str(cells.slice(0, 8)), cells.size() - 8]


func _scenarios(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := "%s/%s" % [dir_path, name]
		if dir.current_is_dir():
			found.append_array(_scenarios(full))
		elif name.ends_with(".tres"):
			found.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return found
