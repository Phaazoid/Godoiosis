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
# (#1051's rule) -- and they show only when there is something to cycle to.
#
# Root is full-rect with mouse_filter IGNORE (PreMissionBar's shape), so it eats no click. The box
# sits on the panel FRAME, which is dark in both palettes, so every ink here is a frame role. It parks
# at the TOP while a dialogue is up (#1033's rule): the dialogue owns the bottom strip and draws over
# the HUD.

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
var _back: Label
var _attack: Label
var _source: Label
var _swap: Label
var _count: Label
var _next: Label


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
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_back = _label(row, HINT_FONT_SIZE)
	_attack = _label(row, NAME_FONT_SIZE)
	_source = _label(row, SOURCE_FONT_SIZE)
	_swap = _label(row, HINT_FONT_SIZE)
	_swap.text = SWAP_TEXT
	_count = _label(row, HINT_FONT_SIZE)
	_next = _label(row, HINT_FONT_SIZE)
	visible = false


func _label(row: HBoxContainer, font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	return label


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
	for hint: Label in [_back, _next, _count]:
		hint.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.FRAME_TEXT))
	visible = true
	_park()


func hide_aim() -> void:
	visible = false


# What the strip says, joined -- for a test to read without walking the row.
func shown_text() -> String:
	var parts: Array[String] = []
	for label: Label in [_back, _attack, _source, _swap, _count, _next]:
		if label.visible and label.text != "":
			parts.append(label.text)
	return " ".join(parts)


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
