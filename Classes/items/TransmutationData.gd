class_name TransmutationData
extends Resource

# An inscribed alchemy circle carved onto a rune — the thing that actually fires.
# Anatomy (docs/design/transmutation-model-proposal.md, provisional pending co-dev):
#   sigils     — the elemental core; REPEATS = WEIGHT ("2 Fire, 1 Earth" = [FIRE,FIRE,EARTH]).
#                Sigils cost rune capacity, scale power off aura, grant flourish slots,
#                and set identity. Base elements only (Elemental.SIGIL_ELEMENTS).
#   flourishes — shaping marks; no capacity cost, limited by slots. Reshape, never add.
# Aura-scaled: a flat parallel to weapon stat-scaling, summed over sigils (weighted).
# NOT equippable itself — it lives in a RuneData's `inscriptions`.

const AURA_FLOOR := 1   # min aura per distinct element needed to channel (before leeway)

@export var display_name: String = ""
@export var sigils: Array[Elemental.Element] = []   # repeats = weight
@export var flourishes: Array[Flourish.Type] = []
@export var power: int = 0
@export var attack_pattern: AttackPattern
@export var can_counter := true
@export var hits_allies := false
@export var carving_cost: int = 0   # capacity it eats on a rune; 0 = derive from sigil count
@export var popup: String = ""
@export var icon: Texture2D
@export var targets: EquippableData.TargetMode = EquippableData.TargetMode.UNIT
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

# Capacity a rune spends to hold this carving. Defaults to sigil count; authorable higher
# for a physically larger carving (a fire WALL costs more than a fireball).
func cost() -> int:
	return carving_cost if carving_cost > 0 else sigils.size()

# Aura scaling: power + the wielder's aura summed over sigils — repeats weight it, so
# 2 Fire scales twice off fire aura. A leeway-covered (0-aura) element adds nothing.
func base_damage(wielder: Unit) -> int:
	var scaling := 0
	for e in sigils:
		scaling += wielder.get_element_aura(e)
	return power + scaling

# Can this wielder channel it? Need AURA_FLOOR in each DISTINCT element; the runestone's
# `leeway` point(s) cover that many otherwise-deficient elements.
func can_channel(wielder: Unit, leeway: int = 1) -> bool:
	var uncovered := 0
	for e in distinct_elements():
		if wielder.get_element_aura(e) < AURA_FLOOR:
			uncovered += 1
	return uncovered <= leeway

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

func hits_map() -> bool:
	return targets == EquippableData.TargetMode.MAP or targets == EquippableData.TargetMode.BOTH
