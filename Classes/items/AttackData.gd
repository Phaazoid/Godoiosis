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
@export var hits_self := false
@export var targets: EquippableData.TargetMode = EquippableData.TargetMode.UNIT
@export var knockback: int = 0
# Deterministic shove (#84, Kinetic Mace): tiles this attack pushes its target directly away
# from the attacker, stopping at the first wall/unit/edge. 0 = no displacement (every attack
# today). Generic on purpose — a future air-blast rune could carry it too. Resolved by
# PlanResolver, applied on execute; the Kinetic Mace's Blowback is the first user.
@export var heals := false   # EITHER damage OR heal, never both; reinterprets base damage as HP restored
# A pure-utility attack (#126): SCALING is suppressed, so neither aura nor a weapon's stat blend can
# sneak damage into a damageless effect. Only the attack's own contribution — an elemental reaction's
# damage_bonus still lands, deliberately (dev, 2026-08-08). Mutually exclusive with `heals`.
@export var deals_no_damage := false
func hits_map() -> bool:
	return targets == EquippableData.TargetMode.MAP or targets == EquippableData.TargetMode.BOTH

func hits_units() -> bool:
	return targets == EquippableData.TargetMode.UNIT or targets == EquippableData.TargetMode.BOTH

# How a readout PHRASES this attack's payload. The number stays per-kind (a carving scales off
# aura, a weapon attack off its weapon — #72 keeps damage math off this base), but the three-state
# question damages/heals/neither is answered HERE, so the two kinds can never word it differently.
func payload_text(amount: int) -> String:
	if deals_no_damage:
		return "No damage"
	if heals:
		return "Heals %d" % amount
	return "Damage %d" % amount

# The targeting channel's readout token (#135 round 2) — same one-spelling rule as payload_text,
# deliberately its own function: payload and targeting are different questions. Concise parens by
# dev call ("(unit)" / "(tile)" / "(unit/tile)"); Glossary's ATTACK_TARGETING entry explains them.
func targets_text() -> String:
	if targets == EquippableData.TargetMode.BOTH:
		return "(unit/tile)"
	return "(tile)" if targets == EquippableData.TargetMode.MAP else "(unit)"
