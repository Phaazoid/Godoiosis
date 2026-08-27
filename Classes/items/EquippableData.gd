class_name EquippableData
extends Item

# Shared base for anything a unit slots into its single equip slot — today WeaponInstance and
# RuneData. Its job is to be the slot's TYPE, so the equip slot, inventory, and save entry can
# hold "an equippable" without caring which kind (docs/design/alchemy-kit.md) — AND to answer
# what that equippable can fire (the attack-source surface) or DO (the weapon-verb surface),
# both declared below as inert defaults.
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

# May this unit equip this? Default = yes; each kind states its own disqualifier — armor reads
# the wearer's BODY stats, a rune reads aura+affinity (#157). Enforced at the equip doors and
# re-enforced at Unit._enforce_gear_gates, so "no" here also means "comes off when it becomes no".
# Deliberately NOT the two-handed wield lock — that is a firing question (Unit.can_wield_equipped).
func can_equip(_wielder: Unit) -> bool:
	return true

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

# Attacks this source offers as a flat menu of EQUALS — the Transmutation category (#88). A rune
# has no authored main_attack: its carvings are interchangeable, so all of them belong in one
# picker. A weapon does have an authored main, so its extras go under Weapon Action instead and
# this stays empty. Exactly the split secondary_attacks() makes, from the other side.
func choice_attacks(_wielder: Unit) -> Array[AttackData]:
	return []

# What an attack's SHOVE and ALLY-SPLASH actually are once the firing source has had its say
# (#529). Two fields a fitted mod may edit, and the pair is deliberately small: an override may
# only touch what is read AFTER the attack is chosen. Anything that changes how an attack is
# AIMED -- its pattern, its reach -- arrives as a whole replacement attack instead, because Reach
# answers those with no wielder in hand.
#
# The default is the attack's own authored value, so a rune carving and a bare fist need neither
# override and armor needs no opinion at all.
func effective_knockback(_wielder: Unit, attack: AttackData) -> int:
	return attack.knockback if attack != null else 0

func effective_hits_allies(_wielder: Unit, attack: AttackData) -> bool:
	return attack != null and attack.hits_allies

func effective_can_overwatch(_wielder: Unit, attack: AttackData) -> bool:
	return attack != null and attack.can_overwatch

# --- Explaining an attack (#166) ---
# Why a menu row is greyed, and what the row does — both asked of the SOURCE, because only it knows
# its own economy (a weapon's readiness, a rune's aura). Keeping them here is what lets the menu
# LIST everything a unit owns and disable what it can't use, instead of hiding it: a menu can only
# grey what it can explain. Inert defaults, so a kind with no economy needs no override.

# "" = fireable. Unit.is_attack_fireable is DERIVED from this, so the refusal and its explanation
# are one answer — never a boolean here and a reason string somewhere else (Law #4).
func attack_block_reason(_wielder: Unit, _attack: AttackData) -> String:
	return ""

# What this attack does for this wielder, for the hover readout. Per-kind because the payload
# number is (a carving scales off aura, a weapon attack off its weapon — #72).
func attack_detail(_wielder: Unit, _attack: AttackData) -> String:
	return ""

# --- Weapon-verb surface (#73/#84, promoted here from WeaponInstance 2026-07-27) ---
# The self-abilities the Weapon Action menu can offer. Same shape and same reasoning as the
# attack surface above: every default is the INERT answer, so Unit asks whatever is in the slot
# without knowing its kind, and a rune or an armour piece answers "no" for free.
#
# Where the line falls: what UNIT delegates lives here; what a deliberate `as WeaponInstance`
# cast reads stays down on WeaponInstance. That is not a style call — `is_attack_fireable` and
# `consume_readiness_for` take a `WeaponAttackData`, so widening them to `AttackData` for this
# base would break every family override's signature. The verbs below take no arguments, so
# they promote cleanly. Real bodies (and per-family overrides) live on WeaponInstance.

func can_reload() -> bool:
	return false

func reload() -> void:
	pass

# What the Weapon Action menu CALLS this rearm. The ORDER is always ActionType.RELOAD — only the
# word changes, so Springspear keeps "Spring Load" while the queue, the AI, and the Play API all
# see one verb (#84).
func reload_label() -> String:
	return "Reload"

func can_rev() -> bool:
	return false

func rev() -> void:
	pass

func tick_rev() -> void:
	pass

func can_burrow() -> bool:
	return false
