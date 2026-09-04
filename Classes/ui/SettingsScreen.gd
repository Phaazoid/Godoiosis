extends ModalCard
class_name SettingsScreen

# The player's settings page (#350): the game's first options surface, reachable from the pause
# menu and the title screen. A ModalCard like its siblings — it claims the modal lock, so the board
# underneath is frozen while the player reads.
#
# TWO PANES since #691: Settings, and a read-only CONTROLS list projected from Classes/core/Controls.gd
# (the same registry the dev Info tab reads, filtered to its PLAYER_CONTEXTS). Both panes are
# projections and this file authors neither's content. Rebinding is deliberately NOT here -- it can
# only reach Input Map actions, and most bindings are hardcoded keycode checks, so a rebind UI would
# offer rows it structurally cannot serve. That is #691 phase 2 and it is gated on promoting them.
#
# Pure projection of PlayerSettings.DEFS: one row per declared setting, built from the table's own
# title, with its description as HOVER TEXT since 2026-09-02 (the page was getting crowded -- see
# _apply_desc_tooltip). Nothing here owns content, and nothing here owns a default. That is what
# makes #217's photosensitivity toggle a one-line diff in the store rather than UI work — the
# ruling in docs/design/presentation-effects.md that a settings surface DRIVES that switch rather
# than a second one growing beside it only holds if this page never learns a setting's name.
#
# TWO ROW KINDS since #418, and the projection survives it: the page learns that a row is a toggle
# or a choice — which the store answers — never WHICH setting it is looking at.
#
# ITS CONTROLS FOLLOW THE STORE, they do not merely write to it (#647, dev ruling 2026-08-28: *"if
# there is a setting in both dev and player controls, I don't want them to ever disagree"*). The
# dev-tools window is a SECOND OS WINDOW and its Game tab writes the real battle-zoom setting, so
# both surfaces can be on screen at once — a control built from a snapshot goes stale the moment the
# other one is touched. A poll rather than a changed signal, which is the store's own doctrine.

signal closed

const BODY_WIDTH := 520
const SEGMENT_GAP := 6
const SEGMENT_HEIGHT := 32
const ROW_SEPARATION := 14
# A floor, not a look: on a viewport too short to hold the chrome the subtraction below goes
# negative, and a card with no body at all is the bug this whole file is fixing.
const MIN_BODY_HEIGHT := 120.0
const HEADING_FONT_SIZE := 18
const KEY_COLUMN_WIDTH := 150.0
const CONDITION_COLOR := Color(1, 1, 1, 0.6)

# The card's two panes (#691). An enum rather than a bool because a third pane is a plausible
# future (Audio, Video) and a bool would have to become one anyway.
enum Pane { SETTINGS, CONTROLS }

var _panes: Dictionary[Pane, Control] = {}
var _pane_buttons: Dictionary[Pane, Button] = {}

# Every control this page built, by the setting it shows: a CheckButton for a toggle row, the ordered
# segment Buttons for a choice row. Kept only so _process can reconcile them against the store.
var _toggles: Dictionary[PlayerSettings.Setting, CheckButton] = {}
var _segments: Dictionary[PlayerSettings.Setting, Array] = {}

func _init() -> void:
	button_size = Vector2(150, 36)

# The GlossaryScreen shape: build, wait for Close, free.
#
# ...plus TWO acts on the way out, and they are the same act aimed at two surfaces. Both are painted
# on an EDGE rather than polled, so a palette picked on this page reaches neither until the player
# happens to trigger that edge.
#
# The BOARD (#422): its two aim layers are painted on entering an aim and on leaving one, so an aim
# palette picked here would reach nothing until the player next aimed an attack -- and the footprint
# layer is shared with PICKING_TARGET, so a rescue or squad-up pick is drawn on it having never aimed
# at all. `refresh_aim_colors` is the door the Game tab's colour knobs already re-apply through.
#
# The QUEUE DOCK (#685 round 5): it renders on a PLAN change and nothing else, so a queue palette
# picked here would not show until the player queued their next order -- and its chrome would have
# waited for a relaunch. `restyle` is likewise the door those knobs already use.
#
# Both cost one call at a moment the board is frozen anyway, rather than a poll on surfaces that have
# no _process by design (every draw here is RETAINED -- OverlayMirror polls THEM). A freeze stops
# callbacks, not method calls, so ModalLock does not block either.
static func show_screen(game_node: Node) -> void:
	var screen := SettingsScreen.new()
	game_node.ui_layer.add_child(screen)
	screen._build(game_node)
	await screen.closed
	var overlays: OverlayManager = game_node.overlay_manager
	overlays.refresh_aim_colors()
	var queue: SquadActionQueueControl = game_node.squad_action_queue_control
	queue.restyle()
	screen.queue_free()

