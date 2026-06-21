extends Object
class_name Stats

# The canonical stat vocabulary. APPEND-ONLY: these serialize as ints in saved .tres
# (UnitData.base_stats /  WeaponData.scaling_stat). Reordering or deleting
# a value silently corrupts existing resources — always add new stats at the END.
# Roster + rationale: docs/design/stats.md. Input stats: STR/DEX/PER. Capacity: MHP/WIL/LDR.
enum Stat { MHP, STR, LDR, WIL, DEX, PER }

const STAT_DEFAULTS: Dictionary[Stat, int] = {
	Stat.MHP: 20,
	Stat.STR: 5,
	Stat.LDR: 5,
	Stat.WIL: 5,
	Stat.DEX: 5,
	Stat.PER: 5,
}
