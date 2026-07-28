extends Node
class_name ZoneManager

# Named regions of the board, each carrying a KIND that says what the region MEANS. A cell belongs
# to at most one zone; painting it into a new zone silently removes it from whichever zone it was
# in before. Round-trips through ScenarioData.zones; drawn by OverlayManager.redraw_zones.
#
# The kind is what makes this ONE mechanism instead of a parallel Array[Vector2i] on ScenarioData
# per objective type (dev call 2026-07-28): a capture point is a zone of size one, and zone kinds
# were always going to expand. Adding a kind costs one enum member, one overlay registry line, and
# whatever rule consumes it -- save/load, authoring and persistence need no edit at all.
#
# PERSISTED, so the enum is APPEND-ONLY (enums serialize as plain ints).

enum Kind {
	PATROL,    # Sentry archetype trigger/leash regions -- the only kind until #96
	CAPTURE,   # objective: stand inside, spend a main action, the zone is claimed (#96 slice 3)
	EXTRACTION,   # objective: get every surviving unit inside, and the mission ends (#96 slice 4)
}

# name -> {"kind": Kind, "cells": Array[Vector2i]}. Plain nested dicts rather than an inner class,
# so to_dict/load_dict stay a straight pass-through into ScenarioData with nothing to serialize by
# hand.
var _zones: Dictionary = {}

func zone_names() -> Array[String]:
	var names: Array[String] = []
	names.assign(_zones.keys())
	return names

func zone_names_of(kind: Kind) -> Array[String]:
	var names: Array[String] = []
	for name in _zones:
		if _zones[name]["kind"] == kind:
			names.append(name)
	return names

func kind_of(zone_name: String) -> Kind:
	return _zones[zone_name]["kind"] if _zones.has(zone_name) else Kind.PATROL

func cells_in(zone_name: String) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if _zones.has(zone_name):
		cells.assign(_zones[zone_name]["cells"])
	return cells

func contains(zone_name: String, cell: Vector2i) -> bool:
	return _zones.has(zone_name) and _zones[zone_name]["cells"].has(cell)

# Which zone (if any) owns this cell, "" when none. The one-zone-per-cell rule is exactly what
# lets this return a single name instead of a list.
func zone_at(cell: Vector2i) -> String:
	for name in _zones:
		if _zones[name]["cells"].has(cell):
			return name
	return ""

func paint_cell(zone_name: String, kind: Kind, cell: Vector2i) -> void:
	erase_cell(cell)
	if not _zones.has(zone_name):
		_zones[zone_name] = {"kind": kind, "cells": []}
	_zones[zone_name]["kind"] = kind   # repainting an existing zone can retype it
	_zones[zone_name]["cells"].append(cell)

func erase_cell(cell: Vector2i) -> void:
	for name in _zones.keys():
		var cells: Array = _zones[name]["cells"]
		if cells.has(cell):
			cells.erase(cell)
			if cells.is_empty():
				_zones.erase(name)

func to_dict() -> Dictionary:
	return _zones.duplicate(true)

func load_dict(data: Dictionary) -> void:
	_zones.clear()
	for name in data:
		var entry: Dictionary = data[name]
		var cells: Array[Vector2i] = []
		cells.assign(entry["cells"])
		if not cells.is_empty():
			_zones[name] = {"kind": entry["kind"] as Kind, "cells": cells}
