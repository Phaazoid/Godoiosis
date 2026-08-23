extends Object
class_name FallRules

# The one answer to what a vertical drop costs (#259; canon docs/design/verticality.md -> Falls).
# Pure and static, LethalityRules' shape. Falls BYPASS DEF (dev, 2026-08-20: armor does not stop
# gravity) -- the resolver adds this after mitigation and before the Iron Will clamp, so the cap
# stays absolute. Slopes never deal fall damage; only the resolver's landing stage calls this.
#
# static var, not const: placeholder tuning the dev pokes freely. Tests pin the SCALING property
# (N levels cost N x one level), never the numbers. Canon's one stated property: a 20-level drop
# must be lethal (2/level = 40 vs stock 20 HP + overkill ceiling 10 -- holds).
static var FALL_DAMAGE_PER_LEVEL := 2

# The #120 interlock's fall-damage half (dev, #116 comment 2026-08-13: "perhaps heavier units take
# more damage"): +1 damage per level per this much carried weight. INERT TODAY -- every weight in
# the repo is 0 (declared debt, CLAUDE.md) -- so this is the wire, live the day gear gains mass.
# #120's other half (weight-banded knockback DISTANCE) stays on #120.
static var WEIGHT_PER_BONUS_DAMAGE := 10


# Takes the drop in HEIGHT UNITS and charges per FULL level (#427): a half-level drop costs nothing
# ("no fall damage for a half level fall" -- dev, 2026-08-23), so the conversion is the ruling.
static func damage_for(units: int, unit: Unit) -> int:
	if units <= 0:
		return 0
	@warning_ignore("integer_division")
	var levels := units / Terrain.UNITS_PER_LEVEL
	if levels <= 0:
		return 0
	var weight := 0 if unit == null else unit.get_weight()
	@warning_ignore("integer_division")
	return levels * (FALL_DAMAGE_PER_LEVEL + weight / WEIGHT_PER_BONUS_DAMAGE)
