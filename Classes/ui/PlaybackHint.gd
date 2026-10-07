extends PanelContainer
class_name PlaybackHint

# The playback keys, on screen while they work (#545): "[key] -> Speed up  [key] -> Skip", in the
# bottom-right slot End Turn leaves empty during playback. A dumb view: PlaybackControl decides when
# it shows and whether Shift is down, and pushes both every frame.
#
# The KEYS are read from Controls, never spelled (the F3 sign's idiom, MissionStatusPanel), so the
# hint cannot name a binding the Input Map has not got. The WORDS are placeholders, the dev's to keep.
# Built in code rather than a .tscn, so no editor save can leave a scene node behind it (#1121).

const FAST_FORWARD_ACTION := "fast_forward"
const SKIP_ACTION := "skip_playback"
const FAST_FORWARD_LABEL := "Speed up"   # PLACEHOLDER, like every line a player reads
const SKIP_LABEL := "Skip"               # PLACEHOLDER

const TEXT_COLOR := Color(0.91, 0.91, 0.91)
const HELD_COLOR := Color(1.0, 0.82, 0.48)
const CAP_BORDER := Color(0.92, 0.92, 0.92, 0.75)
const ENTRY_GAP := 16

var _held := false
# One per entry, fast-forward first.
var _caps: Array[PanelContainer] = []
var _cap_texts: Array[Label] = []
var _labels: Array[Label] = []


# `frame` is the objectives panel's own box, so the two corner panels cannot drift apart.
func _init(frame: StyleBox = null) -> void:
	name = "PlaybackHint"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = UiLayers.MISSION_STATUS   # End Turn's tier: the same slot, the same always-on corner
	visible = false
	if frame != null:
		add_theme_stylebox_override("panel", frame)
	custom_minimum_size.y = MissionStatusPanel.BUTTON_CLEARANCE - EndTurnButton.CORNER_MARGIN
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", ENTRY_GAP)
	add_child(row)
	row.add_child(_entry(FAST_FORWARD_ACTION, FAST_FORWARD_LABEL))
	row.add_child(_entry(SKIP_ACTION, SKIP_LABEL))
	_apply_held()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE,
			EndTurnButton.CORNER_MARGIN)
	# Grows leftward and upward from the corner, so a longer key name never pushes it off screen.
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN


# Lights the Speed up entry while Shift is down.
func set_held(held: bool) -> void:
	if held == _held:
		return
	_held = held
	_apply_held()


func is_held() -> bool:
	return _held


# Everything the hint says, in order -- for a case to read without walking the tree.
func readout() -> String:
	var parts: Array[String] = []
	for i in _labels.size():
		parts.append("%s %s" % [_cap_texts[i].text, _labels[i].text])
	return "  ".join(parts)


func _entry(action: String, words: String) -> HBoxContainer:
	var entry := HBoxContainer.new()
	entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_theme_constant_override("separation", 6)
	var cap := PanelContainer.new()
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap_text := Label.new()
	cap_text.text = Controls.key_for_action(action)
	cap_text.add_theme_font_size_override("font_size", 12)
	cap.add_child(cap_text)
	entry.add_child(cap)
	var label := Label.new()
	label.text = "→ " + words
	label.add_theme_font_size_override("font_size", 13)
	entry.add_child(label)
	_caps.append(cap)
	_cap_texts.append(cap_text)
	_labels.append(label)
	return entry


func _apply_held() -> void:
	for i in _caps.size():
		_style(i, _held and i == 0)


func _style(i: int, lit: bool) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(HELD_COLOR, 0.22) if lit else Color(1, 1, 1, 0.06)
	box.border_color = HELD_COLOR if lit else CAP_BORDER
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	box.content_margin_left = 6
	box.content_margin_right = 6
	_caps[i].add_theme_stylebox_override("panel", box)
	var ink := HELD_COLOR if lit else TEXT_COLOR
	_cap_texts[i].add_theme_color_override("font_color", ink)
	_labels[i].add_theme_color_override("font_color", ink)
