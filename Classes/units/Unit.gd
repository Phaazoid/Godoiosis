extends Node2D
class_name Unit

#This is a container for everything that is a unit on the map.  These only exist during combat. 
#It owns a MovementComponent (board position + walk animation) and UnitVisuals, delegates attack
#geometry to the static Reach, and references a UnitInstance for everything that outlives a battle.

#Core stats
@onready var movement: MovementComponent = $MovementComponent
@onready var map_sprite: Sprite2D = $MapSprite
@onready var move_sprite: Sprite2D = $MoveSprite
@onready var downed_sprite: Sprite2D = $DownedSprite
@onready var visuals: UnitVisuals = $UnitVisuals
@export var unit_data: UnitData

signal unit_died(unit: Unit)
signal went_downed(unit: Unit)

const MAX_INVENTORY_SIZE := 6 #Balance actual size later
const BASE_SPRITE_INDEX = 4

# --- Rally (in-fight Will relief, will-and-death.md). rally_count is BATTLE-scoped — diminishing
# returns must restart each mission — so it lives here on the transient Unit, not on UnitInstance. ---
const RALLY_BASE := 6       # Will restored by the first rally this battle
const RALLY_FALLOFF := 2    # each further rally restores this much less; below 1 it's not offered

const DOWNED_TURNS := 3     # turns a downed unit survives unrescued; Glossary interpolates it

var rally_count: int = 0
var unit_instance: UnitInstance
# Provenance (#177): the standalone character FILE this unit was spawned from, when there is one.
# Set by UnitFactory (null for form-built or scenario-embedded UnitData). Authored saves read it
# so a cast member serializes as a reference to its file, never as an inline copy.
var unit_data_source: UnitData = null
# A dev tool wrote this unit (#259 rework, dev-ratified): an authored save SNAPSHOTS a dev-edited
# unit instead of re-referencing its character file, so fixture edits (inventory, team, stats)
# persist through Update. Sticky across loads by construction -- the snapshot entry respawns with
# no unit_data_source. Battle-scoped on purpose: it describes this board's session, not the cast.
var dev_edited := false
# Drawn from the mission's Roster by the pre-mission phase (#737) rather than authored onto this
# board. Battle-scoped and non-@export like dev_edited above, and read at exactly one place: an
# AUTHORED capture SKIPS these units. Without that, playing a roster mission and then pressing
# Update writes the drawn force into the file's own unit_entries, and the next boot draws a second
# force on top of it -- silently, into a mission file, from an ordinary evening's authoring.
#
# A save slot captures them like anything else: a resume has to restore the force that was actually
# standing there, which is why this rides the `authored` fork rather than refusing outright.
var drawn_from_roster := false
var inventory : Array[Item] = []
var squad: Squad
var pending_grid : TileMapLayer
var pending_cell : Vector2i
var active_attack: AttackData = null   # the specific attack picked to fire this aim — a carving or a weapon attack (#30 C, generalized #72); null = auto
var equipped_weapon: EquippableData = null
var worn_armor: ArmorData = null   # DEF seam (#55), real content since #89. Carried in `inventory`
								   # like a weapon but filling its OWN slot — set only via
								   # wear_armor(), the one place the wear gate lives.

var _projected_knockback_cell: Vector2i
var _has_projected_knockback := false
var _projected_rescue_cell: Vector2i
var _has_projected_rescue := false

# Battle-scoped elemental states (boolean — you have it or you don't). These live on
# the transient Unit, NOT UnitInstance: they reset each mission, so the per-battle node
# owns them (resolution-pipeline.md persistence seam / elemental fork 3). The resolver
# threads a COPY of this set forward as a hypothetical; live mutation is execution-only.
var element_states: Array[Elemental.State] = []

# --- Temporary stat effects (#112) — THE seam for temporary stats ---
# Battle-scoped, so they live here on the transient Unit, which is why UnitInstance.stat_modifiers
# no longer exists. Deliberately NOT captured by ScenarioUnitEntry, same as element_states.
var stat_effects: Array[StatEffect] = []

# The Guard this unit currently has ARMED (#414) — null when it is guarding nobody. Battle-scoped
# like the states above; unlike them it IS captured by ScenarioUnitEntry, because a save taken
# between a pass and the enemy phase is exactly when a live Guard is the whole point.
# Written only through the four doors below.
var guard: GuardWard = null

# The Overwatch this unit currently has ARMED (#413) — null when it is watching nothing. Same
# battle-scoped-but-SAVED reason as `guard` above: a save taken between a pass and the enemy phase
# is exactly when a live watch is the whole point. Written only through the three doors below.
var watch: Watch = null

# Fired once per settled stat change, for READOUTS only. It is not how plan validity is decided —
# "may this be queued?" is a question about the PROJECTED stat and belongs to SquadPlanValidator
# (#113); answering it in a listener would put Law #2 one race away from breaking.
signal stats_changed

# --- Lifecycle (docs/design/will-and-death.md) ---
# State is battle-scoped: it resets each mission, like element_states, so it lives on the
# transient Unit. (Will — the PERSISTENT resource — lives on UnitInstance. Different sides
# of the persistence seam.)
enum LifecycleState { ACTIVE, DOWNED, DEAD }
var lifecycle_state: LifecycleState = LifecycleState.ACTIVE

# Which rung a would-be-fatal hit lands on is decided by LethalityRules.predict(), NOT here —
# the resolver has to ask the same question at plan time (Law #2), so the ladder and its tuning
# (OVERKILL_CEILING, CRISIS_WILL_GATE) live in one shared place. Unit owns only what happens
# NEXT: take_damage carries the named rung out.

# --- Crisis Mode (will-and-death.md; an equipped ability since #158). A FULL-Will unit holding
# the Crisis ability answers a would-be-down by standing straight back up surged — deterministic,
# previewed, no prompt (the gambit's acceptance happened at loadout). Will locks at 0 and there is
# no safety net (a would-be-down is death) for the rest of the battle. The arming read and the
# gambit's tuning live with the ability roster (Abilities.CRISIS_*); the battle-scoped STATE
# lives here on the transient Unit. ---
var in_crisis: bool = false              # afflicted (skull icon, Will locked, die-on-down) for the battle
var crisis_surge_pending: bool = false   # apply the surge at this unit's next turn start

# Turns remaining before a downed unit dies without rescue. Starts at 3 when
# the unit goes down, ticks once per player-turn start, dies at 0. -1 = not counting.
var downed_turns_remaining: int = -1

signal downed_countdown_changed(turns_remaining: int)

func setup(grid : TileMapLayer, cell: Vector2i):
	pending_grid = grid
	pending_cell = cell

# Called when the node enters the scene tree for the first time.
func _ready():
	# Sized before the guard below: bailing out with a zero-length inventory made every later
	# add_item() fail silently rather than just leaving the unit statless.
	inventory.resize(MAX_INVENTORY_SIZE)

	if unit_data == null:
		push_error("Unit missing UnitData.")
		return

	#This exists because node parent/child relations don't exist until node is added to a tree
	if pending_grid:
		movement.set_grid(pending_grid)
		movement.set_cell(pending_cell)

	unit_instance = UnitInstance.new()
	unit_instance.data = unit_data
	unit_instance.initialize()
	unit_instance.died.connect(_on_instance_died)
	_seed_starting_kit(unit_data)
	map_sprite.z_index = BASE_SPRITE_INDEX
	move_sprite.z_index = BASE_SPRITE_INDEX
	downed_sprite.z_index = BASE_SPRITE_INDEX
	
	if unit_data.map_sprite != null:
		map_sprite.texture = unit_data.map_sprite
	if unit_data.move_sprite != null:
		move_sprite.texture = unit_data.move_sprite
	if unit_data.downed_sprite != null:
		downed_sprite.texture = unit_data.downed_sprite
	_apply_faction_visuals()

