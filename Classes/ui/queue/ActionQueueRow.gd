extends PanelContainer
class_name ActionQueueRow

# One row of the action-queue panel: an element rail, the actor sprite, the action icon, the target
# sprite, an hp->hp readout, the cancel X -- and, when the hit had elemental consequences, a second
# CONSEQUENCE line under them. Draws whatever BaseAction it is handed and asks the ORDER every
# question about itself (icon, description, validity, whether it may be dragged), so a new action
# type needs nothing here. Built by SquadActionQueueControl, which owns the drag, the click (#1122)
# and the sectioning.
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
# writes, which the matchup card (#1629) has room for (reported 2026-09-04: "Into the void!" is 72px,
# the line's slack is 46, and a chip too wide to wrap pushes the whole dock open). Same split
# ElementalReaction.short_name already makes for a reaction's word, applied to the other kind of pill
# -- and the dramatic word is not lost, it is the tooltip and the card's pill. OutcomeFacts pairs them.
#
# THEY ARE CONSTS SO A LAW CAN ENUMERATE THEM: tests/ui/test_queue_badge_widths.gd measures each one
# against the real dock, so the next word too long for the row fails CI instead of the panel.
const BADGE_FELL := "Fell %d"
const BADGE_DROWNED := "Drown"
const BADGE_VOID := "Void"
const BADGE_HELD := "Held %d"       # #120: tiles of a shove the target's weight absorbed
const BADGE_INSULATED := "Shrug"
const BADGE_VIAL := "Vial"
const BADGE_TANK := "Tank"
const BADGE_SPLIT := "Split"        # the dev's word (#367); one unit leaves its squad
const BADGE_SPLITS := "Split %d"    # ...and the count when more than one does
const BADGE_FIZZLED := "Fizzle"     # a carving with nothing to work with
const BADGE_WHIFFED := "Whiff"      # a swing at a target this pass already killed (#1350)
const BADGE_EMPOWERED := "Empowered"   # a form that keeps its carving's name (#695); a named one wears its name

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
signal pressed(row: ActionQueueRow)          # the left press; the panel decides drag or click on release
signal expand_toggled(row: ActionQueueRow)   # a volley header's readout (#1122)
signal inspect_requested(row: ActionQueueRow)   # a right-click's release: open the matchup card (#1629)

func setup(action_ref: BaseAction):
	action = action_ref

	_show_in(actor_texture, action.get_actor_texture())
	actor_texture.modulate = action.get_actor_modulate()
	action_icon.texture = action.get_action_icon()
	_show_in(target_texture, action.get_target_texture())
	description_label.text = action.get_description()

	var outcome := action.resolved_outcome()
	_paint_rail(outcome)
	readout_card.visible = false   # a MOVE row has no number, and an empty card is a stray box
	# Any order carrying an outcome shows the readout, not attacks alone (#419) -- a tile's
	# end-of-turn damage reads as a hit like any other.
	if outcome != null:
		# The number is shown by an outcome that READ HP, not by every outcome (#884). An order that
		# only changed a state -- a walk that soaked its mover -- has no hit to report, and printing
		# its subject's HP unchanged either side of an arrow would invent one.
		if outcome.reads_hp:
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

# The consequence chips, IN the line between the target sprite and the readout (dev, 2026-09-03):
# one per OutcomeFacts fact, its BADGE in the chip and its long word on hover. The matchup card draws
# the same list as pills, so the two cannot disagree about what a hit did.
#
# TEXT ONLY, and it is a CHOICE rather than a constraint -- measured, an icon chip still fits the
# row without clipping. It costs ~19px each, which is what decides whether a second chip WRAPS, and
# the loudest complaint about this panel was height. The card is where the icons go.
#
# No visibility toggle: the container holds the line's horizontal EXPAND whether or not it has chips,
# which is what keeps the cancel X on the right edge of a row that has none. It WRAPS rather than
# clips, so a crowded hit costs the row a second line instead of losing a word.
func _build_consequence(outcome: ResolvedOutcome) -> void:
	var fired: AttackData = (action as AttackAction).fired_attack if action is AttackAction else null
	for fact in OutcomeFacts.of(outcome, fired):
		consequence.add_child(_chip(fact.ink, fact.badge, fact.tip))

# One tinted pill. The tooltip goes on the pill AND its label: a Label defaults to
# MOUSE_FILTER_IGNORE, so the viewport never picks it and the text is dead however right it is.
func _chip(tint: Color, text: String, tip: String) -> Control:
	# PASS, not STOP: picked for the tooltip, and the press still reaches the row's click (#1122).
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", QueueStyle.tint_box(tint))
	pill.mouse_filter = Control.MOUSE_FILTER_PASS
	pill.tooltip_text = tip

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", QueueStyle.CONSEQUENCE_FONT_SIZE)
	label.add_theme_color_override("font_color", tint)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.tooltip_text = tip
	pill.add_child(label)
	return pill


# The Split chip's ink (#367): the tether's own orange, adapted to the palette like any authored
# tint. Opaque, because the chip builds its own translucent fill from it.
static func split_ink() -> Color:
	return QueueStyle.adapted_ink(Color(SquadLines2D.TETHER_COLOR, 1.0))

