extends VBoxContainer
class_name TileInfoSections

# The Inspect dock's tile half (#1105): draws TileReadout's sections, one boxed section per layer --
# a heading (wearing the layer's board mark when it has one) over its rows, an explanation drawn
# quieter than a fact. Code-built (data-shaped UI) and handed the dock's own section stylebox, so it
# matches the inventory box beside it by construction rather than by copied values.
#
# It only renders what it is handed; which cell, and when to re-read it, is UnitInfoPanelControl's.

const HEADING_SIZE := 12
const NOTE_SIZE := 14
const HEADING_COLOR := Color(0.6, 0.62, 0.6)
const NOTE_COLOR := Color(0.7, 0.72, 0.7)
const MARK_SIZE := Vector2i(16, 16)

var section_box: StyleBox


func _init(box: StyleBox = null) -> void:
	section_box = box
	add_theme_constant_override("separation", 8)


func show_sections(sections: Array[TileReadout.Section]) -> void:
	# remove_child as well as queue_free, so a freed section never counts toward this frame's size.
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for section in sections:
		add_child(_build_section(section))


func _build_section(section: TileReadout.Section) -> PanelContainer:
	var panel := PanelContainer.new()
	if section_box != null:
		panel.add_theme_stylebox_override("panel", section_box)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)

	var heading_row := HBoxContainer.new()
	heading_row.add_theme_constant_override("separation", 6)
	if section.marking != null:
		var mark := TextureRect.new()
		mark.texture = section.marking
		mark.modulate = section.marking_color
		mark.custom_minimum_size = MARK_SIZE
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		heading_row.add_child(mark)
	var heading := Label.new()
	heading.text = section.heading
	heading.add_theme_font_size_override("font_size", HEADING_SIZE)
	heading.add_theme_color_override("font_color", HEADING_COLOR)
	heading_row.add_child(heading)
	box.add_child(heading_row)

	for row in section.rows:
		var label := Label.new()
		label.text = row.text
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if row.note:
			label.add_theme_font_size_override("font_size", NOTE_SIZE)
			label.add_theme_color_override("font_color", NOTE_COLOR)
		box.add_child(label)
	return panel


# Every label drawn, headings included, in order -- what a reader of the dock sees.
func drawn_texts() -> Array[String]:
	var out: Array[String] = []
	for label in find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return out
