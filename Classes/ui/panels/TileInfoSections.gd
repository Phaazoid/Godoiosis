extends VBoxContainer
class_name TileInfoSections

# A tile's full readout (#1105): draws TileReadout's sections, one boxed section per layer -- a
# header strip (wearing the layer's board mark when it has one) over its rows, an explanation drawn
# quieter than a fact. Code-built (data-shaped UI) in QueueStyle's section box, header strip and
# paper inks, the same family as the action queue's sections, so it follows the player's palette.
# Boxes are asked at build time, so a redraw is all a palette switch needs (the host's restyle()).
#
# ONE SECTION AT A TIME (#1324, dev 2026-10-21): the busiest tile already filled the screen before
# the Air section, and the card cannot scroll (the wheel zooms the board). With more than one
# section, a tab row above the box shows one tab per section in the board mark it wears, the shown
# one lit, and a key-and-arrow control naming what turns the page. A tab or the control turns it
# with a click; the key reaches next_page() through the host.
#
# Which cell, and when to re-read it, is the host's; whether the re-read changed anything is this
# file's (show_if_changed), so no host keeps a diff of its own. A live redraw keeps the section on
# show (matched by layer and heading); a new tile (forget) starts on its first.

const HEADING_SIZE := 12
const NOTE_SIZE := 14
const MARK_SIZE := Vector2i(16, 16)
const TAB_SIZE := Vector2i(26, 22)
const NEXT_ARROW := "→"

# The tile's own picture, worn by the tab of a section with no mark of its own (Ground). The host's.
var fallback_mark: Texture2D
# The key that turns the page, as the control names it ("T"). The host's, read off Controls.
var key_label := ""

var _drawn := ""          # TileReadout.signature of what is drawn now
var _has_drawn := false   # a flag, not a "" sentinel: an empty readout signs as "" too (the rock bug)
var _sections: Array[TileReadout.Section] = []
var _page_key := ""       # which section is on show, as _key() spells it; "" = the first


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


# The next draw starts on the first section: a tile newly opened. A redraw of the same card (a
# restyle, the followed unit walking on) keeps the section on show instead.
func first_page() -> void:
	_page_key = ""


func show_sections(sections: Array[TileReadout.Section]) -> void:
	_sections = sections
	var index := page()
	_page_key = _key(sections[index]) if not sections.is_empty() else ""
	# remove_child as well as queue_free, so a freed section never counts toward this frame's size.
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if sections.size() > 1:
		add_child(_build_tabs(index))
	if not sections.is_empty():
		add_child(_build_section(sections[index]))


# Which section is on show: the one the page key names, else the first.
func page() -> int:
	for i in _sections.size():
		if _key(_sections[i]) == _page_key:
			return i
	return 0


func page_count() -> int:
	return _sections.size()


# The next section, wrapping. What the key and the arrow do.
func next_page() -> void:
	if _sections.size() > 1:
		turn_to((page() + 1) % _sections.size())


func turn_to(index: int) -> void:
	if index < 0 or index >= _sections.size():
		return
	_page_key = _key(_sections[index])
	show_sections(_sections)


static func _key(section: TileReadout.Section) -> String:
	return "%d|%s" % [section.layer, section.heading]


# One tab per section in its board mark, the shown one lit, then the key and its arrow. A press is
# deferred, because the redraw frees the button that is emitting it (#741's locked-object trap).
func _build_tabs(shown: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	for i in _sections.size():
		var tab := Button.new()
		tab.custom_minimum_size = TAB_SIZE
		tab.focus_mode = Control.FOCUS_NONE
		tab.icon = _sections[i].marking if _sections[i].marking != null else fallback_mark
		tab.expand_icon = true
		tab.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tab.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var tint: Color = _sections[i].marking_color if _sections[i].marking != null else Color.WHITE
		for state: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
			tab.add_theme_color_override(state, tint)
		var box := _tab_box(i == shown)
		for state: String in ["normal", "hover", "pressed", "focus"]:
			tab.add_theme_stylebox_override(state, box)
		tab.pressed.connect(turn_to.bind(i), CONNECT_DEFERRED)
		row.add_child(tab)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var next := Button.new()
	next.text = "%s %s" % [key_label, NEXT_ARROW] if key_label != "" else NEXT_ARROW
	next.focus_mode = Control.FOCUS_NONE
	next.custom_minimum_size.y = TAB_SIZE.y
	next.add_theme_font_size_override("font_size", HEADING_SIZE)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		next.add_theme_color_override(state, QueueStyle.ink(QueueStyle.Role.HEADER_TEXT))
	var plain := _tab_box(false)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		next.add_theme_stylebox_override(state, plain)
	next.pressed.connect(next_page, CONNECT_DEFERRED)
	row.add_child(next)
	return row


# The header strip's ground for a tab; the shown one a row's hover ground, underlined in the header ink.
static func _tab_box(lit: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = QueueStyle.ink(QueueStyle.Role.ROW_HOVER_BG if lit else QueueStyle.Role.HEADER_BG)
	box.set_corner_radius_all(3)
	box.content_margin_left = 5.0
	box.content_margin_right = 5.0
	if lit:
		box.border_width_bottom = 2
		box.border_color = QueueStyle.ink(QueueStyle.Role.HEADER_TEXT)
	return box


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