# Starting kit (#177): grant what the character file says this unit carries into every board.
# Runs once, right after initialize() — aura is already seeded, so the #157 equip gates read real
# values. Everything goes through the gated doors; a refusal is an AUTHORING error and warns loudly
# rather than silently correcting. A kit-less UnitData makes this a no-op.
#
# Takes its SOURCE rather than reading unit_data (#589): a spawn seeds from this unit's own copy, the
# dev re-seed below seeds from the character FILE. One rule, two callers — and it has to be a
# parameter, because `unit_data` is the duplicate(true) UnitFactory makes, which by the 2026-07-27
# ruling there deliberately stopped tracking the file it came from.
func _seed_starting_kit(source: UnitData) -> void:
	if not source.has_starting_kit():
		return

	for job_id in source.starting_jobs:
		if not unit_instance.add_job(job_id):
			push_warning("%s: starting job '%s' unknown or duplicate — skipped" % [get_unit_name(), job_id])

	for family: WeaponData.WeaponType in source.starting_proficiency:
		unit_instance.set_proficiency(family, source.starting_proficiency[family])

	# Grant copies, never the authored resources; remember where each kit index landed so the
	# explicit picks below address the CARRIED instance.
	var slot_for_kit_index: Dictionary[int, int] = {}
	for i in source.starting_inventory.size():
		var authored := source.starting_inventory[i]
		if authored == null:
			continue
		var granted := authored.copy_equippable()
		var weapon := granted as WeaponInstance
		if weapon != null and weapon.get_script() == WeaponInstance and weapon.template != null \
				and weapon.template.weapon_type != WeaponData.WeaponType.NONE:
			# A hand-inlined inspector weapon misses its family subclass (make() never ran) —
			# readiness/signature mechanics would be silently inert. Reference an Item Editor
			# variant .tres instead.
			push_warning("%s: starting item '%s' is a base-class WeaponInstance for a subclassed family" % [get_unit_name(), granted.display_name])
		if not add_item(granted):
			push_warning("%s: inventory full — starting item '%s' dropped" % [get_unit_name(), authored.display_name])
			continue
		slot_for_kit_index[i] = inventory.find(granted)

	if source.starting_equipped_index >= 0:
		var equip_slot: int = slot_for_kit_index.get(source.starting_equipped_index, -1)
		if equip_slot < 0 or not set_equipped_weapon(inventory[equip_slot]):
			push_warning("%s: starting equipped pick %d refused" % [get_unit_name(), source.starting_equipped_index])

	if source.starting_worn_index >= 0:
		var wear_slot: int = slot_for_kit_index.get(source.starting_worn_index, -1)
		if wear_slot < 0 or not wear_armor(wear_slot):
			push_warning("%s: starting worn pick %d refused" % [get_unit_name(), source.starting_worn_index])

	for limb_slot: UnitInstance.LimbSlot in source.starting_prosthetics:
		var kit_index: int = source.starting_prosthetics[limb_slot]
		var item_slot: int = slot_for_kit_index.get(kit_index, -1)
		var prosthetic := (inventory[item_slot] as WeaponInstance) if item_slot >= 0 else null
		if prosthetic == null or not unit_instance.install_prosthetic(limb_slot, prosthetic):
			push_warning("%s: starting prosthetic for slot %s refused" % [get_unit_name(), UnitInstance.LimbSlot.keys()[limb_slot]])

# --- Dev re-seed (#589) ---

# "" = this unit can be re-seeded. The REASON rather than a bool, so the button that greys can SAY
# why (#166's shape): a form-built or scenario-embedded UnitData has no file to re-read.
func reseed_block_reason() -> String:
	if unit_data_source == null:
		return "%s wasn't spawned from a character file, so there is no authored kit to re-read." % get_unit_name()
	if not unit_data_source.has_starting_kit():
		return "%s's character file authors no starting kit." % unit_data_source.display_name
	return ""

func can_reseed_kit() -> bool:
	return reseed_block_reason() == ""

# Throw this unit's gear away and re-grant it from the character FILE, so a mod fitted in the Item
# Editor or a new starting_inventory entry reaches a unit already standing on the board. DEV ONLY —
# no guard for a running pass or a mid-action actor (dev ruling 2026-08-27: misuse is his, not the
# tool's). Read through unit_data_source, never `unit_data`, which is a copy that stopped tracking
# its file.
#
# GEAR only: jobs and proficiency come along because the file authors them as part of the kit, but
# HP, Will, limb STATE, element states and lifecycle are this unit's battle, not its loadout.
# Battle state (ammo, rev, spring load) resets with the weapons — the grant is a fresh
# copy_equippable, exactly what a spawn hands back.
#
# The clear is DIRECT rather than remove_item, matching ScenarioUnitEntry.apply_unit_state: an
# installed prosthetic refuses to be dropped, and the seed re-links every fitting anyway. Jobs clear
# so the re-grant's add_job isn't refusing what it just held.
func reseed_kit() -> bool:
	var reason := reseed_block_reason()
	if reason != "":
		push_warning(reason)
		return false
	lapse_watch()          # its stamped attack belongs to a weapon that is about to stop existing
	active_attack = null   # ditto the live aim pick
	for limb_slot: UnitInstance.LimbSlot in unit_instance.limbs:
		unit_instance.limbs[limb_slot].prosthetic_item = null
	inventory.fill(null)
	unequip_weapon()
	worn_armor = null
	unit_instance.jobs.clear()
	_seed_starting_kit(unit_data_source)
	return true

# WHY this unit cannot take another thing -- "" means it can (#741, on #744's shape one layer up).
# The inventory is a FIXED array of MAX_INVENTORY_SIZE nulls, so "full" means every slot is spoken
# for rather than a length check. add_item's bare false is derived from this, so a refusal and the
# sentence explaining it cannot drift.
func add_block_reason(_item: Item) -> String:
	for slot: Item in inventory:
		if slot == null:
			return ""
	return "%s is carrying %d of %d." % [get_unit_name(), MAX_INVENTORY_SIZE, MAX_INVENTORY_SIZE]

func add_item(item: Item) -> bool:
	for i in range(inventory.size()):
		if inventory[i] == null:
			inventory[i] = item

			# Auto-equip the first WEAPON-shaped equippable only. ArmorData is an EquippableData
			# too, but it fills a different slot -- auto-equipping it here would "arm" a unit with
			# a vest and shadow the real weapon they pick up next. Armor is never auto-worn: the
			# wear gate makes silent auto-wear ambiguous, so wearing is always an explicit act.
			# Routed through the one gated door (#157): a dead rune lands carried, not equipped.
			if equipped_weapon == null and item is EquippableData and not item is ArmorData:
				set_equipped_weapon(item)

			return true

	return false

func get_map_sprite_texture() -> Texture2D:
	if map_sprite == null:
		return null
	
	return map_sprite.texture 
	
