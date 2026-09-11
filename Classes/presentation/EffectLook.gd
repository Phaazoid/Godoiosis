class_name EffectLook
extends Resource

# What ONE element's effect looks like when the attack wearing this plays it (#900) -- a named,
# SHARED look, exactly as AttackShape is a named, shared stamp (#808). An attack points at one per
# element it carries, and editing a look reaches every attack wearing it.
#
# PARTIAL BY CONSTRUCTION, and that is the decision rather than a default. `overrides` holds only
# the rows this look DISAGREES with; every absent row falls through to the Game tab's own value.
# That is what keeps the global a real default instead of a set nobody is looking at (#422's
# palette cost, declined here): a new look is empty and changes nothing, and retuning a base value
# still moves every look that never had an opinion about it.
#
# PRESENCE IS THE OVERRIDE. A .tres dictionary can say "no opinion" directly, so this shape needs
# no sentinel at all -- which keeps #660's trap (a row whose resolved value EQUALS the sentinel
# being unauthorable) out of it entirely, and is the one way it improves on ObjectKnobs' columns.
#
# THE KEY IS THE KNOB'S OWN STATIC NAME, the same one GameKnobs.CLASS_KNOBS addresses it by. A
# label would drift the first time a row is reworded; a script path the first time a file moves.
# The static name is what the value IS called. AttackLint refuses a key that names no live row.
#
# DUMB DATA, LookPreset's rule and for its reason: which rows exist for an element is GameKnobs'
# answer, and GameKnobs is a dev-only table. Nothing here reads it -- a read is this dictionary
# with the effect's own static as the fallback -- which is what lets a shipping resource point at
# this type without dragging Classes/dev/ into the game.

# Which elements have an ATTACK-SCOPED effect worth authoring per attack. Fire is deliberately not
# here: a burning tile outlives the attack that lit it and its look belongs to the ground (#890),
# so the Fire knob group is not a tenant. One line per element that earns one; the law in
# tests/dev/test_effect_looks.gd keeps this list and GameKnobs.look_groups from drifting apart.
const LOOKABLE: Array[Elemental.Element] = [Elemental.Element.SHOCK]

@export var display_name := ""
# Which element's effect this look describes. The picker lists only looks matching the slot, and
# Save As stamps it from the slot -- so the two can disagree only by hand-editing a file, which is
# what AttackLint's second finding is for.
@export var element: Elemental.Element = Elemental.Element.NONE
# knob static name -> the authored value. Absent = inherit.
@export var overrides: Dictionary = {}


static func is_lookable(element: Elemental.Element) -> bool:
	return LOOKABLE.has(element)


# The four readers, typed rather than one Variant accessor: warnings-as-errors refuses an untyped
# read into a typed local, and an effect's every value is one of these four kinds.
#
# NULL-TOLERANT ON PURPOSE. The effects hold a look that is never null (an empty one means "inherit
# everything"), but a static helper handed one from a test or a half-built strike must degrade to
# the default rather than crash mid-frame.
func num(key: String, fallback: float) -> float:
	return float(overrides[key]) if overrides.has(key) else fallback


func whole(key: String, fallback: int) -> int:
	return int(overrides[key]) if overrides.has(key) else fallback


func flag(key: String, fallback: bool) -> bool:
	return bool(overrides[key]) if overrides.has(key) else fallback


func tint(key: String, fallback: Color) -> Color:
	return Color(overrides[key]) if overrides.has(key) else fallback


# Does this look say anything at all? An empty one is the shape a freshly made look wears, and the
# shape every attack that names none is read through.
func is_silent() -> bool:
	return overrides.is_empty()
