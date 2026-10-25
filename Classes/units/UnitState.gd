extends RefCounted
class_name UnitState

# One unit's LIVE battle state and the body rules that read it (#1480): what it carries and wears,
# its temporary effects and element states, where it stands on the down-and-death ladder, and the
# effective-stat chain built on top. Unit owns one (`unit.state`) and forwards to it, so outside code
# still asks the Unit.
#
# This IS the transient side of the persistence seam (#8), moved off the node into an object that
# can be copied whole for a resolve pass -- not a third store. The persistent body is `instance`.
# It never emits: what a host does about a change (the stats_changed readout) stays on Unit.

# The Unit this state belongs to. IDENTITY only (faction, name, squad, board cell): a body question
# is answered from the fields below. Content (items/, weapons/, alchemy/) is handed the state, never
# the Unit (#1480 stage 2).
var unit: Unit

# The persistent body: everything that outlives a battle (HP, stats, limbs, aura, jobs, proficiency).
var instance: UnitInstance

var inventory: Array[Item] = []
var equipped_weapon: EquippableData = null
var worn_armor: ArmorData = null   # DEF seam (#55), real content since #89. Carried in `inventory`
								   # like a weapon but filling its OWN slot — set only via
								   # Unit.wear_armor(), the one place the wear gate lives.
# The burned vial this unit is currently attuned to (#697), or null. ONE at a time: a second Use
# replaces the first, which is why this is a slot and not a list. Set by the inventory panel's Use
# verb; cleared by AttackAction.execute when a cast actually draws on it, never at plan time —
# the readiness precedent, and the whole reason cancelling a plan costs nothing.
var attunement: VialData = null

# Battle-scoped elemental states (boolean — you have it or you don't). These live on the transient
# side, NOT UnitInstance: they reset each mission (resolution-pipeline.md persistence seam /
# elemental fork 3). The resolver threads a COPY of this set forward as a hypothetical; live
# mutation is execution-only.
var element_states: Array[Elemental.State] = []

# --- Temporary stat effects (#112) — THE seam for temporary stats ---
# Battle-scoped, so they live here on the transient side, which is why UnitInstance.stat_modifiers
# no longer exists. Never carried across a mission; the mid-battle snapshot (#87) saves them with
# their countdowns.
var stat_effects: Array[StatEffect] = []

# --- Lifecycle (docs/design/will-and-death.md) ---
# Battle-scoped: it resets each mission, like element_states, so it lives on the transient side.
# (Limb loss is the PERSISTENT half and lives on UnitInstance -- different sides of the persistence
# seam.)
var lifecycle_state: Unit.LifecycleState = Unit.LifecycleState.ACTIVE

# Went down this battle (#1174): a smaller blow takes a limb from now on, and the Crisis gambit is
# spent. Battle-scoped like the downed clock; a rescue or a heal does not clear it. Losing a limb
# while STANDING does not wound -- only a down does.
var wounded := false

# --- Crisis Mode (will-and-death.md; an equipped ability since #158). An UNWOUNDED unit holding
# the Crisis ability answers a would-be-down by standing straight back up surged — deterministic,
# previewed, no prompt (the gambit's acceptance happened at loadout). There is no safety net (a
# would-be-down is death) for the rest of the battle. The arming read and the gambit's tuning live
# with the ability roster (Abilities.CRISIS_*); the battle-scoped STATE lives here. ---
var in_crisis: bool = false              # afflicted (skull icon, die-on-down) for the battle
var crisis_surge_pending: bool = false   # apply the surge at this unit's next turn start

# Turns remaining before a downed unit dies without rescue. Starts at 3 when
# the unit goes down, ticks once per player-turn start, dies at 0. -1 = not counting.
var downed_turns_remaining: int = -1

func _init(p_unit: Unit) -> void:
	unit = p_unit

# A unit's state, or null for no unit: what a caller holding a maybe-absent unit hands content (a
# stash weapon nobody carries).
static func of(u: Unit) -> UnitState:
	return u.state if u != null else null