func get_move_texture() -> Texture2D:
	if move_sprite == null:
		return null
	
	return move_sprite.texture
	
func get_unit_name() -> String:
	return unit_data.display_name

# WHY this slot cannot be emptied -- "" means it can (#741). The prosthetic rule used to be a silent
# early return here, which meant anything BUILT on it had to re-ask is_installed_prosthetic and word
# its own refusal: a second gate on one rule, the shape #744 spent a ticket collapsing.
func remove_block_reason(index: int) -> String:
	if index < 0 or index >= inventory.size() or inventory[index] == null:
		return "There is nothing in that slot."
	var weapon := inventory[index] as WeaponInstance
	if weapon != null and unit_instance.is_installed_prosthetic(weapon):
		return "%s is a fitted limb, not carried gear." % weapon.display_name
	return ""

func remove_item(index: int):
	# An installed prosthetic is load-bearing gear, not loose inventory — it can't be dropped.
	if remove_block_reason(index) != "":
		return
	var item := inventory[index]
	if item == equipped_weapon:
		equipped_weapon = null
	if item == worn_armor:
		worn_armor = null
	inventory[index] = null

# Re-settle HP against a max that just moved: a stat change never RAISES current HP, it only
# pulls it down if the new max is below it. Its ONLY caller is _settle_stat_change, so that
# "who re-clamps HP?" has exactly one answer no matter what moved the stat — gear, an expiring
# effect, or a maim.
#
# Cannot kill, and doesn't need a floor to say so: max HP never drops below 1, and a living unit
# is never below 1, so the clamp can't reach the <=0 that emits died(). That invariant is
# currently a content constraint rather than an enforced one — if it ever needs teeth, it belongs
# on get_max_hp (the derivation), not as a floor at every write site.
func reclamp_hp() -> void:
	set_current_hp(get_current_hp())

func apply_stat_effect(effect: StatEffect) -> void:
	if effect == null:
		return
	stat_effects.append(effect.instantiate())
	_settle_stat_change()

# Retire by SOURCE, not by delta — the whole reason this replaced the old bag.
func remove_stat_effects_from(source: String) -> void:
	var kept: Array[StatEffect] = []
	for effect in stat_effects:
		if effect.source_name != source:
			kept.append(effect)
	if kept.size() == stat_effects.size():
		return                      # nothing matched: stay silent rather than fire a no-op signal
	stat_effects = kept
	_settle_stat_change()

func has_stat_effect_from(source: String) -> bool:
	for effect in stat_effects:
		if effect.source_name == source:
			return true
	return false

# One turn of decay, at the OWNING FACTION's turn start (game._run_turn_start_ticks), so a 3-turn
# effect covers three of THIS unit's turns rather than three passes of everyone.
func tick_stat_effects() -> void:
	var kept: Array[StatEffect] = []
	for effect in stat_effects:
		if not effect.tick():
			kept.append(effect)
	if kept.size() == stat_effects.size():
		return
	stat_effects = kept
	_sync_paired_states()
	_settle_stat_change()

# A paired state's clock expiring ends the state itself — and self-heals any marker left without
# its effect, whatever the cause.
func _sync_paired_states() -> void:
	var kept: Array[Elemental.State] = []
	for state in element_states:
		if Elemental.paired_stat_mods(state).is_empty() or has_stat_effect_from(Elemental.state_effect_source(state)):
			kept.append(state)
	if kept.size() != element_states.size():
		element_states = kept

# Everything that has to settle after a stat moves, wherever it moved from. Every mutator ends
# here, so "what happens when a stat changes?" has one answer and one place to extend.
#
# ORDER IS LOAD-BEARING: gates run FIRST (they can strip armour, which moves CON, which moves max
# HP), then HP re-clamps against the settled max. It cannot loop, because gates read get_body_stat
# and so are blind to the gear this may remove.
func _settle_stat_change() -> void:
	_enforce_gear_gates()
	reclamp_hp()
	stats_changed.emit()

# Gear you no longer qualify for comes OFF (#112). It stays in inventory — you're carrying it, just
# not wearing it. Triggered by a buff lapsing, a debuff, or a maim. Two parallel clauses that can't
# cascade: armor's gate reads body stats, a rune's reads aura+affinity (#157) — neither reads gear.
func _enforce_gear_gates() -> void:
	_strip_gear(_gear_failing_gates())

# The same JUDGEMENT with no nulling — "what would come off, standing as this unit stands right now".
# Split out of the enforce above for #742: the job picker asks it of a HYPOTHETICAL body (see
# with_jobs) rather than growing a second reading of the same gates, which is the drift #744 collapsed
# one layer down. One judgement, so the warning and the strip can never name different pieces.
func _gear_failing_gates() -> Array[EquippableData]:
	var failing: Array[EquippableData] = []
	if worn_armor != null and not worn_armor.can_equip(self):
		failing.append(worn_armor)
	if equipped_weapon != null and not equipped_weapon.can_equip(self):
		failing.append(equipped_weapon)
	return failing

# What is actually ON this unit right now, in _gear_failing_gates' own order. The pair those gates
# judge, and the pair a job preview diffs — see gear_lost_under_jobs.
func _worn_gear() -> Array[EquippableData]:
	var worn: Array[EquippableData] = []
	if worn_armor != null:
		worn.append(worn_armor)
	if equipped_weapon != null:
		worn.append(equipped_weapon)
	return worn

# ...and the nulling with no judgement. An INSTALLED PROSTHETIC that stops being wieldable leaves the
# equip slot and stays a limb — _mod_sources reads the fitting, not the slot — so there is deliberately
# nothing here that touches unit_instance.limbs.
func _strip_gear(pieces: Array[EquippableData]) -> void:
	for piece: EquippableData in pieces:
		if piece == worn_armor:
			worn_armor = null
		elif piece == equipped_weapon:
			equipped_weapon = null

func _on_instance_died():
	die()

# The BODY: base → limb → jobs → temporary effects. Everything EXCEPT gear.
#
# This is what wear gates judge against (ArmorData.can_equip). Excluding gear is load-bearing in
# two directions: legality never depends on what you have on, and forced unequip can never cascade.
func get_body_stat(stat: Stats.Stat) -> int:
	return unit_instance.get_effective_stat(stat) + _effect_modifier(stat)

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
	var sources: Array[WeaponInstance] = []
	var held := equipped_weapon as WeaponInstance
	if held != null:
		sources.append(held)
	for slot: UnitInstance.LimbSlot in unit_instance.limbs:
		var fitting: UnitInstance.LimbFitting = unit_instance.limbs[slot]
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
# active_space_count needs a Unit, while UnitInstance.limb_stat(slot) has no wielder to ask.
# The doctrine agrees -- built_in_stat is what the prosthetic IS, a mod is what is bolted to it.
func _gear_modifier(stat: Stats.Stat) -> int:
	return _gear_modifier_for(stat, worn_armor, _mod_sources())

# The walk itself, with the gear handed IN so a hypothetical set can use it (#745). Live and preview
# share this one function: a preview computed by a second walk drifts from the real number the first
# time either side gains a stage, and a number the player is shown before deciding has to be the
# number they get.
func _gear_modifier_for(stat: Stats.Stat, armor: ArmorData, weapons: Array[WeaponInstance]) -> int:
	var total := 0
	if armor != null:
		total += armor.stat_modifiers.get(stat, 0)
	for weapon in weapons:
		for mod in weapon.active_modules(self):
			total += mod.stat_modifiers.get(stat, 0)
	return total

