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

# Elements this armor turns aside (alchemy-kit.md: elemental effects are mitigated by TARGETED
# gear, never a catch-all RES stat). The resolver filters these out of an incoming hit.
@export var immune_elements: Array[Elemental.Element] = []

# Live stat contribution while worn (stats.md "gear carries stat-cost tradeoffs"). Negative
# values are the classic armor tax. Read live off the worn piece -- deliberately NOT pushed into
# UnitInstance.stat_modifiers, which is a stateful add/subtract bag (Crisis surge) that isn't
# serialized; armor swapping through it would desync the moment a save round-tripped.
@export var stat_modifiers: Dictionary[Stats.Stat, int] = {}

func can_equip(wearer: Unit) -> bool:
	# Gates read the wearer's PRE-GEAR stats (base -> limb -> job), never Unit.get_effective_stat.
	# Otherwise a piece's own -DEX could unlock a DEX-ceiling piece, and whether you could wear
	# something would depend on what you happened to have on -- order-dependent and unexplainable.
	# The gate asks about the BODY, not the outfit.
	var inst: UnitInstance = wearer.unit_instance
	for stat in stat_minimums:
		if inst.get_effective_stat(stat) < stat_minimums[stat]:
			return false
	for stat in stat_maximums:
		if inst.get_effective_stat(stat) > stat_maximums[stat]:
			return false
	return true

# Human-readable stat tax, for the equip UI (e.g. "DEX -1").
func modifier_text() -> String:
	var parts: Array[String] = []
	for stat in stat_modifiers:
		parts.append("%s %+d" % [Stats.Stat.keys()[stat], stat_modifiers[stat]])
	return ", ".join(parts)

func blocks_element(element: Elemental.Element) -> bool:
	return immune_elements.has(element)

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
	if not immune_elements.is_empty():
		var names: Array[String] = []
		for e in immune_elements:
			names.append(Elemental.Element.keys()[e].capitalize())
		lines.append("Immune to: %s" % ", ".join(names))
	return "\n".join(lines)
