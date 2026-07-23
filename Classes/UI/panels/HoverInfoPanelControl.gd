extends Control
class_name HoverInfoPanelControl

# The compact hover card. Auto-parks on the screen half opposite the hovered unit; the
# caller can push its left edge right of the docked inspect column (#68). Y is computed
# from the live viewport + panel size — never a hardcoded pixel constant (the old
# BOTTOM_LEFT_POS=410 broke on a viewport-height change once already).

const MARGIN := 8

@onready var hover_panel: Panel = $HoverPanel
@onready var hover_gridcontainer = $HoverPanel/HoverInfoGridContainer

var current_unit: Unit

func set_unit(unit: Unit, left_x: int = MARGIN):
	if unit == null:
		clear()
		return
	if current_unit != unit:
		current_unit = unit
		visible = true
	hover_gridcontainer.set_unit(unit)

	var screen_pos: Vector2 = get_viewport().get_canvas_transform() * unit.global_position
	var y: int = MARGIN
	if screen_pos.y <= get_viewport_rect().size.y / 2.0:
		y = int(get_viewport_rect().size.y - hover_panel.size.y - MARGIN)
	position = Vector2(left_x, y)

func clear():
	current_unit = null
	visible = false
