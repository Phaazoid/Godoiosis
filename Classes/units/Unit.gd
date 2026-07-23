extends Node2D
class_name Unit

#This is a container for everything that is a unit on the map.  These only exist during combat. 
#These have different components (movement, combat) that allow them to work, and reference specific UnitInstances to get their data. 

#Core stats
@onready var combat: CombatComponent = $CombatComponent
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

var rally_count: int = 0
var unit_instance: UnitInstance
var inventory : Array[Item] = []
var squad: Squad
var pending_grid : TileMapLayer
var pending_cell : Vector2i
var active_attack: AttackData = null   # the specific attack picked to fire this aim — a carving or a weapon attack (#30 C, generalized #72); null = auto
var equipped_weapon: EquippableData = null
var worn_armor: ArmorData = null   # DEF seam (#55): fixture-level until the armor content pass

# Battle-scoped elemental states (boolean — you have it or you don't). These live on
# the transient Unit, NOT UnitInstance: they reset each mission, so the per-battle node
# owns them (resolution-pipeline.md persistence seam / elemental fork 3). The resolver
# threads a COPY of this set forward as a hypothetical; live mutation is execution-only.
var element_states: Array[Elemental.State] = []

# --- Lifecycle (docs/design/will-and-death.md) ---
# State is battle-scoped: it resets each mission, like element_states, so it lives on the
# transient Unit. (Will — the PERSISTENT resource — lives on UnitInstance. Different sides
# of the persistence seam.)
enum LifecycleState { ACTIVE, DOWNED, DEAD }
var lifecycle_state: LifecycleState = LifecycleState.ACTIVE

# The rung a would-be-fatal hit lands on. STUB: only DOWN/KILL exist today; MAIM (Will-
# exhausted) and CRISIS join once the Will resource + Forks 2-3 land. Runtime-only enum,
# so it can grow freely.
enum LethalRung { DOWN, KILL }

# Stub overkill ceiling: a hit exceeding remaining HP by more than this kills outright
# (will-and-death.md rung 3 — so low-HP units aren't immortal). Tune to taste; replaced
# by Will math later.
const OVERKILL_CEILING := 10

# --- Crisis Mode (opt-in gambit; will-and-death.md, #33). Offered as a live interrupt when a
# FULL-Will unit would go down: accept -> up at low HP with a one-turn scaling-stat surge, but
# Will locks at 0 and there is no safety net (a would-be-down is death) for the rest of the
# battle. All of this is battle-scoped, so it lives here on the transient Unit. ---
const CRISIS_WILL_GATE := UnitInstance.MAX_WILL        # full Will (20) — an identity gate (placeholder)
const CRISIS_REVIVE_HP := 5                            # HP the unit stands back up with (placeholder)
const CRISIS_SURGE := 5                                # +this to each scaling stat for the surge turn (placeholder)
const CRISIS_SURGE_STATS: Array[Stats.Stat] = [Stats.Stat.STR, Stats.Stat.DEX, Stats.Stat.PER]  # "scaling stats" (assumption)

var in_crisis: bool = false              # afflicted (skull icon, Will locked, die-on-down) for the battle
var crisis_offered_pending: bool = false # this down qualified for the offer (set at down-time, read post-pass)
var crisis_surge_pending: bool = false   # apply the surge at this unit's next turn start
var crisis_surge_active: bool = false    # surge is currently applied (cleared at the following turn start)

# Turns remaining before a downed unit dies without rescue. Starts at 3 when
# the unit goes down, ticks once per player-turn start, dies at 0. -1 = not counting.
var downed_turns_remaining: int = -1

signal downed_countdown_changed(turns_remaining: int)

func setup(grid : TileMapLayer, cell: Vector2i):
	pending_grid = grid
	pending_cell = cell

# Called when the node enters the scene tree for the first time.
func _ready():
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
	inventory.resize(MAX_INVENTORY_SIZE)
	unit_instance.died.connect(_on_instance_died)
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

