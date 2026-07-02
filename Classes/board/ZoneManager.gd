extends Node
class_name ZoneManager

# Named regions of the board (the Sentry archetype triggers/leashes to these -- painted via
# the Tile Brush tab's Zone mode). A cell belongs to at most one zone; painting it into a
# new zone silently removes it from whichever zone it was in before. Round-trips through
# ScenarioData.zones; drawn by OverlayManager.redraw_zones.

var _zones: Dictionary = {}   # String (zone name) -> Array[Vector2i]

func zone_names() -> Array[String]:
	var names: Array[String] = []
	names.assign(_zones.keys())
	return names

func cells_in(zone_name: String) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if _zones.has(zone_name):
		cells.assign(_zones[zone_name])
	return cells

func contains(zone_name: String, cell: Vector2i) -> bool:
	return _zones.has(zone_name) and _zones[zone_name].has(cell)

func paint_cell(zone_name: String, cell: Vector2i) -> void:
	erase_cell(cell)
	if not _zones.has(zone_name):
		_zones[zone_name] = []
	_zones[zone_name].append(cell)

func erase_cell(cell: Vector2i) -> void:
	for name in _zones.keys():
		if _zones[name].has(cell):
			_zones[name].erase(cell)
			if _zones[name].is_empty():
				_zones.erase(name)

func to_dict() -> Dictionary:
	return _zones.duplicate(true)

func load_dict(data: Dictionary) -> void:
	_zones.clear()
	for name in data:
		var cells: Array[Vector2i] = []
		cells.assign(data[name])
		if not cells.is_empty():
			_zones[name] = cells
