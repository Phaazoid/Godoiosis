class_name ItemText
extends Object

# THE one answer to "what does this item say on hover" (#137). It was answered three ways -- the
# inspect panel itemized it, the pre-mission stash fell back to describe() else the name, and a
# card's gear row showed the name alone -- so the same piece of gear read richest in battle and
# poorest on the screen where a stranger picks it up.
#
# Order: the name, the kind's MECHANICAL lines, then authored flavour last. The mechanical half is
# never authored here: ArmorData.mechanical_text, RuneData.attack_detail, VialData.mechanical_text,
# WeaponModData.effect_text and WeaponInstance.status_text own those words, so a number that moves
# re-words every tooltip with no edit at this layer. `description` stays flavour, and stays the
# dev's to write.
#
# Logical lines only -- the caller wraps (UiText.wrap), per that class's own scope note.

# `unit` is who the readout is FOR, and null is legal: the stash has nobody to itemize against
# (dev, 2026-09-05), so the wielder-scaled terms drop out. Null is not a lesser caller to be
# tolerated -- every term that needs a wielder is guarded, because a rune's carving detail reads
# aura straight off the unit and would crash rather than degrade.
static func hover(item: Item, unit: Unit = null) -> String:
	if item == null:
		return ""
	# shown_name(), never display_name: a derived generic carries no name of its own (#745).
	var lines: Array[String] = [item.shown_name()]
	lines.append_array(_mechanical_lines(item, unit))
	# describe(), never the field: a weapon inherits its family's wording when it carries none (#745).
	if item.describe() != "":
		lines.append("")
		lines.append(item.describe())
	return "\n".join(lines)


# One branch per kind that has something a player decides on. A kind with no generator falls
# through to its name alone, which is the honest answer rather than a placeholder.
static func _mechanical_lines(item: Item, unit: Unit) -> Array[String]:
	var lines: Array[String] = []

	var weapon := item as WeaponInstance
	if weapon != null:
		# The headline view is the weapon's MAIN attack, asked for explicitly -- base_damage no longer
		# defaults to it, because null there means "no attack" now (#102).
		var body := UnitState.of(unit)
		var main_atk: WeaponAttackData = weapon.default_attack(body) as WeaponAttackData
		if unit != null:
			# HELD (#962): the number the loadout row prints, the weapon's own once it is in hand.
			lines.append("Damage %d" % weapon.held_damage(body, main_atk))
		# What it scales off, for this holder or -- nobody -- the build: the stash row's own words, and
		# the half the loadout's rows leave to this popup (dev, 2026-10-28).
		if main_atk != null and not main_atk.deals_no_damage:
			lines.append("Scales off %s" % Stats.blend_text(weapon.scaling_of(body, main_atk)))
		var status: String = weapon.status_text()
		if status != "":
			lines.append(status)
		return lines

	var armor := item as ArmorData
	if armor != null:
		# Itemizes DEF for THIS wearer and drops that term for nobody, gate and grants included.
		var mech: String = armor.mechanical_text(UnitState.of(unit))
		if mech != "":
			lines.append(mech)
		return lines

	var rune := item as RuneData
	if rune != null:
		# What a decision actually turns on (#167): temper + capacity headline, then one line per
		# inscribed carving -- readout only, composed from #166's attack_detail/attack_block_reason
		# pair (the same detail-then-reason order the Transmutation submenu's rows already use).
		var temper_text := "Untempered" if rune.temper == Elemental.Element.NONE \
			else "%s temper" % Elemental.display_name(rune.temper)
		lines.append("%s  ·  %s  ·  %d/%d capacity" % [
			RuneData.Size.keys()[rune.size].capitalize(), temper_text,
			rune.used_capacity(), rune.capacity()])
		for t in rune.inscriptions:
			lines.append("")
			lines.append(t.display_name)
			# What it asks for is the recipe's, whoever carries it (#962).
			lines.append("Asks %s" % t.demand_text())
			# Both of these scale off the wielder's aura, so with nobody to ask, the carving is
			# named and left at that.
			if unit == null:
				continue
			var detail: String = rune.attack_detail(unit.state, t)
			if detail != "":
				lines.append(detail)
			var reason: String = rune.attack_block_reason(unit.state, t)
			if reason != "":
				lines.append(reason)
		return lines

	var vial := item as VialData
	if vial != null:
		var attunes: String = vial.mechanical_text()
		if attunes != "":
			lines.append(attunes)
		return lines

	var conduit := item as ConduitData
	if conduit != null:
		var holds: String = conduit.mechanical_text()
		if holds != "":
			lines.append(holds)
		return lines

	var mod := item as WeaponModData
	if mod != null:
		# The card composes size and fitting refusal around this same sentence; here it is the
		# whole readout, because a loose mod has no weapon to be refused by yet.
		lines.append(mod.effect_text())
		return lines

	return lines