# A resolve pass's copy of this state (#1480): the body a pass writes to, so the live one stays
# untouched (R2). It owns everything a pass can change (the instance, the element and effect lists, the
# ladder fields, each carried weapon with its battle state) and shares what is authored (armour, vials,
# runes, templates, mods, each StatEffect). Every link to a carried weapon (the inventory, the hand, a
# fitted prosthetic) names its twin, so one object stays one object and _mod_sources' dedupe holds.
func copy() -> UnitState:
	var carried: Array[Item] = inventory.duplicate()
	carried.append(equipped_weapon)
	if instance != null:
		for slot in instance.limbs:
			carried.append(instance.limbs[slot].prosthetic_item)
	var twins: Dictionary[WeaponInstance, WeaponInstance] = {}
	for item in carried:
		var weapon := item as WeaponInstance
		# A template-less instance (a fixture's bare WeaponInstance.new()) has no family to copy into,
		# and is shared.
		if weapon == null or weapon.template == null or twins.has(weapon):
			continue
		var twin := weapon.copy_for_grant() as WeaponInstance
		if twin == null:
			continue   # an unmapped family: make() has already said so
		twin.apply_battle_state(weapon.capture_battle_state())
		twins[weapon] = twin
	var c := UnitState.new(unit)
	c.instance = instance.copy(twins) if instance != null else null
	for item in inventory:
		c.inventory.append(_twin_of(item, twins))
	c.equipped_weapon = _twin_of(equipped_weapon, twins) as EquippableData
	c.worn_armor = worn_armor
	c.attunement = attunement
	c.element_states = element_states.duplicate()
	c.stat_effects = stat_effects.duplicate()
	c.lifecycle_state = lifecycle_state
	c.wounded = wounded
	c.in_crisis = in_crisis
	c.crisis_surge_pending = crisis_surge_pending
	c.downed_turns_remaining = downed_turns_remaining
	return c

static func _twin_of(item: Item, twins: Dictionary[WeaponInstance, WeaponInstance]) -> Item:
	var weapon := item as WeaponInstance
	return twins[weapon] if weapon != null and twins.has(weapon) else item

# Take the next limb in the rotation (#1174) and settle what it strips: the ONE sever spelling, run by
# Unit.take_damage on the live body and by the resolver on its copy. The slot taken, or -1 for none.
func lose_next_limb() -> int:
	if instance == null:
		return -1
	var slot := instance.next_maim_slot()
	if slot == -1:
		return -1
	instance.sever_next_limb()
	settle()
	return slot

# Everything that has to settle after a stat moves, minus the readout signal (Unit._settle_stat_change
# emits that after calling this).
#
# ORDER IS LOAD-BEARING: gates run FIRST (they can strip armour, which moves CON, which moves max
# HP), then HP re-clamps against the settled max. It cannot loop, because gates read get_body_stat
# and so are blind to the gear this may remove.
func settle() -> void:
	_enforce_gear_gates()
	reclamp_hp()

# Re-settle HP against a max that just moved: a stat change never RAISES current HP, it only
# pulls it down if the new max is below it. Its ONLY caller is settle, so that "who re-clamps HP?"
# has exactly one answer no matter what moved the stat — gear, an expiring effect, or a maim.
#
# Cannot kill, and doesn't need a floor to say so: max HP never drops below 1, and a living unit
# is never below 1, so the clamp can't reach the <=0 that emits died(). That invariant is
# currently a content constraint rather than an enforced one — if it ever needs teeth, it belongs
# on get_max_hp (the derivation), not as a floor at every write site.
func reclamp_hp() -> void:
	set_current_hp(get_current_hp())

# Gear you no longer qualify for comes OFF (#112). It stays in inventory — you're carrying it, just
# not wearing it. Triggered by a buff lapsing, a debuff, or a maim. Two parallel clauses that can't
# cascade: armor's gate reads body stats, a rune's reads aura+affinity (#157) — neither reads gear.
func _enforce_gear_gates() -> void:
	strip_gear(gear_failing_gates())

# The same JUDGEMENT with no nulling — "what would come off, standing as this unit stands right now".
# Split out of the enforce above for #742: the job picker asks it of a HYPOTHETICAL body (see
# Unit.with_jobs) rather than growing a second reading of the same gates, which is the drift #744
# collapsed one layer down. One judgement, so the warning and the strip can never name different pieces.
func gear_failing_gates() -> Array[EquippableData]:
	var failing: Array[EquippableData] = []
	if worn_armor != null and not worn_armor.can_equip(self):
		failing.append(worn_armor)
	if equipped_weapon != null and not equipped_weapon.can_equip(self):
		failing.append(equipped_weapon)
	return failing

