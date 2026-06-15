extends VBoxContainer
class_name TileBrushTool

const TILES := {
	"Grass": Vector2i(5, 0),
	"Mud": Vector2i(5, 4),
	"Rock": Vector2i(18, 10),
}

var brush_active := false
var selected_tile := Vector2i(5, 0)

@onready var tile_dropdown: OptionButton = %TileDropdown

func _ready():
	for tile_name in TILES:
		tile_dropdown.add_item(tile_name)

func _on_tile_brush_toggled(pressed: bool):
	brush_active = pressed

func _on_tile_dropdown_item_selected(index: int):
	var key = TILES.keys()[index]
	selected_tile = TILES[key]

func deactivate():
	$Panel/TileBrushRow/TileBoxCheck.button_pressed = false
