class_name WeaponInstance
extends EquippableData

# A physical weapon a unit carries: a direct ref to its shared TEMPLATE (family base or
# prototype) + this item's own fitted mods — the only per-weapon state (weapons.md).
# display_name (inherited) is this weapon's custom pet name; "" falls back to the template's.
# NEVER duplicate(true) one — that deep-copies the shared template and severs live sync.
# Create via make(), copy via copy_for_grant().

@export var template: WeaponData
@export var limb_kind: WeaponData.LimbKind = WeaponData.LimbKind.ARM
# PROSTHETIC only: which limb THIS instance installs into (moved off WeaponData
# 2026-07-19) — two instances built on the same shared template need independent
# arm/leg identity, so the template can't be the source of truth for it.
@export var spaces: Array[Array] = []
# One inner array of fitted mods per mod space, sized by the TEMPLATE's mod_spaces. Was three
# named fields (space_1/2/3) until #486, which capped every weapon at three spaces no matter
# what a template authored. The OUTER array is untyped because Godot has no nested typed arrays;
# each inner one is built as Array[WeaponModData] by space(), which is the only door that grows
# this — and it hands back the LIVE array, since the fitting UI removes through it.

# Fallback wording for a readiness refusal, used only when the family has no status_text of its
# own. Lives here rather than in the menu (#166): the menu renders reasons, it doesn't know them.
const NOT_READY_TEXT := "Not ready — reload the weapon first"

# A READ-THROUGH, never a copy (#745). An instance is free to carry its own wording -- a named
# variant with a story -- but almost none do, and `make()` has never copied the template's, so every
# weapon a player has ever hovered showed an empty description while the family it belongs to had one
# authored. Copying at make() would have fixed today's tooltips and frozen every scenario already
# saved; reading through fixes those too, and re-wording a family re-words every instance for free.
# That is the same rule that keeps NUMBERS off prose, pointed at the prose itself.
func describe() -> String:
	if description != "":
		return description
	return template.description if template != null else ""


static func make(p_template: WeaponData) -> WeaponInstance:
	var w := _instance_for(p_template.weapon_type)
	if w == null:
		push_error("WeaponInstance.make(): no subclass mapped for weapon_type %s (%s) — every family needs a class (#82)" % [WeaponData.WeaponType.keys()[p_template.weapon_type], p_template.resource_path])
		return null
	w.template = p_template
	return w

# Which concrete class a family's instances are — the ONE place this mapping lives (#73,
# generalized #82). Every real family has a class; an unmapped type (NONE, or a future
# family added to the enum without one) is a loud failure, not a silent generic weapon.
static func _instance_for(type: WeaponData.WeaponType) -> WeaponInstance:
	match type:
		WeaponData.WeaponType.CHAINSWORD:
			return ChainswordWeaponInstance.new()
		WeaponData.WeaponType.DRILL:
			return DrillWeaponInstance.new()
		WeaponData.WeaponType.SPRINGSPEAR:
			return SpringspearWeaponInstance.new()
		WeaponData.WeaponType.CARBINE:
			return CarbineWeaponInstance.new()
		WeaponData.WeaponType.KINETIC_MACE:
			return KineticMaceWeaponInstance.new()
		WeaponData.WeaponType.CHEMICAL_SPITTER:
			return ChemicalSpitterWeaponInstance.new()
		WeaponData.WeaponType.PROSTHETIC:
			return ProstheticWeaponInstance.new()
		_:
			return null

# Readiness seam (#73) — default: no gating at all. A subclass with its own wind-up/recovery
# economy (e.g. SpringspearWeaponInstance) overrides these; every other weapon never thinks about
# readiness. These two stay HERE rather than on EquippableData because they take a
# WeaponAttackData: widening the parameter to fit the base would break every family override.
func is_attack_fireable(_attack: WeaponAttackData) -> bool:
	return true

func consume_readiness_for(_attack: WeaponAttackData) -> void:
	pass

# Supercharge seam (#97) — default: this family has no charge to spend, so its main is always its
# main. The Chemical Spitter's tank overrides it. Sits beside readiness and is deliberately NOT it:
# readiness gates what may fire, this only changes WHAT the same order fires.
func is_supercharged() -> bool:
	return tank_charges() > 0

