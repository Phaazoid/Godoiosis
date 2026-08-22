extends Control
class_name EndTurnButton

# The bottom-right "your move is done" affordance (#189), and since #467 the ONLY door to ending a
# turn -- the action ring dropped its End Turn row, so this button is now PERMANENTLY on screen
# rather than appearing once every squad has acted. What the old visibility rule became is the
# FLASH: it pulses exactly when `game.refresh_end_turn_button()` finds every squad on the active
# faction acted or waited, on the SAME Pulse cue SquadActionQueueControl's Execute button uses
# (EXECUTE_BRIGHT/EXECUTE_FLASH), not a second flash.
#
# The same predicate is why pressing it early ASKS first (game._on_end_turn_button_pressed): the
# button asks exactly when it is not flashing, so the cue and the confirmation can never disagree
# about whether you are done.
#
# Root is full-rect with mouse_filter IGNORE, same shape as MissionStatusPanel (#134) -- it sits in
# UILayer without eating clicks anywhere but its own button.
#
# It shares the bottom-right corner with MissionStatusPanel, which reserves this button's slot by
# sitting BUTTON_CLEARANCE above it -- reserved even when the button was hidden, so making it
# permanent reflows nothing. The queue dock is the other neighbour, and it is safe by MEASUREMENT
# rather than by the old "these two are never up together" argument, which #467 retired: the dock
# occupies y 25..490 and this button y 676..712 at a 720-tall viewport, so they do not meet.
# tests/ui/test_end_turn_button.gd asserts the gap rather than trusting this note.

const CORNER_MARGIN := 8

@onready var _button: Button = $Button

var _flash_tween: Tween = null
var _urgent := false

signal end_turn_requested

func _ready() -> void:
	z_index = UiLayers.MISSION_STATUS   # same always-on corner-HUD tier as the objectives panel
	visible = true
	_button.text = "End Turn"
	_button.focus_mode = Control.FOCUS_NONE
	_button.pressed.connect(func(): end_turn_requested.emit())
	_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, CORNER_MARGIN)

# "Every squad is done -- this is what you want next." The button is up either way.
func set_urgent(urgent: bool) -> void:
	if urgent == _urgent:
		return
	_urgent = urgent
	if urgent:
		_start_flash()
	else:
		_stop_flash()

func is_urgent() -> bool:
	return _urgent

func _start_flash() -> void:
	_flash_tween = Pulse.start(self, _button, &"modulate", SquadActionQueueControl.EXECUTE_BRIGHT, SquadActionQueueControl.EXECUTE_FLASH)

func _stop_flash() -> void:
	Pulse.stop(_flash_tween, _button, &"modulate", SquadActionQueueControl.EXECUTE_BRIGHT)
	_flash_tween = null
