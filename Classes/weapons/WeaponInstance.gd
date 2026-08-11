class_name WeaponInstance
extends EquippableData

# A physical weapon a unit carries: a direct ref to its shared TEMPLATE (family base or
# prototype) + this item's own fitted mods — the only per-weapon state (weapons.md).
# display_name (inherited) is this weapon's custom pet name; "" falls back to the template's.
# NEVER duplicate(true) one — that deep-copies the shared template and severs live sync.
# Create via make(), copy via copy_equippable().

@export var template: WeaponData
@export var limb_kind: WeaponData.LimbKind = WeaponData.LimbKind.ARM
# PROSTHETIC only: which limb THIS instance installs into (moved off WeaponData
# 2026-07-19) — two instances built on the same shared template need independent
# arm/leg identity, so the template can't be the source of truth for it.
@export var space_1: Array[WeaponModData] = []
@export var space_2: Array[WeaponModData] = []
@export var space_3: Array[WeaponModData] = []

# Fallback wording for a readiness refusal, used only when the family has no status_text of its
# own. Lives here rather than in the menu (#166): the menu renders reasons, it doesn't know them.
const NOT_READY_TEXT := "Not ready — reload the weapon first"

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

# Copy for grants/saves: template stays SHARED (the point of the model); spaces copy
# shallowly — fitted mods are authored content refs, so sharing them is correct and keeps
# them as ExtResource refs in saved files.
func copy_equippable() -> EquippableData:
	var w := make(template)
	w.display_name = display_name
	w.icon = icon
	w.description = description
	w.limb_kind = limb_kind
	w.space_1 = space_1.duplicate()
	w.space_2 = space_2.duplicate()
	w.space_3 = space_3.duplicate()
	return w
func shown_name() -> String:
	if display_name != "":
		return display_name
	return template.display_name if template != null else ""

func space(index: int) -> Array[WeaponModData]:
	match index:
		0: return space_1
		1: return space_2
		2: return space_3
		_: return []

func space_count() -> int:
	return template.space_capacities().size() if template != null else 0

func used_capacity(index: int) -> int:
	var total := 0
	for mod in space(index):
		total += mod.size
	return total

func can_fit(index: int, mod: WeaponModData) -> bool:
	if template == null or index < 0 or index >= space_count():
		return false
	return used_capacity(index) + mod.size <= template.space_capacities()[index]

func fit(index: int, mod: WeaponModData) -> bool:
	if not can_fit(index, mod):
		return false
	space(index).append(mod)
	return true

# Proficiency N activates spaces 1..N — reduced capability, never locked out (weapons.md).
func active_space_count(wielder: Unit) -> int:
	if template == null:
		return 0
	return mini(wielder.get_weapon_proficiency(template.weapon_type), space_count())

func active_modules(wielder: Unit) -> Array[WeaponModData]:
	var result: Array[WeaponModData] = []
	for i in range(active_space_count(wielder)):
		result.append_array(space(i))
	return result

# Stock attacks this wielder can choose from — the template's list today. Mod-granted /
# mod-replaced attacks compose here when #74 lands (why wielder is already in the signature).
# --- Attack-source surface (EquippableData) ---

func selectable_attacks(wielder: Unit) -> Array[AttackData]:
	var result: Array[AttackData] = []
	for a in available_attacks(wielder):
		result.append(a)
	return result

func default_attack(_wielder: Unit) -> AttackData:
	return template.main_attack if template != null else null

# ALWAYS main, ignoring any live active_attack pick (#72 ruling; overwatch-style alt-attack
# countering is out of scope, #73). This is the divergence from RuneData.counter_attack.
func counter_attack(_wielder: Unit) -> AttackData:
	return template.main_attack if template != null else null

# available_attacks minus main — what the Weapon Action submenu lists.
func secondary_attacks(wielder: Unit) -> Array[AttackData]:
	var result: Array[AttackData] = []
	if template == null:
		return result
	var main := template.main_attack
	for a in available_attacks(wielder):
		if a != main:
			result.append(a)
	return result

func available_attacks(_wielder: Unit) -> Array[WeaponAttackData]:
	if template == null:
		return []
	return template.attacks()

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

func attack_detail(wielder: Unit, attack: AttackData) -> String:
	var weapon_attack := attack as WeaponAttackData
	if weapon_attack == null:
		return ""
	return "%s %s" % [weapon_attack.payload_text(base_damage(wielder, weapon_attack)),
		weapon_attack.targets_text()]

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

func scaling_contribution(wielder: Unit, mods: Array[WeaponModData]) -> int:
	var blend := template.scaling_blend.duplicate()
	for mod in mods:
		for stat in mod.scaling_nudge:
			blend[stat] = blend.get(stat, 0) + mod.scaling_nudge[stat]
	var total_weight := 0
	var weighted_sum := 0
	for stat in blend:
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
	var mods := active_modules(wielder)
	var eff_power := attack.power
	for mod in mods:
		eff_power += mod.power_delta
	return eff_power + scaling_contribution(wielder, mods)

# No attack means bare fists: not even fitted mods contribute, because the weapon isn't what's
# landing. (A stamped attack still collects mod-added elements on top of its own.)
func get_elements(wielder: Unit, attack: WeaponAttackData) -> Array[Elemental.Element]:
	var result: Array[Elemental.Element] = []
	if template == null or attack == null:
		return result
	if attack.elemental_damage_type != Elemental.Element.NONE:
		result.append(attack.elemental_damage_type)
	for mod in active_modules(wielder):
		if mod.added_element != Elemental.Element.NONE and not result.has(mod.added_element):
			result.append(mod.added_element)
	return result

# hits_map() is gone from here: with the null->main fallback removed it did nothing but forward to
# AttackData.hits_map(), which both attack kinds already answer. PlanResolver calls that directly.
