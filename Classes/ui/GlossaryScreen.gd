extends ModalCard
class_name GlossaryScreen

# The in-game reference page (#135): every Glossary term, browsable by category, reachable from
# the pause menu and the title screen. A ModalCard like its siblings — it claims the modal lock,
# so the board underneath is frozen while the player reads.
#
# Pure projection: every string comes from Glossary (authored entries + reaction lines composed
# from the live catalogs). Nothing here owns content.

signal closed

const BODY_WIDTH := 620
const BODY_HEIGHT := 380
const ENTRY_TITLE_FONT_SIZE := 18
const BODY_COLOR := Color(0.78, 0.78, 0.84)

var _entries_box: VBoxContainer
var _category_buttons: Dictionary = {}   # Glossary.Category -> Button

func _init() -> void:
	button_size = Vector2(150, 36)

# The PauseMenu.show_menu shape: build, wait for Close, free.
static func show_screen(game_node: Node) -> void:
	var screen := GlossaryScreen.new()
	game_node.ui_layer.add_child(screen)
	screen._build(game_node)
	await screen.closed
	screen.queue_free()

func _build(game_node: Node) -> void:
	var content := _build_chrome(game_node)
	_build_title(content, "GLOSSARY")

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", content_separation)
	content.add_child(body)

	# Category column. The active category's button is disabled — that IS the selection marker.
	var categories := VBoxContainer.new()
	categories.alignment = BoxContainer.ALIGNMENT_BEGIN
	categories.add_theme_constant_override("separation", 6)
	body.add_child(categories)
	for category: Glossary.Category in Glossary.Category.values():
		var button := _add_button(categories, Glossary.CATEGORY_NAMES[category],
			func(): _show_category(category))
		_category_buttons[category] = button

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(BODY_WIDTH, BODY_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)

	_entries_box = VBoxContainer.new()
	_entries_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entries_box.add_theme_constant_override("separation", 10)
	scroll.add_child(_entries_box)

	var close_row := _build_button_row(content, false, content_separation)
	_add_button(close_row, "Close", func(): closed.emit())

	_show_category(Glossary.Category.SQUADS)

func _show_category(category: Glossary.Category) -> void:
	for cat: Glossary.Category in _category_buttons:
		_category_buttons[cat].disabled = cat == category
	for child in _entries_box.get_children():
		child.queue_free()

	for term: Glossary.Term in Glossary.terms_in(category):
		_add_entry(Glossary.title(term), Glossary.long_text(term))

	# The elemental page ends with the interaction lists, composed from the authored reaction
	# data — the same .tres the resolver reads, so this page cannot drift from execution.
	if category == Glossary.Category.ELEMENTAL:
		_add_lines("Current reactions", Glossary.reaction_lines())
		_add_lines("Terrain reactions", Glossary.terrain_reaction_lines())

func _add_entry(entry_title: String, body_text: String) -> void:
	var title_label := Label.new()
	title_label.text = entry_title
	title_label.add_theme_font_size_override("font_size", ENTRY_TITLE_FONT_SIZE)
	_entries_box.add_child(title_label)
	_entries_box.add_child(_body_label(body_text))

func _add_lines(heading: String, lines: Array[String]) -> void:
	var title_label := Label.new()
	title_label.text = heading
	title_label.add_theme_font_size_override("font_size", ENTRY_TITLE_FONT_SIZE)
	_entries_box.add_child(title_label)
	for line in lines:
		_entries_box.add_child(_body_label("•  " + line))

# In-page text wraps via autowrap (real labels with real widths) — UiText.wrap is for
# tooltip_text, which has no width to wrap into.
func _body_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.modulate = BODY_COLOR
	return label


# Esc closes the page, the same door the Close button is. Without it this page swallowed the key
# outright, because game._input stands down while any modal is up.
func _on_cancel() -> bool:
	closed.emit()
	return true
