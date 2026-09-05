class_name GearRow
extends GearDropZone

# One line of gear (#741): a stash entry, or a slot in a unit's card. A drop ZONE that can also be
# picked up -- the same row is where a drag starts and where one can land, so a swap-shaped gesture
# needs no second widget.
#
# An EMPTY slot is a real row with a null item: it drags nothing and accepts anything its unit can
# take, which is what makes the card's six slots the drop target a player aims at.

var item: EquippableData = null


func carry(gear: EquippableData) -> void:
	item = gear


func _dragged_item() -> EquippableData:
	return item


func _get_drag_data(_at: Vector2) -> Variant:
	if item == null:
		return null
	var preview := Label.new()
	preview.text = item.display_name
	preview.add_theme_font_size_override("font_size", 11)
	preview.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.HEADER_TEXT))
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", QueueStyle.row_box(false, true))
	plate.add_child(preview)
	set_drag_preview(plate)
	return {PAYLOAD_ITEM: item, PAYLOAD_FROM: owner_unit}
