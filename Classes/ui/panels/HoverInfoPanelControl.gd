extends Control
class_name HoverInfoPanelControl

# The compact hover card. Auto-parks on the screen half opposite the hovered spot; the
# caller can push its left edge right of the docked inspect column (#68). Y is computed
# from the live viewport + stack size — never a hardcoded pixel constant (the old
# BOTTOM_LEFT_POS=410 broke on a viewport-height change once already).
#
# Since #135 the card is a STACK: the unit card from the scene, plus a code-built TILE block
# under it — shown for any hovered cell that is anything other than ordinary ground, with or
# without a unit standing on it. Line content is composed by HoverPresenter (board reads +
# Glossary short texts); this file only renders and parks it.

const MARGIN := 8
const TILE_BLOCK_GAP := 4
const TILE_BLOCK_WIDTH := 160   # the unit card's width, so the stack reads as one card
const TILE_ICON_SIZE := Vector2i(32, 32)

@onready var hover_panel: Panel = $HoverPanel
@onready var hover_gridcontainer = $HoverPanel/HoverInfoGridContainer

var current_unit: Unit
var _tile_panel: PanelContainer
var _tile_box: VBoxContainer
var _tile_icon: TextureRect
var _tile_header: Label
var _tile_lines_box: VBoxContainer

# Set here rather than in the .tscn so UiLayers is the single answer for the whole UI stack --
# the scene used to author a bare 2, which agreed with the rest of the order only by luck.
# The tile card is code-built (data-shaped UI): same stylebox as the unit card's Panel, so the
# two halves of the stack match by construction rather than by copied values.
func _ready() -> void:
	z_index = UiLayers.HOVER_PANEL
	_tile_panel = PanelContainer.new()
	_tile_panel.visible = false
	_tile_panel.add_theme_stylebox_override("panel", hover_panel.get_theme_stylebox("panel"))
	_tile_panel.custom_minimum_size.x = TILE_BLOCK_WIDTH
	_tile_box = VBoxContainer.new()
	_tile_panel.add_child(_tile_box)
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 6)
	_tile_box.add_child(header_row)
	_tile_icon = TextureRect.new()
	_tile_icon.custom_minimum_size = TILE_ICON_SIZE
	_tile_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tile_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tile_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	header_row.add_child(_tile_icon)
	_tile_header = Label.new()
	header_row.add_child(_tile_header)
	_tile_lines_box = VBoxContainer.new()
	_tile_box.add_child(_tile_lines_box)
	add_child(_tile_panel)

# One call per hover: unit card, tile card, or both, parked together. world_pos anchors the
# top-or-bottom parking decision — the hovered unit's position, or the hovered cell's.
# The tile card shows whenever it has ANY content (every real tile does, since #135 round 2);
# `icon` null + `header` empty = a decorative NONE-kind tile, which shows lines only.
func show_hover(unit: Unit, tile_icon: Texture2D, tile_header: String, tile_lines: Array[String],
		world_pos: Vector2, left_x: int = MARGIN) -> void:
	var tile_has_content: bool = tile_header != "" or not tile_lines.is_empty()
	if unit == null and not tile_has_content:
		clear()
		return
	visible = true
	current_unit = unit
	hover_panel.visible = unit != null
	if unit != null:
		hover_gridcontainer.set_unit(unit)
	_set_tile_block(tile_icon, tile_header, tile_lines)
	_tile_panel.visible = tile_has_content
	_tile_panel.position = Vector2(0, hover_panel.size.y + TILE_BLOCK_GAP) \
		if hover_panel.visible else Vector2.ZERO
	_park(world_pos, left_x)

func clear():
	current_unit = null
	visible = false

func _set_tile_block(icon: Texture2D, header: String, lines: Array[String]) -> void:
	_tile_icon.texture = icon
	_tile_icon.visible = icon != null
	_tile_header.text = header
	_tile_header.visible = header != ""
	# remove_child as well as queue_free (the ModalCard._clear_button_row trick): freed-but-parented
	# children would still pollute the same-frame minimum-size measurement _stack_height makes.
	for child in _tile_lines_box.get_children():
		_tile_lines_box.remove_child(child)
		child.queue_free()
	for line in lines:
		var label := Label.new()
		label.text = line
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = TILE_BLOCK_WIDTH
		_tile_lines_box.add_child(label)

func _park(world_pos: Vector2, left_x: int) -> void:
	var screen_pos: Vector2 = get_viewport().get_canvas_transform() * world_pos
	var y: int = MARGIN
	if screen_pos.y <= get_viewport_rect().size.y / 2.0:
		y = int(get_viewport_rect().size.y - _stack_height() - MARGIN)
	position = Vector2(left_x, y)

# Combined minimum for the tile block rather than its .size: size settles a frame after a
# rebuild, and parking must be right on the frame the content changes.
func _stack_height() -> float:
	var height: float = 0.0
	if hover_panel.visible:
		height += hover_panel.size.y
	if _tile_panel.visible:
		if hover_panel.visible:
			height += TILE_BLOCK_GAP
		height += _tile_panel.get_combined_minimum_size().y
	return height