# How many supercharges are banked. The resolver seeds its per-pass thread from this; is_supercharged
# is derived from it so a family declares ONE number rather than a number and a boolean.
func tank_charges() -> int:
	return 0

# Spend one supercharge. Driven by the outcome's charge_spent stamp at execution, never from here,
# so the preview and the spend read one fact.
func spend_charge() -> void:
	pass

# The self-abilities themselves — can_reload/reload/reload_label, can_rev/rev/tick_rev, can_burrow —
# are declared as inert virtuals on EquippableData (promoted there 2026-07-27), because Unit
# delegates them straight to whatever is equipped and shouldn't have to cast first. Families
# override them exactly as before: Chainsword revs, Carbine and Springspear reload, Drill burrows.

# Rev's DEF pierce (#84) — read by PlanResolver through a deliberate `as WeaponInstance` cast,
# never by Unit, so it stays down here with the rest of the weapon-only surface.
func ignores_def() -> bool:
	return false

# Status seam (#44) — default: this family has no battle state worth reporting. Families with a
# signature mechanic override it so the player can SEE the state their decisions depend on
# (a spent spear can't Spring, an uncharged mace can't Blowback). Presentation-only: nothing in
# the rules reads this string.
func status_text() -> String:
	return ""

# Battle-state seam (#87): this family's signature-mechanic runtime state, non-@export so a
# mission boundary still resets it for free. Dict, not one int -- families may need >1 field.
func capture_battle_state() -> Dictionary:
	return {}

func apply_battle_state(_state: Dictionary) -> void:
	pass

# Copy for grants/saves: template stays SHARED (the point of the model); each space's LIST is
# copied while its mods are not — fitted mods are authored content refs, so sharing them is
# correct and keeps them as ExtResource refs in saved files.
func copy_for_grant() -> Item:
	var w := make(template)
	w.display_name = display_name
	w.icon = icon
	w.description = description
	w.limb_kind = limb_kind
	w.spaces = []
	for fitted: Array in spaces:
		var copied: Array[WeaponModData] = []
		copied.assign(fitted)
		w.spaces.append(copied)
	return w
func shown_name() -> String:
	if display_name != "":
		return display_name
	return template.display_name if template != null else ""

# The LIVE array for a space, grown on demand. Growing here rather than at construction is what
# lets a template gain a space without every instance built on it needing a migration -- and an
# instance saved before this field existed simply arrives empty. A space the template does not
# have answers with a throwaway, never by growing.
func space(index: int) -> Array:
	if template == null or index < 0 or index >= space_count():
		return []
	while spaces.size() <= index:
		var fresh: Array[WeaponModData] = []
		spaces.append(fresh)
	return spaces[index]

func space_count() -> int:
	return template.mod_spaces.size() if template != null else 0

func used_capacity(index: int) -> int:
	var total := 0
	for mod: WeaponModData in space(index):
		total += mod.size
	return total

# "" = it fits. can_fit is DERIVED from this (#74), so a refusal and its explanation are one
# answer rather than a boolean here and a hand-written sentence in whichever panel refused — the
# shape EquippableData.attack_block_reason already uses one domain over (#166: a surface can only
# grey what it can explain).
#
# FAMILY is asked before capacity because the two refusals are different in kind: a wrong family
# can never be fixed on this weapon, while a full space is a live state you fix by removing
# something. That ordering is also what the fitting picker leans on — it HIDES what the family
# refuses and merely refuses what capacity does.
#
# A mod that changes scaling while naming NO family is broken content rather than a bad fit, and
# it is refused at the authoring save instead; here it simply fits, since there is nothing to
# disagree with.
#
# The main-replacement clause sits BETWEEN them for the same reason, one step milder: a second
# replacer is fixable, but not by freeing capacity, so saying so first is the more useful answer.
func fit_block_reason(index: int, mod: WeaponModData) -> String:
	if template == null:
		return "This weapon has no template, so it has no spaces."
	if index < 0 or index >= space_count():
		return "Space %d does not exist on this weapon." % (index + 1)
	if not mod.fits_family(template.weapon_type):
		return "Fits %s only — a scaling change is measured against that family's main attack." % \
			WeaponData.WeaponType.keys()[mod.family].capitalize()
	if mod.replaces_main != null:
		var already := _main_replacer()
		if already != null:
			var whose: String = already.display_name if already.display_name != "" else "Another fitted mod"
			return "%s already replaces this weapon's main attack — a weapon has one main." % whose
	if mod.overrides_kind:
		var holder := _kind_overrider()
		if holder != null:
			var name: String = holder.display_name if holder.display_name != "" else "Another fitted mod"
			return "%s already changes this weapon's damage kind -- one kind-changing mod at a time, so fitting order can never decide what armour does to a swing." % name
	var capacity: int = template.mod_spaces[index]
	if used_capacity(index) + mod.size > capacity:
		return "Space %d holds %d of %d — this needs %d more." % [index + 1, used_capacity(index), capacity, mod.size]
	return ""

