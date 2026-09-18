class_name AttackChannelText

# EVERY CHANNEL TWO ATTACKS CAN DIFFER IN, as lines a detail card prints (#1017, shared at #1019).
# One answer for both cards: the weapon's (ModFittingCard) and the rune's (RuneDetailCard).
#
# IT IS SHARED BECAUSE #1017'S LAW SAYS SO. That ticket's finding was not "add knockback", it was
# that a readout drawing four things reports faithfully that its four things did not move -- and its
# fix was to enumerate, so the next pair of near-identical attacks cannot reopen it. A SECOND card
# with a second enumeration is precisely how it reopens: a flag added to AttackData would then have
# to be remembered twice, and the shipped carvings already differ across seven of these fields.
#
# THE COMPOSED VALUES ARRIVE AS PARAMETERS, never looked up (Law #4's "prefer passing"). A weapon's
# knockback, elements, overwatch and ally splash are folded through its fitted mods; a carving's are
# its own, since a carving carries no mods. So the SOURCE is the caller's question and the WORDING is
# this file's -- reading the authored field here would be #1017 one layer down, for every card at once.
#
# WHAT IS DELIBERATELY NOT HERE is what only one kind of attack has: a weapon's readiness rule and its
# empowered form, both WeaponAttackData fields, which that card writes around these lines.
#
# A LINE ONLY APPEARS WHEN IT HAS SOMETHING TO SAY, so a plain sword's readout stays exactly as short
# as it was before any of this.


static func lines(attack: AttackData, knockback: int, elements: Array[Elemental.Element],
		can_overwatch: bool, hits_allies: bool) -> Array[String]:
	var out: Array[String] = []
	if attack == null:
		return out

	if knockback != 0:
		out.append("Shoves %d tile%s" % [knockback, "" if knockback == 1 else "s"])

	if not elements.is_empty():
		var named: Array[String] = []
		for element: Elemental.Element in elements:
			named.append(Elemental.display_name(element))
		out.append("Carries %s" % " and ".join(named))

	if can_overwatch:
		out.append("Watch only — declared as a standing watch, never fired directly")
	if hits_allies:
		out.append("Splashes allies")
	if attack.hits_self:
		out.append("Catches the attacker too")
	if attack.pierces_guard:
		out.append("Pierces guard")
	# can_counter defaults TRUE, so the line is the EXCEPTION -- saying "can counter" on nearly every
	# attack in the game would be noise wearing the shape of information.
	if not attack.can_counter:
		out.append("Never counters")

	out.append_array(_height_lines(attack))
	return out


# What this attack reaches, in one line. Shared for the same reason the channels are: both cards draw
# a range and neither has a different answer to give.
static func range_text(attack: AttackData) -> String:
	if attack == null:
		return ""
	if attack.is_directional():
		return "Aims a facing"
	var span := "Range %d" % attack.max_range if attack.min_range == attack.max_range \
		else "Range %d-%d" % [attack.min_range, attack.max_range]
	return "%s, bevelled corners" % span if attack.max_and_a_half else span


# How this attack answers the height question. MELEE ignores the tolerances outright (AttackData's
# own note), so printing them there would describe a rule that is not running.
static func _height_lines(attack: AttackData) -> Array[String]:
	var out: Array[String] = []
	if attack.vertical_rule == AttackData.VerticalRule.MELEE:
		out.append("Melee height — same step, or a ramp-legal edge")
		return out
	if attack.up_tolerance >= 0:
		out.append("Reaches %d up" % attack.up_tolerance)
	if attack.down_tolerance >= 0:
		out.append("Reaches %d down" % attack.down_tolerance)
	if attack.arc_clearance > 0:
		out.append("Arcs %d over its own sightline" % attack.arc_clearance)
	return out
