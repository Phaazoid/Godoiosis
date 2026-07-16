extends Control
class_name UnitInfoPanelControl

# Controller for the click-to-inspect popup (UnitInfoPanel.tscn): owns show/hide and which
# unit is currently open, and fans set_unit/clear out to its child panels (stats/portrait/
# inventory/squad/states) so they all tear down signal connections together.

const TOP_LEFT_POS = Vector2i(8, 8)
const BOTTOM_LEFT_POS = Vector2i(8, 475)

@onready var status_hbox = $UnitInfoPanel/UnitStatusHBox
@onready var status_bar = $UnitInfoPanel/UnitStatesBar

var current_unit: Unit
var screen_pos
var _on_top := false   # true when the panel is parked on the TOP half

func _ready() -> void:
	$UnitInfoPanel/CloseButton.pressed.connect(_on_close_button_pressed)

func _on_close_button_pressed() -> void:
	clear()

func set_unit(unit: Unit, can_act := false):
	if current_unit != unit:
		current_unit = unit

		if unit == null:
			visible = false
			return
		else:
			visible = true

		status_hbox.set_unit(unit, can_act)
		status_bar.set_unit(unit)

		screen_pos = get_viewport().get_canvas_transform() * unit.global_position
		var viewport_height = get_viewport_rect().size.y
		if screen_pos.y > viewport_height / 2:
			self.position = TOP_LEFT_POS
			_on_top = true
		else:
			self.position = BOTTOM_LEFT_POS
			_on_top = false

func clear():
	current_unit = null
	visible = false
	status_hbox.set_unit(null)
	status_bar.set_unit(null)

func is_showing() -> bool:
	return visible and current_unit != null

func is_showing_unit(unit: Unit) -> bool:
	return visible and current_unit == unit

func is_on_top() -> bool:
	return _on_top
