extends Resource
class_name ScenarioUnitEntry

# One saved unit's snapshot inside a ScenarioData (the persistence seam, #8): spawn cell,
# squad membership, and the UnitInstance state that survives missions (#83) — stats, HP,
# Will, inventory, limbs, proficiency, aura, jobs. What ScenarioManager reads on save
# and writes back on load.

@export var unit_data: UnitData
@export var cell: Vector2i
@export var squad_id := -1   #entries sharing an id form one squad; -1 = solo
@export var is_leader := false
@export var squad_name := ""
@export var squad_archetype: AIArchetype.Type = AIArchetype.Type.FACTION_DEFAULT
@export var squad_zone := ""   # only meaningful on the leader's entry; "" = none
@export var jobs: Array[String] = []

# --- UnitInstance state (#83). All additive: a pre-#83 save reads defaults, and every
# default below means "not saved — keep initialize()'s result". ---
@export var stats: Dictionary[Stats.Stat, int] = {}
@export var current_hp := -1     # -1 = unsaved; live HP is always >= 1
@export var current_will := -1   # -1 = unsaved; 0 is a legal saved value
@export var inventory: Array[EquippableData] = []
@export var equipped_index := -1   # into inventory; -1 = unarmed. Replaced the equipped_weapon copy (#83).
@export var weapon_proficiency: Dictionary[WeaponData.WeaponType, int] = {}
@export var aura: Dictionary[Elemental.Element, int] = {}
@export var limb_states: Dictionary[UnitInstance.LimbSlot, UnitInstance.LimbState] = {}
@export var limb_prosthetic_stats: Dictionary[UnitInstance.LimbSlot, int] = {}   # placeholder fittings (no real item)
@export var limb_prosthetic_items: Dictionary[UnitInstance.LimbSlot, int] = {}   # index into inventory; re-linked on load

# Snapshot the unit's persistent side of the seam. Inventory copies via copy_equippable()
# — never duplicate(true), which would fork a WeaponInstance off its shared template. An
# installed prosthetic saves as the INDEX of its carried instance so load can re-link.
func capture_unit_state(unit: Unit) -> void:
	var inst: UnitInstance = unit.unit_instance
	jobs = inst.jobs.duplicate()
	stats = inst.stats.duplicate()
	current_hp = inst.current_hp
	current_will = inst.current_will
	weapon_proficiency = inst.weapon_proficiency.duplicate()
	aura = inst.aura.duplicate()

	var sources: Array[EquippableData] = []   # pre-copy identities, for the index lookups below
	inventory = []
	for item in unit.inventory:
		var equippable := item as EquippableData
		if item != null and equippable == null:
			push_warning("Scenario save: '%s' is not equippable — dropped" % item.item_name)
		if equippable == null:
			continue
		sources.append(equippable)
		inventory.append(equippable.copy_equippable())

	equipped_index = sources.find(unit.get_equipped_weapon())
	if unit.has_equipped_weapon() and equipped_index == -1:
		# equipped directly without an inventory slot (fixtures do this) — save it anyway
		equipped_index = inventory.size()
		inventory.append(unit.get_equipped_weapon().copy_equippable())

	limb_states = {}
	limb_prosthetic_stats = {}
	limb_prosthetic_items = {}
	for slot in UnitInstance.LimbSlot.values():
		var fitting: UnitInstance.LimbFitting = inst.limbs[slot]
		limb_states[slot] = fitting.state
		if fitting.state != UnitInstance.LimbState.PROSTHETIC:
			continue
		if fitting.prosthetic_item == null:
			limb_prosthetic_stats[slot] = fitting.prosthetic_stat
			continue
		for i in sources.size():
			var carried := sources[i] as WeaponInstance
			if carried != null and carried.template == fitting.prosthetic_item:
				limb_prosthetic_items[slot] = i
				break

# Write the snapshot back onto a freshly spawned unit. Runs AFTER initialize() (which
# rebuilds stats/limbs/aura and refills HP+Will), deliberately overriding that reset.
# Order matters: stats before HP/Will (their maxes may be edited), inventory before
# limbs (the prosthetic re-link reads loaded slots).
func apply_unit_state(unit: Unit) -> void:
	var inst: UnitInstance = unit.unit_instance
	inst.jobs = jobs.duplicate()

	for stat in stats:
		inst.stats[stat] = stats[stat]   # per-key: a stat appended after this save keeps its default

	inst.weapon_proficiency = weapon_proficiency.duplicate()   # empty = all DEFAULT, saved or not

	if not aura.is_empty():
		inst.aura = aura.duplicate()   # whole-dict: the seeded pools + growth/tax, saved together

	for i in inventory.size():
		if inventory[i] == null:
			continue
		if not unit.add_item(inventory[i].copy_equippable()):
			push_warning("Scenario load: inventory full — dropped '%s'" % inventory[i].item_name)
	# add_item auto-equips the first equippable; the save's explicit choice wins either way:
	if equipped_index >= 0:
		unit.equip_weapon_from_inventory(equipped_index)
	else:
		unit.unequip_weapon()

	for slot in limb_states:
		var fitting: UnitInstance.LimbFitting = inst.limbs[slot]
		fitting.state = limb_states[slot]
		fitting.prosthetic_stat = limb_prosthetic_stats.get(slot, 0)
		fitting.prosthetic_item = null
		var idx: int = limb_prosthetic_items.get(slot, -1)
		if idx >= 0 and idx < unit.inventory.size():
			var carried := unit.inventory[idx] as WeaponInstance
			if carried != null:
				fitting.prosthetic_item = carried.template   # re-link: the carried copy's SHARED template, never a fork

	if current_hp >= 0:
		inst.set_current_hp(maxi(1, current_hp))   # floor 1: never fire died() out of a load
	if current_will >= 0:
		inst.set_current_will(current_will)
