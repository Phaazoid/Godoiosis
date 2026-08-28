extends Control
class_name ModalCard

# The shared base for every full-screen UI surface the game puts over the board: the pause card,
# the end-of-mission card, the report card, and the mission-select takeover. (The Crisis offer
# was a tenant until #158 removed the prompt from the game.)
# "Card" is this project's own word for these (BugReporter.open_card, "the report card", "the
# in-play pause card") -- it was ChoiceModal until ReportPanel, a FORM rather than a choice, moved
# onto it. NOT the in-world ActionMenuController (a positioned context menu on its own CanvasLayer,
# a different surface entirely).
#
# WHY IT EXISTS: these surfaces hand-built the same chrome five times, which is why one mistake
# (set_anchors_preset instead of set_anchors_and_offsets_preset, #132) rendered three of them in
# the top-left corner at once. Sizing is now answered here, once.
#
# STYLING IS FIELDS, NOT PARAMETERS. A subclass overrides what it needs in _init() -- which runs at
# .new(), always before _build, so there is no "set it before you call the builder" footgun. The
# defaults below are the canon: change them here and every surface changes. The four surfaces this
# replaced had drifted apart (margins 48/32 vs 32/24, separation 12/16/20, dim alpha
# 0.65/0.70/0.75) with no design reason -- copy-paste noise, now gone. Deliberate differences
# (an oversized ending title, a red alarm title, a vertical button stack) stay as explicit overrides.
#
# CHROME IS OVERRIDABLE STEPS, not one function with a growing parameter list. A surface that needs
# a different backdrop or no panel frame overrides that STEP rather than the base growing another
# knob -- which is what lets MissionSelectScreen (opaque background, branding, no panel) share this
# at all.

# --- Behaviour ----------------------------------------------------------------------------------

# Does this surface freeze the game subtree while it is up (ModalLock)? True for anything the
# player must answer before play continues. MissionSelectScreen sets this FALSE: it is not a modal,
# and a Game left DISABLED behind it would never run the mission picked next.
var claims_modal_lock: bool = true

# --- Backing out ---------------------------------------------------------------------------------

# ESC BELONGS TO THE CARD, and it has nowhere else it could live: game.gd's _input ignores
# ui_cancel while anything is in the `modal` group (#131), so a card that does not answer here
# SWALLOWS the key. That is not a missing nicety, it is a card with no door -- #418's settings page
# grew past the viewport and stranded the player behind a Close button off the bottom edge.
#
# MECHANISM here, POLICY in the override: return true for "I took the key". Three cards spelled
# this themselves before and each had a real reason to differ -- ReportPanel swallows it mid-send
# without acting, SaveLoadScreen yields to a stacked ConfirmCard, ConfirmCard reads it as No -- so
# a shared BEHAVIOUR would have had to grow their differences back as flags.
#
# The default takes NOTHING, which is the right answer for a card that must be answered:
# MissionEndBanner and MissionSelectScreen both keep it.
func _on_cancel() -> bool:
	return false

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _on_cancel():
		accept_event()

# --- Styling ------------------------------------------------------------------------------------

var card_z_index: int = UiLayers.MODAL_CARD
var backdrop_color: Color = Color(0, 0, 0, 0.70)   # a Color, not an alpha: a takeover needs RGB too
var margin_h: int = 48
var margin_v: int = 32
var content_separation: int = 16
var content_alignment: BoxContainer.AlignmentMode = BoxContainer.ALIGNMENT_CENTER
var framed: bool = true                             # false = no panel/margin (full-screen takeover)
var title_font_size: int = 32
var title_color: Color = Color.WHITE
var button_size: Vector2 = Vector2(160, 44)

# --- The chrome ---------------------------------------------------------------------------------

# Called first from a subclass's own _build(). Returns the content box for it to fill.
# game_node is only needed when claims_modal_lock is true -- it is what gets frozen.
func _build_chrome(game_node: Node = null) -> VBoxContainer:
	if claims_modal_lock:
		ModalLock.claim(self, game_node)
	_apply_root()
	_build_backdrop()
	_build_branding()
	return _build_content_box(_build_frame())

func _apply_root() -> void:
	# set_anchors_and_offsets_preset, NEVER set_anchors_preset -- a code-built Control under a
	# CanvasLayer stays 0x0 with anchors alone, so the backdrop covers nothing and CenterContainer
	# centres on the origin. This is the #132 bug, and it lives here now so it can only happen once.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # eat stray clicks meant for the board behind
	z_index = card_z_index

func _build_backdrop() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = backdrop_color
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

# Anything drawn over the backdrop but outside the content frame (a logo, a watermark). Default
# empty. It is a step rather than something a subclass adds after _build_chrome returns, so its
# nodes land in the right SIBLING ORDER -- after the backdrop, before the content.
func _build_branding() -> void:
	pass

# Center [> Panel > Margin]. Returns whatever the content box should be parented to.
func _build_frame() -> Container:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	if not framed:
		return center

	var panel := PanelContainer.new()
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", margin_h)
	margin.add_theme_constant_override("margin_right", margin_h)
	margin.add_theme_constant_override("margin_top", margin_v)
	margin.add_theme_constant_override("margin_bottom", margin_v)
	panel.add_child(margin)
	return margin

func _build_content_box(host: Container) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", content_separation)
	box.alignment = content_alignment
	host.add_child(box)
	return box

# --- Content helpers ----------------------------------------------------------------------------

func _build_title(parent: Container, text: String) -> Label:
	var title := Label.new()
	title.text = text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", title_font_size)
	title.modulate = title_color
	parent.add_child(title)
	return title

func _build_body(parent: Container, text: String) -> Label:
	var body := Label.new()
	body.text = text
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(body)
	return body

# vertical: a stacked VBoxContainer; otherwise side-by-side HBoxContainer.
func _build_button_row(parent: Container, vertical: bool, separation: int) -> BoxContainer:
	var row: BoxContainer = VBoxContainer.new() if vertical else HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", separation)
	parent.add_child(row)
	return row

func _add_button(row: Container, text: String, on_pressed: Callable,
		tint: Color = Color.WHITE) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = button_size
	button.modulate = tint
	button.pressed.connect(on_pressed)
	row.add_child(button)
	return button

# For a surface whose choices CHANGE while it is up (ReportPanel: collecting -> sending -> outcome).
# remove_child as well as queue_free, so a rebuild in the same frame does not briefly show both sets.
func _clear_button_row(row: Container) -> void:
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