func add_item(item: Item) -> bool:
	for i in range(inventory.size()):
		if inventory[i] == null:
			inventory[i] = item

			if equipped_weapon == null and item is EquippableData:
				equipped_weapon = item

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

func remove_item(index: int):
	if index >= 0 and index < inventory.size():
		var item := inventory[index]
		if unit_instance.is_installed_prosthetic(_template_of(item)):
			return
		if item == equipped_weapon:
			equipped_weapon = null
		inventory[index] = null
		
func _on_instance_died():
	die()

func get_base_stat(stat: Stats.Stat) -> int:
	if unit_instance == null:
		return -1
	return unit_instance.get_base_stat(stat)

func get_effective_stat(stat: Stats.Stat) -> int:
	return unit_instance.get_effective_stat(stat)

func get_modifier(stat: Stats.Stat) -> int:
	return unit_instance.stat_modifiers.get(stat, 0)

func get_current_hp() -> int:
	return unit_instance.get_current_hp()

func get_mov() -> int:
	return unit_instance.get_mov(_gear_weight())

func get_weight() -> int:
	return unit_instance.get_weight(_gear_weight())

func get_weapon_proficiency(family: WeaponData.WeaponType) -> int:
	return unit_instance.get_proficiency(family)

func _gear_weight() -> int:
	var weapon := get_equipped_weapon() as WeaponInstance
	return weapon.get_effective_weight() if weapon != null else 0

func get_max_hp() -> int:
	return unit_instance.get_max_hp()

func get_effective_ldr() -> int:
	return unit_instance.get_effective_ldr()

func get_effective_def() -> int:
	# DEF is gear-only (stats.md); the CON math lives with the stat doctrine in Stats.
	if worn_armor == null:
		return 0
	return Stats.armor_def(worn_armor.def_power, get_effective_stat(Stats.Stat.CON))

func has_element_state(state: Elemental.State) -> bool:
	return element_states.has(state)

func add_element_state(state: Elemental.State) -> void:
	if state == Elemental.State.NONE:
		return
	if not element_states.has(state):
		element_states.append(state)

func remove_element_state(state: Elemental.State) -> void:
	element_states.erase(state)

func _template_of(item: EquippableData) -> WeaponData:
	var weapon := item as WeaponInstance
	return weapon.template if weapon != null else null

func get_all_stats() -> Dictionary:
	var result := {}
	for stat in unit_data.base_stats.keys():
		result[stat] = get_base_stat(stat)
	return result

func get_faction() -> Team.Faction:
	return unit_data.faction

func has_squad() -> bool:
	if squad.get_members().size() == 1:
		return false
	else:
		return true

func is_leader() -> bool:
	if squad.get_leader() == self:
		return true
	else:
		return false
	
func die():
	lifecycle_state = LifecycleState.DEAD
	unit_died.emit(self)
	queue_free()

func take_damage(damage: int):
	# Lifecycle-aware combat damage entry (CombatComponent routes here). Raw HP math stays
	# on UnitInstance; the down/kill DECISION is battle-scoped, so it lives here on the Unit.
	if lifecycle_state == LifecycleState.DEAD:
		return
	if lifecycle_state == LifecycleState.DOWNED:
		die()                                   # Fork 3 (provisional): hitting a downed unit kills it
		return
	var hp := get_current_hp()
	if damage < hp:
		unit_instance.apply_damage(damage)      # survivable hit — ordinary HP loss, no rung decision
		return
	# Would-be-fatal: pick the rung instead of dying automatically.
	if in_crisis:
		die()   # Crisis traded the safety net away — a would-be-down is death now (will-and-death.md)
		return
	match _select_lethal_rung(damage, hp):
		LethalRung.KILL:
			unit_instance.apply_damage(damage)  # HP -> 0 -> died -> _on_instance_died -> die()
		LethalRung.DOWN:
			_go_downed()

