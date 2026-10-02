extends LineEdit
class_name DevSearchBox

# The dev-tools search box (#1184): top right of the window, visible from every leaf. Typing lists
# what DevSearch finds; choosing a result emits `chosen`, and DevOverlay.reveal goes there.
#
# The result list is an in-window panel under the box, NOT a popup: a popup is a subwindow in a
# window that embeds its own (CLAUDE.md sharp edges), and a PopupMenu takes the keyboard away from
# the field being typed in. Nothing in the list can take focus, so typing carries on while it shows.
#
# After a jump the box clears and gives focus up. DevOverlay._input drops dev keys while a LineEdit
# has focus -- the guard that stops a query firing Z or C -- so a box that kept focus would leave the
# brush keys dead until something else was clicked.

signal chosen(entry: Dictionary)

const MAX_ROWS := 8
const LIST_WIDTH := 520.0
const KIND_WIDTH := 62.0
const DIM := Color(0.62, 0.62, 0.66)
const LIST_BG := Color(0.13, 0.13, 0.15)
const LIST_EDGE := Color(0.36, 0.36, 0.4)
const HIGHLIGHT_BG := Color(0.24, 0.3, 0.42)

# () -> Array[Dictionary]: the window's DevSearch.index, handed in so the box never reaches up.
var index_source: Callable

var _entries: Array[Dictionary] = []
var _results: Array[Dictionary] = []
var _highlight := 0
var _panel: PanelContainer
var _rows: Array[PanelContainer] = []
var _kinds: Array[Label] = []
var _texts: Array[RichTextLabel] = []
var _footer: Label
var _row_box: StyleBoxFlat
var _row_lit: StyleBoxFlat


func _ready() -> void:
	placeholder_text = "Search tabs, sections, values"
	clear_button_enabled = true
	_build_list()
	text_changed.connect(_refresh)
	focus_entered.connect(_reindex)
	# Deferred, so a press on a row still lands before the list goes.
	focus_exited.connect(func() -> void: _close_list.call_deferred())


func _build_list() -> void:
	_panel = PanelContainer.new()
	_panel.top_level = true   # draws over the page below, positioned in window space
	_panel.visible = false
	_panel.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	var frame := StyleBoxFlat.new()
	frame.bg_color = LIST_BG
	frame.border_color = LIST_EDGE
	frame.set_border_width_all(1)
	frame.set_content_margin_all(4)
	_panel.add_theme_stylebox_override("panel", frame)
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	_panel.add_child(column)
	_row_box = StyleBoxFlat.new()
	_row_box.bg_color = Color(0, 0, 0, 0)
	_row_box.set_content_margin_all(4)
	_row_lit = _row_box.duplicate()
	_row_lit.bg_color = HIGHLIGHT_BG
	for i in MAX_ROWS:
		column.add_child(_build_row(i))
	_footer = Label.new()
	_footer.add_theme_font_size_override("font_size", 11)
	_footer.add_theme_color_override("font_color", DIM)
	column.add_child(_footer)


func _build_row(i: int) -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _row_box)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(_on_row_input.bind(i))
	row.mouse_entered.connect(_light.bind(i))
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var kind := Label.new()
	kind.custom_minimum_size = Vector2(KIND_WIDTH, 0)
	kind.add_theme_font_size_override("font_size", 11)
	kind.add_theme_color_override("font_color", DIM)
	line.add_child(kind)
	var text_label := RichTextLabel.new()
	text_label.bbcode_enabled = true
	text_label.fit_content = true
	text_label.scroll_active = false
	text_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	text_label.clip_contents = true
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(text_label)
	_rows.append(row)
	_kinds.append(kind)
	_texts.append(text_label)
	return row


# Indexed on taking focus rather than per keystroke: a walk of the whole window costs ~14 ms
# (measured, 862 entries over ~4200 nodes), and nothing on a page rebuilds while you type.
func _reindex() -> void:
	_entries.clear()
	if index_source.is_valid():
		_entries = index_source.call()
	if text != "":
		_refresh(text)


