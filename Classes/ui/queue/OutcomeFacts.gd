extends RefCounted
class_name OutcomeFacts

# What a hit did to the body it landed on, as a list of FACTS, each drawn its own way by each surface
# that shows it: the queue row prints a fact's BADGE in a chip with its WORD on hover, the matchup
# card (#1629) prints its ICON and full WORD in a pill. One list, so the two can never disagree about
# what a hit did (Law #4). Every fact is read off the outcome's own stamps, or the attack its row
# fired, which the resolver stamped too (Law #2).
#
# A SETUP reaction is deliberately absent: the state chip it produced already says it (#685). Only a
# fired COMBO gets a fact of its own.

class Fact:
	var ink: Color
	var badge: String        # the row's short spelling, sized for the dock
	var word: String         # the full word, sized for a card
	var tip: String          # the row chip's hover text
	var icon: Texture2D      # null when the fact has no art

	func _init(ink_: Color, badge_: String, word_: String, tip_: String, icon_: Texture2D = null) -> void:
		ink = ink_
		badge = badge_
		word = word_
		tip = tip_
		icon = icon_


# `fired` is the attack the row fired (AttackAction.fired_attack, stamped at resolve), which is where
# an empowered form shows: the outcome records what a hit did, never which form did it.
static func of(outcome: ResolvedOutcome, fired: AttackData = null) -> Array[Fact]:
	var facts: Array[Fact] = []
	if outcome == null:
		return facts
	var form := _form_fact(fired)
	if form != null:
		facts.append(form)
	for state in outcome.states_added:
		if state == Elemental.State.NONE:
			continue
		var name := Elemental.state_display_name(state)
		facts.append(Fact.new(QueueStyle.state_ink(state), name, name,
				UiText.wrap("%s -- %s" % [name, Glossary.short(Glossary.term_for_element_state(state))]),
				StateIcons.texture_of(state)))

	# The guard asks the ACCESSOR whether there is a word, not the raw popup.
	for reaction: ElementalReaction in outcome.fired_reactions:
		if not reaction.is_combo() or reaction.badge_name() == "":
			continue
		facts.append(Fact.new(QueueStyle.element_ink(setter_of(reaction, outcome)), reaction.badge_name(),
				reaction.popup if reaction.popup != "" else reaction.badge_name(),
				UiText.wrap(Glossary.reaction_line(reaction)), reaction.icon))

	# What the WORLD did, read off the outcome's recorded facts rather than parsed back out of
	# `popups`: the badge is the dock's spelling, the resolver's dramatic word is the long one.
	# A FIZZLE (Deep Alchemy Phase 2): the carving lands nothing. Its outcome reads no HP, so this is
	# the row's whole readout.
	if outcome.fizzled:
		facts.append(_event(ActionQueueRow.BADGE_FIZZLED, PlanResolver.FIZZLED_POPUP))
	# A WHIFF (#1350): the target is already gone by this swing, but the swing still happens.
	if outcome.whiffed:
		facts.append(_event(ActionQueueRow.BADGE_WHIFFED, PlanResolver.WHIFFED_POPUP))
	if outcome.insulated:
		facts.append(_event(ActionQueueRow.BADGE_INSULATED, PlanResolver.INSULATED_POPUP))
	# A fully held shove draws no trail, so this is the queue's whole account of it (Law #2).
	if outcome.knockback_held > 0:
		facts.append(_event(ActionQueueRow.BADGE_HELD % outcome.knockback_held,
				PlanResolver.HELD_POPUP % outcome.knockback_held))
	if outcome.fall_levels > 0:
		facts.append(_event(ActionQueueRow.BADGE_FELL % outcome.fall_levels,
				PlanResolver.FELL_POPUP % outcome.fall_levels))
	if outcome.drown_damage > 0:
		facts.append(_event(ActionQueueRow.BADGE_DROWNED, PlanResolver.DROWNING_POPUP))
	if outcome.removed:
		facts.append(_event(ActionQueueRow.BADGE_VOID, PlanResolver.VOID_POPUP))
	var vial := _vial_fact(outcome)
	if vial != null:
		facts.append(vial)
	# The TANK spend (#97): this shot is the supercharged one and the next will not be.
	if outcome.charge_spent:
		var spent := "Spends a supercharged shot"
		facts.append(Fact.new(QueueStyle.ink(QueueStyle.Role.EVENT_TINT), ActionQueueRow.BADGE_TANK,
				spent, UiText.wrap(spent)))
	# A SPLIT (#367): this blow knocks someone out of a squad. The hover names who; the wording is
	# the dev's to add.
	if not outcome.splits.is_empty():
		var word: String = ActionQueueRow.BADGE_SPLIT if outcome.splits.size() == 1 \
				else ActionQueueRow.BADGE_SPLITS % outcome.splits.size()
		var names: Array[String] = []
		for unit in outcome.splits:
			if is_instance_valid(unit):
				names.append(unit.get_unit_name())
		facts.append(Fact.new(ActionQueueRow.split_ink(), word, word, UiText.wrap(", ".join(names))))
	return facts