func get_current_hp() -> int:
	return unit_instance.get_current_hp()

func get_mov() -> int:
	return unit_instance.get_mov(get_effective_stat(Stats.Stat.DEX))

# Everything carried, equipped or not: armor and the equipped weapon both live in `inventory`,
# so one sweep covers them. No body term -- weight is gear only.
func get_weight() -> int:
	var total := 0
	for item in inventory:
		if item != null:
			total += item.get_effective_weight()
	return total

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
func previewed_stat(stat: Stats.Stat, candidate: EquippableData) -> int:
	var gear := _candidate_gear(candidate)
	return get_body_stat(stat) + _gear_modifier_for(stat, gear[0], gear[1])


func previewed_def(candidate: EquippableData) -> int:
	var gear := _candidate_gear(candidate)
	return _def_for(gear[0], previewed_stat(Stats.Stat.CON, candidate))


func previewed_weight(candidate: EquippableData, incoming: bool) -> int:
	if candidate == null or not incoming:
		return get_weight()
	return get_weight() + candidate.get_effective_weight()


# The substitution itself: [armor, weapons] with the candidate in whichever slot it fills. A weapon
# displaces the EQUIPPED one rather than joining the list -- a unit swings one thing -- while
# prosthetics stay, because a fitted limb contributes whatever else is in hand.
func _candidate_gear(candidate: EquippableData) -> Array:
	var armor := worn_armor
	var weapons: Array[WeaponInstance] = _mod_sources()
	var as_armor := candidate as ArmorData
	if as_armor != null:
		armor = as_armor
	else:
		var as_weapon := candidate as WeaponInstance
		var held := equipped_weapon as WeaponInstance
		if held != null:
			weapons.erase(held)
		if as_weapon != null and not weapons.has(as_weapon):
			weapons.append(as_weapon)
	return [armor, weapons]


# --- Changing a job (#742) ------------------------------------------------------------------------

# THE one place a job changes for a player. It REPLACES rather than adds, because one-job-at-a-time
# binds at the ROSTER (#731 ruling 10) — the model stays uncapped, since an enemy's held jobs are its
# readable kit (docs/design/jobs.md). "" = done, else why not.
#
# It settles, and that is the whole reason this exists rather than callers reaching into
# unit_instance.jobs: a job moves body stats, and WEAR GATES READ BODY STATS, so a pick can strip the
# armour a unit is standing in. One door means the strip, the HP re-clamp and the signal are not three
# things every caller has to remember.
func set_sole_job(job_id: String) -> String:
	var refusal := job_change_block_reason(job_id)
	if refusal != "":
		return refusal
	unit_instance.jobs.clear()
	if job_id != "":
		unit_instance.add_job(job_id)
	_settle_stat_change()
	return ""

# "" = this unit's job may be set to that. The REASON rather than a bool (#166's shape), so a picker
# that greys can say why it did.
func job_change_block_reason(job_id: String) -> String:
	if unit_instance.jobs.size() > 1:
		return "%s holds %d jobs. This picker sets one, so changing it here would quietly drop the rest." % [
			get_unit_name(), unit_instance.jobs.size()]
	if job_id != "" and JobCatalog.get_job(job_id) == null:
		return "No job with the id '%s' is in the catalogue." % job_id
	return ""


# --- What a job WOULD do (#742) -------------------------------------------------------------------

# Ask a question of this unit as if it held these jobs: the job list is swapped, THE GEAR THE NEW BODY
# CANNOT HOLD IS TAKEN OFF, the question is asked, and all three are put back.
#
# THE GEAR HALF IS NOT AN EXTRA, IT IS THE POINT. Swapping jobs alone answers with the old plate still
# on — DEF would preview unchanged and an ability granted by that plate would not show as lost — so
# the two readings the preview exists for are exactly the two a bare swap cannot produce.
#
# Around a PURE READ only: no await, no signal, no mutation in the question. The alternative is a
# parallel spelling of every wear gate, and a preview that can disagree with the change it is
# previewing is worse than a swap. #745 passed explicit arguments instead for the opposite reason —
# a candidate ITEM is not the unit's yet, so there was no state to lend it.
func with_jobs(job_ids: Array[String], question: Callable) -> Variant:
	var held_jobs: Array[String] = unit_instance.jobs
	var held_armor := worn_armor
	var held_weapon := equipped_weapon
	unit_instance.jobs = job_ids.duplicate()
	_strip_gear(_gear_failing_gates())
	var answer: Variant = question.call()
	unit_instance.jobs = held_jobs
	worn_armor = held_armor
	equipped_weapon = held_weapon
	return answer

# What the wear gates would take off if this unit held these jobs. The piece stays in inventory either
# way — this is what stops being WORN, which is also what does not come back when the old job is picked
# again, and therefore the one consequence of a pick worth warning about before the click.
#
# A DIFF OF THE SAME FUNCTION UNDER BOTH BODIES, not a second reading of the gates: asking
# _gear_failing_gates inside the swap answers "nothing", because with_jobs has already taken those
# pieces off by then. Both sides come from _worn_gear, so the two halves cannot drift.
func gear_lost_under_jobs(job_ids: Array[String]) -> Array[EquippableData]:
	var kept: Array[EquippableData] = with_jobs(job_ids, _worn_gear)
	var lost: Array[EquippableData] = []
	for piece: EquippableData in _worn_gear():
		if not kept.has(piece):
			lost.append(piece)
	return lost

func previewed_stat_for_jobs(stat: Stats.Stat, job_ids: Array[String]) -> int:
	var value: int = with_jobs(job_ids, func() -> int: return get_effective_stat(stat))
	return value

func previewed_def_for_jobs(job_ids: Array[String]) -> int:
	var value: int = with_jobs(job_ids, get_effective_def)
	return value

func previewed_abilities_for_jobs(job_ids: Array[String]) -> Array[AbilityData]:
	var live: Array[AbilityData] = with_jobs(job_ids, get_live_abilities)
	return live


func get_weapon_proficiency(family: WeaponData.WeaponType) -> int:
	return unit_instance.get_proficiency(family)

func get_max_hp() -> int:
	return unit_instance.get_max_hp(get_effective_stat(Stats.Stat.CON))

# The one door for WRITING hp. UnitInstance can't derive its own ceiling (gear and temporary
# effects both live here), so this is where the two halves meet: outside code asks the Unit, it
# never reaches through into the instance and rebuilds the answer.
func set_current_hp(value: int) -> void:
	unit_instance.set_current_hp(value, get_max_hp())

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
# never re-derives from whatever gear happens to be worn. The body still reads worn_armor
# directly; #90b moves it onto the ability kit, at which point immunity stops being an
# armor-specific channel at all — it arrives as an ability, from whatever source granted it.
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
	AbilityData.add_live(live, unit_instance.get_live_abilities())
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

# --- Guard (#414, docs/design/standing-reactions.md) ---
# The four doors on the armed ward. Everything that reads WHETHER a Guard covers a given hit goes
# through PlanResolver; these only own the state's life.

# How far this unit's Guard may hold its pair apart. One answer, three readers (the menu's candidate
# query, the validator's clause, the resolver's range check) — authored on the granting content
# later, the base constant today.
func get_guard_range() -> int:
	return Abilities.GUARD_BASE_RANGE