# What is actually ON this unit right now, in gear_failing_gates' own order. The pair those gates
# judge, and the pair a job preview diffs — see Unit.gear_lost_under_jobs.
func worn_gear() -> Array[EquippableData]:
	var worn: Array[EquippableData] = []
	if worn_armor != null:
		worn.append(worn_armor)
	if equipped_weapon != null:
		worn.append(equipped_weapon)
	return worn

# ...and the nulling with no judgement. An INSTALLED PROSTHETIC that stops being wieldable leaves the
# equip slot and stays a limb — _mod_sources reads the fitting, not the slot — so there is deliberately
# nothing here that touches instance.limbs.
func strip_gear(pieces: Array[EquippableData]) -> void:
	for piece: EquippableData in pieces:
		if piece == worn_armor:
			worn_armor = null
		elif piece == equipped_weapon:
			equipped_weapon = null

# The BODY: base → limb → jobs → temporary effects. Everything EXCEPT gear.
#
# This is what wear gates judge against (ArmorData.can_equip). Excluding gear is load-bearing in
# two directions: legality never depends on what you have on, and forced unequip can never cascade.
func get_body_stat(stat: Stats.Stat) -> int:
	return instance.get_effective_stat(stat) + _effect_modifier(stat)

func get_effective_stat(stat: Stats.Stat) -> int:
	return get_body_stat(stat) + _gear_modifier(stat)

# The stored half of the temporary stage. Additive across sources (dev, 2026-07-28) — a source
# that imposed a CAP rather than a delta is unsupported and would need its own decision.
func _effect_modifier(stat: Stats.Stat) -> int:
	var total := 0
	for effect in stat_effects:
		total += effect.get_modifier(stat)
	return total

# THE answer to "whose fitted mods contribute to this unit?" (#74) -- read by _gear_modifier and
# get_live_abilities, never re-derived, so the two can never disagree about which weapons count.
#
# The equipped weapon, plus every INSTALLED PROSTHETIC: a prosthetic is a limb, so its fitted
# components ride the body that carries them whether or not it is the thing being swung. An idle
# inventory weapon contributes nothing, the same way get_effective_def reads the worn piece rather
# than everything carried.
#
# DEDUPED, and that is load-bearing rather than defensive: add_item auto-equips the first
# weapon-shaped equippable and a ProstheticWeaponInstance qualifies, so one prosthetic arm can be
# the equipped weapon AND a limb fitting at once. Counted twice, its mods pay out twice.
func _mod_sources() -> Array[WeaponInstance]:
	return _mod_sources_holding(equipped_weapon)

# The same answer with `in_hand` held instead (#1453): the preview's substitution, so a candidate
# displaces exactly what equipping it would, and every fitted limb stays a source whatever is held.
func _mod_sources_holding(in_hand: EquippableData) -> Array[WeaponInstance]:
	var sources: Array[WeaponInstance] = []
	var held := in_hand as WeaponInstance
	if held != null:
		sources.append(held)
	for slot: UnitInstance.LimbSlot in instance.limbs:
		var fitting: UnitInstance.LimbFitting = instance.limbs[slot]
		if fitting.state != UnitInstance.LimbState.PROSTHETIC:
			continue
		var prosthetic := fitting.prosthetic_item
		if prosthetic != null and not sources.has(prosthetic):
			sources.append(prosthetic)
	return sources

# The "-> gear" tail of the effective-stat chain (stats.md). Derived live from what's worn,
# the same way get_effective_def reads worn_armor live -- no stored mirror to keep in sync.
#
# A fitted mod contributes HERE, at the gear stage, never at the limb stage a prosthetic's own
# built_in_stat feeds. Forced rather than chosen: the walk is proficiency-gated and
# active_space_count needs a wielder, while UnitInstance.limb_stat(slot) has no wielder to ask.
# The doctrine agrees -- built_in_stat is what the prosthetic IS, a mod is what is bolted to it.
func _gear_modifier(stat: Stats.Stat) -> int:
	return _gear_modifier_for(stat, worn_armor, _mod_sources())

# The walk itself, with the gear handed IN so a hypothetical set can use it (#745). Live and preview
# share this one function: a preview computed by a second walk drifts from the real number the first
# time either side gains a stage, and a number the player is shown before deciding has to be the
# number they get.
func _gear_modifier_for(stat: Stats.Stat, armor: ArmorData, weapons: Array[WeaponInstance]) -> int:
	var total := 0
	for term: Array in _gear_terms_for(stat, armor, weapons):
		total += term[1]
	return total