func can_fit(index: int, mod: WeaponModData) -> bool:
	return fit_block_reason(index, mod) == ""

# The fitted mod replacing this weapon's main, if any. Scans EVERY space rather than the active
# ones: fitting has no wielder, so there is no proficiency to ask about, and a mod parked in a
# space this unit cannot reach still occupies the one main a weapon has.
func _main_replacer() -> WeaponModData:
	for i in range(space_count()):
		for mod: WeaponModData in space(i):
			if mod.replaces_main != null:
				return mod
	return null

# The fitted mod overriding the damage kind, if any (#424). Same every-space scan and the same reason:
# a parked kind-changer still occupies the one kind an attack delivers.
func _kind_overrider() -> WeaponModData:
	for i in range(space_count()):
		for mod: WeaponModData in space(i):
			if mod.overrides_kind:
				return mod
	return null

func fit(index: int, mod: WeaponModData) -> bool:
	if not can_fit(index, mod):
		return false
	space(index).append(mod)
	return true

# Proficiency N activates spaces 1..N — reduced capability, never locked out (weapons.md).
# UNREDUCED means every space, whatever the count: since #486 a template authors how many it has,
# so no fixed number can stand for "all of them" the way 3 used to.
func active_space_count(wielder: Unit) -> int:
	if template == null:
		return 0
	var proficiency := wielder.get_weapon_proficiency(template.weapon_type)
	if proficiency == UnitInstance.UNREDUCED:
		return space_count()
	return mini(proficiency, space_count())

func active_modules(wielder: Unit) -> Array[WeaponModData]:
	var result: Array[WeaponModData] = []
	for i in range(active_space_count(wielder)):
		result.append_array(space(i))
	return result

# The mods whose EFFECTS reach this attack — the ONE place applies_to is interpreted (#530).
# Every effect answers to it: power, element, and the scaling shift its callers weigh.
#
# GRANTS deliberately do not come through here — available_attacks reads active_modules straight,
# because "which attacks does this mod change" and "which attacks does it add" are different
# questions. A MAIN_ATTACK mod still hands over whatever it grants; it just doesn't buff it.
#
# Asked of is_main_form rather than of effective_main directly (#97): the supercharge makes what
# effective_main answers depend on the TANK, and a stamp frozen under the other form would silently
# lose every MAIN_ATTACK mod's power, element, kind and knockback. Both forms are the main.
func _mods_for(wielder: Unit, attack: WeaponAttackData) -> Array[WeaponModData]:
	var result: Array[WeaponModData] = []
	for mod in active_modules(wielder):
		if mod.applies_to == WeaponModData.AppliesTo.EVERY_ATTACK or is_main_form(wielder, attack):
			result.append(mod)
	return result

# --- Attack-source surface (EquippableData) ---

func selectable_attacks(wielder: Unit) -> Array[AttackData]:
	return fireable_only(wielder, repertoire(wielder))

# The repertoire in the base's own terms (#590). available_attacks answers the same question in
# WeaponAttackData terms and stays the family-facing one; both views come off THIS.
func repertoire(wielder: Unit) -> Array[AttackData]:
	var result: Array[AttackData] = []
	for a in available_attacks(wielder):
		result.append(a)
	return result