func _select_lethal_rung(damage: int, hp: int) -> LethalRung:
	# STUB of will-and-death.md's deterministic stakes ladder. No Will yet:
	#   overkill (exceeds remaining HP by more than the ceiling) -> KILL (rung 3)
	#   otherwise                                                -> DOWN (rung 1, the safe down)
	# Rungs 2 (MAIM / Will-exhausted) and 4 (CRISIS) are gated on the Will resource + forks.
	# This is the SINGLE home of the rung decision: when the resolution pipeline grows its
	# Will stage (resolution-pipeline.md R7), it calls this at plan time and the preview
	# renders the result (Law #2). Today it runs only at execution time.
	var overkill := damage - hp
	if overkill > OVERKILL_CEILING:
		return LethalRung.KILL
	return LethalRung.DOWN

func _go_downed():
	crisis_offered_pending = is_crisis_eligible()  # capture BEFORE spend — eligibility reads FULL Will
	lifecycle_state = LifecycleState.DOWNED
	unit_instance.set_current_hp(1)  # clings at 1 HP (stub) — stays >0, so no death emission
	unit_instance.spend_will_for_down()  # pays the flat Will cost; maims (limb + Will->0) if it can't afford it
	downed_turns_remaining = 3
	_show_downed_sprite(true)
	went_downed.emit(self)
	downed_countdown_changed.emit(downed_turns_remaining)

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
	
func get_unit_actions() -> Array[BaseAction]:
	var actions = []
	for action in squad.get_actions():
		if action.actor == self:
			actions.append(action)
	return actions
	
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

func get_projected_destination() -> Vector2i:
	for action in squad.get_actions():
		if action.actor == self and action.action_type == BaseAction.ActionType.MOVE and action.is_valid:
			return action.get_destination()
	return self.movement.cell
	
func get_equipped_weapon() -> EquippableData:
	return equipped_weapon

func has_equipped_weapon() -> bool:
	return equipped_weapon != null

func set_equipped_weapon(weapon: EquippableData) -> bool:
	if weapon == null:
		equipped_weapon = null
		return true

	if not inventory.has(weapon):
		return false

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

	equipped_weapon = item
	return true

func unequip_weapon():
	equipped_weapon = null

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
	
func is_crisis_eligible() -> bool:
	# Crisis gates on a FULL Will pool (will-and-death.md) — an identity gate, faction-agnostic
	# since #57. Eligibility is universal; the DECISION differs by controller (live prompt vs
	# archetype stance — see game._offer_crisis).
	return not in_crisis \
		and unit_instance.get_current_will() >= CRISIS_WILL_GATE

func enter_crisis():
	# Player accepted the live offer (game._process_downed_pending). The unit went DOWNED during the
	# pass; reverse that into the gambit: up at CRISIS_REVIVE_HP, Will locked at 0, surge primed for
	# next turn, no safety net for the rest of the battle.
	in_crisis = true
	lifecycle_state = LifecycleState.ACTIVE
	downed_turns_remaining = -1
	_show_downed_sprite(false)
	unit_instance.set_current_hp(CRISIS_REVIVE_HP)
	unit_instance.set_current_will(0)                         # locked: can_rally() refuses while in_crisis
	crisis_surge_pending = true

func advance_crisis_surge():
	# Called at this unit's faction-turn start. The surge runs for exactly one turn:
	# pending -> (this turn) active -> (next turn) cleared. Applying from the NEXT turn keeps the
	# Crisis-entry pass to "survives standing" only (will-and-death.md ripple containment).
	if crisis_surge_active:
		_clear_crisis_surge()
	elif crisis_surge_pending:
		_apply_crisis_surge()

func _apply_crisis_surge():
	for stat in CRISIS_SURGE_STATS:
		unit_instance.stat_modifiers[stat] = get_modifier(stat) + CRISIS_SURGE
	crisis_surge_pending = false
	crisis_surge_active = true