# The walk's terms one source at a time, [source Item, delta], skipping a source that moves nothing.
# The sum above is built FROM this, so a readout that itemizes the gear stage (#1410) and the number
# it explains are one walk and cannot disagree.
func _gear_terms_for(stat: Stats.Stat, armor: ArmorData, weapons: Array[WeaponInstance]) -> Array[Array]:
	var terms: Array[Array] = []
	if armor != null and armor.stat_modifiers.get(stat, 0) != 0:
		terms.append([armor, armor.stat_modifiers[stat]])
	for weapon in weapons:
		for mod in weapon.active_modules(self):
			if mod.stat_modifiers.get(stat, 0) != 0:
				terms.append([mod, mod.stat_modifiers[stat]])
	return terms

# The live gear's terms: the worn piece, then every mod _mod_sources says contributes.
func gear_terms(stat: Stats.Stat) -> Array[Array]:
	return _gear_terms_for(stat, worn_armor, _mod_sources())

func get_current_hp() -> int:
	return instance.get_current_hp()

func get_mov() -> int:
	return instance.get_mov(get_effective_stat(Stats.Stat.DEX), get_weight())

# The body plus everything carried (#120). BLD is read EFFECTIVE so a job or a temporary effect can
# move it; armor and the equipped weapon both live in `inventory`, so one sweep covers the gear.
# CON is never a term (retracted 2026-07-27), and gear's mass is Item.weight alone --
# tests/law/test_gear_has_one_mass.gd refuses a piece that names BLD in its stat_modifiers.
func get_weight() -> int:
	return get_effective_stat(Stats.Stat.BLD) + get_carried_weight()

# The gear half of get_weight, for a readout that shows the two apart. A rule asks get_weight.
func get_carried_weight() -> int:
	return Item.total_weight(inventory)

# --- preview-at-decision (#745) ---------------------------------------------------------------
#
# "What would these numbers BE if this unit had that." Every one of the three below is the live
# function with the gear substituted, going through the SAME walk -- see _gear_modifier_for.
#
# INCOMING says which question is being asked, and the two have different answers for weight alone:
# an item coming from the stash or another unit ADDS its mass, while one already carried and merely
# equipped moves nothing. The stat and DEF answers do not fork -- an idle inventory weapon
# contributes neither, so where the thing came from cannot change them.
#
# NOT GATED HERE. can_equip_reason (#744) decides whether the player is shown these at all, and that
# is a surface's decision: previewing a piece a unit cannot wear is a lie, but the arithmetic is the
# same arithmetic and a model that refused to do it would only push the refusal somewhere worse.
func previewed_stat(stat: Stats.Stat, candidate: Item) -> int:
	var gear := _candidate_gear(candidate)
	return get_body_stat(stat) + _gear_modifier_for(stat, gear[0], gear[1])


func previewed_def(candidate: Item) -> int:
	var gear := _candidate_gear(candidate)
	return _def_for(gear[0], previewed_stat(Stats.Stat.CON, candidate))


func previewed_weight(candidate: Item, incoming: bool) -> int:
	if candidate == null or not incoming:
		return get_weight()
	return get_weight() + candidate.get_effective_weight()


# MOV reads both of the answers above (#1176): a piece can move DEX through its modifiers AND add mass,
# so each goes through its own preview rather than this re-deriving either.
func previewed_mov(candidate: Item, incoming: bool) -> int:
	return instance.get_mov(previewed_stat(Stats.Stat.DEX, candidate), previewed_weight(candidate, incoming))


# The substitution itself: [armor, weapons] with the candidate in whichever slot it fills
# (Item.equip_slot, #1453). A hand candidate displaces the EQUIPPED one -- a unit swings one thing --
# while prosthetics stay, because a fitted limb contributes whatever else is in hand. A carried kind
# fills no slot and displaces nothing.
func _candidate_gear(candidate: Item) -> Array:
	var armor := worn_armor
	var weapons := _mod_sources()
	var slot: Item.EquipSlot = candidate.equip_slot() if candidate != null else Item.EquipSlot.NONE
	match slot:
		Item.EquipSlot.ARMOR:
			armor = candidate as ArmorData
		Item.EquipSlot.WEAPON:
			weapons = _mod_sources_holding(candidate as EquippableData)
	return [armor, weapons]


