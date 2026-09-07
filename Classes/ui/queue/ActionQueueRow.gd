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

# The BADGE this row prints for each world consequence, as against the dramatic word PlanResolver
# hands the board's floating text (reported 2026-09-04: "Into the void!" is 72px, the line's slack is
# 46, and a chip too wide to wrap pushes the whole dock open). Same split ElementalReaction.short_name
# already makes for a reaction's word, applied to the other kind of pill -- and the dramatic word is
# not lost, it is the tooltip.
#
# THEY ARE CONSTS SO A LAW CAN ENUMERATE THEM: tests/ui/test_queue_badge_widths.gd measures each one
# against the real dock, so the next word too long for the row fails CI instead of the panel.
const BADGE_FELL := "Fell %d"
const BADGE_DROWNED := "Drown"
const BADGE_VOID := "Void"
const BADGE_INSULATED := "Shrug"
const BADGE_VIAL := "Vial"
const BADGE_TANK := "Tank"

@onready var rail: ColorRect = $Frame/Rail
@onready var actor_texture: TextureRect = $Frame/Pad/Body/Line/ActorTexture
@onready var action_icon: TextureRect = $Frame/Pad/Body/Line/ActionIcon
@onready var target_texture: TextureRect = $Frame/Pad/Body/Line/TargetTexture
@onready var readout_card: PanelContainer = $Frame/Pad/Body/Line/ReadoutCard
@onready var readout: Label = $Frame/Pad/Body/Line/ReadoutCard/Readout
@onready var cancel_button: Button = $Frame/Pad/Body/Line/CancelButton
@onready var description_label: Label = $Frame/Pad/Body/Line/DescriptionLabel
@onready var consequence: HFlowContainer = $Frame/Pad/Body/Line/Consequence

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
		rail.color = QueueStyle.ink(QueueStyle.Role.RAIL_NEUTRAL)
		return
	rail.color = QueueStyle.element_ink(outcome.elements[0])

# The consequence chips, IN the line between the target sprite and the readout (dev, 2026-09-03).
# A STATE the hit applied gets a chip, a fired COMBO gets its BADGE word, and an event popup the
# resolver already recorded ("Fell 2!", "Drowning!", "Insulated!") gets a neutral one. A SETUP
# reaction is deliberately silent -- already fully said by the chip it produced, and saying it twice
# is the noise the split-by-weight ruling exists to prevent (#685).
#
# TEXT ONLY, and it is a CHOICE rather than a constraint -- measured, an icon chip still fits the
# row without clipping. It costs ~19px each, which is what decides whether a second chip WRAPS, and
# the loudest complaint about this panel was height. `badge_name()` is the other half: the badge word
# is what fits, and the dramatic one keeps its place in the tooltip and the glossary.
func _build_consequence(outcome: ResolvedOutcome) -> void:
	for state in outcome.states_added:
		if state == Elemental.State.NONE:
			continue
		var tip: String = UiText.wrap("%s -- %s" % [Elemental.state_display_name(state),
				Glossary.short(Glossary.term_for_element_state(state))])
		consequence.add_child(_chip(QueueStyle.state_ink(state),
				Elemental.state_display_name(state), tip))

	# A fired COMBO gets its badge word. The SETUP half stays silent -- already fully said by the
	# state chip it just produced, and saying it twice is the noise the split-by-weight ruling exists
	# to prevent (#685). The guard asks the ACCESSOR whether there is a word, not the raw popup.
	for reaction: ElementalReaction in outcome.fired_reactions:
		if not reaction.is_combo() or reaction.badge_name() == "":
			continue
		consequence.add_child(_chip(QueueStyle.element_ink(reaction.incoming_element),
				reaction.badge_name(), UiText.wrap(Glossary.reaction_line(reaction))))

	# What the WORLD did, read off the outcome's own recorded FACTS rather than parsed back out of
	# `popups`. That channel is the BOARD's floating text, where the dramatic word has room and
	# nothing has to fit -- reading it here printed a string sized for a different surface, and
	# "Into the void!" is 72px against a 46px slack, which pushed the row, its section and the whole
	# scroll column clean out of the dock (reported 2026-09-04). The BADGE is this panel's own short
	# spelling; the dramatic word is the tooltip, which is where the wording is headed anyway.
	#
	# Reading facts also deletes the string bookkeeping this loop used to need: nothing has to work
	# out which popup belonged to which reaction, because the two channels no longer share one list.
	if outcome.insulated:
		_add_event(BADGE_INSULATED, PlanResolver.INSULATED_POPUP)
	if outcome.fall_levels > 0:
		_add_event(BADGE_FELL % outcome.fall_levels, PlanResolver.FELL_POPUP % outcome.fall_levels)
	if outcome.drown_damage > 0:
		_add_event(BADGE_DROWNED, PlanResolver.DROWNING_POPUP)
	if outcome.removed:
		_add_event(BADGE_VOID, PlanResolver.VOID_POPUP)
	# The vial BURN (#697). Law #2's plainest case: this cast spends an item out of the caster's
	# inventory, and a plan that spent one the player never saw spent is the queue lying. Element-
	# tinted rather than EVENT_TINT because the burn is an elemental fact, and the vial names itself
	# on hover -- the badge stays one short word for the dock's sake.
	if outcome.burned_vial != null:
		var burned := outcome.burned_vial
		var ink := QueueStyle.element_ink(burned.element) if not burned.is_alkahest \
				else QueueStyle.ink(QueueStyle.Role.EVENT_TINT)
		consequence.add_child(_chip(ink, BADGE_VIAL, UiText.wrap("Burns %s" % burned.display_name)))
	# The TANK spend (#97), the vial burn's twin one economy over and there for the same Law #2
	# reason: this shot is the supercharged one and the next will not be. The resolver threads the
	# count across the pass, so two shots in one pass cannot both wear this.
	if outcome.charge_spent:
		consequence.add_child(_chip(QueueStyle.ink(QueueStyle.Role.EVENT_TINT), BADGE_TANK,
			UiText.wrap("Spends a supercharged shot")))
	# No visibility toggle: the container holds the line's horizontal EXPAND whether or not it has
	# chips, which is what keeps the cancel X on the right edge of a row that has none. It WRAPS
	# rather than clips, so a crowded hit costs the row a second line instead of losing a word.

