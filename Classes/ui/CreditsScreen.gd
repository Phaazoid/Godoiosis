extends ModalCard
class_name CreditsScreen

# The in-game credits page (#139): who made what in this build, reachable from the title screen.
# A ModalCard like its siblings — it claims the modal lock, so the board underneath is frozen.
#
# Pure projection: every string comes from Credits. Nothing here owns content, and in particular
# nothing here decides who is CREDITED — two of these rows are licence conditions, and the rule
# that they ship lives next to the data that says so.
#
# TITLE SCREEN ONLY, unlike GlossaryScreen which is on the pause menu too. #724 already calls the
# pause menu "a build history, not a decision" and leaves its ordering as the dev's open call;
# adding a ninth row to a list he has flagged as too long makes that ticket harder to settle.
# Credits is a front door thing. One line in PauseMenu whenever he wants it in both.

signal closed

const BODY_WIDTH := 620
const BODY_HEIGHT := 380
const SECTION_FONT_SIZE := 20
const NAME_FONT_SIZE := 16
const SECTION_COLOR := Color(0.72, 0.76, 0.88)
const ROLE_COLOR := Color(0.78, 0.78, 0.84)
const DETAIL_COLOR := Color(0.62, 0.66, 0.74)

var _entries_box: VBoxContainer


func _init() -> void:
	button_size = Vector2(150, 36)


# The GlossaryScreen shape: build, wait for Close, free.
static func show_screen(game_node: Node) -> void:
	var screen := CreditsScreen.new()
	game_node.ui_layer.add_child(screen)
	screen._build(game_node)
	await screen.closed
	screen.queue_free()


func _build(game_node: Node) -> void:
	var content := _build_chrome(game_node)
	_build_title(content, "CREDITS")

	# GlossaryScreen's shape: a bounded scroll between the title and Close, horizontal disabled so
	# a long detail line wraps instead of widening the card.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(BODY_WIDTH, BODY_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)

	_entries_box = VBoxContainer.new()
	_entries_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entries_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_entries_box)

	for section: Credits.Section in Credits.Section.values():
		var rows: Array = Credits.ENTRIES.get(section, [])
		if rows.is_empty():
			continue
		_add_section(Credits.SECTION_NAMES[section])
		for entry: Dictionary in rows:
			_add_entry(entry)

	var close_row := _build_button_row(content, false, content_separation)
	_add_button(close_row, "Close", func(): closed.emit())


func _add_section(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	label.modulate = SECTION_COLOR
	# Breathing room above a heading, but not above the first one.
	if _entries_box.get_child_count() > 0:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 12)
		_entries_box.add_child(spacer)
	_entries_box.add_child(label)


func _add_entry(entry: Dictionary) -> void:
	var name_label := Label.new()
	name_label.text = String(entry.get("name", ""))
	name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	_entries_box.add_child(name_label)

	var role := String(entry.get("role", ""))
	if role != "":
		_entries_box.add_child(_line(role, ROLE_COLOR))

	var detail := String(entry.get("detail", ""))
	if detail != "":
		_entries_box.add_child(_line(detail, DETAIL_COLOR))


# In-page text wraps via autowrap (real labels with real widths) — UiText.wrap is for
# tooltip_text, which has no width to wrap into.
func _line(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.modulate = color
	return label


# Esc closes the page, the same door the Close button is. Without it this page swallows the key
# outright, because game._input stands down while any modal is up.
func _on_cancel() -> bool:
	closed.emit()
	return true
