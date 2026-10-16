class_name TransmutationData
extends AttackData

# An inscribed alchemy circle carved onto a rune -- the thing that actually fires. Since Deep Alchemy
# Phase 2 (docs/design/deep-alchemy.md -> What is built) it is a RECIPE in codev's notation: verbs
# with substances as their arguments, `Break(F, A) + Push(F2)`. CarvingRecipe parses it; everything
# below reads that parse:
#   cost      -- verbs, what a rune spends to hold it
#   demand    -- atoms across every argument, what the wielder's aura must cover
#   delivered -- what the last delivering verb leaves at the target: the hit's element, and the
#                elements its damage scales off (once each)
# Shape, range, shove, power and states stay AUTHORED on AttackData; verbs never move geometry.
# NOT equippable itself -- it lives in a RuneData's `inscriptions`.

@export var recipe: String = "":
	set(value):
		recipe = value
		_parsed = null
@export var popup: String = ""
@export var icon: Texture2D
# materia: casting needs no fuel (ratified 2026-08-29). A verb whose argument is not present
#   fizzles -- CellSubstances.fizzle_reason, asked with the cell the cast is made from.

var _parsed: CarvingRecipe


# The parse, cached until the recipe text changes -- the channel ladder runs inside queue-time
# gating and the AI's candidate probe, so it must not re-parse per call.
func parsed() -> CarvingRecipe:
	if _parsed == null:
		_parsed = CarvingRecipe.parse(recipe)
	return _parsed


# Why the recipe cannot be carved, or "" -- the parse's own words.
func recipe_error() -> String:
	return parsed().error


# What this carving asks of each element (atoms across every argument).
func demand() -> Dictionary[Elemental.Element, int]:
	return parsed().demand()


func demand_of(element: Elemental.Element) -> int:
	return parsed().demand().get(element, 0)

func tier() -> int:
	return distinct_elements().size()

# The elements the recipe asks for, first-seen order -- ties in primary_element go to the first named.
func distinct_elements() -> Array[Elemental.Element]:
	var result: Array[Elemental.Element] = []
	result.assign(parsed().demand().keys())
	return result

# Capacity a rune spends to hold this carving: its verbs (Phase 2, 2026-10-11 -- each verb brings its
# own argument slots, so counting the arguments too would count one carving twice). Derived from the
# recipe, never author-set (#60).
func cost() -> int:
	return parsed().verb_count()


# The elements a hit's damage scales off: those in what it delivers, ONCE each, so a one-element hit
# scales exactly as a one-sigil carving did. First-seen order.
func damage_elements() -> Array[Elemental.Element]:
	return parsed().damage_elements()

# Aura scaling: power + the wielder's aura in each element of what this carving delivers, once each
# (Fireball's flame scales off fire once). A wildcard-covered (0-aura) element adds nothing.
# A utility carving (#126) skips the scaling entirely: aura still GATES channeling, it just
# never adds damage to a damageless effect.
#
# `empowered` (#694) is the elements the caster may draw materia from where they stand — PASSED,
# never looked up, because a carving has no board and must not grow one (Law #4). It is +1
# EFFECTIVE aura in each delivered element it matches, the same once-each the wielder's aura gets.
#
# It is SCALING ONLY. Nothing here may reach the channeling ladder below: the anchor, the deficit
# and the wildcard pools all read wielder.get_element_aura directly, and RuneData.can_equip_reason
# derives from channel_block_reason — so leaving that accessor alone is what keeps empowerment out
# of all three at once. Never make get_element_aura position-aware.
#
# `air` is the board's atmosphere bonus (#1324, Atmosphere.bonus_of), passed for empowered's reason.
# It is added after the damageless guard, so a utility carving stays at 0, and floored there.
func base_damage(wielder: Unit, empowered: Array[Elemental.Element] = [], air := 0) -> int:
	if deals_no_damage:
		return 0
	var scaling := 0
	for e: Elemental.Element in damage_elements():
		scaling += wielder.get_element_aura(e)
		if empowered.has(e):
			scaling += 1
	return maxi(0, power + scaling + air)

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
#               all, so a carving's own temper demand is measured against capacity first.
# No strain, no HP price, nothing spent — aura is a stat measured against, never a resource
# (fork 3). The old strain math (recoil HP per forced point) left the system entirely; it is
# preserved in the "strain as a job ability" issue if it ever returns as a job passive.

