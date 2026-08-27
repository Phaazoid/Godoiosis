extends Resource
class_name WeaponModData

# A physical component fitted into one of a weapon's spaces (docs/design/weapons.md
# "Ratified model"). Effects are TYPED FIELDS, not scripts — keep this vocabulary small and
# additive. Exotic effects (alt-fire modes, blocking, overwatch) are LATER content; see
# weapon-mod-ideas.md for the authored bank this pulls fixtures from.
#
# The GRANT fields below (#74) are the second job the ratified model always gave mods: changing
# what a weapon can do, not just how hard it hits. Since #529/#530 a mod may also REPLACE the
# weapon's main attack outright and EDIT what the attacks applies_to names do -- so "additive
# only", which this header claimed until then, is no longer the whole model.


@export var id: String = ""
@export var display_name: String = ""
@export var size: int = 1   # 1-3, capacity cost within whichever space it's fitted to

enum AppliesTo { EVERY_ATTACK, MAIN_ATTACK }
@export var applies_to: AppliesTo = AppliesTo.EVERY_ATTACK
# Which of this weapon's attacks the mod's effects reach (#530). ONE answer for every effect it
# carries — power, element, scaling shift, and the overrides — rather than a target per field:
# "what does this mod reach" is one question (design law #4), and a mod meant to sharpen one swing
# has no reason to sharpen it in only some of those ways.
#
# EVERY_ATTACK is the storage's own zero AND what every mod did before this field existed, so no
# authored .tres changes meaning by gaining it. WeaponInstance._mods_for is the only reader.
@export var power_delta: int = 0
@export var added_element: Elemental.Element = Elemental.Element.NONE
@export var weight: int = 0

enum Override { UNCHANGED, ON, OFF }

@export var knockback_delta: int = 0
# Tiles this mod adds to the shove of whatever attacks applies_to names (#529) -- Recoil Lugs and
# Pneumatic Ram, from the bank. A DELTA, stacking like power_delta, so two mods cannot disagree
# and 0 means "changes nothing" without needing a sentinel. WeaponInstance.effective_knockback
# clamps the composed total at 0: a negative shove is not a pull, it is no shove.

@export var hits_allies_override: Override = Override.UNCHANGED
# Whether the attacks applies_to names splash allies, overriding what each one authored (#529).
# The Safety Governor's field: a mod that makes a volley safe to stand beside.
#
# OFF beats ON whatever space each mod sits in -- order-INDEPENDENT deliberately, because
# rearranging fitted mods must not change what an attack does (design law #1), and a safety device
# a later mod could silently cancel is worse than no safety device at all.

@export var can_overwatch_override: Override = Override.UNCHANGED
# Whether the attacks applies_to names may be declared as a standing watch, overriding what each one
# authored (#413) -- Watchman's Sear's original job. Same OFF-beats-ON composition as
# hits_allies_override above and for the same reason: fitting order must never change what a weapon
# can do. The base carbines author the capability themselves; this is the grant for everything else.

@export var scaling_change: Dictionary[Stats.Stat, int] = {}
# Percentage-POINT shifts against the blend of the family main attack this was authored against,
# +/-, stacked additively across every fitted mod. Was `scaling_nudge` until #74 — the storage is
# unchanged, but the editor now authors ABSOLUTE percentages and stores the difference, so "nudge"
# stopped describing what the dev types.
#
# A DELTA rather than an absolute is load-bearing since #485 put the blend on the ATTACK: an
# absolute would force every attack the weapon fires onto identical numbers, flattening exactly the
# per-attack variety that ticket exists to create. A shift moves them all and leaves the
# differences intact.

@export var family: WeaponData.WeaponType = WeaponData.WeaponType.NONE
# Which family this mod fits; NONE fits anything. REQUIRED once scaling_change is non-empty — a
# stored delta is measured against ONE family's main attack blend and means nothing anywhere else.
# The restriction is DERIVED (requires_family below), never a second field to set wrong, per the
# dev's ruling: "only mods with stat bumps are forced to be weapon specific". Set voluntarily it is
# still a lock, which is what the mod bank's own [CS]/[CB] tags have always meant.
#

# May this mod go on that family? NONE fits anything; anything else is a lock — including on a mod
# that changes no scaling, because setting the field is already a statement, and it is what the
# bank's own [CS]/[CB] tags have always meant. WeaponInstance.fit_block_reason is the one reader.
func fits_family(weapon_type: WeaponData.WeaponType) -> bool:
	return family == WeaponData.WeaponType.NONE or family == weapon_type


# The derived restriction (#74, dev ruling: "only mods with stat bumps are forced to be weapon
# specific"). A stored shift is measured against ONE family's main attack, so it means nothing
# anywhere else — no second field to author, and nothing to keep in sync.
func requires_family() -> bool:
	return not scaling_change.is_empty()


# "" = savable. The REASON lives here rather than in the panel that refuses, so a second surface
# cannot invent different words for the same rule — WeaponInstance.fit_block_reason's shape, and
# #166's before it. The Item Editor's save gate is its one reader today.
func save_block_reason() -> String:
	if requires_family() and family == WeaponData.WeaponType.NONE:
		return "This mod changes scaling, so it needs a family — the change is measured against that family's main attack, and means nothing without one."
	return ""