func _refresh(query: String) -> void:
	if _entries.is_empty() and index_source.is_valid():
		_entries = index_source.call()
	_results.clear()
	for entry: Dictionary in DevSearch.rank(_entries, query):
		if is_instance_valid(entry["control"]):
			_results.append(entry)
	_highlight = 0
	if query.strip_edges() == "":
		_close_list()
		return
	var words := query.to_lower().split(" ", false)
	for i in MAX_ROWS:
		var shown := i < _results.size()
		_rows[i].visible = shown
		if shown:
			var entry: Dictionary = _results[i]
			_kinds[i].text = DevSearch.KIND_LABELS[entry["kind"]]
			_texts[i].text = _row_text(entry, words[0] if not words.is_empty() else "")
	var more := _results.size() - MAX_ROWS
	var hint := "Up/Down move · Enter go · Esc clear"
	if _results.is_empty():
		_footer.text = "No matches · Esc clear"
	elif more > 0:
		_footer.text = "+%d more · %s" % [more, hint]
	else:
		_footer.text = hint
	_paint_highlight()
	_place_list()
	_panel.visible = true


# The name with the first query word bolded, then where it lives in grey.
func _row_text(entry: Dictionary, word: String) -> String:
	var entry_name: String = entry["name"]
	var at := entry_name.to_lower().find(word) if word != "" else -1
	var shown := _escape(entry_name)
	if at >= 0:
		shown = "%s[b]%s[/b]%s" % [_escape(entry_name.substr(0, at)),
			_escape(entry_name.substr(at, word.length())), _escape(entry_name.substr(at + word.length()))]
	return "%s   [color=#%s][font_size=12]%s[/font_size][/color]" \
		% [shown, DIM.to_html(false), _escape(String(entry["where"]))]


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


# Right edge on the box's right edge, just under it -- the box sits at the window's top right.
func _place_list() -> void:
	_panel.reset_size()
	_panel.global_position = global_position + Vector2(size.x - LIST_WIDTH, size.y + 2)


func _close_list() -> void:
	if _panel != null:
		_panel.visible = false


func _gui_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	match key.keycode:
		KEY_DOWN:
			_move(1)
			accept_event()
		KEY_UP:
			_move(-1)
			accept_event()
		KEY_ENTER, KEY_KP_ENTER:
			if _panel.visible and not _results.is_empty():
				_choose(_highlight)
			accept_event()
		KEY_ESCAPE:
			if text != "":
				clear()
				_refresh("")
			else:
				release_focus()
			accept_event()


# A press anywhere outside the box and its list closes the list.
func _input(event: InputEvent) -> void:
	var press := event as InputEventMouseButton
	if press == null or not press.pressed or not _panel.visible:
		return
	if not _panel.get_global_rect().has_point(press.position) \
			and not get_global_rect().has_point(press.position):
		_close_list()


func _on_row_input(event: InputEvent, i: int) -> void:
	var press := event as InputEventMouseButton
	if press != null and press.pressed and press.button_index == MOUSE_BUTTON_LEFT:
		_choose(i)
		_rows[i].accept_event()


func _move(step: int) -> void:
	if _results.is_empty():
		return
	_highlight = clampi(_highlight + step, 0, mini(_results.size(), MAX_ROWS) - 1)
	_paint_highlight()


func _light(i: int) -> void:
	_highlight = i
	_paint_highlight()


func _paint_highlight() -> void:
	for i in MAX_ROWS:
		_rows[i].add_theme_stylebox_override("panel", _row_lit if i == _highlight else _row_box)


func _choose(i: int) -> void:
	if i < 0 or i >= _results.size():
		return
	var entry: Dictionary = _results[i]
	clear()
	_results.clear()
	_close_list()
	release_focus()
	chosen.emit(entry)


# What the list is offering right now, best first -- for tests and nothing else.
func results() -> Array[Dictionary]:
	return _results


func list_showing() -> bool:
	return _panel.visible


func row_control(i: int) -> Control:
	return _rows[i]
