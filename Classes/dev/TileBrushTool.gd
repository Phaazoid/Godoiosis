extends VBoxContainer
class_name TileBrushTool

const TILES := {
	"Grass": Vector2i(5, 0),
	"Mud": Vector2i(5, 4),
	"Rock": Vector2i(18, 10),
}

var brush_active := false
var selected_tile := Vector2i(5, 0)
var game   # injected by DevOverlay

var _width_spin: SpinBox
var _height_spin: SpinBox

@onready var tile_dropdown: OptionButton = %TileDropdown

func _ready():
	for tile_name in TILES:
		tile_dropdown.add_item(tile_name)
	_build_extra_controls()

func _on_tile_brush_toggled(pressed: bool):
	brush_active = pressed

func _on_tile_dropdown_item_selected(index: int):
	var key = TILES.keys()[index]
	selected_tile = TILES[key]

func deactivate():
	$Panel/TileBrushRow/TileBoxCheck.button_pressed = false


func _build_extra_controls() -> void:
	# Part 2: visible erase hint (the tab tooltip already says it, but this is in-panel).
	var note := Label.new()
	note.text = "Left-drag paints  ·  right-click erases"
	add_child(note)

	# Part 1: map-resize row.
	var row := HBoxContainer.new()

	var size_label := Label.new()
	size_label.text = "Map size (cells)"
	row.add_child(size_label)

	_width_spin = SpinBox.new()
	_width_spin.min_value = 1
	_width_spin.max_value = 200
	_width_spin.value = 20
	row.add_child(_width_spin)

	_height_spin = SpinBox.new()
	_height_spin.min_value = 1
	_height_spin.max_value = 200
	_height_spin.value = 12
	row.add_child(_height_spin)

	var apply := Button.new()
	apply.text = "Resize Map"
	apply.pressed.connect(_on_resize_pressed)
	row.add_child(apply)

	add_child(row)

func _on_resize_pressed() -> void:
	if game == null:
		return
	game.resize_map(int(_width_spin.value), int(_height_spin.value), selected_tile)
