extends Node2D
class_name OverlayIcon

# One marker hung on a UNIT rather than a cell: a Sprite2D that follows the unit it was built for.
# Built and pooled by OverlayManager (icons_by_unit), styled by its _style_icon (#325: a ring
# underfoot, the crown over the head), and mirrored by OverlayMirror._icons into
# BoardOverlays.Layer.GROUND_ICONS (rings, surface decals) or Layer.ICONS (crowns, billboards).

@onready var sprite = $Sprite2D
var icon_type
# The unit this marker hangs on, and the grid its cells are measured in. The CELL is deliberately
# not stored -- see current_cell.
var unit: Unit
var grid: TileMapLayer

# The above-the-head channel: what a unit IS, never what the current interaction is about
# (#346 -- ground markup carries the interaction). CURSOR/TARGET/INVALID lived here and are
# retired: CURSOR and INVALID never had a producer, and TARGET duplicated the target-pick
# ground marker. Ordinals are read by OverlayMirror's z-stagger and persisted nowhere.
enum IconType {
	CROWN,
	SQUADMEMBER
}

func setup(texture: Texture2D, marker_unit: Unit, board_grid: TileMapLayer, type: IconType):
	sprite.texture = texture
	unit = marker_unit
	grid = board_grid
	icon_type = type

# THE answer to where this marker sits -- read by the 2D position below and by OverlayMirror alike,
# so the two views cannot drift into two answers. Derived, never copied: a stored cell goes stale
# silently the moment a marker outlives one repaint (#308), which was invisible while markers lived
# only as long as a selection and got rebuilt constantly. get_projected_destination already returns
# the projected cell while a move is queued and movement.cell otherwise, so planning and settled
# state both read correctly from the one expression.
func current_cell() -> Vector2i:
	return unit.get_projected_destination()

func has_unit() -> bool:
	return is_instance_valid(unit)

# Following the unit is the icon's own job rather than something each redraw path must remember;
# forgetting is what left a persistent ring behind on the cell its unit walked off.
func _process(_delta: float) -> void:
	if not has_unit() or grid == null:
		return
	position = grid.map_to_local(current_cell())
