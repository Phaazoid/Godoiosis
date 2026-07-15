class_name ArmorData
extends EquippableData

# Defensive gear. DEF lives on GEAR ONLY (stats.md) — CON scales it as a multiplier
# with no base, so a naked unit has zero DEF no matter their CON.
@export var def_power: int = 0
@export var con_requirement: int = 0   # heavy-armor gate: 0 = anyone. Mirrors a future STR weapon gate.

func can_equip(wearer: Unit) -> bool:
	return wearer.get_effective_stat(Stats.Stat.CON) >= con_requirement
