class_name RuneData
extends EquippableData

# A blank rune is alkahest-saturated runestone — element/pattern AGNOSTIC until an alchemist
# INSCRIBES transmutation carvings onto it. The carvings (TransmutationData) are the attacks;
# the rune is the customizable LOADOUT that holds them (docs/design/alchemy-kit.md).
#
# Size = TWO knobs (transmutation-model-proposal.md, grilled 2026-07-04): CIRCLE_CAP bounds the
# raw sigil count of any ONE inscribed carving; CAPACITY bounds the summed sigil count across
# ALL carvings. Channeling a held carving needs the wielder's AURA: floors = sigil weight, the temper
# element is never brute-forced, and trained temper aura is the leeway budget for the rest,
# priced in strain (TransmutationData.can_channel). RUNE_LEEWAY is dead (2026-07-04 grill):
# leeway is TRAINED, not stone-granted.
#
# Equippable (inherits the EquippableData slot surface). FIRING a chosen inscription through
# the resolver is the next slice; the inherited single-attack fields stay dormant until then.

enum Size { SMALL, MEDIUM, LARGE }   # APPEND-ONLY (serialized as int)

const CAPACITY := {
	Size.SMALL: 1,    # pures + single flourishes — the low-risk sandbox
	Size.MEDIUM: 3,   # a pair with a pure riding along
	Size.LARGE: 6,    # two triples, or a triple + pair + pure
}   # pseudo-locked 2026-07-04 — playtest-tunable, not a shape change

const CIRCLE_CAP := {
	Size.SMALL: 1,    # pures only — twins are impossible by construction
	Size.MEDIUM: 2,   # the Conjunction (pairs) table
	Size.LARGE: 3,    # triples
}   # max raw sigils in a SINGLE carving inscribed on this size

@export var size: Size = Size.SMALL
@export var inscriptions: Array[TransmutationData] = []
@export var temper: Elemental.Element = Elemental.Element.NONE   # set PERMANENTLY by the first carving

static func max_circle_cap() -> int:
	return CIRCLE_CAP[Size.LARGE]

func capacity() -> int:
	return CAPACITY[size]

func used_capacity() -> int:
	var total := 0
	for t in inscriptions:
		total += t.cost()
	return total

func remaining_capacity() -> int:
	return capacity() - used_capacity()

func can_inscribe(t: TransmutationData) -> bool:
	if t == null or t.sigils.is_empty():
		return false
	if t.sigils.size() > CIRCLE_CAP[size]:
		return false
	if t.cost() > remaining_capacity():
		return false
	if temper != Elemental.Element.NONE and not _fits_temper(t):
		return false
	return true

# The temper rule: every later carving must CONTAIN the temper element and can never be
# primarily another element — off-temper weight <= temper weight; ties are legal.
func _fits_temper(t: TransmutationData) -> bool:
	var temper_weight := t.sigils.count(temper)
	if temper_weight == 0:
		return false
	for e in t.distinct_elements():
		if t.sigils.count(e) > temper_weight:
			return false
	return true

func inscribe(t: TransmutationData) -> bool:
	if not can_inscribe(t):
		return false
	if temper == Elemental.Element.NONE:
		temper = t.primary_element()   # the first carving IS the temper choice — permanent
	inscriptions.append(t)
	return true

# Load-time guard (both knobs + the temper rule), independent of can_inscribe's add-time
# gate — a rune resized down after inscribing, or hand-edited on disk, could otherwise
# carry a saved violation.
func is_legal() -> bool:
	if used_capacity() > capacity():
		return false
	for t in inscriptions:
		if t.sigils.size() > CIRCLE_CAP[size]:
			return false
	if not inscriptions.is_empty():
		if temper == Elemental.Element.NONE:
			return false
		for t in inscriptions:
			if not _fits_temper(t):
				return false
	return true

# The held carvings this wielder can actually channel (temper floors + trained leeway).
func channelable(wielder: Unit) -> Array[TransmutationData]:
	var result: Array[TransmutationData] = []
	for t in inscriptions:
		if t.can_channel(wielder, temper):
			result.append(t)
	return result