# The facts that belong to the AIM rather than to one body it hit (#695): what the carving fired as,
# and the vial it burned. Every member wears them; a collapsed volley's header draws these alone, off
# its lead, so neither hides behind the fold.
static func of_aim(outcome: ResolvedOutcome, fired: AttackData = null) -> Array[Fact]:
	var facts: Array[Fact] = []
	var form := _form_fact(fired)
	if form != null:
		facts.append(form)
	var vial := _vial_fact(outcome)
	if vial != null:
		facts.append(vial)
	return facts


# The EMPOWERED FORM (#695): the row fired its carving's form. The badge is the form's own name, or
# BADGE_EMPOWERED for a form that kept its carving's; the ink is the first element it asked for.
static func _form_fact(fired: AttackData) -> Fact:
	var form := fired as TransmutationData
	if form == null or form.form_of == null:
		return null
	var carving := form.form_of
	var needed := carving.form_requires()
	var word := "Empowered by %s" % carving.form_requires_text()
	var badge := form.display_name if form.display_name != carving.display_name else ActionQueueRow.BADGE_EMPOWERED
	var ink := QueueStyle.element_ink(needed[0]) if not needed.is_empty() \
			else QueueStyle.ink(QueueStyle.Role.EVENT_TINT)
	return Fact.new(ink, badge, word, UiText.wrap("%s: fires as %s" % [word, form.display_name]))


# The vial BURN (#697): this cast spends an item, and a plan that spent one unseen is the queue
# lying. Element-tinted, because the burn is an elemental fact.
static func _vial_fact(outcome: ResolvedOutcome) -> Fact:
	if outcome == null or outcome.burned_vial == null:
		return null
	var burned := outcome.burned_vial
	var ink := QueueStyle.element_ink(burned.element) if not burned.is_alkahest \
			else QueueStyle.ink(QueueStyle.Role.EVENT_TINT)
	var spent := "Burns %s" % burned.display_name
	return Fact.new(ink, ActionQueueRow.BADGE_VIAL, spent, UiText.wrap(spent))


# Which of the hit's elements set this reaction off -- its ink. A reaction answers to more than its
# primary (heat dries what fire does), so a heat hit's Quick Dry wears Heat, not Fire.
static func setter_of(reaction: ElementalReaction, outcome: ResolvedOutcome) -> Elemental.Element:
	for e: Elemental.Element in outcome.elements:
		var one: Array[Elemental.Element] = [e]
		if reaction.fires_for(one):
			return e
	return reaction.incoming_element


static func _event(badge: String, spoken: String) -> Fact:
	return Fact.new(QueueStyle.ink(QueueStyle.Role.EVENT_TINT), badge, spoken, UiText.wrap(spoken))
