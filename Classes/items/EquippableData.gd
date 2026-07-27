class_name EquippableData
extends Item

# Shared base for anything a unit slots into its single equip slot — today WeaponInstance and
# RuneData. Its job is to be the slot's TYPE, so the equip slot, inventory, and save entry can
# hold "an equippable" without caring which kind (docs/design/alchemy-kit.md) — AND to answer
# what that equippable can fire (see the attack-source surface below).
#
# NOTE (2026-07-26) — this REPLACES the older rule that EquippableData deliberately had no combat
# surface and that "combat sites cast as WeaponInstance; a rune yields null -> inert path". That
# held while there was one cast site. There were eventually four fork methods on Unit restating
# the same two-kind dispatch. The outcome is unchanged — a rune still does nothing in melee — but
# it is now declared ONCE, as inert defaults each kind overrides. This mirrors the pattern
# WeaponInstance already uses a level down, where the base declares the readiness surface as
# no-op virtuals so families with no signature mechanic pay nothing (#73).

# Which side of the world an attack affects (#50). Shared vocabulary: both WeaponData.targets
# and TransmutationData.targets are this enum. APPEND-ONLY (serializes as an int in .tres).
enum TargetMode { UNIT, MAP, BOTH }

# Grant/save copy: how a unit receives its own copy of this equippable. Default = full
# deep copy; WeaponInstance overrides to keep its shared template UN-copied.
func copy_equippable() -> EquippableData:
	return duplicate(true)

# --- Attack-source surface ---
# Every default here is the INERT answer, so a kind that can't fire (armor) needs no override.

# Everything the wielder could choose to fire right now — the attack pick-menu's contents.
func selectable_attacks(_wielder: Unit) -> Array[AttackData]:
	return []

# What fires when the player hasn't picked anything specific.
func default_attack(_wielder: Unit) -> AttackData:
	return null

# What a COUNTER fires. Separate from default_attack because the two kinds genuinely diverge on
# whether a live pick counts — see each override.
func counter_attack(wielder: Unit) -> AttackData:
	return default_attack(wielder)

# Non-default attacks, surfaced under the Weapon Action submenu. Weapons only.
func secondary_attacks(_wielder: Unit) -> Array[AttackData]:
	return []
