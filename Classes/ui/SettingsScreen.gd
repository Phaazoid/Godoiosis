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

signal closed

const BODY_WIDTH := 520
const DESC_COLOR := Color(0.78, 0.78, 0.84)
const DESC_INDENT := 8
const SEGMENT_GAP := 6
const SEGMENT_HEIGHT := 32

func _init() -> void:
	button_size = Vector2(150, 36)

# The GlossaryScreen shape: build, wait for Close, free.
static func show_screen(game_node: Node) -> void:
	var screen := SettingsScreen.new()
	game_node.ui_layer.add_child(screen)
	screen._build(game_node)
	await screen.closed
	screen.queue_free()

func _build(game_node: Node) -> void:
	var content := _build_chrome(game_node)
	_build_title(content, "SETTINGS")

	var rows := VBoxContainer.new()
	rows.custom_minimum_size = Vector2(BODY_WIDTH, 0)
	rows.add_theme_constant_override("separation", 14)
	content.add_child(rows)

	for setting: PlayerSettings.Setting in PlayerSettings.Setting.values():
		_add_row(rows, setting)

	var close_row := _build_button_row(content, false, content_separation)
	_add_button(close_row, "Close", func(): closed.emit())

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
	parent.add_child(strip)

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
