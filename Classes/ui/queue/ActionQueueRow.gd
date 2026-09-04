extends PanelContainer
class_name ActionQueueRow

# One row of the action-queue panel: an element rail, the actor sprite, the action icon, the target
# sprite, an hp->hp readout, the cancel X -- and, when the hit had elemental consequences, a second
# CONSEQUENCE line under them. Draws whatever BaseAction it is handed and asks the ORDER every
# question about itself (icon, description, validity, whether it may be dragged), so a new action
# type needs nothing here. Built by SquadActionQueueControl, which owns the drag and the sectioning.
#
# EVERY FACT GETS ITS OWN SLOT (#685). The row used to stack four of them into three 32px squares
# through `show_behind_parent`: state icons under the verb, the hp readout over it, reaction art
# under the target, and the leader's crown under the actor. Nothing overlays anything now, and
# `show_behind_parent` has no user left in this file -- do not reintroduce one.
#
# TWO CHANNELS, TWO MEANINGS (visual-clarity.md principle 2): the row's BORDER says whether the
# order is refused; the RAIL says what element the hit carries. Neither may borrow the other.
#
# EVERY SLOT IS 16px AND THE ROW HAS NO HEIGHT FLOOR (dev, 2026-09-03): a 32px slot bought nothing
# -- the action art is authored at 16 and was being upscaled -- and cost so much height that barely
# one and a half rows fit the dock. The CONSEQUENCE line is indented to start under TargetTexture,
# because a status lands on the unit RECEIVING it and reading it under the attacker is a lie about
# who is wet.

@onready var rail: ColorRect = $Frame/Rail
@onready var actor_texture: TextureRect = $Frame/Pad/Body/Line/ActorTexture
@onready var action_icon: TextureRect = $Frame/Pad/Body/Line/ActionIcon
@onready var target_texture: TextureRect = $Frame/Pad/Body/Line/TargetTexture
@onready var readout_card: PanelContainer = $Frame/Pad/Body/Line/ReadoutCard
@onready var readout: Label = $Frame/Pad/Body/Line/ReadoutCard/Readout
@onready var cancel_button: Button = $Frame/Pad/Body/Line/CancelButton
@onready var description_label: Label = $Frame/Pad/Body/Line/DescriptionLabel
@onready var consequence_row: MarginContainer = $Frame/Pad/Body/ConsequenceRow
@onready var consequence: HFlowContainer = $Frame/Pad/Body/ConsequenceRow/Consequence

var action: BaseAction
var draggable := false
var is_volley_header := false
var _hovered := false

signal cancel_requested(action: BaseAction)
signal hover_changed(action: BaseAction, hovering: bool)
signal drag_requested(row: ActionQueueRow)

