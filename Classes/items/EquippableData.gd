class_name EquippableData
extends Item

# Shared base for anything a unit slots into its single equip slot — today WeaponData and
# RuneData. Its only job is to be the slot's TYPE, so the equip slot, inventory, and save
# entry can hold "an equippable" without caring which kind (docs/design/alchemy-kit.md).
#
# Deliberately has NO combat surface. A weapon carries its own built-in attack (WeaponData);
# a rune is an inert container that FIRES a selected inscribed TransmutationData. The resolver
# reads that "attack source" (weapon | transmutation), never a bare EquippableData — so a rune
# does nothing in melee. Combat sites cast `as WeaponData`; a rune yields null -> inert path.

# Which side of the world an attack affects (#50). Shared vocabulary: both WeaponData.targets
# and TransmutationData.targets are this enum. APPEND-ONLY (serializes as an int in .tres).
enum TargetMode { UNIT, MAP, BOTH }
