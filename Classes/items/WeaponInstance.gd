class_name WeaponInstance
extends EquippableData

# A physical weapon a unit carries: a direct ref to its shared TEMPLATE (family base or
# prototype) + this item's own fitted mods — the only per-weapon state (weapons.md).
# item_name (inherited) is this weapon's custom pet name; "" falls back to the template's.
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

static func make(p_template: WeaponData) -> WeaponInstance:
	var w := _instance_for(p_template.weapon_type)
	w.template = p_template
	return w

# Which concrete class a family's instances are — the ONE place this mapping lives (#73).
# Any weapon_type not listed falls through to plain WeaponInstance; #82 tracks giving every
# family its own class and removing that fallback.
static func _instance_for(type: WeaponData.WeaponType) -> WeaponInstance:
	match type:
		WeaponData.WeaponType.SPRINGSPEAR:
			return SpringWeaponInstance.new()
		_:
			return WeaponInstance.new()

# Readiness seam (#73) — default: no gating at all. A subclass with its own wind-up/recovery
# economy (e.g. SpringWeaponInstance) overrides these; every other weapon never thinks about
# readiness.
func is_attack_fireable(_attack: WeaponAttackData) -> bool:
	return true

func can_reload() -> bool:
	return false

func reload() -> void:
	pass

func consume_readiness_for(_attack: WeaponAttackData) -> void:
	pass

# Copy for grants/saves: template stays SHARED (the point of the model); spaces copy
# shallowly — fitted mods are authored content refs, so sharing them is correct and keeps
# them as ExtResource refs in saved files.
func copy_equippable() -> EquippableData:
	var w := make(template)
	w.item_name = item_name
	w.icon = icon
	w.description = description
	w.limb_kind = limb_kind
	w.space_1 = space_1.duplicate()
	w.space_2 = space_2.duplicate()
	w.space_3 = space_3.duplicate()
	return w
func shown_name() -> String:
	if item_name != "":
		return item_name
	return template.item_name if template != null else ""

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
func available_attacks(_wielder: Unit) -> Array[WeaponAttackData]:
	if template == null:
		return []
	return template.attacks()

# ALL fitted modules count, active or not — mass is physical, not capability-gated.
func get_effective_weight() -> int:
	if template == null:
		return 0
	var total := template.base_weight
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

# attack = null means the MAIN attack — counters, AI, and single-attack weapons all want
# the default, so most call sites never pass one. Slice 2 threads the player's pick.
func base_damage(wielder: Unit, attack: WeaponAttackData = null) -> int:
	if template == null:
		return 0
	var atk := attack if attack != null else template.main_attack
	var mods := active_modules(wielder)
	var eff_power := atk.power if atk != null else 0
	for mod in mods:
		eff_power += mod.power_delta
	return eff_power + scaling_contribution(wielder, mods)

func get_elements(wielder: Unit, attack: WeaponAttackData = null) -> Array[Elemental.Element]:
	var result: Array[Elemental.Element] = []
	if template == null:
		return result
	var atk := attack if attack != null else template.main_attack
	if atk != null and atk.elemental_damage_type != Elemental.Element.NONE:
		result.append(atk.elemental_damage_type)
	for mod in active_modules(wielder):
		if mod.added_element != Elemental.Element.NONE and not result.has(mod.added_element):
			result.append(mod.added_element)
	return result

func hits_map(attack: WeaponAttackData = null) -> bool:
	if template == null:
		return false
	var atk := attack if attack != null else template.main_attack
	return atk != null and atk.hits_map()
