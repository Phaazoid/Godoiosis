extends Node2D
class_name HeightDebugOverlay

# THROWAWAY dev readout for elevation (#257): each cell's height, and an arrow on ramp cells showing
# which way they rise. F5 toggles it; dev builds only.
#
# It exists because slice 1 ships the RULES for verticality with no art to render them — wall-face
# autotiles, ramp sprites and per-level sprite offsets are a separate ticket gated on a tileset
# choice. Without something like this, a board with elevation is indistinguishable from a flat one.
# Expect it to be deleted, not extended, once the real 2D height render lands.
#
# A child of the grid so map_to_local lands in this node's own space with no conversion. Draws with
# _draw rather than pooling a Label per cell: one node and one pass, and nothing to keep in sync.

const RISE_ARROWS: Dictionary[Terrain.RampRise, String] = {
	Terrain.RampRise.NONE: "",
	Terrain.RampRise.NORTH: "^",
	Terrain.RampRise.SOUTH: "v",
	Terrain.RampRise.EAST: ">",
	Terrain.RampRise.WEST: "<"
}

const FONT_SIZE := 8
const FLAT_COLOR := Color(1, 1, 1, 0.35)     # height 0 is the overwhelming majority — keep it quiet
const RAISED_COLOR := Color(1, 0.85, 0.4, 0.9)
const RAMP_COLOR := Color(0.5, 0.9, 1.0, 0.95)

var grid: TileMapLayer
var heights: BoardHeights

# TWO independent reasons to be lit, and `visible` is DERIVED from both rather than assigned by
# either (#260) — ModalLock's shape. Painting height into an invisible store is blind, so the brush
# that carries a level lights this on its own; but if F5 already asked for it, leaving that paint
# mode must not silently switch it off.
var _toggled := false        # F5
var _brush_active := false   # the level brush is LIVE -- DevController.elevation_brush_live (#340)

func _ready() -> void:
	visible = false
	z_index = 100   # above the tile overlays, which sit below Unit.BASE_SPRITE_INDEX

func toggle() -> void:
	_toggled = not _toggled
	_apply()

func set_brush_active(active: bool) -> void:
	if _brush_active == active:
		return
	_brush_active = active
	_apply()

func _apply() -> void:
	visible = _toggled or _brush_active
	refresh()

# Call after anything mutates the store — the height brush (#260) is the first real caller. Not
# wired to a signal because BoardHeights deliberately has none: it is a data store, not a subject.
func refresh() -> void:
	if visible:
		queue_redraw()

func _draw() -> void:
	if grid == null or heights == null:
		return
	var font := ThemeDB.fallback_font
	for cell in grid.get_used_cells():
		var height := heights.elevation_at(cell)
		var rise := heights.ramp_rise_at(cell)
		# A gentle ramp wears a half sign (#427 slice 2): steepness is authored now, and an arrow
		# alone could not tell a 26.6 degree slope from a 45 degree one.
		var arrow := RISE_ARROWS[rise]
		if rise != Terrain.RampRise.NONE and heights.ramp_climb_at(cell) < Terrain.UNITS_PER_LEVEL:
			arrow += "½"
		var label := str(height) + arrow
		var color := FLAT_COLOR
		if rise != Terrain.RampRise.NONE:
			color = RAMP_COLOR
		elif height != 0:
			color = RAISED_COLOR
		# map_to_local is the cell CENTRE; nudge so the glyphs sit centred-ish rather than hanging
		# off the corner. Eyeballed, and deliberately not a knob — this whole node is temporary.
		var at := grid.map_to_local(cell) + Vector2(-5, 4)
		draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