# What this weapon's main attack ACTUALLY is: the template's, unless a proficiency-active mod
# replaces it (#529). FOUR surfaces read it -- default aim, counters, the secondary filter and
# available_attacks below -- and they have to agree, which is why it is a seam rather than a clause
# each of them repeats. #529 named only the counter; secondary_attacks is the sharper one,
# because filtering by the OLD main lists the replacement in the submenu as well as firing it
# from Attack, so the same swing shows up twice.
#
# FIRST replacer in space order wins. fit_block_reason refuses a second, so a weapon fitted
# through the normal door can only carry one -- this is the answer for a hand-edited .tres, and
# it is first rather than last so fitting into a LATER space cannot silently move the main.
func effective_main(wielder: Unit) -> WeaponAttackData:
	var main := base_main(wielder)
	# The supercharge substitution (#97), applied AFTER the mod replacement so a mod-replaced main
	# keeps its own empowered form rather than losing one. THE single point the whole feature enters
	# the pipeline: the menu, Reach, the resolver, the queue row and the AI all read this, so none of
	# them learns what a tank is.
	if main != null and main.empowered_form != null and is_supercharged():
		return main.empowered_form
	return main

# The main BEFORE the supercharge, which is the answer to "what does this weapon fire" in the
# weapon's own terms -- what a mod replaced, or the template's. Split out because the tank asks it
# (an empowered form is what a vial BUYS and so cannot be what qualifies one) and because
# is_main_form needs both sides.
func base_main(wielder: Unit) -> WeaponAttackData:
	if template == null:
		return null
	for mod in active_modules(wielder):
		if mod.replaces_main != null:
			return mod.replaces_main
	return template.main_attack

# Is this attack THE main, under either form? One question with two right answers, which is why it
# is asked here rather than by comparing against whichever form happens to be live.
func is_main_form(wielder: Unit, attack: AttackData) -> bool:
	var main := base_main(wielder)
	if main == null or attack == null:
		return false
	return attack == main or attack == main.empowered_form

func default_attack(wielder: Unit) -> AttackData:
	return effective_main(wielder)

# ALWAYS main, ignoring any live active_attack pick (#72 ruling; overwatch-style alt-attack
# countering is out of scope, #73). This is the divergence from RuneData.counter_attack.
func counter_attack(wielder: Unit) -> AttackData:
	return effective_main(wielder)

# The FIREABLE set minus main -- what the Weapon Action submenu lists. Was available_attacks minus
# main until #590: a watch-only attack must never be offered as something to fire, and
# selectable_attacks is the one place that clause is spelled.
func secondary_attacks(wielder: Unit) -> Array[AttackData]:
	var result: Array[AttackData] = []
	if template == null:
		return result
	# is_main_form, not `!= effective_main`: while a tank is hot the main IS the empowered form, and
	# comparing against it alone would offer the BASE form here as though it were a second attack.
	for a in selectable_attacks(wielder):
		if not is_main_form(wielder, a):
			result.append(a)
	return result

# Every attack this wielder can choose from: its main (whatever a mod has made that, #529), the
# family's other stock attacks, then whatever THIS weapon's proficiency-active mods add (#74).
# Main stays first, so the canonical order survives.
#
# Deliberately NOT template.attacks() any more: that answers what the TEMPLATE carries, which is
# right for the Attack Editor and AttackLint and wrong here, where the main is a fact about this
# INSTANCE. One question each, rather than one function bent to serve both.
#
# Reads its OWN fitted mods, deliberately NOT Unit._mod_sources() -- an attack belongs to the
# weapon that fires it, so a prosthetic leg's mod must not add a swing to the carbine in your
# hands. That is the asymmetry against granted_abilities/stat_modifiers, which describe the
# WIELDER and therefore union across every contributing weapon.
#
# Deduped by identity, so two mods granting one authored resource list it once -- and so a
# replacement that is also a stock extra does not appear twice.
func available_attacks(wielder: Unit) -> Array[WeaponAttackData]:
	if template == null:
		return []
	var result: Array[WeaponAttackData] = []
	var main := effective_main(wielder)
	if main != null:
		result.append(main)
	for attack in template.extra_attacks:
		if attack != null and not result.has(attack):
			result.append(attack)
	for mod in active_modules(wielder):
		for attack in mod.granted_attacks:
			if attack != null and not result.has(attack):
				result.append(attack)
	return result