func _clear_crisis_surge():
	for stat in CRISIS_SURGE_STATS:
		unit_instance.stat_modifiers[stat] = get_modifier(stat) - CRISIS_SURGE
	crisis_surge_active = false

func get_element_aura(element: Elemental.Element) -> int:
	if unit_instance == null:
		return 0
	return unit_instance.get_element_aura(element)

func has_any_affinity() -> bool:
	return unit_instance != null and unit_instance.has_any_affinity()

# The attack this unit would fire right now: a rune auto-picks its first channelable carving; a
# weapon defaults to its main attack. active_attack (the player's live pick) always wins when set
# — reset at the start of _begin_attack, so it's fresh for the unit's OWN declared aim. #30 B2/#72.
func get_fired_attack() -> AttackData:
	if active_attack != null:
		return active_attack
	var rune := get_equipped_weapon() as RuneData
	if rune != null:
		var fireable := rune.channelable(self)
		if not fireable.is_empty():
			return fireable[0]
		return null
	var weapon := get_equipped_weapon() as WeaponInstance
	if weapon != null and weapon.template != null:
		return weapon.template.main_attack
	return null

# The full menu of attacks this unit could choose to fire — for the pick-menu at attack entry.
# A rune offers its channelable carvings; a weapon offers its stock attacks (main + extras, #72).
func get_selectable_attacks() -> Array[AttackData]:
	var result: Array[AttackData] = []
	var rune := get_equipped_weapon() as RuneData
	if rune != null:
		for t in rune.channelable(self):
			result.append(t)
		return result
	var weapon := get_equipped_weapon() as WeaponInstance
	if weapon != null:
		for a in weapon.available_attacks(self):
			result.append(a)
	return result

# What a COUNTER fires — deliberately separate from get_fired_attack(): a rune counters with
# whatever it would currently fire (unchanged #30 quirk), but a weapon ALWAYS counters with its
# main attack, ignoring any live active_attack selection (#72 ruling; overwatch-style alt-attack
# countering is out of scope, #73).
func get_counter_attack() -> AttackData:
	var rune := get_equipped_weapon() as RuneData
	if rune != null:
		return get_fired_attack()
	var weapon := get_equipped_weapon() as WeaponInstance
	if weapon != null and weapon.template != null:
		return weapon.template.main_attack
	return null

# Does this unit's CURRENT attack source permit a counter? #30/#72: reads get_counter_attack(),
# never the live selection — see that method's header for why.
func attack_source_can_counter() -> bool:
	var atk := get_counter_attack()
	return atk != null and atk.can_counter

# Does this unit's CURRENT attack source splash allies (friendly fire)? Reads whatever this unit
# would fire right now (get_fired_attack) -- the AoE mirror of attack_source_can_counter, but
# NOT counter-locked to main: the ally-splash check reflects the live aim. #30/#72.
func attack_source_hits_allies() -> bool:
	var atk := get_fired_attack()
	return atk != null and atk.hits_allies
	
# Readiness seam (#73) — delegates entirely to the equipped WeaponInstance; Unit carries no
# readiness state of its own (two weapons in inventory must track independently).
func is_attack_fireable(attack: AttackData) -> bool:
	if not (attack is WeaponAttackData):
		return true
	var weapon := get_equipped_weapon() as WeaponInstance
	return weapon == null or weapon.is_attack_fireable(attack as WeaponAttackData)

func has_any_fireable_attack() -> bool:
	for a in get_selectable_attacks():
		if is_attack_fireable(a):
			return true
	return false

func can_reload_weapon() -> bool:
	var weapon := get_equipped_weapon() as WeaponInstance
	return weapon != null and weapon.can_reload()

func reload_weapon() -> void:
	var weapon := get_equipped_weapon() as WeaponInstance
	if weapon != null:
		weapon.reload()
