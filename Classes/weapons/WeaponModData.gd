extends Resource
class_name WeaponModData

# A physical component fitted into one of a weapon's spaces (docs/design/weapons.md
# "Ratified model"). Effects are TYPED FIELDS, not scripts — keep this vocabulary small and
# additive. Exotic effects (alt-fire modes, blocking, overwatch) are LATER content; see
# weapon-mod-ideas.md for the authored bank this pulls fixtures from.
#
# The three GRANT fields below (#74) are the second job the ratified model always gave mods:
# changing what a weapon can do, not just how hard it hits. They are additive only — a mod
# ADDS an attack to the repertoire, never replaces or rewrites one. That half stays with #74.

@export var id: String = ""
@export var display_name: String = ""
@export var size: int = 1   # 1-3, capacity cost within whichever space it's fitted to
@export var power_delta: int = 0
@export var scaling_nudge: Dictionary[Stats.Stat, int] = {}   # percentage-point shifts within the wielded weapon's blend, +/-
@export var added_element: Elemental.Element = Elemental.Element.NONE
@export var weight: int = 0

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
		"size": "Capacity this mod costs in whichever space it is fitted to. Spaces hold 1 / 2 / 3, so a size-3 keystone only ever fits the big space.",
		"power_delta": "Flat shift to the damage of every attack this weapon fires, before scaling. Negative is a real option -- a heavy mod that trades power for reach.",
		"scaling_nudge": "Percentage-POINT shifts inside the weapon family's stat blend, not a replacement for it. +30 DEX on a 100 STR blend makes it 100/30, so the weapon still reads mostly STR.",
		"added_element": "An element this mod adds to every hit, ON TOP of whatever the attack already carries. NONE = adds nothing.",
		"weight": "Mass this mod adds to the weapon. Counts whether or not the space is proficiency-active -- mass is physical, not a capability.",
		"granted_attacks": "Attacks this mod ADDS to the weapon's repertoire, alongside the family's stock list. Additive only: nothing here replaces or edits an existing attack. Pick from attacks authored in the Attack Editor.",
		"granted_abilities": "Abilities the WIELDER has while this weapon contributes -- the equipped weapon, or an installed prosthetic. Granted live: unequip the weapon and the ability leaves with it.",
		"stat_modifiers": "Stat changes to the WIELDER while this weapon contributes, not to the weapon. Negative is the classic tax. These never open a wear gate -- gates read the body, never gear.",
	}
