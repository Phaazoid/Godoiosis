extends Object
class_name Stats

# The canonical stat vocabulary. APPEND-ONLY: these serialize as ints in saved .tres
# (UnitData.base_stats /  WeaponData.scaling_stat). Reordering or deleting
# a value silently corrupts existing resources — always add new stats at the END.
# Roster + rationale: docs/design/stats.md. Input stats: STR/DEX/PER/CON. Capacity: MHP/WIL/LDR.
enum Stat { MHP, STR, LDR, WIL, DEX, PER, CON }

const STAT_DEFAULTS: Dictionary[Stat, int] = {
	Stat.MHP: 20,
	Stat.STR: 5,
	Stat.LDR: 5,
	Stat.WIL: 5,
	Stat.DEX: 5,
	Stat.PER: 5,
	Stat.CON: 5,
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

static func armor_def(def_power: int, con: int) -> int:
	# DEF x CON (stats.md): a multiplier with NO base — zero armor or zero CON -> zero DEF.
	return int(round(def_power * con * CON_DEF_FACTOR))

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