# The bonus DEF this unit brings to a hit it ABSORBS (the doc's brace bonus). Bare Guard blocks at
# +0; kit raises it. Deliberately NOT part of RulesService.def_breakdown: this applies to one
# substituted instance, not to the unit's standing DEF, and the inspect panel must never show it as
# though a Guard were walking around tougher (Iron Will's cap sits outside the breakdown for the
# same reason).
func get_brace_bonus() -> int:
	return Abilities.BRACE_DEF_BONUS if has_live_ability(Abilities.Id.BRACE) else 0

# `spent` is not a defaulted convenience: a Guard that absorbed a hit during its OWN pass (your
# splash landing after its queue slot) must arm already-used, and GuardAction.execute is the only
# caller that can know — the resolver told it (GuardAction.resolved_spent).
func arm_guard(warded_unit: Unit, ward_range: int, spent := false) -> void:
	if warded_unit == null or not is_instance_valid(warded_unit) or warded_unit == self:
		return
	guard = GuardWard.arm(self, warded_unit, ward_range)
	guard.spent = spent

# Absorbed its one trigger. The ward object stays (spent), rather than clearing: "you already used
# your Guard" and "you never had one" are different facts, and the save round-trip carries both.
func spend_guard() -> void:
	if guard != null:
		guard.spent = true

# The lifetime rule, fired from the owning faction's turn-start tick pass: last turn's Guard is gone
# BEFORE this turn's move phase, which is what makes "no Guard is live during its own faction's move
# phase" structural rather than a special case.
func lapse_guard() -> void:
	guard = null

# The three doors on the armed watch (#413), mirroring the ward's. Whether a watch TRIGGERS on a
# given entry is the resolver's question; these only own the state's life.
#
# `spent` carries the same fact GuardAction.resolved_spent does: a watch its own pass's shove combo
# already fired must arm used, and OverwatchAction.execute is the only caller that can know.
func arm_watch(origin: Vector2i, aim_cell: Vector2i, watched_cells: Array[Vector2i],
		attack: AttackData, spent := false) -> void:
	if attack == null or watched_cells.is_empty():
		return
	watch = Watch.arm(self, origin, aim_cell, watched_cells, attack)
	watch.spent = spent

# Fired its one shot. The watch object stays (spent) for the same reason a spent ward does: "you
# already took your shot" and "you were never watching" are different facts, and both save.
func spend_watch() -> void:
	if watch != null:
		watch.spent = true

# The lifetime rule, from the owning faction's turn-start tick pass beside lapse_guard: a watch that
# nobody walked into is gone before its owner acts again. What drops it EARLY is the anchor rule,
# and that is the resolver's read (Watch.is_anchored) rather than a door here — the watcher can be
# shoved off its cell mid-pass, and a pass mutates copies.
func lapse_watch() -> void:
	watch = null

# The element-state doors own the paired-StatEffect lockstep (Elemental.paired_stat_mods): the
# marker answers "is it chilled", the effect carries the stat change and the clock. The two
# restore paths (ScenarioUnitEntry.apply_unit_state, restore_stat_effects) bypass these doors on
# purpose — a restore replays the RESULT, and both sides round-trip verbatim.
# `turns` overrides the state's default clock (0 = default); only paired states read it.
func add_element_state(state: Elemental.State, turns: int = 0) -> void:
	if state == Elemental.State.NONE:
		return
	if not element_states.has(state):
		element_states.append(state)
	_apply_paired_effect(state, turns)

func remove_element_state(state: Elemental.State) -> void:
	element_states.erase(state)
	if not Elemental.paired_stat_mods(state).is_empty():
		remove_stat_effects_from(Elemental.state_effect_source(state))

func _apply_paired_effect(state: Elemental.State, turns: int) -> void:
	var mods := Elemental.paired_stat_mods(state)
	if mods.is_empty():
		return
	var source := Elemental.state_effect_source(state)
	var requested: int = turns if turns > 0 else Elemental.STATE_DEFAULT_TURNS.get(state, StatEffect.PERMANENT)
	# A re-application refreshes, never stacks: one effect, whichever clock runs longer.
	for effect in stat_effects:
		if effect.source_name == source and effect.turns_remaining > requested:
			requested = effect.turns_remaining
	remove_stat_effects_from(source)
	apply_stat_effect(StatEffect.make(source, mods, requested))

func get_faction() -> Team.Faction:
	return unit_data.faction

# NB: "has squadMATES" — a solo unit still belongs to a managed squad of one.
func has_squad() -> bool:
	return squad != null and squad.has_squadmates()

func is_leader() -> bool:
	return squad.get_leader() == self


func die():
	# Idempotent on purpose: four call sites reach here (the instance's died signal, two branches
	# of take_damage, the downed countdown, plus the dev kill button), and unit_died drives squad
	# teardown in both game.gd and play_session. Every current path is guarded upstream, so this
	# is belt-and-braces -- but the invariant belongs at the one place that can violate it.
	if lifecycle_state == LifecycleState.DEAD:
		return
	lifecycle_state = LifecycleState.DEAD
	unit_died.emit(self)
	queue_free()

func take_damage(damage: int):
	# Lifecycle-aware damage entry -- every damage source calls this. LethalityRules names the
	# rung (the same call PlanResolver makes at plan time, so the preview cannot disagree —
	# Law #2); this function is the only thing that CARRIES it out. Raw HP math stays on
	# UnitInstance; which rung to pay is battle-scoped, so paying it lives here on the Unit.
	match LethalityRules.predict(LethalityRules.situation_for(self), damage):
		ResolvedOutcome.Lethality.NONE:
			if lifecycle_state != LifecycleState.DEAD:
				unit_instance.apply_damage(damage, get_max_hp())   # survivable hit — ordinary HP loss
		ResolvedOutcome.Lethality.KILLED:
			if lifecycle_state == LifecycleState.DEAD:
				return                               # already gone; the flag is preview-only (R9)
			if lifecycle_state == LifecycleState.DOWNED or in_crisis:
				die()                                # Fork 3 / the Crisis gambit: no safety net left
			else:
				unit_instance.apply_damage(damage, get_max_hp())   # HP -> 0 -> died -> _on_instance_died -> die()
		ResolvedOutcome.Lethality.CRISIS:
			# The armed gambit (#158): stand straight back up, never DOWNED — no went_downed, no
			# ejection queueing, no Will down-spend. Exactly what the resolver's hypo threads for
			# this rung, which is what keeps preview and execution one thing with no offer step.
			enter_crisis()
		_:
			# DOWNED and MAIMED are the same execution: go down. spend_will_for_down picks
			# clean-vs-maimed.
			_go_downed()

func heal(amount: int) -> void:
	# take_damage's sibling: same HP door, no lethality check, clamp handles overheal.
	set_current_hp(get_current_hp() + amount)

# The downed STATE. Its PRICE is the one opt-out: spend_will_for_down is the only source of a
# maim-on-down, so skipping it is the whole of what a costless down means.
func _go_downed(pay_will_cost := true):
	lifecycle_state = LifecycleState.DOWNED
	set_current_hp(1)  # clings at 1 HP (stub) — stays >0, so no death emission
	if pay_will_cost:
		unit_instance.spend_will_for_down()  # pays the flat Will cost; maims (limb + Will->0) if it can't afford it
		_settle_stat_change()                # a maim moves STR/DEX, which can drop the wearer under a gate
	downed_turns_remaining = DOWNED_TURNS
	_show_downed_sprite(true)
	went_downed.emit(self)
	downed_countdown_changed.emit(downed_turns_remaining)

