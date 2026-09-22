extends PanelContainer
class_name WhatsNewCard

# "WHAT'S NEW" (#1075): a small panel in the title screen's top-right corner listing what changed in
# every release since the last one this install was shown, newest first, from CHANGELOG.md via
# ReleaseNotes. Closed with its x.
#
# NOT A ModalCard, and that is the ruling rather than an omission (dev, 2026-09-22, picked against a
# 1:1 mockup of a centred card): no backdrop, no modal lock, and the menu beside it stays live. A
# what's-new is read, never answered, so it must not stand between a returning player and the menu.
# It borrows only the look every card shares, QueueStyle.panel_box().
#
# A CHILD OF THE TITLE SCREEN, so it dies with it -- a player who starts a mission without closing it
# must not carry it into the battle.
#
# SHOWN ONCE, marked on SHOW rather than on close: MissionController rebuilds the title screen after
# every mission, and a panel somebody chose to ignore must not keep coming back. No record at all
# (a fresh install, or the first build carrying this card) records the running build and shows
# nothing (dev ruling, 2026-09-22).
#
# THE COPY IS HIS. TITLE is a placeholder, as TelemetryNotice's is, and every line comes from the
# ledger's player section, which he rewrites in each release PR.

const TITLE := "What's new"   # PLACEHOLDER, for the dev to replace
const CLOSE := "×"
const BULLET := "•"

# Layout, drawn 1:1 in the mockup the shape was ruled on.
const WIDTH := 360.0
const INSET := 24
const PAD_H := 16
const PAD_V := 14
const SEPARATION := 10
const ENTRY_SEPARATION := 12
const TITLE_SIZE := 18
const VERSION_SIZE := 13
const LINE_SIZE := 14
const CLOSE_SIZE := Vector2(26, 26)
# The list grows with its content until here, then scrolls: about five releases' worth.
const MAX_BODY_HEIGHT := 400.0

# Cleared headless, as TelemetryNotice and UpdateBanner clear theirs: 89 suites boot Main.tscn and
# reach the title screen, and none of them may meet this panel unasked.
static var enabled := true

var _scroll: ScrollContainer
var _list: VBoxContainer


static func _static_init() -> void:
	if DisplayServer.get_name() == "headless":
		enabled = false


# The one door. Returns null when there is nothing to show, so MissionController states no policy.
static func show_if_needed(host: Control) -> WhatsNewCard:
	return _show_if_needed(host, Build.version())


# The running version as a PARAMETER, so a suite can drive every answer without moving project.godot.
#
# Refuses when nothing can be recorded, on TelemetryNotice's reasoning: a panel we cannot remember
# showing would come back on every trip through the title screen.
static func _show_if_needed(host: Control, running: String) -> WhatsNewCard:
	if not enabled or not ReleaseNotes.persistence_enabled:
		return null
	var seen := ReleaseNotes.last_seen()
	if seen == "":
		ReleaseNotes.mark_seen(running)
		return null
	var due := ReleaseNotes.since(seen, running, ReleaseNotes.entries())
	if due.is_empty():
		return null
	# Marked BEFORE it is built, so a player who quits in the same breath is still recorded as told.
	ReleaseNotes.mark_seen(running)
	var card := WhatsNewCard.new()
	card._build(due)
	host.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, INSET)
	card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	return card


func _build(due: Array[Dictionary]) -> void:
	add_theme_stylebox_override("panel", QueueStyle.panel_box())
	custom_minimum_size.x = WIDTH
	mouse_filter = Control.MOUSE_FILTER_STOP

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", PAD_H)
	margin.add_theme_constant_override("margin_right", PAD_H)
	margin.add_theme_constant_override("margin_top", PAD_V)
	margin.add_theme_constant_override("margin_bottom", PAD_V)
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", SEPARATION)
	margin.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = TITLE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", TITLE_SIZE)
	title.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.TITLE_TEXT))
	head.add_child(title)
	var close := Button.new()
	close.text = CLOSE
	close.custom_minimum_size = CLOSE_SIZE
	close.pressed.connect(queue_free)
	head.add_child(close)

	# DISABLED, so the scroll takes its content's full height and the panel fits it. _cap_body turns
	# scrolling on only if the list outgrows MAX_BODY_HEIGHT once its lines have wrapped.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", ENTRY_SEPARATION)
	_scroll.add_child(_list)
	for entry: Dictionary in due:
		_add_entry(entry)
	_list.minimum_size_changed.connect(_cap_body)


func _add_entry(entry: Dictionary) -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)
	_list.add_child(block)
	var version := Label.new()
	version.text = "v" + str(entry["version"])
	version.add_theme_font_size_override("font_size", VERSION_SIZE)
	version.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.FRAME_TEXT))
	block.add_child(version)
	var lines: Array = entry["lines"]
	for text: String in lines:
		var row := HBoxContainer.new()
		block.add_child(row)
		var dot := Label.new()
		dot.text = BULLET
		dot.add_theme_font_size_override("font_size", LINE_SIZE)
		dot.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.FRAME_TEXT))
		row.add_child(dot)
		var line := Label.new()
		line.text = text
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_theme_font_size_override("font_size", LINE_SIZE)
		row.add_child(line)


# One-way: once the list has outgrown the cap it scrolls for the life of the panel. reset_size is
# what shrinks the panel back, since a Control outside a container only ever grows to its minimum.
func _cap_body() -> void:
	if _scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		return
	if _list.get_combined_minimum_size().y <= MAX_BODY_HEIGHT:
		return
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.custom_minimum_size.y = MAX_BODY_HEIGHT
	reset_size()
