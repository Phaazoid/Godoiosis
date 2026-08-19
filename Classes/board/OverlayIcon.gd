extends Node2D
class_name OverlayIcon

# One marker hung on a UNIT rather than a cell: a Sprite2D plus the cell it was anchored to.
# Built and pooled by OverlayManager (icons_by_unit), styled by its _style_icon (#325: a ring
# underfoot or the legacy head square), and mirrored by OverlayMirror._icons into
# BoardOverlays.Layer.GROUND_ICONS (rings, surface decals) or Layer.ICONS (squares, billboards).

@onready var sprite = $Sprite2D
var icon_type
var target_cell: Vector2i

# The above-the-head channel: what a unit IS, never what the current interaction is about
# (#346 -- ground markup carries the interaction). CURSOR/TARGET/INVALID lived here and are
# retired: CURSOR and INVALID never had a producer, and TARGET duplicated the target-pick
# ground marker. Ordinals are read by OverlayMirror's z-stagger and persisted nowhere.
enum IconType {
	CROWN,
	SQUADMEMBER
}

func setup(texture: Texture2D, cell: Vector2i, type: IconType):
	sprite.texture = texture
	target_cell = cell
	icon_type = type
