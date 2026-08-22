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
# How this attack answers the height question at aim time (#258; judged by Reach.vertical_aim_ok,
# directional spreads exempt in v1 — their per-cell height question is the deferred footprint one):
#   RANGED — the target may sit up to up_tolerance above / down_tolerance below the attacker
#            (-1 = unlimited). A lob's climb ceiling is its up_tolerance; a gun stays -1.
#   MELEE  — dev ruling 2026-08-20: same step, or a facing half step — same elevation, or adjacent
#            across a ramp-legal edge (RulesService.height_step_ok). A sheer 1-level edge is
#            melee-illegal in BOTH directions; the tolerances are ignored.
# A null attack (bare fists) reads as MELEE — punching is melee.
# Named for what they MEAN, not the mechanism each uses (#473, was TOLERANCE/STEP): the dev read
# "tolerance" as the lob setting, which is arc_clearance below. Members keep their order, so every
# authored `vertical_rule = 1` still means melee — this was a source rename, never a content one.
enum VerticalRule { RANGED, MELEE }
@export var vertical_rule: VerticalRule = VerticalRule.RANGED
@export var up_tolerance: int = -1
@export var down_tolerance: int = -1
# How high the shot arcs above its own sightline mid-flight (#218's number, built 2026-08-20).
# 0 = a flat shot; there is deliberately no unlimited sentinel ("nothing clears infinity" — dev).
# The sightline runs at eye height and the arc is the ONE trajectory both the legality check and
# the in-game bead trace read (Reach.sight_trace) — the drawn path IS the rule.
@export var arc_clearance: int = 0
@export var heals := false   # EITHER damage OR heal, never both; reinterprets base damage as HP restored
# A pure-utility attack (#126): SCALING is suppressed, so neither aura nor a weapon's stat blend can
# sneak damage into a damageless effect. Only the attack's own contribution — an elemental reaction's
# damage_bonus still lands, deliberately (dev, 2026-08-08). Mutually exclusive with `heals`.
@export var deals_no_damage := false
# Ignores a Guard (#414): the hit lands on whoever it was aimed at, bodyguard or no. The first entry
# in Guard's authored counterplay set — the others are positional (shove the blocker out of range,
# shove the ward, AoE the cluster) and need no flag. On the shared base beside the two above, so a
# weapon attack and a carving author it identically.
@export var pierces_guard := false
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


# What each field MEANS, for the dev tools' reflective editor (#473). Every field above carries a
# comment already, but a comment reaches nobody editing in the running game -- the Attack Editor
# draws these rows from get_property_list() and had no text on any of them, which is how a range
# edit landed in the wrong box of two adjacent lookalike spinboxes with nothing to say so.
#
# A FUNCTION rather than a const table, and not by preference: GDScript refuses to let a subclass
# declare a member its parent already has, so a `const PROPERTY_TIPS` here makes one on
# WeaponAttackData a parse error. A subclass overrides this and merges instead. It lives beside the
# @export it describes rather than in a table inside DevWidgets, so the tip and the field cannot
# drift apart in different files.
static func property_tips() -> Dictionary:
	return {
		"power": "Base damage before scaling. A weapon attack scales this off its weapon's stat blend and fitted mods; a carving scales it off the wielder's aura.",
		"attack_pattern": "The geometry -- which cells this attack may be aimed at. Pick the class here; that class's own fields appear indented underneath.",
		"can_counter": "May this attack be used when countering? A weapon always counters with its MAIN attack whatever is picked, so this only matters on a main.",
		"hits_allies": "Splash reaches your own side too, not just enemies.",
		"hits_self": "The attacker is a legal victim of its own attack.",
		"targets": "What an aim may land on -- a unit, a tile, or either.",
		"knockback": "Tiles the target is shoved directly away from the attacker, stopping at the first wall, unit or board edge. 0 = no shove.",
		"vertical_rule": "MELEE: same elevation at any range, or ONE adjacent ramp-connected half step. A sheer edge refuses in both directions and the two tolerances below are ignored entirely.\nRANGED: the tolerances below decide.\nThis also decides whether the in-game sight-line beads are DRAWN -- only a RANGED attack with a point (non-directional) pattern draws them.",
		"up_tolerance": "RANGED only: how many levels ABOVE the attacker a target may stand. -1 = unlimited, which is what a gun wants. A lob's climb ceiling.",
		"down_tolerance": "RANGED only: how many levels BELOW the attacker a target may stand. -1 = unlimited.",
		"arc_clearance": "How high the shot arcs above its own sight line mid-flight -- this is the LOB setting, not the tolerances above. 0 = a flat, straight shot. Higher clears taller walls to the far side. There is deliberately no unlimited value.",
		"heals": "Reinterprets the damage number as HP restored instead. An attack is either damage or a heal, never both.",
		"deals_no_damage": "Pure utility: scaling is suppressed, so neither aura nor a weapon's stat blend can sneak damage into a damageless effect. Mutually exclusive with Heals.",
		"pierces_guard": "Ignores a Guard -- the hit lands on whoever it was aimed at, bodyguard or no.",
	}
