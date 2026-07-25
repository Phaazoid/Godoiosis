class_name DrillWeaponInstance
extends WeaponInstance

# Drill's signature is Burrow (#84): a main action that lays a permanent COVER tile (flat terrain
# DEF) on the burrower's cell — the melee terrain-engineer. No per-weapon battle state (the deposit
# lives in the plan/terrain layer, not on the weapon), so can_burrow() is the entire surface.

func can_burrow() -> bool:
	return true
