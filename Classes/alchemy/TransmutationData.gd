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
# A utility carving (#126) skips the scaling entirely: aura still GATES channeling, it just
# never adds damage to a damageless effect.
func base_damage(wielder: Unit) -> int:
	if deals_no_damage:
		return 0
	var scaling := 0
	for e in sigils:
		scaling += wielder.get_element_aura(e)
	return power + scaling

# --- Channeling: anchor + wildcards (dev, 2026-08-10 — REPLACES the 2026-07-04 temper/leeway
# model; repeal record in transmutation-model-proposal.md -> Temper & channeling) ---
# The temper no longer gates channeling AT ALL — it clamps what can be INSCRIBED (RuneData) and
# keys pool B below, nothing else. Lore: runestone is alkahest fallout, tunable to any element.
# Two rules:
#   ANCHOR    — real aura >= 1 in at least one of THIS CARVING's elements. Wildcards never
#               substitute. (Subsumes the Rebecca rule per-carving; a maim-taxed pool at 0
#               loses the anchor.)
#   COVERAGE  — total deficit <= wildcard capacity. Two pools that NEVER stack, so capacity is
#               whichever is better: every rune grants +1 (pool A); a rune tempered in an
#               element you hold grants your SPARE temper aura instead (pool B) — spare, not
#               all, so a carving's own temper sigils are measured against capacity first.
# No strain, no HP price, nothing spent — aura is a stat measured against, never a resource
# (fork 3). The old strain math (recoil HP per forced point) left the system entirely; it is
# preserved in the "strain as a job ability" issue if it ever returns as a job passive.

# Summed aura shortfall across ALL the carving's elements — what wildcards must cover.
func total_deficit(wielder: Unit) -> int:
	var deficit := 0
	for e in distinct_elements():
		deficit += maxi(0, sigils.count(e) - wielder.get_element_aura(e))
	return deficit

# max(pool A, pool B): the universal +1, or spare temper aura on a matching rune — never both.
func wildcard_capacity(wielder: Unit, temper: Elemental.Element) -> int:
	var spare := wielder.get_element_aura(temper) - sigils.count(temper)
	return maxi(1, spare)

# THE channeling ladder, and the only one (#166). It answers WHY rather than just whether, so the
# menu can grey a carving and say what it needs — the boolean below is derived from it, which is
# what stops the refusal and its explanation from ever drifting apart (Law #4; #108's lesson that a
# seam unable to say what content needs grows a second one). "" = channelable.
#
# Every refusal branch builds its string only on the way out, so the success path — the one that
# runs inside queue-time gating and the AI's candidate probe — allocates nothing.
func channel_block_reason(wielder: Unit, temper: Elemental.Element) -> String:
	var anchored := false
	for e in distinct_elements():
		if wielder.get_element_aura(e) >= 1:
			anchored = true
			break
	if not anchored:
		return "Needs aura in %s" % _element_list_text()
	var deficit := total_deficit(wielder)
	var capacity := wildcard_capacity(wielder, temper)
	if deficit > capacity:
		return "Needs %d wildcard%s (have %d)" % [deficit, "" if deficit == 1 else "s", capacity]
	return ""

func can_channel(wielder: Unit, temper: Elemental.Element) -> bool:
	return channel_block_reason(wielder, temper).is_empty()

# "Fire or Earth" — the anchor refusal names what would open the carving.
func _element_list_text() -> String:
	var names: Array[String] = []
	for e in distinct_elements():
		names.append(Elemental.display_name(e))
	return " or ".join(names)

# The recipe in words ("Fire 2, Earth 1") — repeats are weight, so the count IS the number shown.
func sigil_text() -> String:
	var parts: Array[String] = []
	for e in distinct_elements():
		parts.append("%s %d" % [Elemental.display_name(e), sigils.count(e)])
	return ", ".join(parts)

# What this carving DOES for this wielder, for the menu's hover readout (#166) — the carving's
# answer to the role ArmorData.mechanical_text plays for a worn piece. Itemized per wielder because
# both numbers depend on them: damage scales off their aura, wildcards off their gaps.
func mechanical_text(wielder: Unit, _temper: Elemental.Element) -> String:
	var parts: Array[String] = [sigil_text(), payload_text(base_damage(wielder))]
	var deficit := total_deficit(wielder)
	if deficit > 0:
		parts.append("Wildcards %d" % deficit)
	return "  ·  ".join(parts)

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