func _show_hp_delta(outcome: ResolvedOutcome, subject: Unit) -> void:
	# target_hp_after is threaded across the whole pass (R4): for the Nth hit it already accounts
	# for the earlier hits this combat. Since #1002 the resolver threads what the rung LEAVES
	# (LethalityRules.hp_after), so a down already reads 1 here; only a kill still goes negative,
	# and displayed_hp clamps that to 0. That clamp is LethalityRules' since #313: the ghost readout
	# over the unit draws the same prediction, and two spellings would let this panel and the board
	# disagree -- which is why the clamp is asked through the outcome's own door (#1428).
	var hp_before: int = outcome.hp_before
	var hp_after: int = outcome.displayed_hp_after()

	# The "->" spelling is load-bearing: tests/presentation/test_predicted_health.gd finds this
	# label by searching for it and parses split("->")[1].
	readout.text = "%d->%d" % [hp_before, hp_after]
	# The number explains itself on hover (#424, Law #2): what kind the hit delivered and what the
	# target's DEF did with it, read off the outcome's own stamps so this can never name a
	# subtraction other than the one made.
	var tip := damage_tip(outcome)
	readout.tooltip_text = tip
	readout_card.tooltip_text = tip
	readout.mouse_filter = Control.MOUSE_FILTER_PASS   # the chips' reason, see _chip

	_show_readout(side_ink(subject))


# A body's side colour: green for the player's side, red for anyone hostile to it. The readout's
# number and the matchup card's figures both wear it (#1629).
static func side_ink(unit: Unit) -> Color:
	var friendly := true
	if unit != null and is_instance_valid(unit):
		friendly = not Team.is_enemy(unit.get_faction(), Team.Faction.PLAYER)
	return QueueStyle.ink(QueueStyle.Role.READOUT_ALLY if friendly else QueueStyle.Role.READOUT_ENEMY)

# The damage number's hover text (#424): the delivered kind, then the mitigation and why, then what the
# board's air added (#1324). A heal or a utility hit has no kind, so it names only the air, which a
# heal draws on too. Static and string-only so tests/ui can read it without a scene, the def_tooltip
# shape.
static func damage_tip(outcome: ResolvedOutcome) -> String:
	var lines: Array[String] = []
	if outcome.kind != AttackData.Kind.NONE:
		var kind := AttackData.kind_name(outcome.kind)
		lines.append("%s damage" % kind.capitalize())
		if outcome.worn_armor != null and not outcome.worn_armor.covers(outcome.kind):
			lines.append("%s does not cover %s" % [outcome.worn_armor.display_name, kind])
		if outcome.mitigation > 0:
			lines.append("DEF %d subtracted" % outcome.mitigation)
	lines.append_array(_air_lines(outcome.air_steps))
	return "" if lines.is_empty() else UiText.wrap("\n".join(lines))


# One line per substance the air moved this hit by: "Rich vital air: +2", "Thin vapor: -1".
static func _air_lines(steps: Dictionary[String, int]) -> Array[String]:
	var lines: Array[String] = []
	for id: String in steps:
		var word := "Rich" if steps[id] > 0 else "Thin"
		lines.append("%s %s: %+d" % [word, SubstanceCatalog.name_of(id).to_lower(), steps[id]])
	return lines

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
	# EVERY row takes the press since #1122, because a click on any row means something. Which it
	# was, a drag or a click, is only known on the release, so that call is the panel's.
	if action == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pressed.emit(self)
		accept_event()
	elif _is_right(event):
		_take_right(event)
		accept_event()

# A volley header's readout is its expand toggle (#1122): a click on the row requeues the volley like
# any other order, so expanding needed a target of its own. STOP keeps this press from the row, so the
# readout answers a right-click itself, the same as the row.
func _on_readout_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		expand_toggled.emit(self)
		readout_card.accept_event()
	elif _is_right(event):
		_take_right(event)
		readout_card.accept_event()

# A right-click opens the matchup card (#1629) on its RELEASE, the edge the board's cancel acts on in
# 3D. BOTH edges are taken, so neither reaches the board's cancel or the camera's orbit.
static func _is_right(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT

func _take_right(event: InputEvent) -> void:
	if action != null and not (event as InputEventMouseButton).pressed:
		inspect_requested.emit(self)

# A unit's sheet is 64px holding a ~23x20 character, so fitting the whole CELL into a 32px slot drew
# everyone at a third of the slot (#1082, the #937 law). The slot is handed the square around the
# sprite's own ink and stretches it, so every unit fills its slot on its own scale (dev ruling).
func _show_in(slot: TextureRect, texture: Texture2D) -> void:
	slot.texture = MapSpriteInk.portrait(texture)

func setup_volley_summary(lead: AttackAction, count: int, expanded: bool) -> void:
	action = lead
	is_volley_header = true

	_show_in(actor_texture, lead.get_actor_texture())
	actor_texture.modulate = lead.get_actor_modulate()

	# Plain attack icon (not the lead's lethality icon — the group has many outcomes).
	action_icon.texture = AttackAction.group_icon(lead, count)
	action_icon.modulate = lead.get_ui_modulate()
	target_texture.texture = null
	_paint_rail(null)   # the group's hits may carry different elements; the folder's rows say which
	# ...but what the AIM did is one answer for every hit (#695): the form it fired as and the vial it
	# burned, off the lead, so a folded volley still says both.
	for fact in OutcomeFacts.of_aim(lead.resolved, lead.fired_attack):
		consequence.add_child(_chip(fact.ink, fact.badge, fact.tip))

	# The READOUT slot becomes the hit-count + expand affordance -- the group has no single hp->hp,
	# and this is the slot that is free rather than one to draw over (#685).
	readout.text = ("[-] x%d" if expanded else "[+] x%d") % count
	_show_readout(QueueStyle.ink(QueueStyle.Role.HEADER_TEXT))
	readout_card.mouse_filter = Control.MOUSE_FILTER_STOP
	readout_card.gui_input.connect(_on_readout_input)
	_apply_row_style()

	# Cancelling the summary cancels the whole volley (it's one aim) — keep the X live.
	cancel_button.modulate.a = 1.0
	cancel_button.disabled = false
	cancel_button.mouse_filter = Control.MOUSE_FILTER_STOP
	cancel_button.pressed.connect(_on_cancel_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