# Dev bypass (#156), the inverse of revive(): straight into DOWNED with none of the ladder's
# consequences — no Will spend, no maim, no Crisis however the unit is armed. take_damage stays the
# only rule-governed way down. The guard keeps a second press from reseeding a downed unit's clock.
func force_down() -> void:
	if lifecycle_state != LifecycleState.ACTIVE:
		return
	_go_downed(false)

func tick_downed_countdown():
	if lifecycle_state != LifecycleState.DOWNED:
		return
	downed_turns_remaining -= 1
	downed_countdown_changed.emit(downed_turns_remaining)
	if downed_turns_remaining <= 0:
		die()

func _show_downed_sprite(downed: bool):
	# Default downed art lives on $DownedSprite (per-unit override applied in _ready). Revive
	# flips this back. Visibility swap keeps MapSprite as the single texture for everything else.
	map_sprite.visible = not downed
	downed_sprite.visible = downed

func is_active() -> bool:
	return lifecycle_state == LifecycleState.ACTIVE

func is_downed() -> bool:
	return lifecycle_state == LifecycleState.DOWNED

# DECLARED three-way split (re-verified #104, guard declared on UnitInstance.permadead):
# THIS is "went down the permanent path this mission" and is the only one anything reads.
# UnitInstance.is_dead() is `current_hp <= 0` (currently zero call sites); permadead is
# "never fields again" (unwired). Don't add a fourth, and don't rename any of them to `dead`.
func is_dead() -> bool:
	return lifecycle_state == LifecycleState.DEAD

func _apply_faction_visuals():
	match unit_data.faction:
		Team.Faction.PLAYER:
			modulate = Color.WHITE
		Team.Faction.ENEMY:
			modulate = Color(1, 0.6, 0.6)
		Team.Faction.OTHER:
			modulate = Color(0.6, 0.8, 1)
		_:
			modulate = Color.WHITE

func change_faction(new_faction: Team.Faction):
	unit_data.faction = new_faction
	_apply_faction_visuals()

func has_main_action_queued() -> bool:
	for action in squad.action_queue:
		if action.actor == self and action.is_main_action():
			return true
	return false

func has_action_type_queued(actiontype: BaseAction.ActionType) -> bool:
	for action in squad.action_queue:
		if action.actor == self:
			if action.action_type == actiontype:
				if action.action_type == BaseAction.ActionType.MOVE and action.is_hold_position:  #treat hold moves like not having a move queued
					return false
				else:
					return true
	return false

func has_valid_move_queued() -> bool:
	if self.has_action_type_queued(BaseAction.ActionType.MOVE):
		var move = self.get_move_action()
		if move.is_valid:
			return true
	return false
	
func get_move_action() -> MoveAction:
	for action in squad.get_actions():
		if action.actor == self and action.action_type == BaseAction.ActionType.MOVE:
			return action
	return null
	
func has_any_actions() -> bool:
	for action in squad.get_actions():
		if action.actor == self:
			return true
	return false

# A queued blowback's landing cell, so this unit's projected position reflects the shove (#84,
# approach B): counter derivation, attack re-targeting, and the board preview all read one source.
# Set/cleared by SquadManager.resolve_plan each pass; a unit's OWN queued move still wins.
func set_projected_knockback(cell: Vector2i) -> void:
	_projected_knockback_cell = cell
	_has_projected_knockback = true

func clear_projected_knockback() -> void:
	_has_projected_knockback = false

# The same shape one displacement later (#116): a queued rescue HAULS a body it cannot leave where it
# lies out onto the bank, so the board draws it there rather than jumping it on Execute. What is
# published is the cell STAMPED on the order — the one the player picked — never a fresh derivation,
# so the drawing cannot disagree with what executes. Published by the same SquadManager.resolve_plan
# pass and cleared beside the shove above; the clearing is what keeps RulesService.rescue_landings
# from reading its own last answer as the body's position.
func set_projected_rescue(cell: Vector2i) -> void:
	_projected_rescue_cell = cell
	_has_projected_rescue = true

func clear_projected_rescue() -> void:
	_has_projected_rescue = false

# --- Projected position: the ONE derivation (#105) ---
# Every "where will this unit end up?" question resolves through here. Two callers want genuinely
# different things, and the two axes below are the ONLY legitimate differences between them —
# anything else answering this question is a duplicate seam (Design law #4).
#
#   require_valid  An invalid move doesn't move anyone. TRUE everywhere EXCEPT plan validation,
#                  which runs inside the fixed-point loop that COMPUTES is_valid and would
#                  otherwise read its own half-finished output.
#   use_published  Fall back to a displacement a resolve pass PUBLISHED onto this unit — a shove's
#                  landing (#84) or a rescue's haul (#116). TRUE everywhere EXCEPT plan validation:
#                  both come out of a resolve pass that reads validity, so letting validity read
#                  them back would close the loop. It was `use_knockback` until #116 gave the
#                  resolve a second thing to publish; the axis is unchanged, its name was just one
#                  displacement narrower than its reason.
#
# `actions` is passed rather than read off the squad because the hover preview validates a
# HYPOTHETICAL queue (SquadManager.validate_squad_plan_preview).
static func projected_cell(unit: Unit, actions: Array[BaseAction], require_valid: bool, use_published: bool) -> Vector2i:
	# A rescue beats everything, because it runs LAST — the side channel, after every move and shove
	# has played back. Same "later wins" reasoning that makes a real move beat a shove below.
	if use_published and unit._has_projected_rescue:
		return unit._projected_rescue_cell
	var shoved: bool = use_published and unit._has_projected_knockback
	for action in actions:
		if action.actor != unit or action.action_type != BaseAction.ActionType.MOVE:
			continue
		if require_valid and not action.is_valid:
			continue
		# A hold-position move means "not going anywhere under my own power" — a shove still moves
		# you, so it wins. A REAL move beats the shove: you walked out from under it. A walk the
		# pass HALTED (#413) did not: it was stopped where the shot found it.
		if shoved and (action.is_hold_position or (action as MoveAction).was_halted()):
			return unit._projected_knockback_cell
		return action.get_destination()
	return unit._projected_knockback_cell if shoved else unit.movement.cell

# The INVERSE of projected_cell: which unit ENDS UP on this cell? Derived from the forward answer
# rather than re-implemented — the old version scanned MOVE orders, which meant it could not see a
# knocked-back unit at all and only ever looked at one squad (#105). Takes the unit set explicitly
# for the same reason the forward version takes the action list: callers legitimately have
# different sets, and there is one rule.
static func projected_unit_at(units: Array[Unit], cell: Vector2i) -> Unit:
	for unit in units:
		if is_instance_valid(unit) and unit.get_projected_destination() == cell:
			return unit
	return null

# The live reading: my own squad's real queue, validity honoured, shoves included.
func get_projected_destination() -> Vector2i:
	if squad == null:
		return movement.cell   # spawned but not yet squadded — game.spawn_unit's one-line window
	return projected_cell(self, squad.get_actions(), true, true)
	
func get_equipped_weapon() -> EquippableData:
	return equipped_weapon