func get_weapon_proficiency(family: WeaponData.WeaponType) -> int:
	return instance.get_proficiency(family)

func get_max_hp() -> int:
	return instance.get_max_hp(get_effective_stat(Stats.Stat.CON))

# The one door for WRITING hp. UnitInstance can't derive its own ceiling (gear and temporary
# effects both live here), so this is where the two halves meet: outside code asks the Unit, it
# never reaches through into the instance and rebuilds the answer.
func set_current_hp(value: int) -> void:
	instance.set_current_hp(value, get_max_hp())

func get_effective_ldr() -> int:
	# Lives here, not on UnitInstance (#106): both terms are FINISHED effective stats, and the
	# chain's gear stage is only reachable from this layer. LDR is not cosmetic — it drives
	# Squad.max_size(), so a gear-less reading silently caps how many units a leader can field.
	return get_effective_stat(Stats.Stat.LDR) + Stats.per_ldr_band(get_effective_stat(Stats.Stat.PER))

func get_effective_def() -> int:
	return _def_for(worn_armor, get_effective_stat(Stats.Stat.CON))

# DEF is a SECOND walk, not a term in the first, and that is what makes a preview of it easy to get
# wrong: a candidate plate moves its own def_power AND the CON the scaling reads, through its
# stat_modifiers. Judging the new plate against the old plate's CON is the bug this shape prevents.
func _def_for(armor: ArmorData, con: int) -> int:
	# DEF is gear-only (stats.md); the CON math lives with the stat doctrine in Stats.
	if armor == null:
		return 0
	return Stats.armor_def(armor.def_power, con, armor.flat_def)

# THE composition point for "what is this unit immune to" — the role RulesService.def_breakdown
# plays for DEF. Any UNIT-level immunity readout (a status icon, an inspect row) asks HERE and
# never re-derives from whatever gear happens to be worn. The body reads the ability union
# (has_live_ability), so immunity is no armor-specific channel: it arrives as an ability, from
# whatever source granted it.
func is_immune_to(element: Elemental.Element) -> bool:
	if not Abilities.INSULATION.has(element):
		return false
	return has_live_ability(Abilities.INSULATION[element])

# What this unit can do RIGHT NOW: everything persistent (innate ∪ jobs) ∪ gear, deduped
# by id, earlier sources winning ties. THE answer — UnitInstance's version is the persistent
# inner layer. Derived live off what's worn, never stored, which is also what makes a wear-gate
# strip correct for free: drop the armor and its grants leave with it, no invalidation needed.
func get_live_abilities() -> Array[AbilityData]:
	var live: Array[AbilityData] = []
	AbilityData.add_live(live, instance.get_live_abilities())
	if worn_armor != null:
		AbilityData.add_live(live, worn_armor.granted_abilities)
	# The weapon half (#74) -- which slots contribute is _mod_sources' one answer, and the merge is
	# add_live exactly as above, so a mod and a worn piece granting the same id dedupe by id.
	for weapon in _mod_sources():
		for mod in weapon.active_modules(self):
			AbilityData.add_live(live, mod.granted_abilities)
	# A RUNE grants nothing, and that is RULED rather than pending (#531, dev 2026-08-26): a rune's
	# payload is its carvings. equipped_weapon is typed EquippableData, so a RuneData sitting there
	# falls out of _mod_sources' cast on purpose -- do not "fix" that, and do not add a fourth arm.
	return live

func has_live_ability(id: Abilities.Id) -> bool:
	for ability in get_live_abilities():
		if ability.id == id:
			return true
	return false

# The bonus DEF this unit brings to a hit it ABSORBS (the doc's brace bonus). Bare Guard blocks at
# +0; kit raises it. Deliberately NOT part of RulesService.def_breakdown: this applies to one
# substituted instance, not to the unit's standing DEF, and the inspect panel must never show it as
# though a Guard were walking around tougher (Iron Will's cap sits outside the breakdown for the
# same reason).
func get_brace_bonus() -> int:
	return Abilities.BRACE_DEF_BONUS if has_live_ability(Abilities.Id.BRACE) else 0

func get_element_aura(element: Elemental.Element) -> int:
	if instance == null:
		return 0
	return instance.get_element_aura(element)

