extends Control
class_name AimStrip

# The aim names itself (#929): a strip at the bottom centre while an aim is open, saying which attack
# is being aimed and which weapon fires it. The board already shows WHERE an attack lands and the
# health bars WHAT it would do; with F / Shift+F cycling every attack across every carried weapon,
# neither says WHICH one is up, and that is this strip's one job.
#
# A DUMB VIEW: game.gd tells it what to say at the aim's two doors (enter_attack_mode, which the cycle
# re-enters, and exit_current_mode) and it asks nothing of the board. The cycle keys come through
# Controls.key_for_action, never spelled, so it cannot advertise a binding the Input Map has not got
# (#1051's rule) -- and they show only when there is something to cycle to. They are BUTTONS as well,
# onto the keys' own door: cycle_requested, which game wires to cycle_aimed_attack.
#
# Root is full-rect with mouse_filter IGNORE (PreMissionBar's shape), so the board stays clickable
# around it; the BOX catches the mouse, because a click through it lands on the board and aims at the
# cell underneath (it queued an attack at nothing). tests/law/test_hud_catches_its_clicks.gd walks
# every HUD surface for that. The box sits on the panel FRAME, which is dark in both palettes, so
# every ink here is a frame role. It parks at the TOP while a dialogue is up (#1033's rule): the
# dialogue owns the bottom strip and draws over the HUD.

# step +1 for the next attack, -1 for the previous, as F / Shift+F.
signal cycle_requested(step: int)

const EDGE_MARGIN := 14
const PAD_H := 12
const PAD_V := 5
const SEPARATION := 10
const NAME_FONT_SIZE := 16
const SOURCE_FONT_SIZE := 13
const HINT_FONT_SIZE := 11
# Player-facing wording, the dev's to reword: a cycled-to weapon is equipped by the click (#929).
const SWAP_TEXT := "swaps on click"

# () -> bool: is a dialogue up. game wires the director's is_talking; unset reads as no.
var talking_source: Callable

var _box: PanelContainer
var _back: Button
var _attack: Label
var _source: Label
var _swap: Label
var _count: Label
var _next: Button


static func open(game_node: Node) -> AimStrip:
	var strip := AimStrip.new()
	var layer: CanvasLayer = game_node.ui_layer
	layer.add_child(strip)
	strip._build()
	return strip


func _build() -> void:
	name = "AimStrip"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = PanelContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_box)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", PAD_H)
	margin.add_theme_constant_override("margin_right", PAD_H)
	margin.add_theme_constant_override("margin_top", PAD_V)
	margin.add_theme_constant_override("margin_bottom", PAD_V)
	_box.add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", SEPARATION)
	margin.add_child(row)
	_back = _arrow(row, -1)
	_attack = _label(row, NAME_FONT_SIZE)
	_source = _label(row, SOURCE_FONT_SIZE)
	_swap = _label(row, HINT_FONT_SIZE)
	_swap.text = SWAP_TEXT
	_count = _label(row, HINT_FONT_SIZE)
	_next = _arrow(row, 1)
	visible = false


func _label(row: HBoxContainer, font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	return label


# A key hint that is also the click. No box in any state, so it reads as the hint it was; the ink
# lifts on hover instead. FOCUS_NONE, or Space and Enter would press it (PreMissionBar's reason).
func _arrow(row: HBoxContainer, step: int) -> Button:
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.pressed.connect(cycle_requested.emit.bind(step))
	row.add_child(button)
	return button


# All four states: a Button falls back to the theme's ink for any state left unset.
func _ink_arrow(button: Button) -> void:
	var rest := QueueStyle.ink(QueueStyle.Role.FRAME_TEXT)
	var lit := QueueStyle.ink(QueueStyle.Role.TITLE_TEXT)
	button.add_theme_color_override("font_color", rest)
	button.add_theme_color_override("font_focus_color", rest)
	button.add_theme_color_override("font_hover_color", lit)
	button.add_theme_color_override("font_pressed_color", lit)


# Say what is being aimed. `at` is the aim's place in the cycle, 0-based, or -1 when it is not
# in it; `count` is how many attacks the cycle holds. `swaps` is whether the click would equip
# `source_name` -- an attack from a carried weapon rather than the one in hand.
func show_aim(attack_name: String, source_name: String, swaps: bool, at: int, count: int) -> void:
	_box.add_theme_stylebox_override("panel", QueueStyle.panel_box())
	_attack.text = attack_name
	_attack.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.TITLE_TEXT))
	_source.text = source_name
	_source.visible = source_name != ""
	# The frame's one warm ink, which the queue's refusal lines also wear: a swap is a consequence
	# the click carries, and the plain frame grey would let it read as a caption.
	var source_role := QueueStyle.Role.FRAME_REFUSED_TEXT if swaps else QueueStyle.Role.FRAME_TEXT
	_source.add_theme_color_override("font_color", QueueStyle.ink(source_role))
	_swap.visible = swaps
	_swap.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.FRAME_REFUSED_TEXT))
	var cycles := count > 1
	_back.visible = cycles
	_next.visible = cycles
	_count.visible = cycles and at >= 0
	_back.text = "◀ %s" % Controls.key_for_action("select_previous_squadmate")
	_next.text = "%s ▶" % Controls.key_for_action("select_next_squadmate")
	_count.text = "%d / %d" % [at + 1, count]
	_count.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.FRAME_TEXT))
	_ink_arrow(_back)
	_ink_arrow(_next)
	visible = true
	_park()


func hide_aim() -> void:
	visible = false


# What the strip says, joined -- for a test to read without walking the row.
func shown_text() -> String:
	var parts: Array[String] = []
	if _back.visible:
		parts.append(_back.text)
	for label: Label in [_attack, _source, _swap, _count]:
		if label.visible and label.text != "":
			parts.append(label.text)
	if _next.visible:
		parts.append(_next.text)
	return " ".join(parts)


# The two arrows, for a test to click: back first.
func arrows() -> Array[Button]:
	return [_back, _next]


func _process(_delta: float) -> void:
	if visible:
		_park()


# Bottom centre, or top centre while a dialogue holds the bottom. Re-read every frame the strip is up,
# because a dialogue can start or end under an open aim and the viewport can resize.
func _park() -> void:
	var box_size := _box.get_combined_minimum_size()
	_box.size = box_size
	var talking := talking_source.is_valid() and bool(talking_source.call())
	var y: float = float(EDGE_MARGIN) if talking else size.y - box_size.y - EDGE_MARGIN
	_box.position = Vector2(roundf((size.x - box_size.x) / 2.0), y)
