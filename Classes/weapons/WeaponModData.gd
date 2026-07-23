extends Resource
class_name WeaponModData

# A physical component fitted into one of a weapon's spaces (docs/design/weapons.md
# "Ratified model"). Effects are TYPED FIELDS, not scripts — keep this vocabulary small and
# additive. Exotic effects (alt-fire modes, blocking, overwatch) are LATER content; see
# weapon-mod-ideas.md for the authored bank this pulls fixtures from.

@export var id: String = ""
@export var display_name: String = ""
@export var size: int = 1   # 1-3, capacity cost within whichever space it's fitted to
@export var power_delta: int = 0
@export var scaling_nudge: Dictionary[Stats.Stat, int] = {}   # percentage-point shifts within the wielded weapon's blend, +/-
@export var added_element: Elemental.Element = Elemental.Element.NONE
@export var weight: int = 0
