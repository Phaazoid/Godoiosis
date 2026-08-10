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
@export var worn_armor_index := -1   # into inventory; -1 = unarmored. Mirrors equipped_index (#65).
@export var weapon_proficiency: Dictionary[WeaponData.WeaponType, int] = {}
@export var aura: Dictionary[Elemental.Element, int] = {}
@export var affinity: Array[Elemental.Element] = []
@export var is_alkahest_affine := false
@export var affinity_saved := false   # sentinel: empty affinity is a LEGAL value, can't double as "unsaved"
@export var limb_states: Dictionary[UnitInstance.LimbSlot, UnitInstance.LimbState] = {}
@export var limb_prosthetic_stats: Dictionary[UnitInstance.LimbSlot, int] = {}   # placeholder fittings (no real item)
@export var limb_prosthetic_items: Dictionary[UnitInstance.LimbSlot, int] = {}   # index into inventory; re-linked on load

# --- Battle-scoped state (#87): a save is a true mid-battle snapshot, captured explicitly
# (not @export'd on Unit/WeaponInstance, so a mission boundary still resets for free). ---
@export var weapon_battle_states: Dictionary[int, Dictionary] = {}   # inventory index -> that weapon's own keys
@export var element_states: Array[Elemental.State] = []
@export var stat_effects: Array[StatEffect] = []
@export var lifecycle_state: Unit.LifecycleState = Unit.LifecycleState.ACTIVE   # DEAD never saves: a corpse is absent, not stored
@export var downed_turns_remaining := -1   # -1 = not counting, same sentinel Unit uses
@export var in_crisis := false
@export var crisis_surge_pending := false
@export var rally_count := 0
@export var squad_has_acted := false   # LEADER's entry only, beside squad_name/archetype/zone

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
	affinity = inst.affinity.duplicate()
	is_alkahest_affine = inst.is_alkahest_affine
	affinity_saved = true

	var sources: Array[EquippableData] = []   # pre-copy identities, for the index lookups below
	inventory = []
	for item in unit.inventory:
		var equippable := item as EquippableData
		if item != null and equippable == null:
			push_warning("Scenario save: '%s' is not equippable — dropped" % item.display_name)
		if equippable == null:
			continue
		sources.append(equippable)
		inventory.append(equippable.copy_equippable())

	equipped_index = sources.find(unit.get_equipped_weapon())
	if unit.has_equipped_weapon() and equipped_index == -1:
		# equipped directly without an inventory slot (fixtures do this) — save it anyway
		equipped_index = inventory.size()
		inventory.append(unit.get_equipped_weapon().copy_equippable())
	worn_armor_index = sources.find(unit.worn_armor)
	if unit.worn_armor != null and worn_armor_index == -1:
		# worn without an inventory slot (dev/fixtures do this) — save it anyway
		worn_armor_index = inventory.size()
		inventory.append(unit.worn_armor.copy_equippable())

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
		limb_prosthetic_items[slot] = sources.find(fitting.prosthetic_item)
		for i in sources.size():
			var carried := sources[i] as WeaponInstance
			if carried != null and carried.template == fitting.prosthetic_item:
				limb_prosthetic_items[slot] = i
				break

	# By inventory INDEX, like the prosthetic re-link -- two of one family must stay distinct.
	weapon_battle_states = {}
	for i in sources.size():
		var weapon := sources[i] as WeaponInstance
		if weapon == null:
			continue
		var weapon_state = weapon.capture_battle_state()
		if not weapon_state.is_empty():
			weapon_battle_states[i] = weapon_state

	element_states = unit.element_states.duplicate()
	stat_effects = []
	for effect in unit.stat_effects:
		stat_effects.append(effect.duplicate(true))
	lifecycle_state = unit.lifecycle_state
	downed_turns_remaining = unit.downed_turns_remaining
	in_crisis = unit.in_crisis
	crisis_surge_pending = unit.crisis_surge_pending
	rally_count = unit.rally_count

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

	# Affinity before aura: it's the gate aura's legality is judged against.
	if affinity_saved:
		inst.affinity = affinity.duplicate()
		inst.is_alkahest_affine = is_alkahest_affine

	if not aura.is_empty():
		inst.aura = aura.duplicate()   # whole-dict: the seeded pools + growth/tax, saved together

	# Before gear (settling enforces wear gates) and before HP (a +CON effect moves the max).
	unit.restore_stat_effects(stat_effects)

	for i in inventory.size():
		if inventory[i] == null:
			continue
		if not unit.add_item(inventory[i].copy_equippable()):
			push_warning("Scenario load: inventory full — dropped '%s'" % inventory[i].display_name)
	# add_item auto-equips the first equippable; the save's explicit choice wins either way.
	# Direct assign, never the gated door (#157) — a save is authoritative, same as the armor
	# slot below: re-gating would strip a rune off a unit whose aura drifted after saving.
	unit.unequip_weapon()
	if equipped_index >= 0 and equipped_index < unit.inventory.size():
		var chosen := unit.inventory[equipped_index] as EquippableData
		if chosen != null and not chosen is ArmorData:
			unit.equipped_weapon = chosen
	if worn_armor_index >= 0 and worn_armor_index < unit.inventory.size():
		unit.worn_armor = unit.inventory[worn_armor_index] as ArmorData
	else:
		unit.worn_armor = null

	# After the inventory exists, since the index IS the identity.
	for i: int in weapon_battle_states:
		if i < 0 or i >= unit.inventory.size():
			continue
		var weapon := unit.inventory[i] as WeaponInstance
		if weapon != null:
			weapon.apply_battle_state(weapon_battle_states[i])

	for slot in limb_states:
		var fitting: UnitInstance.LimbFitting = inst.limbs[slot]
		fitting.state = limb_states[slot]
		fitting.prosthetic_stat = limb_prosthetic_stats.get(slot, 0)
		fitting.prosthetic_item = null
		var idx: int = limb_prosthetic_items.get(slot, -1)
		if idx >= 0 and idx < unit.inventory.size():
			var carried := unit.inventory[idx] as WeaponInstance
			if carried != null:
				fitting.prosthetic_item = carried   # re-link: the exact carried instance, by index

	unit.element_states = element_states.duplicate()
	unit.in_crisis = in_crisis
	unit.crisis_surge_pending = crisis_surge_pending
	unit.rally_count = rally_count
	unit.restore_lifecycle(lifecycle_state, downed_turns_remaining)

	if current_hp >= 0:
		# Through the UNIT, not inst: armor was restored above, and until #106 this clamp read a
		# gear-less max — so every save/load of an armoured unit quietly shed the band's worth of
		# HP. A data-losing round trip, not just a bad readout.
		unit.set_current_hp(maxi(1, current_hp))   # floor 1: never fire died() out of a load
	if current_will >= 0:
		inst.set_current_will(current_will)
