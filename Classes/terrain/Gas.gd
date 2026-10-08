extends Object
class_name Gas

# The atmosphere's vocabulary (#508): which gases exist, how thick one may lie on a cell, and the
# packing that keeps every kind's state for one cell in a single int (four bits a kind).
#
# A kind's int is what a save holds, so Kind is APPEND-ONLY: rename a member freely, never reorder
# or delete one. Steam is the only gas with rules (GasRules); the rest are looks only.
#
# THREE LEVELS, NOT AN AMOUNT (dev, 2026-10-03): thin, medium, thick -- more steps than that read
# alike on the board. A kind's nibble is its LEVEL (bits 0-1) and how many rounds it has held that
# level (bits 2-3), which the spread rule reads (GasSpread).
#
# One int per cell rather than a dictionary of kinds: it is a VALUE, so a read never hands out the
# store's own object (BoardHeights' #447 reason), two snapshots compare with ==, and the nibble IS
# the cap. tests/terrain/test_gas_field.gd pins the limits the packing leans on.

enum Kind { STEAM, SMOKE, POISON, FROST, THUNDER, SULFUR }
enum Level { NONE, THIN, MEDIUM, THICK }

const MAX_LEVEL := 3
const MAX_AGE := 3
const BITS := 4
const NIBBLE := 0xF
const LEVEL_MASK := 0x3
const AGE_SHIFT := 2


static func level_in(packed: int, kind: Kind) -> int:
	return (packed >> (int(kind) * BITS)) & LEVEL_MASK


# Rounds this kind has held its level on the cell; 0 when it has none.
static func age_in(packed: int, kind: Kind) -> int:
	return ((packed >> (int(kind) * BITS)) & NIBBLE) >> AGE_SHIFT


# Level clamped to 0..MAX_LEVEL, age to 0..MAX_AGE; no level means no age.
static func with_level(packed: int, kind: Kind, level: int, age := 0) -> int:
	var shift := int(kind) * BITS
	var lvl := clampi(level, 0, MAX_LEVEL)
	var nibble := 0 if lvl == 0 else lvl | (clampi(age, 0, MAX_AGE) << AGE_SHIFT)
	return (packed & ~(NIBBLE << shift)) | (nibble << shift)


# Which kinds a cell holds, in enum order.
static func kinds_in(packed: int) -> Array[Kind]:
	var out: Array[Kind] = []
	for kind: Kind in Kind.values():
		if level_in(packed, kind) > 0:
			out.append(kind)
	return out


# One bit per kind present: what the renderer's board texture carries in a byte.
static func kind_mask(packed: int) -> int:
	var mask := 0
	for kind: Kind in Kind.values():
		if level_in(packed, kind) > 0:
			mask |= 1 << int(kind)
	return mask


static func name_of(kind: Kind) -> String:
	return Kind.keys()[kind]


# What the PLAYER calls this gas ("Steam") -- Elemental.display_name's rule. name_of stays the raw key,
# which is what the look files are named by.
static func display_name(kind: Kind) -> String:
	return name_of(kind).capitalize()
