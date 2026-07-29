class_name ArmorData
extends EquippableData

# Defensive gear. DEF lives on GEAR ONLY (stats.md): the SCALED term is def_power x CON with
# no base, so a naked unit has zero DEF no matter their CON. flat_def rides on top un-scaled --
# a CON-gated piece shouldn't have to double-dip CON to be worth wearing.
@export var def_power: int = 0
@export var flat_def: int = 0

# Wear gates, generalized past #55's single con_requirement: a piece can demand a floor on any
# stat AND a ceiling on any other (bulky rigs only a slow unit can move in). Empty = no gate.
@export var stat_minimums: Dictionary[Stats.Stat, int] = {}
@export var stat_maximums: Dictionary[Stats.Stat, int] = {}

# Abilities this piece grants while WORN — the gear source of the chassis (jobs.md). Read LIVE
# off the worn piece by Unit.get_live_abilities, never mirrored onto UnitInstance: a stored copy
# would restore worn_armor on load and silently lose whatever it granted (#89's rule).
@export var granted_abilities: Array[AbilityData] = []

# Live stat contribution while worn (stats.md "gear carries stat-cost tradeoffs"). Negative
# values are the classic armor tax. Read live off the worn piece by Unit._gear_modifier --
# deliberately NOT applied as a stored StatEffect (#112). Wearing a piece stores nothing, so
# taking it off removes the contribution with no bookkeeping and a save round-trip cannot desync
# it. Only effects with a life of their OWN (a timed tonic, the Crisis surge) get stored.
@export var stat_modifiers: Dictionary[Stats.Stat, int] = {}

func can_equip(wearer: Unit) -> bool:
	# Gates read the wearer's BODY — base -> limb -> jobs -> temporary effects — and NEVER gear
	# (#112, amending #55/#89). Two rules in one line:
	#
	#   * A piece's own -DEX can't unlock a DEX-ceiling piece, so equip legality never depends on
	#     what you happen to have on, or on the order you put it on in.
	#   * Because NO gate reads gear, stripping one piece can never change another piece's answer.
	#     That is precisely what keeps Unit._enforce_gear_gates to a SINGLE pass with no cascade
	#     and no termination question. Do not "simplify" this into get_effective_stat.
	#
	# A tonic that raises CON DOES let you wear the heavy plate — and when it lapses, the plate
	# comes off. Carrying armour you can only wear while buffed is legal, just fragile; and
	# debuffing an enemy under a gate strips their kit.
	for stat in stat_minimums:
		if wearer.get_body_stat(stat) < stat_minimums[stat]:
			return false
	for stat in stat_maximums:
		if wearer.get_body_stat(stat) > stat_maximums[stat]:
			return false
	return true

# Human-readable stat tax, for the equip UI (e.g. "DEX -1").
func modifier_text() -> String:
	return Stats.modifier_text(stat_modifiers)

# Human-readable gate, for the equip UI's "why can't I wear this" label.
func requirement_text() -> String:
	var parts: Array[String] = []
	for stat in stat_minimums:
		parts.append("%s %d+" % [Stats.Stat.keys()[stat], stat_minimums[stat]])
	for stat in stat_maximums:
		parts.append("%s %d or less" % [Stats.Stat.keys()[stat], stat_maximums[stat]])
	return ", ".join(parts)
	
	# Mechanical readout for the inventory tooltip (#44). Itemized for the unit who'd wear it, since
# the scaled term depends on their CON -- "DEF 6" means nothing without saying 6 for whom.
func mechanical_text(wearer: Unit) -> String:
	var lines: Array[String] = []
	if wearer != null:
		var con := wearer.get_effective_stat(Stats.Stat.CON)
		var total := Stats.armor_def(def_power, con, flat_def)
		if def_power > 0 and flat_def > 0:
			lines.append("DEF %d  (%d x CON %d, +%d flat)" % [total, def_power, con, flat_def])
		elif def_power > 0:
			lines.append("DEF %d  (%d x CON %d)" % [total, def_power, con])
		elif flat_def > 0:
			lines.append("DEF %d  (flat)" % total)
		else:
			lines.append("DEF 0")
	var gate := requirement_text()
	if gate != "":
		lines.append("Requires: %s" % gate)
	var mods := modifier_text()
	if mods != "":
		lines.append("While worn: %s" % mods)
	if not granted_abilities.is_empty():
		var names: Array[String] = []
		for ability in granted_abilities:
			if ability != null and ability.id != Abilities.Id.NONE:
				names.append(ability.display_name)
		if not names.is_empty():
			lines.append("Grants: %s" % ", ".join(names))
	return "\n".join(lines)