# Summed aura shortfall across ALL the carving's elements — what wildcards must cover.
func total_deficit(wielder: Unit) -> int:
	var deficit := 0
	for e in distinct_elements():
		deficit += maxi(0, demand_of(e) - wielder.get_element_aura(e))
	return deficit

# max(pool A, pool B): the universal +1, or spare temper aura on a matching rune — never both.
func wildcard_capacity(wielder: Unit, temper: Elemental.Element) -> int:
	var spare := wielder.get_element_aura(temper) - demand_of(temper)
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


# The channelling verdict as ONE sentence, whichever way it falls (#1019) -- what a readout prints
# beside the ring, so the picture's marks and the words under it come from one walk.
#
# THE LADDER IS ASKED FIRST AND ITS ANSWER IS RETURNED VERBATIM. The positive half is built only when
# the ladder comes back empty, which is can_channel's own derivation one line up: worded
# independently, a refusal and its explanation are two answers to one question and drift the first
# time either is edited (Law #4; #166's whole reason for the ladder existing).
func aura_text(wielder: Unit, temper: Elemental.Element) -> String:
	var refusal := channel_block_reason(wielder, temper)
	if refusal != "":
		return refusal
	# SURPLUS IS WHAT DAMAGE READS: aura past the recipe's demand in each element the hit scales off,
	# once each -- base_damage's own count. Spare aura in an element it only spends is not damage.
	var spare := 0
	for e: Elemental.Element in damage_elements():
		spare += maxi(0, wielder.get_element_aura(e) - demand_of(e))
	# A utility carving suppresses scaling outright, so its surplus buys nothing and claiming a number
	# here would promise damage the resolver never adds (deals_no_damage, #126).
	if spare == 0 or deals_no_damage:
		return "Channels on %s" % demand_text()
	return "Channels on %s, and the aura past it adds %d damage" % [demand_text(), spare]


# HOW COMFORTABLY this channels, which is the THIRD answer the ladder already computes and throws
# away (#1022, dev: *"red for pressure spray since the unit cannot cast, yellow for zap cannon since
# it can only be cast with the extra slot, none for fireball since it can be comfortably cast"*).
#
# IT LIVES HERE RATHER THAN ON THE CARD for #166's own reason, one rung further up: a surface can
# only grey what the data layer can explain, and a card re-deriving total_deficit/wildcard_capacity
# for itself would be a second answer to *how close to the line is this* -- one that goes on saying
# "comfortable" the first time either pool's rule is edited.
#
# NOBODY CARRYING IT READS AS CLEAR, matching the card's own "no verdict" state: channeling is a
# property of the PAIRING, so with one half missing there is no discomfort to report.
enum Channel { CLEAR, WILDCARD, REFUSED }


func channel_state(wielder: Unit, temper: Elemental.Element) -> Channel:
	if wielder == null:
		return Channel.CLEAR
	if channel_block_reason(wielder, temper) != "":
		return Channel.REFUSED
	# A DEFICIT WITH NO REFUSAL means the wildcards are carrying it -- the ladder passed COVERAGE, so
	# the shortfall is real and something is paying for it that the recipe did not ask for.
	return Channel.WILDCARD if total_deficit(wielder) > 0 else Channel.CLEAR

# "Fire or Earth" — the anchor refusal names what would open the carving.
func _element_list_text() -> String:
	var names: Array[String] = []
	for e in distinct_elements():
		names.append(Elemental.display_name(e))
	return " or ".join(names)

