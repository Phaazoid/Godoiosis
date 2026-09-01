extends ModalCard
class_name SettingsScreen

# The player's settings page (#350): the game's first options surface, reachable from the pause
# menu and the title screen. A ModalCard like its siblings — it claims the modal lock, so the board
# underneath is frozen while the player reads.
#
# Pure projection of PlayerSettings.DEFS: one row per declared setting, built from the table's own
# title and description. Nothing here owns content, and nothing here owns a default. That is what
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
const DESC_COLOR := Color(0.78, 0.78, 0.84)
const DESC_INDENT := 8
const SEGMENT_GAP := 6
const SEGMENT_HEIGHT := 32
const ROW_SEPARATION := 14
# A floor, not a look: on a viewport too short to hold the chrome the subtraction below goes
# negative, and a card with no body at all is the bug this whole file is fixing.
const MIN_BODY_HEIGHT := 120.0

# Every control this page built, by the setting it shows: a CheckButton for a toggle row, the ordered
# segment Buttons for a choice row. Kept only so _process can reconcile them against the store.
var _toggles: Dictionary[PlayerSettings.Setting, CheckButton] = {}
var _segments: Dictionary[PlayerSettings.Setting, Array] = {}

func _init() -> void:
	button_size = Vector2(150, 36)

# The GlossaryScreen shape: build, wait for Close, free.
#
# ...plus ONE act on the way out (#422). The board's two aim layers are painted on entering an aim
# and on leaving one, so an aim palette picked here would reach nothing until the player next aimed
# an attack -- and the footprint layer is shared with PICKING_TARGET, so a rescue or squad-up pick
# is drawn on it having never aimed at all. `refresh_aim_colors` is the door the Game tab's colour
# knobs already re-apply through; this is the same act from the player's side, and it costs one call
# at a moment the board is frozen anyway rather than a poll on a manager that has no _process by
# design (every draw here is RETAINED -- OverlayMirror polls IT).
static func show_screen(game_node: Node) -> void:
	var screen := SettingsScreen.new()
	game_node.ui_layer.add_child(screen)
	screen._build(game_node)
	await screen.closed
	var overlays: OverlayManager = game_node.overlay_manager
	overlays.refresh_aim_colors()
	screen.queue_free()

func _build(game_node: Node) -> void:
	var content := _build_chrome(game_node)
	_build_title(content, "SETTINGS")

	# GlossaryScreen's shape: a bounded scroll between the title and Close, horizontal disabled so
	# the descriptions wrap rather than run off the side. Built at ZERO height and given its real
	# ceiling below, once the chrome around it can be measured.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(BODY_WIDTH, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)

	var rows := VBoxContainer.new()
	rows.custom_minimum_size = Vector2(BODY_WIDTH, 0)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", ROW_SEPARATION)
	scroll.add_child(rows)

	for setting: PlayerSettings.Setting in PlayerSettings.Setting.values():
		_add_row(rows, setting)

	var close_row := _build_button_row(content, false, content_separation)
	_add_button(close_row, "Close", func(): closed.emit())

	# THE BODY'S CEILING IS WHATEVER THE VIEWPORT LEAVES, and the chrome is MEASURED rather than
	# added up -- no fudge constant, and a sixth setting cannot do what the fifth did.
	scroll.custom_minimum_size.y = maxf(
			MIN_BODY_HEIGHT, get_viewport_rect().size.y - _chrome_height(content))

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
	if PlayerSettings.is_choice(setting):
		_add_choice_row(parent, setting)
	else:
		_add_toggle_row(parent, setting)
	_add_desc(parent, setting)

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

func _add_desc(parent: Container, setting: PlayerSettings.Setting) -> void:
	# Autowrap against a real width, the way GlossaryScreen's body text does — UiText.wrap is for
	# tooltip_text, which has no width to wrap into.
	var desc := Label.new()
	desc.text = PlayerSettings.desc_of(setting)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.modulate = DESC_COLOR
	var indent := MarginContainer.new()
	indent.add_theme_constant_override("margin_left", DESC_INDENT)
	indent.add_child(desc)
	parent.add_child(indent)


# Esc closes the page, the same door the Close button is -- and the reason this file grew a scroll
# region in the same pass: a card whose only exit can leave the screen needs a second one that
# cannot.
func _on_cancel() -> bool:
	closed.emit()
	return true
