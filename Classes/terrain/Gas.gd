extends Object
class_name Gas

# The atmosphere's vocabulary (#508): which gases exist, how much of one a cell may hold, and the
# packing that keeps every kind's amount for one cell in a single int (four bits a kind).
#
# A kind's int is what a save holds, so Kind is APPEND-ONLY: rename a member freely, never reorder
# or delete one. Steam is the only gas with rules on the way; the rest exist for #508's look harness
# and get their own tickets.
#
# One int per cell rather than a dictionary of kinds: it is a VALUE, so a read never hands out the
# store's own object (BoardHeights' #447 reason), two snapshots compare with ==, and the nibble IS
# the cap. tests/terrain/test_gas_field.gd pins both limits the packing leans on.

enum Kind { STEAM, SMOKE, POISON, FROST, THUNDER, SULFUR }

const MAX_AMOUNT := 14
const BITS := 4
const NIBBLE := 0xF


static func amount_in(packed: int, kind: Kind) -> int:
	return (packed >> (int(kind) * BITS)) & NIBBLE


static func with_amount(packed: int, kind: Kind, amount: int) -> int:
	var shift := int(kind) * BITS
	return (packed & ~(NIBBLE << shift)) | (clampi(amount, 0, MAX_AMOUNT) << shift)


# Which kinds a cell holds, in enum order.
static func kinds_in(packed: int) -> Array[Kind]:
	var out: Array[Kind] = []
	for kind: Kind in Kind.values():
		if amount_in(packed, kind) > 0:
			out.append(kind)
	return out


# One bit per kind present: what the renderer's board texture carries in a byte.
static func kind_mask(packed: int) -> int:
	var mask := 0
	for kind: Kind in Kind.values():
		if amount_in(packed, kind) > 0:
			mask |= 1 << int(kind)
	return mask


static func name_of(kind: Kind) -> String:
	return Kind.keys()[kind]


# What the PLAYER calls this gas ("Steam") -- Elemental.display_name's rule. name_of stays the raw key,
# which is what the look files are named by.
static func display_name(kind: Kind) -> String:
	return name_of(kind).capitalize()