# --- Explaining an attack (#166, EquippableData surface) ---

# The family already says this in its own words, so REUSE status_text rather than authoring a
# second set of strings: "Spent — needs Spring Load", "Ammo 0/2 — needs Reload". The constant is
# only the fallback for a family with a readiness rule but nothing to say about it.
func attack_block_reason(_wielder: Unit, attack: AttackData) -> String:
	var weapon_attack := attack as WeaponAttackData
	if weapon_attack == null or is_attack_fireable(weapon_attack):
		return ""
	var status := status_text()
	return status if status != "" else NOT_READY_TEXT

# Two lines: what the attack does, then WHERE the number came from (#485, dev call 2026-08-25).
# The second itemises the way ArmorData.mechanical_text itemises DEF -- for THIS wielder, since
# both halves depend on them. It reads the same effective_blend base_damage weighs, so a fitted
# mod's shift is visible on hover rather than something you infer from a damage number moving.
func attack_detail(wielder: Unit, attack: AttackData) -> String:
	var weapon_attack := attack as WeaponAttackData
	if weapon_attack == null:
		return ""
	var damage := base_damage(wielder, weapon_attack)
	var headline := "%s %s" % [weapon_attack.payload_text(damage, effective_kind(wielder, weapon_attack)), weapon_attack.targets_text()]
	if weapon_attack.deals_no_damage:
		return headline   # scaling is suppressed entirely (#126) -- printing a blend would be a lie
	var mods := _mods_for(wielder, weapon_attack)
	var eff_power := weapon_attack.power
	for mod in mods:
		eff_power += mod.power_delta
	var from_stats := scaling_contribution(wielder, weapon_attack, mods)
	var blend := Stats.blend_text(effective_blend(weapon_attack, mods))
	return "%s\n%d power + %d from %s" % [headline, eff_power, from_stats, blend]

# ALL fitted modules count, active or not -- mass is physical, not capability-gated. The
# instance's own weight rides on top of the family's, so a one-off heavier copy is authorable.
func get_effective_weight() -> int:
	if template == null:
		return weight
	var total := weight + template.weight
	for i in range(space_count()):
		for mod in space(i):
			total += mod.weight
	return total

# What this attack ACTUALLY scales off on this weapon: its own authored blend, shifted by every
# fitted mod's nudge. THE one answer (#485) -- scaling_contribution weighs it and attack_detail
# prints it, so the number a player is shown and the number they take can never disagree.
#
# Raw weights, not percentages: the caller below divides by the total, and normalising here would
# round twice. Stats.blend_text does the normalising for display.
#
# A nudge can drive a weight NEGATIVE -- a mod authored against a family that uses STR, fitted to
# one that does not -- and a negative weight subtracts the wielder's stat from their own damage.
# Clamped at 0 rather than propagated: the mod simply contributes nothing to a stat the attack
# never used. #74's family gate is the real fix; this is the floor under it.
func effective_blend(attack: WeaponAttackData, mods: Array[WeaponModData]) -> Dictionary:
	var blend: Dictionary[Stats.Stat, int] = {}
	if attack != null:
		for stat: Stats.Stat in attack.scaling_blend:
			blend[stat] = attack.scaling_blend[stat]
	for mod in mods:
		for stat: Stats.Stat in mod.scaling_change:
			blend[stat] = maxi(0, blend.get(stat, 0) + mod.scaling_change[stat])
	return blend

func scaling_contribution(wielder: Unit, attack: WeaponAttackData, mods: Array[WeaponModData]) -> int:
	var blend := effective_blend(attack, mods)
	var total_weight := 0
	var weighted_sum := 0
	for stat: Stats.Stat in blend:
		total_weight += blend[stat]
		weighted_sum += wielder.get_effective_stat(stat) * blend[stat]
	if total_weight == 0:
		return 0
	return int(round(float(weighted_sum) / total_weight))

