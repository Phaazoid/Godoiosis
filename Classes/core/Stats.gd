extends Object
class_name Stats

# Canonical stat vocabulary + derived-stat math used across units/weapons/jobs: the Stat
# enum, its defaults, and the "stat-shadow" band doctrine (coarse DEX/CON/PER rungs
# feeding MOV/MHP/LDR) plus armor_def — pure statics per docs/design/stats.md.

# The canonical stat vocabulary. APPEND-ONLY: these serialize as ints in saved .tres
# (UnitData.base_stats / WeaponData.scaling_blend keys). Reordering or deleting
# a value silently corrupts existing resources — always add new stats at the END.
# Roster + rationale: docs/design/stats.md. Input stats: STR/DEX/PER/CON. Capacity: MHP/WIL/LDR.
# Squad: COH.
enum Stat { MHP, STR, LDR, WIL, DEX, PER, CON, COH }

const STAT_DEFAULTS: Dictionary[Stat, int] = {
	Stat.MHP: 20,
	Stat.STR: 5,
	Stat.LDR: 5,
	Stat.WIL: 5,
	Stat.DEX: 5,
	Stat.PER: 5,
	Stat.CON: 5,
	# Cohesion radius: how far a squadmate may stand from its LEADER, in PATH distance over terrain
	# the member can traverse (#151 — walls block cohesion; was Manhattan until 2026-08-06). Read off
	# the leader only — Squad.get_max_squad_range() is the single reader. Still decoupled from LDR
	# (#63): LDR buys squad capacity, COH buys leash length, and no band feeds either into the other.
	Stat.COH: 4,   # playtest-tunable; 3 -> 4 on 2026-08-06 ahead of path-based cohesion (#151),
				   # which is a strictly tighter leash at the same number (path >= Manhattan always)
}

const CON_DEF_FACTOR := 0.2   # playtest-tunable: CON 5 wears armor at its printed value

# Band doctrine (docs/design/stats.md): input stats cast small, coarse, bounded shadows.
# Three rungs, shared thresholds; coarse is a feature — don't smooth into per-point scaling.
const BAND_LOW_MAX := 3    # 0-3 = low rung  # playtest-tunable
const BAND_MID_MAX := 7    # 4-7 = mid rung (all defaults land here); 8+ = high

# DEX->MOV rungs (retuned 2026-07-15, jobs.md): default DEX (5) TOPS its rung — one point
# of investment buys the first MOV jump, four buy the second. # playtest-tunable
const DEX_MOV_MID_MAX := 5    # 4-5 = +0
const DEX_MOV_HIGH_MAX := 8   # 6-8 = +1; 9+ = +2

static func armor_def(def_power: int, con: int, flat_def: int = 0) -> int:
	# DEF = flat term + (power x CON) (stats.md). The SCALED term is a multiplier with NO base,
	# so zero armor or zero CON contributes nothing to it; flat_def is the un-scaled term a piece
	# may carry on top, so a CON-GATED piece can pay out without double-dipping CON (2026-07-24).
	return flat_def + int(round(def_power * con * CON_DEF_FACTOR))

# Human-readable stat delta ("DEX -1, CON +2") for any modifier dict — armour taxes, StatEffects,
# a future weapon mod. One renderer so two sources can't drift on formatting.
static func modifier_text(mods: Dictionary[Stat, int]) -> String:
	var parts: Array[String] = []
	for stat in mods:
		parts.append("%s %+d" % [Stat.keys()[stat], mods[stat]])
	return ", ".join(parts)

# The stats a weapon attack's damage may scale off (#485). weapons.md has said "across
# STR/DEX/PER/CON" since the blend was written and no code declared it, so the Attack Editor drew
# all eight -- MHP, LDR, WIL and COH included, none of which means anything in a damage blend.
# One list, read by the editor's sliders and by AttackLint.
const SCALING_STATS: Array[Stat] = [Stat.STR, Stat.DEX, Stat.PER, Stat.CON]

# A blend's weights always total this once the editor has touched it. Not enforced by the math --
# scaling_contribution normalises whatever it is given -- but a percentage on screen is only true
# when the weights already sum to it, so the editor pins it and AttackLint refuses anything else.
const BLEND_TOTAL := 100

# Human-readable scaling blend ("STR 60%, DEX 40%") for a weights dict (#485). Sibling of
# modifier_text and separate for the same reason payload_text and targets_text are: a DELTA and a
# SHARE are different questions, and only one of them wants a sign.
#
# NORMALISES, and that is the whole point rather than a nicety. The weights are read as a weighted
# average, so {STR: 100, DEX: 30} really is 77/23 -- printing the raw numbers would put "100%" and
# "30%" on screen for a weapon that is neither. Zero-weight stats are omitted; an empty or
# all-zero blend answers "no stat scaling", which is a real authored state a reader must not
# mistake for a missing one.
static func blend_text(blend: Dictionary[Stat, int]) -> String:
	var total := 0
	for stat in blend:
		total += blend[stat]
	if total <= 0:
		return "no stat scaling"
	var parts: Array[String] = []
	for stat in blend:
		if blend[stat] <= 0:
			continue
		parts.append("%s %d%%" % [Stat.keys()[stat], int(round(blend[stat] * 100.0 / total))])
	return ", ".join(parts)

static func dex_mov_band(dex: int) -> int:
	if dex <= BAND_LOW_MAX:
		return -1
	if dex <= DEX_MOV_MID_MAX:
		return 0
	if dex <= DEX_MOV_HIGH_MAX:
		return 1
	return 2

static func con_mhp_band(con: int) -> int:
	# Extremes 4 MHP apart end to end (stats.md: <=4-5).  # playtest-tunable
	if con <= BAND_LOW_MAX:
		return -2
	if con <= BAND_MID_MAX:
		return 0
	return 2

static func per_ldr_band(per: int) -> int:
	if per <= BAND_LOW_MAX:
		return -1
	if per <= BAND_MID_MAX:
		return 0
	return 1
