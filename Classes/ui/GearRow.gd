class_name GearRow
extends GearDropZone

# One line of gear (#741): a stash entry, or a slot in a unit's card. A drop ZONE that can also be
# picked up -- the same row is where a drag starts and where one can land, so a swap-shaped gesture
# needs no second widget.
#
# An EMPTY slot is a real row with a null item: it drags nothing and accepts anything its unit can
# take, which is what makes the card's six slots the drop target a player aims at.

var item: Item = null


func carry(gear: Item) -> void:
	item = gear


func _dragged_item() -> Item:
	return item


# How solid the lifted row reads against what it is passing over. Not quite opaque, so the cursor
# still says "carrying" rather than "this row now lives here".
const PREVIEW_ALPHA := 0.92


func _get_drag_data(at: Vector2) -> Variant:
	if item == null:
		return null
	set_drag_preview(build_drag_preview(at))
	return {PAYLOAD_ITEM: item, PAYLOAD_FROM: owner_unit}


# What the cursor carries. SPLIT OUT because set_drag_preview refuses outside a live drag, which no
# headless suite can start -- so the preview itself is the only half a test can hold and measure.
#
# TWO things here are the whole of why it drew NOTHING before (#798), and neither is about the plate:
#
#   * Z IS EXPLICIT AND ABSOLUTE. Godot parents the preview to the topmost Control of the row being
#     dragged -- this screen, which ModalCard draws at UiLayers.MENU_SCREEN over an OPAQUE backdrop --
#     and then makes it TOP-LEVEL, which severs the relative-z chain. So it inherited nothing, drew at
#     0, and was painted over by the very menu it was lifted out of. Every other part worked: it was
#     built, sized and positioned correctly the whole time, and the drop landed.
#   * IT IS THE SIZE OF THE ROW IT CAME FROM, held at the point it was GRABBED. Godot puts the
#     preview's own origin under the cursor, so a plate shrink-wrapped to its label hangs off to the
#     bottom-right of the pointer and reads as a tooltip rather than as something carried.
func build_drag_preview(grab: Vector2) -> Control:
	# The wrapper is what Godot positions at the cursor; the plate inside it carries the grab offset,
	# which is the only way to place it, since the engine writes the preview's position itself.
	var wrapper := Control.new()
	wrapper.z_index = UiLayers.DRAG_PREVIEW
	wrapper.z_as_relative = false
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE   # it rides the cursor; it must not catch it
	wrapper.modulate.a = PREVIEW_ALPHA

	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", QueueStyle.row_box(false, true))
	plate.custom_minimum_size = size   # the row's own footprint, so the grab point still means something
	plate.position = -grab
	wrapper.add_child(plate)

	var label := Label.new()
	label.text = item.display_name
	label.clip_text = true
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.TITLE_TEXT))
	plate.add_child(label)
	return wrapper
