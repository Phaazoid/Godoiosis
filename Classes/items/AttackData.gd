class_name AttackData
extends Resource

# Shared base for anything a unit can FIRE: a weapon attack (WeaponAttackData) or an
# inscribed carving (TransmutationData). Carries the attack's identity, geometry, and
# combat flags — what every consumer (pattern reach, counter gate, ally-splash, target
# mode) reads without caring which kind it is. Damage math deliberately stays on the
# subclasses: carvings scale off the wielder's AURA, weapon attacks off the wielding
# WEAPON (scaling_blend + mods) — there is no shared damage surface. #72.

@export var display_name: String = ""
@export var power: int = 0
@export var attack_pattern: AttackPattern
@export var can_counter := true
@export var hits_allies := false
@export var targets: EquippableData.TargetMode = EquippableData.TargetMode.UNIT
@export var knockback: int = 0
# Deterministic shove (#84, Kinetic Mace): tiles this attack pushes its target directly away
# from the attacker, stopping at the first wall/unit/edge. 0 = no displacement (every attack
# today). Generic on purpose — a future air-blast rune could carry it too. Resolved by
# PlanResolver, applied on execute; the Kinetic Mace's Blowback is the first user.

func hits_map() -> bool:
	return targets == EquippableData.TargetMode.MAP or targets == EquippableData.TargetMode.BOTH