func _build(game_node: Node) -> void:
	var content := _build_chrome(game_node)
	_build_title(content, "SETTINGS")

	# TWO PANES since #691, on GlossaryScreen's marker: the active pane's button is DISABLED, and
	# that is the selection indicator -- no second highlight state to keep in step with which pane
	# is actually up. Settings first, because that is what the card is named and what the pause
	# menu row promises; Controls is a reference the player consults and leaves.
	var tabs := _build_button_row(content, false, SEGMENT_GAP)
	_pane_buttons[Pane.SETTINGS] = _add_button(tabs, "Settings", func(): _show_pane(Pane.SETTINGS))
	_pane_buttons[Pane.CONTROLS] = _add_button(tabs, "Controls", func(): _show_pane(Pane.CONTROLS))

	# GlossaryScreen's shape: a bounded scroll between the title and Close, horizontal disabled so
	# the descriptions wrap rather than run off the side. Built at ZERO height and given its real
	# ceiling below, once the chrome around it can be measured.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(BODY_WIDTH, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)

	# ONE scroll holding both panes, hidden by `visible` rather than rebuilt on every switch: a
	# container skips invisible children entirely, so the chrome measurement below is unaffected and
	# _process keeps reconciling the settings controls whichever pane is up. Rebuilding instead
	# would mean _toggles and _segments emptying and refilling, i.e. a second lifetime to get right
	# for no gain -- the panes are static once built.
	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(BODY_WIDTH, 0)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", ROW_SEPARATION)
	body.add_child(rows)
	_panes[Pane.SETTINGS] = rows
	for setting: PlayerSettings.Setting in PlayerSettings.Setting.values():
		_add_row(rows, setting)

	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", ROW_SEPARATION)
	body.add_child(controls)
	_panes[Pane.CONTROLS] = controls
	_build_controls(controls)

	var close_row := _build_button_row(content, false, content_separation)
	_add_button(close_row, "Close", func(): closed.emit())

	_show_pane(Pane.SETTINGS)

	# THE BODY'S CEILING IS WHATEVER THE VIEWPORT LEAVES, and the chrome is MEASURED rather than
	# added up -- no fudge constant, and a sixth setting cannot do what the fifth did.
	scroll.custom_minimum_size.y = maxf(
			MIN_BODY_HEIGHT, get_viewport_rect().size.y - _chrome_height(content))


# A pure projection of Controls.gd's player contexts (#691), the way the rows above are of
# PlayerSettings.DEFS -- this page owns no binding text and no list of what a player may see.
# PLAYER_CONTEXTS is the filter, declared in the store, so a dev context cannot leak onto a
# player's page by being added to the enum.
func _build_controls(parent: Container) -> void:
	for context: Controls.Context in Controls.PLAYER_CONTEXTS:
		var heading := Label.new()
		heading.text = Controls.context_name(context)
		heading.add_theme_font_size_override("font_size", HEADING_FONT_SIZE)
		parent.add_child(heading)
		for entry: Dictionary in Controls.in_context(context):
			_add_binding_row(parent, entry)