@export var replaces_main: WeaponAttackData = null
# Swaps out the weapon's MAIN attack (#529) -- "the standard attack BECOMES this", which is how
# half the mod bank is written. Composed in WeaponInstance.effective_main, proficiency-gated like
# every other effect; null = the template's own main, which is every mod today.
#
# The MAIN only -- a SLOT, not a named attack, and that is the whole of the choice. A mod CAN
# already name a specific attack by resource reference (granted_attacks does exactly that, and
# Super Scope ships one), so identity was never the obstacle; #529's own fork list said it was,
# and this comment repeated it until the dev asked.
#
# The real argument is that the two readings differ where it matters. A slot means "whatever this
# weapon's main is", which survives a prototype authoring its own main and is how every entry in
# the bank is phrased. A named attack means "swap it if you find it" -- and a MISS is SILENT, so a
# mod authored against a family main does nothing at all on a prototype that replaced it. What the
# named form buys is reaching an EXTRA (swapping Springspear's Spring); nothing wants that yet.
#
# Two mods replacing the main is refused at the FIT (fit_block_reason), where the dev can act on it.
#
# Anything that changes how an attack is AIMED belongs here rather than in an override: Reach
# reads a pattern with no wielder in hand, so a swapped pattern has to arrive as a whole attack.

# Attacks this mod ADDS to the repertoire of the weapon it is fitted to. Composed in
# WeaponInstance.available_attacks, which reads only its OWN fitted mods — see that method's
# comment for why this one field is per-weapon while the two below are per-unit.
@export var granted_attacks: Array[WeaponAttackData] = []

# Abilities this mod grants while its weapon contributes (#74, copying ArmorData's field and its
# ruling). Read LIVE by Unit.get_live_abilities, never mirrored onto UnitInstance: a stored copy
# would survive a load that dropped the gear (#89's rule).
@export var granted_abilities: Array[AbilityData] = []

# Live stat contribution while its weapon contributes — the wielder's stats, not the weapon's.
# Read live by Unit._gear_modifier and deliberately NOT applied as a stored StatEffect (#112):
# fitting stores nothing, so unfitting removes the contribution with no bookkeeping and a save
# round-trip cannot desync it. Only effects with a life of their OWN get stored.
@export var stat_modifiers: Dictionary[Stats.Stat, int] = {}

# Per-field text for the dev tools' reflective editor (#473's shape, first written for this
# resource by #74 — the Item Editor's mod mode is the first thing to draw these fields at all).
static func property_tips() -> Dictionary:
	return {
		"id": "Stable internal name, for content that has to refer to this mod by something other than its display name.",
		"display_name": "What the fitting picker and the weapon's space list call this mod.",
		"size": "Capacity this mod costs in whichever space it is fitted to. Each space has its own capacity, authored on the template -- a plain family gets 1 / 2 / 3, so a size-3 keystone only ever fits that family's big space.",
		"applies_to": "Which of the weapon's attacks this mod affects. Every Attack is the classic behaviour -- the mod is part of the weapon. Main Attack aims everything it does at the standard swing alone, so a mod can sharpen one attack without sharpening the rest.",
		"power_delta": "Flat shift to damage, before scaling, on whichever attacks Applies To names. Negative is a real option -- a heavy mod that trades power for reach.",
		"scaling_change": "How this mod re-mixes damage scaling. You author the absolute percentages you want; what is STORED is the shift from the family main attack's own blend, so the attacks Applies To names move by the same amount and keep their own character.",
		"family": "Which weapon family this mod fits. Required once it changes scaling -- the shift is measured against that family's main attack and means nothing on another. Leave it unset for a mod that fits anything.",
		"added_element": "An element this mod adds ON TOP of whatever the attack already carries, on whichever attacks Applies To names. NONE = adds nothing.",
		"knockback_delta": "Tiles this mod ADDS to the shove of the attacks it affects. Stacks with other mods; 0 changes nothing. A negative total is no shove, never a pull.",
		"hits_allies_override": "Whether the attacks this mod affects splash allies, overriding what each attack authored. Unchanged leaves them alone. Off wins over On no matter which space each mod sits in, so rearranging your mods never changes what an attack does.",
		"can_overwatch_override": "Whether the attacks this mod affects are OVERWATCH attacks -- On makes them watch-only, aimed as a standing watch and never fired directly. Unchanged leaves each attack's own setting alone; Off wins over On whichever space each mod sits in, same as ally splash above.",
		"weight": "Mass this mod adds to the weapon. Counts whether or not the space is proficiency-active -- mass is physical, not a capability.",
		"replaces_main": "Swaps out the weapon's MAIN attack -- the standard swing BECOMES this one. Counters, default aim and the weapon menu all follow it. Leave unset for a mod that does not change what the weapon swings.",
		"granted_attacks": "Attacks this mod ADDS to the weapon's repertoire, alongside the family's stock list. To CHANGE the standard attack rather than add beside it, use Replaces Main. Pick from attacks authored in the Attack Editor.",
		"granted_abilities": "Abilities the WIELDER has while this weapon contributes -- the equipped weapon, or an installed prosthetic. Granted live: unequip the weapon and the ability leaves with it.",
		"stat_modifiers": "Stat changes to the WIELDER while this weapon contributes, not to the weapon. Negative is the classic tax. These never open a wear gate -- gates read the body, never gear.",
	}
