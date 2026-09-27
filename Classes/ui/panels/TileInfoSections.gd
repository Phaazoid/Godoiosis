extends VBoxContainer
class_name TileInfoSections

# A tile's full readout (#1105): draws TileReadout's sections, one boxed section per layer -- a
# header strip (wearing the layer's board mark when it has one) over its rows, an explanation drawn
# quieter than a fact. Code-built (data-shaped UI) in QueueStyle's section box, header strip and
# paper inks, the same family as the action queue's sections, so it follows the player's palette.
# Boxes are asked at build time, so a redraw is all a palette switch needs (the host's restyle()).
#
# Which cell, and when to re-read it, is the host's; whether the re-read changed anything is this
# file's (show_if_changed), so no host keeps a diff of its own.

const HEADING_SIZE := 12
const NOTE_SIZE := 14
const MARK_SIZE := Vector2i(16, 16)

var _drawn := ""          # TileReadout.signature of what is drawn now
var _has_drawn := false   # a flag, not a "" sentinel: an empty readout signs as "" too (the rock bug)


func _init() -> void:
	add_theme_constant_override("separation", 8)


# Redraw only when the sections say something other than what is already drawn.
func show_if_changed(sections: Array[TileReadout.Section]) -> void:
	var said := TileReadout.signature(sections)
	if _has_drawn and said == _drawn:
		return
	_has_drawn = true
	_drawn = said
	show_sections(sections)


# The next show_if_changed draws whatever it is handed, the empty readout included.
func forget() -> void:
	_has_drawn = false


func show_sections(sections: Array[TileReadout.Section]) -> void:
	# remove_child as well as queue_free, so a freed section never counts toward this frame's size.
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for section in sections:
		add_child(_build_section(section))


func _build_section(section: TileReadout.Section) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", QueueStyle.section_box())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	panel.add_child(column)

	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", QueueStyle.header_box())
	column.add_child(strip)
	var heading_row := HBoxContainer.new()
	heading_row.add_theme_constant_override("separation", 6)
	strip.add_child(heading_row)
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
	heading.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.HEADER_TEXT))
	heading_row.add_child(heading)

	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 6)
	column.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)
	for row in section.rows:
		var label := Label.new()
		label.text = row.text
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if row.note:
			label.add_theme_font_size_override("font_size", NOTE_SIZE)
			label.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.HEADER_TEXT))
		else:
			label.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.BODY_TEXT))
		box.add_child(label)
	return panel


# Every label drawn, headings included, in order -- what a reader of the card sees.
func drawn_texts() -> Array[String]:
	var out: Array[String] = []
	for label in find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return out