# One tinted pill. The tooltip goes on the pill AND its label: a Label defaults to
# MOUSE_FILTER_IGNORE, so the viewport never picks it and the text is dead however right it is.
func _chip(tint: Color, text: String, tip: String) -> Control:
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", QueueStyle.tint_box(tint))
	pill.mouse_filter = Control.MOUSE_FILTER_STOP
	pill.tooltip_text = tip

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", QueueStyle.CONSEQUENCE_FONT_SIZE)
	label.add_theme_color_override("font_color", tint)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.tooltip_text = tip
	pill.add_child(label)
	return pill


# A world-event pill: this panel's short badge, with the resolver's dramatic word on hover.
func _add_event(badge: String, spoken: String) -> void:
	consequence.add_child(_chip(QueueStyle.ink(QueueStyle.Role.EVENT_TINT), badge, UiText.wrap(spoken)))

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
	# The number explains itself on hover (#424, Law #2): what kind the hit delivered and what the
	# target's DEF did with it, read off the outcome's own stamps so this can never name a
	# subtraction other than the one made.
	var tip := damage_tip(outcome, subject)
	readout.tooltip_text = tip
	readout_card.tooltip_text = tip
	readout.mouse_filter = Control.MOUSE_FILTER_STOP

	# Team-color the readout: green when a friendly is losing HP, red for an enemy.
	var friendly := true
	if subject != null and is_instance_valid(subject):
		friendly = not Team.is_enemy(subject.get_faction(), Team.Faction.PLAYER)
	var role: QueueStyle.Role = QueueStyle.Role.READOUT_ALLY if friendly else QueueStyle.Role.READOUT_ENEMY
	_show_readout(QueueStyle.ink(role))

# The damage number's hover text (#424): the delivered kind, then the mitigation and why. A heal or a
# utility hit has no kind and says nothing. Static and string-only so tests/ui can read it without a
# scene, the def_tooltip shape.
static func damage_tip(outcome: ResolvedOutcome, subject: Unit) -> String:
	if outcome.kind == AttackData.Kind.NONE:
		return ""
	var kind := AttackData.kind_name(outcome.kind)
	var lines: Array[String] = ["%s damage" % kind.capitalize()]
	if subject != null and is_instance_valid(subject) and subject.worn_armor != null \
			and not subject.worn_armor.covers(outcome.kind):
		lines.append("%s does not cover %s" % [subject.worn_armor.display_name, kind])
	if outcome.mitigation > 0:
		lines.append("DEF %d subtracted" % outcome.mitigation)
	return UiText.wrap("\n".join(lines))

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
	_show_readout(QueueStyle.ink(QueueStyle.Role.HEADER_TEXT))
	_apply_row_style()

	# Cancelling the summary cancels the whole volley (it's one aim) — keep the X live.
	cancel_button.modulate.a = 1.0
	cancel_button.disabled = false
	cancel_button.mouse_filter = Control.MOUSE_FILTER_STOP
	cancel_button.pressed.connect(_on_cancel_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
