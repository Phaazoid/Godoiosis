extends SceneTree

# What #890's spread step would actually set alight on the SHIPPED boards -- the blast radius of
# "fire takes its flammable neighbours" stated as a list rather than assumed to be empty.
#
#   godot --headless --path <repo> --script res://tools/audit_fire_fuel.gd
#
# NOT a test and nothing here asserts: it reports what the shipped content contains, and the answer
# is read by a person deciding whether a map needs re-authoring. Same shape and same home as
# tools/audit_groundless.gd, for the same reason (extends SceneTree, and the suite runner scans
# res://tests) -- and it borrows that tool's TEXT read of the .tres for that tool's stated reason:
# Prolog references .dtl dialog resources whose loader only the editor plugin registers, so load()
# fails to parse the one shipped mission that actually paints fire.
#
# Flammability is asked of the AUTHORED REACTIONS, never a hardcoded kind list -- that is the one
# spelling the build must not duplicate, so the audit must not duplicate it either.

const TILESET := "res://Resources/TestTiles.tres"
const REACTION_DIR := "res://Resources/TerrainReactions/"
const FIRE_STATE_INTS := {1: "BURNING", 4: "BLAZE"}


func _init() -> void:
	var tileset: TileSet = load(TILESET)
	var igniters := _ignition_reactions()
	print("Ignition reactions (FIRE -> BURNING): %d" % igniters.size())
	for r: TerrainReaction in igniters:
		print("    required_kind = %s" % Terrain.Kind.keys()[r.required_kind])
	print("")
	var paths := _scenarios("res://Scenarios")
	paths.sort()
	for path in paths:
		_audit(path, tileset, igniters)
	quit()


func _audit(path: String, tileset: TileSet, igniters: Array) -> void:
	var bytes := _tile_bytes(path)
	if bytes.is_empty():
		return
	var fires := _painted_fires(path)
	var grid := TileMapLayer.new()
	grid.tile_set = tileset
	grid.tile_map_data = bytes
	var rect := grid.get_used_rect()

	var fuel := 0
	for cell in grid.get_used_cells():
		if _flammable(grid, cell, igniters):
			fuel += 1

	if fires.is_empty() and fuel == 0:
		grid.free()
		return
	print("%-30s rect %s = %d cells, flammable ground %d, painted fire %d"
			% [path.get_file(), rect.size, rect.size.x * rect.size.y, fuel, fires.size()])
	if fires.is_empty():
		grid.free()
		return
	var touching := 0
	for cell: Vector2i in fires:
		var names := PackedStringArray()
		for s: int in fires[cell]:
			if FIRE_STATE_INTS.has(s):
				names.append(FIRE_STATE_INTS[s])
		var under: String = Terrain.Kind.keys()[GridUtils.get_terrain_kind_at_cell(grid, cell)]
		var catchers := PackedStringArray()
		for dir in GridUtils.CARDINAL_DIRECTIONS:
			if _flammable(grid, cell + dir, igniters):
				var k: String = Terrain.Kind.keys()[GridUtils.get_terrain_kind_at_cell(grid, cell + dir)]
				catchers.append("%s %s" % [cell + dir, k])
		if not catchers.is_empty():
			touching += 1
		var verdict := "SPREADS -> " + ", ".join(catchers) if not catchers.is_empty() \
				else "no flammable neighbour"
		print("      %-11s %-8s on %-6s  %s" % [str(cell), ",".join(names), under, verdict])
	print("    -> %d of %d painted fires would start spreading on turn one\n"
			% [touching, fires.size()])
	grid.free()


# "Would a FIRE hit light this cell?" asked of the authored reactions, exactly as the build will.
func _flammable(grid: TileMapLayer, cell: Vector2i, igniters: Array) -> bool:
	if grid.get_cell_source_id(cell) == -1:
		return false
	var kind := GridUtils.get_terrain_kind_at_cell(grid, cell)
	var none: Array[Terrain.TileState] = []
	for r: TerrainReaction in igniters:
		if r.applies_to_tile(kind, none):
			return true
	return false


func _ignition_reactions() -> Array:
	var out: Array = []
	var dir := DirAccess.open(REACTION_DIR)
	if dir == null:
		return out
	for file in dir.get_files():
		var name := file.trim_suffix(".remap")
		if not name.ends_with(".tres"):
			continue
		var r: TerrainReaction = load(REACTION_DIR + name)
		if r != null and r.incoming_element == Elemental.Element.FIRE \
				and r.add_tile_states.has(Terrain.TileState.BURNING):
			out.append(r)
	return out


# The board's bytes straight out of the .tres TEXT -- see the header for why this is not a load().
func _tile_bytes(path: String) -> PackedByteArray:
	var text := FileAccess.get_file_as_string(path)
	var head := text.find("tile_data = PackedByteArray(")
	if head < 0:
		return PackedByteArray()
	var start := text.find("\"", head) + 1
	var stop := text.find("\"", start)
	if start <= 0 or stop <= start:
		return PackedByteArray()
	return Marshalls.base64_to_raw(text.substr(start, stop - start))


# The authored terrain_states block, read out of the same text. Cell -> the state ints on it.
func _painted_fires(path: String) -> Dictionary:
	var out: Dictionary = {}
	var text := FileAccess.get_file_as_string(path)
	var head := text.find("terrain_states = {")
	if head < 0:
		return out
	var stop := text.find("}", head)
	var block := text.substr(head, stop - head)
	var re := RegEx.create_from_string(r"Vector2i\((-?\d+),\s*(-?\d+)\):\s*Array\[int\]\(\[([\d,\s]*)\]\)")
	for m in re.search_all(block):
		var cell := Vector2i(m.get_string(1).to_int(), m.get_string(2).to_int())
		var states: Array[int] = []
		for piece in m.get_string(3).split(",", false):
			var s := piece.strip_edges().to_int()
			if FIRE_STATE_INTS.has(s):
				states.append(s)
		if not states.is_empty():
			out[cell] = states
	return out


func _scenarios(root: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	for sub in dir.get_directories():
		found.append_array(_scenarios(root + "/" + sub))
	for file in dir.get_files():
		var name := file.trim_suffix(".remap")
		if name.ends_with(".tres"):
			found.append(root + "/" + name)
	return found
