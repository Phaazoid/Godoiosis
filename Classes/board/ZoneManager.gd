extends Node
class_name ZoneManager

# Named regions of the board, each carrying a KIND that says what the region MEANS. Zones OVERLAP
# freely (dev call 2026-08-12 -- enemies patrol an area containing a capture point), so a cell can
# belong to any number of zones; a kind-sensitive reader must ask a kind-filtered question
# (MissionController.capturable_zone_at), never "the" zone at a cell. A zone's kind is fixed when
# its first cell is painted -- repainting never retypes; changing kind = delete and repaint.
# Round-trips through ScenarioData.zones; drawn by OverlayManager.redraw_zones.
#
# The kind is what makes this ONE mechanism instead of a parallel Array[Vector2i] on ScenarioData
# per objective type (dev call 2026-07-28): a capture point is a zone of size one, and zone kinds
# were always going to expand. Adding a kind costs one enum member, one overlay registry line, and
# whatever rule consumes it -- save/load, authoring and persistence need no edit at all.
#
# PERSISTED, so the enum is APPEND-ONLY (enums serialize as plain ints).

# Fires on any mutation (paint/erase/load) that actually changed the store. The Tile Brush's zone
# picker rebuilds off this; per-cell drag emissions are cheap because the listener diffs first.
signal zones_changed

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

# Kind applies only at creation; painting more of an existing zone keeps its own kind whatever the
# brush has picked (the silent-retype trap, reported 2026-08-12). Repainting an owned cell is a
# no-op so a drag doesn't churn listeners.
func paint_cell(zone_name: String, kind: Kind, cell: Vector2i) -> void:
	if not _zones.has(zone_name):
		_zones[zone_name] = {"kind": kind, "cells": []}
	elif _zones[zone_name]["cells"].has(cell):
		return
	_zones[zone_name]["cells"].append(cell)
	zones_changed.emit()

# Scoped to ONE zone (dev call 2026-08-12): with overlap legal, an unscoped erase could never
# carve one zone out from under another. A zone erased down to nothing is deleted.
func erase_cell_from(zone_name: String, cell: Vector2i) -> void:
	if not contains(zone_name, cell):
		return
	var cells: Array = _zones[zone_name]["cells"]
	cells.erase(cell)
	if cells.is_empty():
		_zones.erase(zone_name)
	zones_changed.emit()

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
	zones_changed.emit()