# What the recipe asks of the wielder, in words ("Fire 3, Air 1").
func demand_text() -> String:
	var parts: Array[String] = []
	for e in distinct_elements():
		parts.append("%s %d" % [Elemental.display_name(e), demand_of(e)])
	return ", ".join(parts)

# The HIT half alone: what this carving does, with neither its recipe nor its wildcard count
# (#1022). Split out because the rune card's rows draw both of those as MARKS -- the recipe as cost
# bars, the wildcards as the row's own tint -- and printing them again underneath would be the same
# fact twice on one row. Extracted rather than re-spelled, so "Damage 11, Blunt (unit)" exists once
# and the hover readout below and the row cannot word it two ways.
func effect_text(wielder: Unit) -> String:
	return "%s %s" % [hit_text(base_damage(wielder), delivered_kind()), targets_text()]

# What this carving DOES for this wielder, for the menu's hover readout (#166) — the carving's
# answer to the role ArmorData.mechanical_text plays for a worn piece. Itemized per wielder because
# both numbers depend on them: damage scales off their aura, wildcards off their gaps.
func mechanical_text(wielder: Unit, _temper: Elemental.Element) -> String:
	var parts: Array[String] = [recipe, effect_text(wielder)]
	var deficit := total_deficit(wielder)
	if deficit > 0:
		parts.append("Wildcards %d" % deficit)
	return "  ·  ".join(parts)

# Load-time guard: the recipe parses, and is small enough to ever fit on a rune (the largest
# circle cap, L, is the global ceiling -- RuneData owns the per-size knobs).
func is_legal() -> bool:
	return parsed().is_legal() and cost() <= RuneData.max_circle_cap()

# The most-demanded element sets the headline identity, and a rune's temper (Fire 3 / Air 1 is fire).
func primary_element() -> Elemental.Element:
	var best := Elemental.Element.NONE
	var best_count := 0
	for e in distinct_elements():
		var count := demand_of(e)
		if count > best_count:
			best = e
			best_count = count
	return best

# Outgoing hit tags for the combinatrix: the element each delivered substance carries (flame is
# FIRE, lightning SHOCK, ice ICE -- SubstanceMap read backwards). Replaces the old flourish table.
func get_elements() -> Array[Elemental.Element]:
	return parsed().hit_elements().duplicate()


# A carving's authored elements ARE its outgoing tags (#900) -- derived from the recipe rather than
# stored, so a carving that delivers lightning is a shock attack and the Attack Editor's look section
# appears with it. Nothing else to compose: a carving carries no mods.
func authored_elements() -> Array[Elemental.Element]:
	return get_elements()


# Where a carving's own fields sit in the Attack Editor's form (#825). The recipe gets a SECTION
# rather than a row inside Identity: it is the carving's whole grammar, its bespoke UI carries the
# derived readouts, and what it resolves to is the first thing worth seeing after the name.
static func property_sections() -> Array[Dictionary]:
	var sections := AttackData.property_sections()
	AttackData.in_section(sections, "Identity", PackedStringArray(["popup", "icon"]))
	sections.insert(1, {"title": "Recipe", "fields": PackedStringArray(["recipe"])})
	return sections


# The carving's own rows (#473). The recipe gets a bespoke row with live readouts in the Attack
# Editor, and still owes text -- the editor tips the block it draws. AttackData's shared fields merge in.
static func property_tips() -> Dictionary:
	var tips := AttackData.property_tips()
	tips.merge({
		"popup": "Floating text shown over the target when this carving lands. Blank = nothing.",
		"icon": "The carving's icon in the rune and attack menus.",
		"recipe": "The carving in codev's notation: verbs with substances as their arguments, joined by +. Break(F, A) + Push(F2) frees fire from the air and pushes the flame. Break and Bind take two arguments; Extract, Infuse, Push, Pull, Spread, Focus, Quicken and Still take one. Each verb costs one slot of rune capacity; the atoms across every argument are the aura the wielder must cover; what the last verb leaves at the target is what the hit carries and scales off.",
	})
	return tips