func setup(action_ref: BaseAction):
	action = action_ref

	actor_texture.texture = action.get_actor_texture()
	actor_texture.modulate = action.get_actor_modulate()
	action_icon.texture = action.get_action_icon()
	target_texture.texture = action.get_target_texture()
	description_label.text = action.get_description()

	var outcome := action.resolved_outcome()
	_paint_rail(outcome)
	readout_card.visible = false   # a MOVE row has no number, and an empty card is a stray box
	# Any order carrying an outcome shows the readout, not attacks alone (#419) -- a tile's
	# end-of-turn damage reads as a hit like any other.
	if outcome != null:
		_show_hp_delta(outcome, action.aimed_at())
		_build_consequence(outcome)

	action_icon.modulate = action.get_ui_modulate()
	_apply_row_style()

	# The X keeps its slot on every row (so content stays aligned) but is inert on rows that
	# can't be cancelled. That is exactly "not an order the player sequenced", which the order
	# already answers for the drag -- one question, one answer (#419; was a hand-listed triple).
	if not action.is_reorderable():
		cancel_button.modulate.a = 0.0
		cancel_button.disabled = true
		cancel_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		cancel_button.modulate.a = 1.0
		cancel_button.disabled = false
		cancel_button.mouse_filter = Control.MOUSE_FILTER_STOP

	cancel_button.pressed.connect(_on_cancel_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _on_cancel_pressed():
	cancel_requested.emit(action)

func _on_mouse_entered():
	_hovered = true
	_apply_row_style()
	hover_changed.emit(action, true)

func _on_mouse_exited():
	_hovered = false
	_apply_row_style()
	hover_changed.emit(action, false)

# The row's chrome answers two independent questions at once -- refused, and hovered -- so both go
# to QueueStyle rather than a wash drawn over whatever the panel put underneath.
func _apply_row_style() -> void:
	var refused: bool = action != null and action.is_refused()
	add_theme_stylebox_override("panel", QueueStyle.row_box(refused, _hovered))

# What element actually REACHED the target (post-insulation), read off the recorded outcome rather
# than the authored attack -- a hit the target shrugged off wears no rail. First element wins; a
# multi-element hit still says its consequences on the line below.
func _paint_rail(outcome: ResolvedOutcome) -> void:
	if outcome == null or outcome.elements.is_empty():
		rail.color = ElementPalette.NEUTRAL
		return
	rail.color = ElementPalette.color_for_element(outcome.elements[0])

# The consequence line: a STATE the hit applied gets a compact chip, a fired COMBO gets its authored
# word, and an event popup the resolver already recorded ("Fell 2!", "Drowning!", "Insulated!") gets
# a neutral one. A SETUP reaction is deliberately silent -- it is already fully said by the chip it
# produced, and saying it twice is the noise the split-by-weight ruling exists to prevent (#685).
func _build_consequence(outcome: ResolvedOutcome) -> void:
	var entries: Array[Control] = []

	for state in outcome.states_added:
		if state == Elemental.State.NONE:
			continue
		var tip: String = UiText.wrap("%s -- %s" % [Elemental.state_display_name(state),
				Glossary.short(Glossary.term_for_element_state(state))])
		entries.append(_chip(ElementPalette.color_for_state(state),
				StateIcons.ICONS.get(state, null), Elemental.state_display_name(state), tip))

	# A reaction OWNS its popup whether or not it earns a line: the setup half is already fully said
	# by the chip it just produced, so claiming the word here is what stops "Wet" appearing twice --
	# once as its chip and again as a neutral event pill.
	var spoken: Array[String] = []
	for reaction: ElementalReaction in outcome.fired_reactions:
		if reaction.popup == "":
			continue
		spoken.append(reaction.popup)
		if not reaction.is_combo():
			continue
		entries.append(_chip(ElementPalette.color_for_element(reaction.incoming_element),
				reaction.icon, reaction.popup, UiText.wrap(Glossary.reaction_line(reaction))))

	for popup in outcome.popups:
		if spoken.has(popup):
			continue   # a reaction's own word, said above as its line or as its chip
		entries.append(_chip(ElementPalette.NEUTRAL, null, popup, ""))

	for entry in entries:
		consequence.add_child(entry)
	# A hidden Control contributes nothing to get_combined_minimum_size, so an unflipped `visible`
	# loses the line AND the height the section reserves for it (#592's shape).
	consequence_row.visible = not entries.is_empty()

# One tinted pill, art optional. Tooltip goes on EVERY control in it: a Label defaults to
# MOUSE_FILTER_IGNORE, so the viewport never picks it and the text is dead however right it is.
func _chip(tint: Color, art: Texture2D, text: String, tip: String) -> Control:
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", QueueStyle.tint_box(tint))
	pill.mouse_filter = Control.MOUSE_FILTER_STOP
	pill.tooltip_text = tip

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	pill.add_child(row)

	if art != null:
		var icon := TextureRect.new()
		icon.texture = art
		icon.custom_minimum_size = Vector2(QueueStyle.CHIP_ICON, QueueStyle.CHIP_ICON)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_STOP
		icon.tooltip_text = tip
		row.add_child(icon)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", QueueStyle.CONSEQUENCE_FONT_SIZE)
	label.add_theme_color_override("font_color", tint)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.tooltip_text = tip
	row.add_child(label)
	return pill

func _show_hp_delta(outcome: ResolvedOutcome, subject: Unit) -> void:
	# target_hp_after is threaded across the whole pass (R4): for the Nth hit it already accounts
	# for the earlier hits this combat. The raw number goes negative on a fatal hit, so the
	# DISPLAYED "after" is clamped by the lifecycle result -- a down/maim leaves HP at 1, a kill at 0.
	# That clamp is LethalityRules' since #313: the ghost readout over the unit draws the same
	# prediction, and two spellings of it would let this panel and the board disagree.
	var hp_before: int = outcome.hp_before
	var hp_after: int = LethalityRules.displayed_hp(outcome.target_hp_after,
			LethalityRules.lifecycle_for(outcome.lethality))

	# The "->" spelling is load-bearing: tests/presentation/test_predicted_health.gd finds this
	# label by searching for it and parses split("->")[1].
	readout.text = "%d->%d" % [hp_before, hp_after]

	# Team-color the readout: green when a friendly is losing HP, red for an enemy.
	var friendly := true
	if subject != null and is_instance_valid(subject):
		friendly = not Team.is_enemy(subject.get_faction(), Team.Faction.PLAYER)
	_show_readout(QueueStyle.READOUT_ALLY if friendly else QueueStyle.READOUT_ENEMY)

# The number wears the same tinted card the elemental chips do (dev, 2026-09-03: the digits "are a
# bit odd on their own... the damage numbers should have that feel too"). One card language across
# the row, so QueueStyle.tint_box is shared rather than copied.
func _show_readout(tint: Color) -> void:
	readout.add_theme_color_override("font_color", tint)
	readout_card.add_theme_stylebox_override("panel", QueueStyle.tint_box(tint))
	readout_card.visible = readout.text != ""

func is_reorderable_row() -> bool:
	# The order answers for itself (BaseAction.is_reorderable) -- a derived counter and a
	# hold-position filler are not orders the player sequenced (#412).
	return action != null and action.is_reorderable()

func _gui_input(event: InputEvent) -> void:
	# Draggable single attacks AND volley headers (collapsed header: drag to reorder / click to expand).
	if not (draggable or is_volley_header):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		drag_requested.emit(self)
		accept_event()

func setup_volley_summary(lead: AttackAction, count: int, expanded: bool) -> void:
	action = lead
	is_volley_header = true

	actor_texture.texture = lead.get_actor_texture()
	actor_texture.modulate = lead.get_actor_modulate()

	# Plain attack icon (not the lead's lethality icon — the group has many outcomes).
	action_icon.texture = AttackAction.ATTACK_ICON
	action_icon.modulate = lead.get_ui_modulate()
	target_texture.texture = null
	_paint_rail(null)   # the group's hits may carry different elements; the folder's rows say which

	# The READOUT slot becomes the hit-count + expand affordance -- the group has no single hp->hp,
	# and this is the slot that is free rather than one to draw over (#685).
	readout.text = ("[-] x%d" if expanded else "[+] x%d") % count
	_show_readout(QueueStyle.HEADER_TEXT)
	_apply_row_style()

	# Cancelling the summary cancels the whole volley (it's one aim) — keep the X live.
	cancel_button.modulate.a = 1.0
	cancel_button.disabled = false
	cancel_button.mouse_filter = Control.MOUSE_FILTER_STOP
	cancel_button.pressed.connect(_on_cancel_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
