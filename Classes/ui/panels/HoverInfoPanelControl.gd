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

@onready var hover_panel: Panel = $HoverPanel
@onready var hover_gridcontainer = $HoverPanel/HoverInfoGridContainer

var current_unit: Unit
var _tile_panel: PanelContainer
var _tile_lines_box: VBoxContainer

# Set here rather than in the .tscn so UiLayers is the single answer for the whole UI stack --
# the scene used to author a bare 2, which agreed with the rest of the order only by luck.
func _ready() -> void:
	z_index = UiLayers.HOVER_PANEL
	_tile_panel = PanelContainer.new()
	_tile_panel.visible = false
	_tile_lines_box = VBoxContainer.new()
	_tile_panel.add_child(_tile_lines_box)
	add_child(_tile_panel)

# One call per hover: unit card, tile block, or both, parked together. world_pos anchors the
# top-or-bottom parking decision — the hovered unit's position, or the hovered cell's.
func show_hover(unit: Unit, tile_lines: Array[String], world_pos: Vector2,
		left_x: int = MARGIN) -> void:
	if unit == null and tile_lines.is_empty():
		clear()
		return
	visible = true
	current_unit = unit
	hover_panel.visible = unit != null
	if unit != null:
		hover_gridcontainer.set_unit(unit)
	_set_tile_lines(tile_lines)
	_tile_panel.position = Vector2(0, hover_panel.size.y + TILE_BLOCK_GAP) \
		if hover_panel.visible else Vector2.ZERO
	_park(world_pos, left_x)

func clear():
	current_unit = null
	visible = false

func _set_tile_lines(lines: Array[String]) -> void:
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
	_tile_panel.visible = not lines.is_empty()

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
