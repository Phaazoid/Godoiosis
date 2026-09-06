class_name ArmorData
extends EquippableData

# Defensive gear. DEF lives on GEAR ONLY (stats.md): the SCALED term is def_power x CON with
# no base, so a naked unit has zero DEF no matter their CON. flat_def rides on top un-scaled --
# a CON-gated piece shouldn't have to double-dip CON to be worth wearing.
@export var def_power: int = 0
@export var flat_def: int = 0

# Which damage kinds this piece's DEF applies to (#424). EMPTY means every kind -- the storage's own
# default, so a piece authored before kinds existed keeps stopping everything until someone says
# otherwise. A piece that lists kinds stops ONLY those: plate lists the three physical kinds and a
# fireball goes straight through it. On/off deliberately, not a number per kind (dev, 2026-09-05:
# "too early to make a call"); a per-kind table would be a superset of this list if content ever
# asks. Cover and the brace bonus are kind-blind; only armour carries this.
@export var covered_kinds: Array[AttackData.Kind] = []

# Does this piece's DEF apply to a hit delivered as `kind`? The one reader of covered_kinds'
# empty-means-all rule; RulesService.def_against asks it and nothing else does.
func covers(kind: AttackData.Kind) -> bool:
	return covered_kinds.is_empty() or covered_kinds.has(kind)

# "vs blunt, slash, pierce" for the readouts, or "" when the piece covers everything.
func coverage_text() -> String:
	if covered_kinds.is_empty():
		return ""
	var names: Array[String] = []
	for kind: AttackData.Kind in covered_kinds:
		names.append(AttackData.kind_name(kind))
	return "vs " + ", ".join(names)

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

# The wear gate, and what it would take to pass it (#744 widened this from a bare bool).
#
# EVERY failing gate is named, not the first: two points short on CON and three over on DEX is a
# piece your build cannot wear, and a player told only about the CON goes and fixes the wrong thing.
func can_equip_reason(wearer: Unit) -> String:
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
	var short: Array[String] = []
	for stat: Stats.Stat in stat_minimums:
		var has: int = wearer.get_body_stat(stat)
		if has < stat_minimums[stat]:
			short.append("%s (has %d)" % [_gate_text(stat, stat_minimums[stat], false), has])
	for stat: Stats.Stat in stat_maximums:
		var has: int = wearer.get_body_stat(stat)
		if has > stat_maximums[stat]:
			short.append("%s (has %d)" % [_gate_text(stat, stat_maximums[stat], true), has])
	return "" if short.is_empty() else "Needs " + ", ".join(short)

# Human-readable stat tax, for the equip UI (e.g. "DEX -1").
func modifier_text() -> String:
	return Stats.modifier_text(stat_modifiers)

# What this piece DEMANDS, with nobody holding it — the question a list of loose gear can ask and
# can_equip_reason cannot, since that one takes a wearer (dev, 2026-09-05: an invalid readout needs a
# unit to be validated against, so it lives on the card while this lives wherever gear is listed
# alone). Two scopes deliberately; ONE grammar, through the helper below.
func requirement_text() -> String:
	var parts: Array[String] = []
	for stat: Stats.Stat in stat_minimums:
		parts.append(_gate_text(stat, stat_minimums[stat], false))
	for stat: Stats.Stat in stat_maximums:
		parts.append(_gate_text(stat, stat_maximums[stat], true))
	return ", ".join(parts)

# ONE spelling of one gate, shared by the two questions above. Separate formatting is how "DEX 5 or
# less" and "DEX max 5" end up on two surfaces describing the same number.
static func _gate_text(stat: Stats.Stat, value: int, is_ceiling: bool) -> String:
	return "%s %d%s" % [Stats.Stat.keys()[stat], value, " or less" if is_ceiling else "+"]
	
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
		var coverage := coverage_text()
		if coverage != "":
			lines[lines.size() - 1] += "  " + coverage
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
