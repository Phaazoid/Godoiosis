extends Object
class_name Stats

# The canonical stat vocabulary. APPEND-ONLY: these serialize as ints in saved .tres
# (UnitData.base_stats / growth_ranges, WeaponData.scaling_stat). Reordering or deleting
# a value silently corrupts existing resources — always add new stats at the END.
enum Stat { MHP, STR, LDR, WIL }

const STAT_DEFAULTS: Dictionary[Stat, int] = {
	Stat.MHP: 20,
	Stat.STR: 5,
	Stat.LDR: 5,
	Stat.WIL: 5,
}
