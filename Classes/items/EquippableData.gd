class_name EquippableData
extends Item

# Shared base for anything a unit equips into its combat slot. Weapons and runes both
# extend this so the equip slot, inventory, and resolver treat them uniformly, while each
# subclass keeps its own divergent fields (docs/design/alchemy-kit.md — the stack).
#
# The combat/resolution layer reads ONLY this surface; what it SCALES off is polymorphic
# (base_damage below). WeaponData scales its built-in attack off a stat; a rune presents a
# selected inscribed TransmutationData, which scales off per-element aura (wired when firing lands).
#
# These @exports moved up from WeaponData. .tres serialize @exports by NAME, so the move is
# transparent to existing weapon resources. APPEND-ONLY for any enums (serialized as ints).

@export var power: int = 0
@export var attack_pattern: AttackPattern
@export var can_counter := true
@export var hits_allies := false
@export var elemental_damage_type: Elemental.Element = Elemental.Element.NONE

# Base damage this equippable contributes for a given wielder. Overridden per subclass;
# the resolver calls this instead of branching on type (E1 base-damage stage).
func base_damage(wielder: Unit) -> int:
	return power