func has_equipped_weapon() -> bool:
	return equipped_weapon != null

# THE door into the weapon slot (#157): equip_weapon_from_inventory and add_item's auto-equip
# both route through here, so the equip gate has exactly one home. Scenario load deliberately
# does not — a save is authoritative (ScenarioUnitEntry.apply_unit_state).
func set_equipped_weapon(weapon: EquippableData) -> bool:
	if weapon == null:
		equipped_weapon = null
		return true

	if not inventory.has(weapon):
		return false

	if weapon is ArmorData:
		return false   # armor fills its OWN slot -- wear_armor() is the door, same as the other two

	if not weapon.can_equip(self):
		return false   # a rune with nothing channelable is carryable, never wieldable (#157)

	equipped_weapon = weapon
	return true

func can_wield_equipped() -> bool:
	# Verb lock: any missing arm locks two-handed patterns. One-handed kit is unaffected.
	var weapon := get_equipped_weapon() as WeaponInstance
	if weapon == null or weapon.template == null or not weapon.template.two_handed:
		return true
	return not unit_instance.has_missing_arm()

func can_rescue_carry() -> bool:
	return not unit_instance.has_missing_arm()

func equip_weapon_from_inventory(index: int) -> bool:
	if index < 0 or index >= inventory.size():
		return false

	var item := inventory[index]
	if item == null:
		return false

	if not item is EquippableData:
		return false

	return set_equipped_weapon(item)   # armor refusal + the equip gate live at the one door (#157)

func unequip_weapon():
	equipped_weapon = null

func wear_armor(index: int) -> bool:
	# The ONE chokepoint where armor gets worn, so the wear gate has exactly one place to live.
	if index < 0 or index >= inventory.size():
		return false
	var armor := inventory[index] as ArmorData
	if armor == null:
		return false
	if not armor.can_equip(self):
		return false
	worn_armor = armor
	_settle_stat_change()
	return true

func remove_armor():
	worn_armor = null
	_settle_stat_change()

func revive():
	# Rescue brings a downed unit back up — ACTIVE again, still at 1 HP (no heal). It stays in
	# its solo squad; rescue does NOT auto-rejoin the old one (per design).
	if lifecycle_state != LifecycleState.DOWNED:
		return
	lifecycle_state = LifecycleState.ACTIVE
	downed_turns_remaining = -1
	_show_downed_sprite(false)

func next_rally_amount() -> int:
	return RALLY_BASE - RALLY_FALLOFF * rally_count

func can_rally() -> bool:
	# Offered while the next rally restores >= 1 Will and there's room to restore into.
	# Crisis locks Will at 0 for the battle, so Rally is refused outright.
	return is_active() and not in_crisis and next_rally_amount() >= 1 and unit_instance.get_current_will() < unit_instance.get_max_will()

func rally() -> void:
	var amount := next_rally_amount()
	if amount < 1:
		return
	unit_instance.set_current_will(unit_instance.get_current_will() + amount)
	rally_count += 1
	
func enter_crisis():
	# The armed gambit fires (take_damage's CRISIS rung, #158): up at CRISIS_REVIVE_HP, Will locked
	# at 0, surge primed for next turn, no safety net for the rest of the battle. Called on a unit
	# that never went DOWNED, so the lifecycle/clock/sprite resets are usually no-ops — kept because
	# they make this function total over any state it could ever be reached from.
	in_crisis = true
	lifecycle_state = LifecycleState.ACTIVE
	downed_turns_remaining = -1
	_show_downed_sprite(false)
	set_current_hp(Abilities.CRISIS_REVIVE_HP)
	unit_instance.set_current_will(0)                         # locked: can_rally() refuses while in_crisis
	crisis_surge_pending = true

func advance_crisis_surge():
	# Called at this unit's faction-turn start. Primed on ENTRY and applied on the NEXT turn start,
	# which keeps the Crisis-entry pass to "survives standing" only (will-and-death.md ripple
	# containment) — that timing is unchanged. EXPIRY is no longer this function's business: the
	# surge is a StatEffect with a duration, and tick_stat_effects retires it. The old +5/-5 pair
	# had to be balanced by hand and had already gone permanent once (#112).
	if not crisis_surge_pending:
		return
	crisis_surge_pending = false
	var mods: Dictionary[Stats.Stat, int] = {}
	for stat in Abilities.CRISIS_SURGE_STATS:
		mods[stat] = Abilities.CRISIS_SURGE
	apply_stat_effect(StatEffect.make(Abilities.CRISIS_SURGE_SOURCE, mods, Abilities.CRISIS_SURGE_TURNS))

func get_element_aura(element: Elemental.Element) -> int:
	if unit_instance == null:
		return 0
	return unit_instance.get_element_aura(element)

func has_any_affinity() -> bool:
	return unit_instance != null and unit_instance.has_any_affinity()

# --- What this unit fires ---
# Each question is asked of the EQUIPPABLE, which answers for its own kind (EquippableData's
# attack-source surface). Unit used to fork on `as RuneData` / `as WeaponInstance` in every one
# of these; the kind-specific behaviour now lives with the kind, and an empty slot is the only
# case Unit still handles.

# active_attack (the player's live pick) always wins when set — reset at the start of
# MainActionMenu.begin_attack, so it's fresh for the unit's OWN declared aim. #30 B2/#72.
func get_fired_attack() -> AttackData:
	if active_attack != null:
		return active_attack
	if equipped_weapon == null:
		return null
	return equipped_weapon.default_attack(self)

# The full menu of attacks this unit could choose to fire — the pick-menu at attack entry.
func get_selectable_attacks() -> Array[AttackData]:
	if equipped_weapon == null:
		return []
	return equipped_weapon.selectable_attacks(self)

# The equipped WEAPON's non-main attacks — surfaced under the Weapon Action menu (2026-07-24).
# Empty for a rune or an empty slot. A rune's carvings are the OTHER side of this fork
# (choice_attacks -> the Transmutation category, #88), never Weapon Action and no longer
# a submenu hanging off Attack.
func get_weapon_secondary_attacks() -> Array[AttackData]:
	if equipped_weapon == null:
		return []
	return equipped_weapon.secondary_attacks(self)

# Which of this unit's attacks may be declared as a WATCH (#413) -- normally exactly one, since a
# weapon carries one Overwatch action rather than a menu of them (dev, 2026-08-26). ONE answer, two
# readers -- the kit-slice gate below and the menu's Overwatch rows -- so the slice can never offer
# a watch that picks nothing, or hide one the unit could take.
#
# Reads the equipped source's WATCH view, never the fireable one it used to filter (#590): the two
# are disjoint now, so filtering the fire list here would come back empty every time.
func overwatch_attacks() -> Array[AttackData]:
	if equipped_weapon == null:
		return []
	return equipped_weapon.watch_attacks(self)

# Does the Weapon Action submenu have anything ACTIONABLE right now? A weapon self-ability (rev /
# reload), a fireable secondary attack, OR a watchable attack it could fire right now -- #413 made
# Overwatch a weapon action, so the slice has to open for it. Mere existence isn't enough -- a
# mace's Blowback that can't fire yet (0 charge) must not light up the button. Unfireable picks
# still LIST (disabled) inside the submenu once something else opens it. Runes never qualify (the
# ability queries fail the cast).
func has_weapon_actions() -> bool:
	if can_rev_weapon() or can_reload_weapon() or can_burrow_weapon():
		return true
	for atk in get_weapon_secondary_attacks():
		if is_attack_fireable(atk):
			return true
	for atk in overwatch_attacks():
		if is_attack_fireable(atk):
			return true
	return false