# The attack is REQUIRED, and `null` means NO ATTACK -- not "the main one" (dev call 2026-07-28:
# if a caller wants main, it says so). These used to default to main, which made null mean "no
# attack" to the geometry layer (Reach) and "main" here: one value, two meanings, which is design
# law #4 one level down from #102 itself. Callers wanting the headline view of a weapon pass
# default_attack() explicitly -- see inventory_panel.
func base_damage(wielder: Unit, attack: WeaponAttackData) -> int:
	if template == null or attack == null:
		return 0
	if attack.deals_no_damage:
		return 0   # utility attack (#126): the stat blend never sneaks damage into a damageless effect
	var mods := _mods_for(wielder, attack)
	var eff_power := attack.power
	for mod in mods:
		eff_power += mod.power_delta
	return eff_power + scaling_contribution(wielder, attack, mods)

# No attack means bare fists: not even fitted mods contribute, because the weapon isn't what's
# landing. (A stamped attack still collects mod-added elements on top of its own.)
func get_elements(wielder: Unit, attack: WeaponAttackData) -> Array[Elemental.Element]:
	var result: Array[Elemental.Element] = []
	if template == null or attack == null:
		return result
	if attack.elemental_damage_type != Elemental.Element.NONE:
		result.append(attack.elemental_damage_type)
	for mod in _mods_for(wielder, attack):
		if mod.added_element != Elemental.Element.NONE and not result.has(mod.added_element):
			result.append(mod.added_element)
	return result

# The two overrides a fitted mod may make (#529), composed the same way power and elements are and
# gated by the same applies_to selector -- one answer to what a mod reaches, not one per field.
# The kind the attack DELIVERS for this wielder (#424): the authored kind, replaced by the one fitted
# kind-overriding mod that reaches it, then AttackData.deliver applies the heal / no-damage rule --
# one home for that rule, so a modded utility swing cannot come out blunt. A carving never comes
# through here; it has no mods and answers delivered_kind() itself.
func effective_kind(wielder: Unit, attack: AttackData) -> AttackData.Kind:
	var weapon_attack := attack as WeaponAttackData
	if weapon_attack == null:
		return attack.delivered_kind()
	var kind := weapon_attack.damage_kind
	for mod in _mods_for(wielder, weapon_attack):
		if mod.overrides_kind:
			kind = mod.kind
	return weapon_attack.deliver(kind)

func effective_knockback(wielder: Unit, attack: AttackData) -> int:
	var weapon_attack := attack as WeaponAttackData
	if weapon_attack == null:
		return super(wielder, attack)
	var total := weapon_attack.knockback
	for mod in _mods_for(wielder, weapon_attack):
		total += mod.knockback_delta
	return maxi(0, total)   # a shove below zero is no shove, not a pull

# OFF short-circuits, which is what makes the rule order-independent: an OFF anywhere wins, so
# fitting the same mods into different spaces cannot give different answers.
func effective_hits_allies(wielder: Unit, attack: AttackData) -> bool:
	var weapon_attack := attack as WeaponAttackData
	if weapon_attack == null:
		return super(wielder, attack)
	var answer := weapon_attack.hits_allies
	for mod in _mods_for(wielder, weapon_attack):
		if mod.hits_allies_override == WeaponModData.Override.OFF:
			return false
		if mod.hits_allies_override == WeaponModData.Override.ON:
			answer = true
	return answer

# Same composition, same reason (#413): a mod may grant or revoke the watch capability, and OFF
# short-circuits so fitting order cannot change the answer.
func effective_can_overwatch(wielder: Unit, attack: AttackData) -> bool:
	var weapon_attack := attack as WeaponAttackData
	if weapon_attack == null:
		return super(wielder, attack)
	var answer := weapon_attack.can_overwatch
	for mod in _mods_for(wielder, weapon_attack):
		if mod.can_overwatch_override == WeaponModData.Override.OFF:
			return false
		if mod.can_overwatch_override == WeaponModData.Override.ON:
			answer = true
	return answer

# hits_map() is gone from here: with the null->main fallback removed it did nothing but forward to
# AttackData.hits_map(), which both attack kinds already answer. PlanResolver calls that directly.
