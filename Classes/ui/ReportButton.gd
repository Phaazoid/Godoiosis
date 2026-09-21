extends Control
class_name ReportButton

# THE ON-SCREEN REPORT MARK (#1051) -- the half of "make reporting easier" that a stranger can
# actually find. #1050 gave the player F3, and a key nobody is told about is not a door.
#
# EndTurnButton's exact shape and for its reasons: a full-rect Control with mouse_filter IGNORE
# wrapping one Button, so it sits in UILayer without eating a click anywhere but its own rect;
# `z_index = UiLayers.MISSION_STATUS`, the always-on corner-HUD tier; and it is DUMB -- it emits
# `report_requested` and game.gd wires it to open_report_card, exactly as `end_turn_requested` is
# wired. Nothing here knows what a report contains.
#
# IT DOES NOT STAND DOWN, which is the one place it deliberately parts from End Turn. That button
# hides for a cinematic pass (#722) and the pre-mission phase (#739); this one has no such gate,
# because a pass playing back at you is exactly when something looks wrong and you want to say so --
# and the pause menu is already reachable mid-pass (#723, playback parks on a card). The title
# screen needs no case either: MissionSelectScreen's backdrop is fully opaque by design, so the HUD
# behind it is already hidden.
#
# THE WORD IS A PLACEHOLDER, in End Turn's register but still the dev's to change (player-facing
# prose is his).

const CORNER_MARGIN := 8

# HOW FAR LEFT OF THE CORNER, and it is a MEASUREMENT rather than a taste: the action-queue dock's
# BackgroundPanel is anchored right at offset_left -223, so anything whose right edge sits at or
# past -223 is under it. 231 is that plus a gap.
#
# The corner ITSELF cannot hold this button, which is worth writing down because it is the obvious
# place to reach for and the numbers are the whole argument. MEASURED in the 1280x720 design space:
# MissionStatusPanel's VersionLabel sits at x 1230..1274, y 6..22 (it is repositioned in code at
# MissionStatusPanel.gd:40, so the offsets in that .tscn are dead and must not be read as the
# answer), and the dock's panel begins at y 25 -- so the free band beside the stamp is 25px tall,
# while this button measures 73x31. It does not fit there at any margin.
#
# This clearance is a second spelling of where the dock's edge is, so it is pinned rather than
# trusted: tests/ui/test_report_button.gd measures the LIVE rects. Note which of those two guards
# actually bites -- the DOCK one does (16px of gap, and it reds at clearance 0), while the version
# stamp sits ~190px away and its case is a tripwire against a future move rather than a live guard.
const DOCK_CLEARANCE := 231

@onready var _button: Button = $Button

signal report_requested

func _ready() -> void:
	z_index = UiLayers.MISSION_STATUS
	_button.text = "Report"
	_button.focus_mode = Control.FOCUS_NONE
	_button.pressed.connect(func(): report_requested.emit())
	_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, CORNER_MARGIN)
	_button.offset_left -= DOCK_CLEARANCE
	_button.offset_right -= DOCK_CLEARANCE

# Where the mark actually sits, in the design space. Public because the law test asks it rather
# than re-deriving the arithmetic above -- a guard that recomputes what it is guarding cannot fail.
func button_rect() -> Rect2:
	return Rect2(_button.global_position, _button.size)