# Key on the left at a fixed width, meaning on the right, wrapping. The condition rides ABOVE the
# description rather than beside the key, because "the newest order is one unit's own move" is a
# sentence and a key name is two words.
func _add_binding_row(parent: Container, entry: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", SEGMENT_GAP)
	var key := Label.new()
	key.text = entry["key"]
	key.custom_minimum_size = Vector2(KEY_COLUMN_WIDTH, 0)
	key.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	row.add_child(key)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var when: String = entry["when"]
	if when != "":
		var condition := Label.new()
		condition.text = when
		condition.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		condition.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		condition.modulate = CONDITION_COLOR
		text.add_child(condition)
	var does := Label.new()
	does.text = entry["does"]
	does.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# An autowrap Label collapses to zero width in a container without the expand flag.
	does.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(does)
	row.add_child(text)
	parent.add_child(row)


func _show_pane(pane: Pane) -> void:
	for other: Pane in _panes:
		_panes[other].visible = other == pane
		_pane_buttons[other].disabled = other == pane

# Everything the card needs around its body: title, separations, the Close row, the margins and the
# panel's own padding, whatever those have been restyled to.
#
# ASK THE OUTERMOST CONTAINER, never `self`: a plain Control aggregates nothing (measured -- this
# node's combined minimum is (0, 0) with the whole page built under it), because only a Container
# rolls its children's minimums up. Read with the scroll still at ZERO, so what comes back is the
# chrome alone; minimums are computed on demand, so no layout pass is needed.
func _chrome_height(content: Control) -> float:
	var outer: Control = content
	while outer.get_parent() is Control and outer.get_parent() != self:
		outer = outer.get_parent()
	return outer.get_combined_minimum_size().y

func _add_row(parent: Container, setting: PlayerSettings.Setting) -> void:
	var first := parent.get_child_count()
	if PlayerSettings.is_choice(setting):
		_add_choice_row(parent, setting)
	else:
		_add_toggle_row(parent, setting)
	_apply_desc_tooltip(parent, first, setting)

# A CheckButton rather than a Button: this page's rows have a STATE the player is reading back,
# which is the one thing every other ModalCard row does not (they emit a choice and close).
func _add_toggle_row(parent: Container, setting: PlayerSettings.Setting) -> void:
	var toggle := CheckButton.new()
	toggle.text = PlayerSettings.title_of(setting)
	toggle.button_pressed = PlayerSettings.is_on(setting)
	# Written straight through to the store, which persists on every write — no Apply button, and
	# no local copy that could disagree with what the board is already drawing.
	toggle.toggled.connect(func(on: bool): PlayerSettings.set_on(setting, on))
	parent.add_child(toggle)
	_toggles[setting] = toggle

# A segmented strip, NOT an OptionButton: a dropdown opens an embedded PopupMenu, and those do not
# dismiss on outside-click inside GameView (CLAUDE.md's SubViewport gotcha 2 — the #26 reason the
# action menu is Control-based). ReportPanel's kind row is the same shape and states the other half
# of the reason: every choice is readable, and which one is picked is readable, without a click.
func _add_choice_row(parent: Container, setting: PlayerSettings.Setting) -> void:
	var title := Label.new()
	title.text = PlayerSettings.title_of(setting)
	parent.add_child(title)

	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", SEGMENT_GAP)
	var group := ButtonGroup.new()
	var options: Array = PlayerSettings.options_of(setting)
	var current := PlayerSettings.choice_of(setting)
	var built: Array[Button] = []
	for i in options.size():
		var segment := Button.new()
		segment.text = str(options[i])
		segment.toggle_mode = true
		segment.button_group = group
		segment.button_pressed = i == current
		segment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		segment.custom_minimum_size = Vector2(0, SEGMENT_HEIGHT)
		# Straight through to the store, same as a toggle row — no Apply, no local copy. `toggled`
		# rather than `pressed` because what the store mirrors is the segment's STATE, exactly as on
		# the rows above; the group un-presses the outgoing one, and that false is not a choice.
		segment.toggled.connect(func(on: bool):
			if on:
				PlayerSettings.set_choice(setting, i))
		strip.add_child(segment)
		built.append(segment)
	parent.add_child(strip)
	_segments[setting] = built


# Reconcile every control against the store, so a change made anywhere else lands here (#647 — see
# the header). Each write is `no_signal`, or setting the control would fire its own handler back into
# the store; the value would agree, but the page would be writing on a frame the player did not touch
# it, which is exactly the second writer the ruling refuses.
func _process(_delta: float) -> void:
	for setting: PlayerSettings.Setting in _toggles:
		var toggle: CheckButton = _toggles[setting]
		var on := PlayerSettings.is_on(setting)
		if toggle.button_pressed != on:
			toggle.set_pressed_no_signal(on)
	for setting: PlayerSettings.Setting in _segments:
		var picked := PlayerSettings.choice_of(setting)
		var strip: Array = _segments[setting]
		for i in strip.size():
			var segment: Button = strip[i]
			# Set every segment rather than only the live one: a ButtonGroup un-presses the outgoing
			# button through the SIGNAL path, which is the path this is deliberately not using.
			if segment.button_pressed != (i == picked):
				segment.set_pressed_no_signal(i == picked)

# THE DESCRIPTION IS HOVER TEXT, not a line under the row (dev, 2026-09-02: the page was getting too
# crowded). The store is untouched -- `desc` is still the one place the words live and this page still
# never learns a setting's NAME, so the projection is unchanged in everything but where it draws.
#
# Wrapped through UiText, because Godot's built-in tooltip is a Label with autowrap OFF and no theme
# item to switch it on: an unwrapped line runs off the screen edge instead. Every tooltip in
# Classes/ui/ routes through wrap() for that reason, and tests/ui/test_tooltip_rendering.gd walks the
# live tree to check they all did.
#
# EVERY CONTROL THE ROW BUILT, never the row -- a Button has mouse_filter STOP, so Godot asks IT and
# never walks up to a parent that holds the text. The same rule DevWidgets.apply_tooltip follows one
# window over, and info_panel's stat pair follows here.
#
# ...which is also why the filter is set: a LABEL defaults to MOUSE_FILTER_IGNORE, so a choice row's
# title would never be asked at all. That is half the page silently without hover text, and the half
# a screenshot cannot tell from the other. `info_panel._badge` sets it beside its own tooltip for
# exactly this reason.
func _apply_desc_tooltip(parent: Container, first: int, setting: PlayerSettings.Setting) -> void:
	var wrapped := UiText.wrap(PlayerSettings.desc_of(setting))
	for i in range(first, parent.get_child_count()):
		_tooltip_subtree(parent.get_child(i), wrapped)


# A row is not one node -- a choice row is a title plus a strip of buttons -- so the text goes on the
# whole span, gaps between segments included.
func _tooltip_subtree(node: Node, wrapped: String) -> void:
	var control := node as Control
	if control != null:
		control.tooltip_text = wrapped
		control.mouse_filter = Control.MOUSE_FILTER_STOP
	for child: Node in node.get_children():
		_tooltip_subtree(child, wrapped)


# Esc closes the page, the same door the Close button is -- and the reason this file grew a scroll
# region in the same pass: a card whose only exit can leave the screen needs a second one that
# cannot.
func _on_cancel() -> bool:
	closed.emit()
	return true
