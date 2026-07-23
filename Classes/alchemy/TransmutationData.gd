class_name TransmutationData
extends AttackData

# An inscribed alchemy circle carved onto a rune — the thing that actually fires.
# Anatomy (docs/design/transmutation-model-proposal.md, provisional pending co-dev):
#   sigils     — the elemental core; REPEATS = WEIGHT ("2 Fire, 1 Earth" = [FIRE,FIRE,EARTH]).
#                Sigils cost rune capacity, scale power off aura, grant flourish slots,
#                and set identity. Base elements only (Elemental.SIGIL_ELEMENTS).
# flourishes — shaping marks; no capacity cost, limited by slots. Reshape, never add.
# Aura-scaled: a flat parallel to weapon stat-scaling, (identity/geometry/flags live on AttackData since #72) 
# summed over sigils (weighted). # NOT equippable itself — it lives in a RuneData's `inscriptions`.

@export var sigils: Array[Elemental.Element] = []   # repeats = weight
@export var flourishes: Array[Flourish.Type] = []
@export var popup: String = ""
@export var icon: Texture2D
# materia: DEFERRED — some carvings will require fuel; not modeled yet.
# flourish magnitudes (Spread/Focus reshaping): DEFERRED until numbers firm up.

func tier() -> int:
	return distinct_elements().size()

# First-seen order — ties in primary_element resolve to the first inscribed.
func distinct_elements() -> Array[Elemental.Element]:
	var result: Array[Elemental.Element] = []
	for e in sigils:
		if not result.has(e):
			result.append(e)
	return result

# Capacity a rune spends to hold this carving — always the raw sigil count (dev ruling, #60:
# cost is derived from the recipe, never author-set; a carving costs more because it takes
# more/heavier sigils, not because of a manual override).
func cost() -> int:
	return sigils.size()

# Aura scaling: power + the wielder's aura summed over sigils — repeats weight it, so
# 2 Fire scales twice off fire aura. A leeway-covered (0-aura) element adds nothing.
func base_damage(wielder: Unit) -> int:
	var scaling := 0
	for e in sigils:
		scaling += wielder.get_element_aura(e)
	return power + scaling

# --- Channeling: temper + trained leeway (transmutation-model-proposal.md, grilled 2026-07-04) ---
# Floors = WEIGHT: channeling needs real aura >= each element's sigil weight. The rune's
# temper element is EARNED, never brute-forced. Real aura in the temper element is the leeway
# budget for every OTHER element's deficit — breadth and depth alike, point for point — and
# every forced point costs strain: recoil HP, a COST not damage (will-and-death.md).

const STRAIN_BY_FORCED: Array[int] = [0, 1, 3, 6]   # playtest-tunable; superlinear. Index = forced
													 # points; a legal carving can't force more than 3.

# Brute-forced points: summed aura deficit across NON-temper elements. A temper deficit is
# not forceable — that's can_channel's hard floor, never a strain purchase.
func forced_points(wielder: Unit, temper: Elemental.Element) -> int:
	var forced := 0
	for e in distinct_elements():
		if e == temper:
			continue
		forced += maxi(0, sigils.count(e) - wielder.get_element_aura(e))
	return forced

func can_channel(wielder: Unit, temper: Elemental.Element) -> bool:
	if not wielder.has_any_affinity():
		return false   # the Rebecca rule: runes are inert rock in her hands
	if wielder.get_element_aura(temper) < sigils.count(temper):
		return false   # temper depth is trained, full stop
	return forced_points(wielder, temper) <= wielder.get_element_aura(temper)

# Recoil HP to channel this carving — 0 when real aura covers everything. Affordability
# (can the caster pay without hitting 0?) is the menu/resolver's job (A7), not here.
# Materia seam: carried materia will absorb strain when the materia pass lands.
func strain_cost(wielder:Unit, temper: Elemental.Element) -> int:
	return STRAIN_BY_FORCED[mini(forced_points(wielder, temper), STRAIN_BY_FORCED.size() - 1)]

# Sigil count sets how many flourishes fit: 1 -> 1, 2 -> 3, 3 -> 5.
func flourish_slots() -> int:
	return maxi(0, 2 * sigils.size() - 1)

# Authoring gate: a free slot, and no opposite already carved (opposites cancel — we
# reject rather than net to zero). Stacking the SAME flourish is allowed for now.
func can_add_flourish(f: Flourish.Type) -> bool:
	if f == Flourish.Type.NONE:
		return false
	if flourishes.size() >= flourish_slots():
		return false
	return not flourishes.has(Flourish.OPPOSITES.get(f, Flourish.Type.NONE))

func has_legal_sigils() -> bool:
	for e in sigils:
		if not Elemental.is_sigil_element(e):
			return false
	return true

# Load-time guard: legal elements AND small enough to ever fit on any rune (the largest
# circle cap, L, is the global ceiling — RuneData owns the actual per-size knobs).
func is_legal() -> bool:
	return has_legal_sigils() and sigils.size() <= RuneData.max_circle_cap()

# The highest-weight sigil sets the headline identity ("2 Fire / 1 Earth" burns first).
func primary_element() -> Elemental.Element:
	var best := Elemental.Element.NONE
	var best_count := 0
	for e in distinct_elements():
		var count := sigils.count(e)
		if count > best_count:
			best = e
			best_count = count
	return best

# Outgoing hit tags for the combinatrix: each distinct sigil, transformed by the first
# flourish that derives an exotic from it (Water+Stillness -> ICE). Aura scaling stays on
# the raw sigils — only the tag derives.
func get_elements() -> Array[Elemental.Element]:
	var result: Array[Elemental.Element] = []
	for e in distinct_elements():
		result.append(_resolved_element(e))
	return result

func _resolved_element(e: Elemental.Element) -> Elemental.Element:
	for f in flourishes:
		var derived := Flourish.derive(e, f)
		if derived != Elemental.Element.NONE:
			return derived
	return e
