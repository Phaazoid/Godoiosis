extends Resource
class_name ScenarioUnitEntry

# One saved unit's snapshot inside a ScenarioData (the persistence seam, #8): spawn cell,
# squad membership, and the UnitInstance state that survives missions (#83) — stats, HP,
# Will, inventory, limbs, proficiency, aura, jobs. What ScenarioManager reads on save
# and writes back on load.

@export var unit_data: UnitData
# The reference/snapshot fork (#177) — affinity_saved's pattern widened to the whole state block.
# TRUE (the default, so every pre-#177 save reads as the snapshot it is): the fields below are a
# captured snapshot and apply_unit_state replays them. FALSE: this entry is a REFERENCE — unit_data
# points at a standalone character file, nothing below was captured, and the loader must NOT call
# apply_unit_state (the spawn's own initialize + starting kit are the whole answer).
@export var state_saved := true
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
@export var inventory: Array[Item] = []
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
# The Guard this unit had armed (#414), as an INDEX into ScenarioData.unit_entries — a live Unit ref
# cannot serialize and a name is not unique, so this is the limb_prosthetic_items re-link pattern.
# -1 = guarding nobody. Written and re-linked by ScenarioManager (a pair needs every entry to exist
# first), not by capture_unit_state/apply_unit_state, which only ever see one unit.
@export var guard_ward_index := -1
@export var guard_spent := false

# The Overwatch this unit had armed (#413). Unlike a Guard it names no second unit, so it needs no
# re-link and capture_unit_state/apply_unit_state own it like the rest of the battle state.
#
# `watch_cells` EMPTY is the "no watch" sentinel, and it is the field's own default — a watch with an
# empty footprint is not a thing that can exist (Unit.arm_watch refuses one), so nothing is lost.
# The footprint is STORED rather than re-derived on load: freezing it is the mechanic, and asking
# Reach again would be a second authority for geometry that is deliberately not re-asked.
#
# The attack is an INDEX into the watcher's own selectable attacks rather than a Resource reference —
# equipped_index's pattern, and the reason is #253's: a dangling ext_resource can fail the whole
# scenario load, while a stale index degrades to "no watch". A carving the wielder's aura no longer
# channels is the one way it can drift, and losing the watch is the right answer there anyway.
@export var watch_anchor := Vector2i.ZERO
@export var watch_aim := Vector2i.ZERO
@export var watch_cells: Array[Vector2i] = []
@export var watch_attack_index := -1
@export var watch_spent := false

# Snapshot the unit's persistent side of the seam. Inventory copies via copy_for_grant()
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

	# Every carried thing, not just the slottable ones. This used to drop a non-EquippableData with
	# a push_warning, which was the narrow authoring type showing through as a rule -- #697 widened
	# the three doors to Item and the refusal went with them. `sources` stays index-parallel with
	# `inventory`, which is what the two find() lookups below depend on.
	var sources: Array[Item] = []   # pre-copy identities, for the index lookups below
	inventory = []
	for item: Item in unit.inventory:
		if item == null:
			continue
		sources.append(item)
		inventory.append(item.copy_for_grant())

	equipped_index = sources.find(unit.get_equipped_weapon())
	if unit.has_equipped_weapon() and equipped_index == -1:
		# equipped directly without an inventory slot (fixtures do this) — save it anyway
		equipped_index = inventory.size()
		inventory.append(unit.get_equipped_weapon().copy_for_grant())
	worn_armor_index = sources.find(unit.worn_armor)
	if unit.worn_armor != null and worn_armor_index == -1:
		# worn without an inventory slot (dev/fixtures do this) — save it anyway
		worn_armor_index = inventory.size()
		inventory.append(unit.worn_armor.copy_for_grant())

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

	# The armed watch (#413). A save taken between a pass and the enemy phase is exactly when a live
	# one is the whole point, which is why it is captured here rather than left to reset.
	# Indexed into the WATCH view, not the fireable one (#590) -- the two lists are disjoint now, so
	# a watch attack is not in get_selectable_attacks() at all and the find would never resolve.
	watch_cells = []
	watch_attack_index = -1
	watch_spent = false
	if unit.watch != null and unit.watch.is_intact():
		watch_attack_index = unit.overwatch_attacks().find(unit.watch.attack)
		if watch_attack_index >= 0:
			watch_anchor = unit.watch.anchor_cell
			watch_aim = unit.watch.aim_cell
			watch_cells = unit.watch.footprint.duplicate()
			watch_spent = unit.watch.spent

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

	# A snapshot is authoritative over whatever the spawn seeded (#177): _seed_starting_kit may
	# have already granted a character's kit, and appending the save's copies on top would double
	# it. Direct clears, not remove_item — the limb loop below rebuilds every fitting anyway.
	unit.inventory.fill(null)
	unit.unequip_weapon()
	unit.worn_armor = null

	for i in inventory.size():
		if inventory[i] == null:
			continue
		if not unit.add_item(inventory[i].copy_for_grant()):
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

	# The armed watch (#413), after the inventory, because the stored index IS the attack's identity —
	# the same way weapon_battle_states' index is a weapon's. An index that no longer resolves loses
	# the watch rather than failing the load: a stale reference degrades, it never breaks a board.
	# Same list the capture indexed into (#590): the unit's watch view.
	unit.lapse_watch()
	if not watch_cells.is_empty():
		var watchable := unit.overwatch_attacks()
		if watch_attack_index >= 0 and watch_attack_index < watchable.size():
			unit.arm_watch(watch_anchor, watch_aim, watch_cells.duplicate(),
					watchable[watch_attack_index], watch_spent)

	if current_hp >= 0:
		# Through the UNIT, not inst: armor was restored above, and until #106 this clamp read a
		# gear-less max — so every save/load of an armoured unit quietly shed the band's worth of
		# HP. A data-losing round trip, not just a bad readout.
		unit.set_current_hp(maxi(1, current_hp))   # floor 1: never fire died() out of a load
	if current_will >= 0:
		inst.set_current_will(current_will)