# --- The Transmutation submenu (#88) ---

func get_transmutation_choices() -> Array[AttackData]:
	if equipped_weapon == null:
		return []
	return equipped_weapon.choice_attacks(self)

# Does the category have anything ACTIONABLE right now? Exactly has_weapon_actions()'s rule and
# exactly its loop: a carving you can't pay for still LISTS (greyed) inside the submenu, but it
# must not light up the row on its own (#166 — get_transmutation_choices became the full
# catalogue). Any ONE channelable carving is enough — deliberately NOT "2 or more": with one
# carving this duplicates what Attack fires, and that's accepted, because the submenu is a READOUT
# as much as a picker. Dev call 2026-07-29.
func has_transmutations() -> bool:
	for atk in get_transmutation_choices():
		if is_attack_fireable(atk):
			return true
	return false

# What a COUNTER fires — deliberately separate from get_fired_attack(), because the two kinds
# diverge on whether the live pick counts: a rune counters with whatever it would currently fire
# (#30 quirk), a weapon ALWAYS counters with main (#72). Each kind states its own answer.
func get_counter_attack() -> AttackData:
	if equipped_weapon == null:
		return null
	return equipped_weapon.counter_attack(self)

# This attack's shove and ally-splash as the EQUIPPED SOURCE reports them (#529) -- a fitted mod
# may edit either. Thin delegators, the get_counter_attack shape: they live here because the two
# readers (PlanResolver's shove, RulesService's victim gather) hold a Unit and no weapon, and
# re-deriving the equipped source at each would be two answers to one question.
func get_attack_knockback(attack: AttackData) -> int:
	if equipped_weapon == null:
		return attack.knockback if attack != null else 0
	return equipped_weapon.effective_knockback(self, attack)

func attack_hits_allies(attack: AttackData) -> bool:
	if equipped_weapon == null:
		return attack != null and attack.hits_allies
	return equipped_weapon.effective_hits_allies(self, attack)

# Whether this attack may be declared as a standing watch (#413) -- same delegation, same reason:
# the menu holds a Unit, and the answer is the equipped source's to give once a mod may edit it.
func attack_can_overwatch(attack: AttackData) -> bool:
	if equipped_weapon == null:
		return attack != null and attack.can_overwatch
	return equipped_weapon.effective_can_overwatch(self, attack)

# Does this unit's CURRENT attack source permit a counter? #30/#72: reads get_counter_attack(),
# never the live selection — see that method's header for why. Since #84 the counter attack must
# also be FIREABLE: an empty Carbine magazine (and, latently since #73, a sprung Springspear whose
# Stab requires_readiness) can't counter with an attack the menu already refuses. A counter that
# DOES land spends whatever its main consumes — AttackAction.execute()'s post-fire hook.
func attack_source_can_counter() -> bool:
	var atk := get_counter_attack()
	return atk != null and atk.can_counter and is_attack_fireable(atk)

# Why this unit can't fire this attack right now, in the equipped source's own words — "" when it
# can. Asked of the EQUIPPABLE, which owns its economy: a weapon answers readiness, a rune answers
# aura (#166). An empty slot and a null attack both answer "" — see is_attack_fireable below.
func attack_block_reason(attack: AttackData) -> String:
	if attack == null or equipped_weapon == null:
		return ""
	return equipped_weapon.attack_block_reason(self, attack)

# What this attack does for this unit, for hover readouts. Same delegation, different question.
func attack_detail(attack: AttackData) -> String:
	if attack == null or equipped_weapon == null:
		return ""
	return equipped_weapon.attack_detail(self, attack)

# Readiness seam (#73), widened to aura by #166 — and DERIVED from the reason above rather than
# re-asking, so a greyed menu row and a refused order can never disagree about what is fireable.
# Note it now answers false for an unchannelable carving, which it could not before: the rune's
# list was pre-filtered, so the question never reached here. That makes the queue-time gate
# (AttackAction.actor_can_perform) refuse one too, which is the correct reading of strict queueing.
func is_attack_fireable(attack: AttackData) -> bool:
	return attack_block_reason(attack).is_empty()

func has_any_fireable_attack() -> bool:
	for a in get_selectable_attacks():
		if is_attack_fireable(a):
			return true
	return false
	
# Can the ATTACK entry offer anything? It gates on the ONE default attack, which the action ring
# then lists by its own name (#467 — there is no generic "Attack" row any more). Deliberately NOT
# get_fired_attack(): that returns a live active_attack, i.e. an aiming cursor left over from a
# previous aim, so the gate would judge the entry by an attack it will never fire (#102).
# A weapon with NO main attack (the #80 data-rot shape) fires nothing, so the entry closes:
# is_attack_fireable(null) answers true (null isn't a WeaponAttackData), which is the right
# answer to "is this gated?" and the wrong one to "is there anything here?".
func can_fire_default_attack() -> bool:
	var atk := get_default_attack()
	return atk != null and is_attack_fireable(atk)

# What this unit swings if it just attacks -- a weapon's authored main, a rune's first channelable
# carving. A thin delegator to whatever is equipped, the same shape as get_weapon_secondary_attacks
# beside it; the action ring lists it by its own NAME since #467, so it needs a public reader.
func get_default_attack() -> AttackData:
	if equipped_weapon == null:
		return null
	return equipped_weapon.default_attack(self)

# --- The equipped thing's self-abilities ---
# Each is asked of the EQUIPPABLE, which answers for its own kind — same pattern as the attack
# surface above. These used to open with `get_equipped_weapon() as WeaponInstance` seven times
# over; the inert defaults now live on EquippableData, so an empty slot is the only case left
# for Unit to handle. Families override the real behaviour (Chainsword revs, Carbine and
# Springspear reload, Drill burrows).

func can_reload_weapon() -> bool:
	return equipped_weapon != null and equipped_weapon.can_reload()

func reload_weapon() -> void:
	if equipped_weapon != null:
		equipped_weapon.reload()

func reload_label() -> String:
	return equipped_weapon.reload_label() if equipped_weapon != null else "Reload"

func can_rev_weapon() -> bool:
	return equipped_weapon != null and equipped_weapon.can_rev()

func rev_weapon() -> void:
	if equipped_weapon != null:
		equipped_weapon.rev()

func tick_weapon_rev() -> void:
	if equipped_weapon != null:
		equipped_weapon.tick_rev()

func can_burrow_weapon() -> bool:
	return equipped_weapon != null and equipped_weapon.can_burrow()

# --- Restoring battle state from a mid-battle save (#87) ---
# Replays the RESULT, never the EVENT: the normal entry points (_go_downed, apply_stat_effect)
# have side effects a restore must not repeat (squad ejection, Will spend, countdown reseed).

func restore_lifecycle(state: LifecycleState, turns_remaining: int) -> void:
	lifecycle_state = state
	downed_turns_remaining = turns_remaining
	_show_downed_sprite(state == LifecycleState.DOWNED)

func restore_stat_effects(effects: Array[StatEffect]) -> void:
	stat_effects.clear()
	for effect in effects:
		if effect != null:
			stat_effects.append(effect.duplicate(true))
	_settle_stat_change()
