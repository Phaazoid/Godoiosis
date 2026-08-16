extends Control
class_name EndTurnButton

# The bottom-right "your move is done" affordance (#189): a HUD element that stays hidden until
# game.refresh_end_turn_button() decides every squad on the active faction has acted or waited,
# then appears flashing -- the SAME Pulse cue SquadActionQueueControl's Execute button uses
# (SquadActionQueueControl.EXECUTE_BRIGHT/EXECUTE_FLASH), not a second flash. Root is full-rect
# with mouse_filter IGNORE, same shape as MissionStatusPanel (#134) -- it sits in UILayer without
# eating clicks anywhere but its own button.
#
# It shares the bottom-right corner with MissionStatusPanel, which reserves this button's slot by
# sitting BUTTON_CLEARANCE above it. Safe by construction: the button only exists once every squad
# has acted, and an acted squad's queue is cleared, so the queue dock (right edge, down to y=525)
# can never be on screen at the same time as this button.

const CORNER_MARGIN := 8

@onready var _button: Button = $Button

var _flash_tween: Tween = null

signal end_turn_requested

func _ready() -> void:
	z_index = UiLayers.MISSION_STATUS   # same always-on corner-HUD tier as the objectives panel
	visible = false
	_button.text = "End Turn"
	_button.focus_mode = Control.FOCUS_NONE
	_button.pressed.connect(func(): end_turn_requested.emit())
	_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, CORNER_MARGIN)

func set_active(active: bool) -> void:
	if active == visible:
		return
	visible = active
	if active:
		_start_flash()
	else:
		_stop_flash()

func _start_flash() -> void:
	_flash_tween = Pulse.start(self, _button, &"modulate", SquadActionQueueControl.EXECUTE_BRIGHT, SquadActionQueueControl.EXECUTE_FLASH)

func _stop_flash() -> void:
	Pulse.stop(_flash_tween, _button, &"modulate", SquadActionQueueControl.EXECUTE_BRIGHT)
	_flash_tween = null
