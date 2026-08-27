class_name RuneData
extends EquippableData

# A blank rune is alkahest-saturated runestone — element/pattern AGNOSTIC until an alchemist
# INSCRIBES transmutation carvings onto it. The carvings (TransmutationData) are the attacks;
# the rune is the customizable LOADOUT that holds them (docs/design/alchemy-kit.md).
#
# Size = TWO knobs (transmutation-model-proposal.md, grilled 2026-07-04): CIRCLE_CAP bounds the
# raw sigil count of any ONE inscribed carving; CAPACITY bounds the summed sigil count across
# ALL carvings. Channeling a held carving = anchor + wildcards (dev, 2026-08-10 — see
# TransmutationData.channel_block_reason): real aura in one of the CARVING's elements, and the
# total deficit covered by the rune's universal +1 wildcard OR the wielder's spare temper aura,
# never both. The temper's only channel-side role is keying that second pool — its GATE role is
# inscription-time only (_fits_temper), which was the original intent the 2026-07-04 model drifted
# from. (That model's trained-leeway/strain rules are repealed; record in
# transmutation-model-proposal.md -> Temper & channeling.)
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
# --- Attack-source surface (EquippableData) ---
# A rune fires whichever inscribed carving it can currently channel; an aura-dry rune offers
# nothing, which is the honest bare-fist fallback.

# FILTERED on purpose, and deliberately no longer the same list as choice_attacks (#166): this is
# "what could actually fire", the list the AI probes and has_any_fireable_attack scans. The
# catalogue the menu draws is choice_attacks. Don't collapse them back together.
#
# Both of them drop watch-only carvings (#590) -- a carving authored can_overwatch is declared as
# a standing watch and never channelled, so it belongs to watch_attacks and to nothing here.
func selectable_attacks(wielder: Unit) -> Array[AttackData]:
	return fireable_only(wielder, repertoire_of(channelable(wielder)))

# Every carving this rune holds, fireable or watch-only -- the list watch_attacks comes off (#590).
# Deliberately the UNFILTERED set, matching choice_attacks: an unaffordable watch carving lists and
# greys with its reason like any other row.
func repertoire(_wielder: Unit) -> Array[AttackData]:
	return repertoire_of(inscriptions)

# Array[TransmutationData] -> Array[AttackData]. GDScript will not pass the first where the second
# is declared, and the three surfaces above all need the widening.
func repertoire_of(carvings: Array[TransmutationData]) -> Array[AttackData]:
	var result: Array[AttackData] = []
	for t in carvings:
		result.append(t)
	return result

func default_attack(wielder: Unit) -> AttackData:
	var fireable := selectable_attacks(wielder)
	if fireable.is_empty():
		return null
	return fireable[0]

# EVERY carving inscribed on this rune — the catalogue, not the affordable subset (#166,
# reversing #88's aura-filtered version). An unchannelable carving is LISTED and greyed with a
# reason, the same law _attack_entry has always applied to a weapon's unfireable secondary, which
# is why WeaponInstance.secondary_attacks likewise returns all of them. Whether a carving can be
# paid for is asked per entry, by attack_block_reason.
func choice_attacks(wielder: Unit) -> Array[AttackData]:
	return fireable_only(wielder, repertoire(wielder))

# A rune counters with whatever it is CURRENTLY firing — the live pick included (#30 quirk).
# A weapon deliberately does NOT; see WeaponInstance.counter_attack.
func counter_attack(wielder: Unit) -> AttackData:
	return wielder.get_fired_attack()

func channelable(wielder: Unit) -> Array[TransmutationData]:
	var result: Array[TransmutationData] = []
	for t in inscriptions:
		if t.can_channel(wielder, temper):
			result.append(t)
	return result

# --- Explaining a carving (#166, EquippableData surface) ---
# Both delegate to the carving with this rune's TEMPER, which the carving cannot know on its own —
# channeling is a property of the pairing, not of either half.

func attack_block_reason(wielder: Unit, attack: AttackData) -> String:
	var carving := attack as TransmutationData
	return carving.channel_block_reason(wielder, temper) if carving != null else ""

func attack_detail(wielder: Unit, attack: AttackData) -> String:
	var carving := attack as TransmutationData
	return carving.mechanical_text(wielder, temper) if carving != null else ""

# The equip gate (#157): at least ONE channelable carving, never "all" — a one-of-three rune is
# good gear. No affinity exemption (dev call 2026-08-10): a dead rune is carryable, not wieldable,
# and a blank rune fails for everyone. Scenario load bypasses this — a save is authoritative.
func can_equip(wielder: Unit) -> bool:
	return not channelable(wielder).is_empty()
