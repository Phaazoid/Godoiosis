extends Control
class_name HoverInfoPanelControl

@onready var hover_gridcontainer = $HoverPanel/HoverInfoGridContainer

var current_unit: Unit
var screen_pos

const TOP_LEFT_POS = Vector2i(8, 8)
const BOTTOM_LEFT_POS = Vector2i(8, 410)

enum Half { AUTO, TOP, BOTTOM }

func set_unit(unit: Unit, half: int = Half.AUTO):
	if current_unit != unit:
		current_unit = unit

		if unit == null:
			visible = false
			return
		else:
			visible = true
	hover_gridcontainer.set_unit(unit)

	# Forced half (inspect panel is up) wins; otherwise auto-place opposite the unit.
	match half:
		Half.TOP:
			self.position = TOP_LEFT_POS
		Half.BOTTOM:
			self.position = BOTTOM_LEFT_POS
		_:
			screen_pos = get_viewport().get_canvas_transform() * unit.global_position
			var viewport_height = get_viewport_rect().size.y
			if screen_pos.y > viewport_height / 2:
				self.position = TOP_LEFT_POS
			else:
				self.position = BOTTOM_LEFT_POS

func clear():
	current_unit = null
	visible = false