# Can this unit EVER grow aura in this element -- its own field, never "aura >= 1" (UnitInstance's
# note: the limb tax empties a pool while the growth right survives). Delegated for the same reason
# the accessor above is: a surface reaching the instance directly is the duplicate seam #930's
# readout would otherwise open, and both of its surfaces ask this question.
func has_affinity(element: Elemental.Element) -> bool:
	return instance != null and instance.has_affinity(element)

# The affinity set IN RANK ORDER, [0] first. A COPY: the stored array is the unit's own, and a menu
# holding the live one could reorder a genetic fact by accident.
func affinity_order() -> Array[Elemental.Element]:
	if instance == null:
		var none: Array[Elemental.Element] = []
		return none
	return instance.affinity.duplicate()

func has_any_affinity() -> bool:
	return instance != null and instance.has_any_affinity()

# What a burned vial empowers this unit in (#697) — [] when nothing is attuned. Deliberately NOT
# folded into get_element_aura above: that accessor must stay blind to materia, because the anchor,
# the channel deficit, both wildcard pools and the equip gate all read it, and making it aware would
# leak empowerment into every one of those gates at once. Empowerment is a damage-time term only.
func attunement_elements() -> Array[Elemental.Element]:
	if attunement == null:
		var none: Array[Elemental.Element] = []
		return none
	return attunement.granted_elements()

# --- The attack source's rules (#1480 stage 4) ---
# Asked of the body, so a resolve pass asks its copy: an actor maimed or stripped earlier in the pass
# swings with what it has left. Unit forwards to each under its own name.

# What a COUNTER fires. A rune counters with its live pick (#30), which is aim state on the Unit,
# so it is handed in; a weapon always counters with its main (#72).
func counter_attack(live_pick: AttackData) -> AttackData:
	if equipped_weapon == null:
		return null
	return equipped_weapon.counter_attack(self, live_pick)

# This attack's shove and ally-splash as the equipped source reports them: a fitted mod may edit
# either (#529).
func attack_knockback(attack: AttackData) -> int:
	if equipped_weapon == null:
		return attack.knockback if attack != null else 0
	return equipped_weapon.effective_knockback(self, attack)

func attack_hits_allies(attack: AttackData) -> bool:
	if equipped_weapon == null:
		return attack != null and attack.hits_allies
	return equipped_weapon.effective_hits_allies(self, attack)

# Whether this attack may stand as a watch (#413).
func attack_can_overwatch(attack: AttackData) -> bool:
	if equipped_weapon == null:
		return attack != null and attack.can_overwatch
	return equipped_weapon.effective_can_overwatch(self, attack)

# Does the counter this source would fire count at all? It must exist, be a kind that ever counters
# (a heal, a map-only attack and a watch never do, #1135, #1440), and be fireable (#84).
func attack_source_can_counter(live_pick: AttackData) -> bool:
	var atk := counter_attack(live_pick)
	return atk != null and atk.can_ever_counter(attack_can_overwatch(atk)) and is_attack_fireable(atk)

# Why this body can't fire this attack right now, "" when it can. Ownership first (#1283), then the
# equipped source's own economy (#166). A null attack is bare fists and answers "".
func attack_block_reason(attack: AttackData) -> String:
	if attack == null:
		return ""
	if equipped_weapon == null:
		return "%s has nothing in hand to fire %s with." % [unit.get_unit_name() if unit != null else "", attack.display_name]
	if not equipped_weapon.carries(self, attack):
		return "%s doesn't have %s." % [equipped_weapon.shown_name(), attack.display_name]
	return equipped_weapon.attack_block_reason(self, attack)

# Derived from the reason, so a greyed row and a refused order cannot disagree (#73).
func is_attack_fireable(attack: AttackData) -> bool:
	return attack_block_reason(attack).is_empty()

# THE weapon-slot gate (#157): a weapon this body carries, that fills the WEAPON slot (armour has its
# own, Item.equip_slot, #1453), and that it can wield (a rune with nothing channelable is carried,
# never wielded). Null empties the hand. Unit.set_equipped_weapon forwards here; a resolve pass's copy
# holds a carried weapon through it (PlanResolver.hold_in_hand).
func equip(weapon: EquippableData) -> bool:
	if weapon == null:
		equipped_weapon = null
		return true
	if not inventory.has(weapon):
		return false
	if weapon.equip_slot() != Item.EquipSlot.WEAPON:
		return false
	if not weapon.can_equip(self):
		return false
	equipped_weapon = weapon
	return true
