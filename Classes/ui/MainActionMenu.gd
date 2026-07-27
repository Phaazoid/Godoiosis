extends Node
class_name MainActionMenu

# The player's action-menu system: menu item ids/display data, which options a unit can take
# right now, opening the menus, and dispatch when one is picked. Holds a back-ref to the Game
# coordinator (mirrors DevController/AIController/HoverPresenter) for everything it reads from
# or calls back into.
#
# Menu CONSTRUCTION moved here from game.gd 2026-07-26 to sit next to the gating and dispatch
# it belongs with -- three near-identical copies of the ActionMenuController boilerplate
# collapsed into _open_menu(), and two copies of the fireable-or-disabled row into
# _attack_entry(). The coordinator now only says "open the menu for this unit at this point".
#
# Three menus live here. The MAIN menu (ACTION_DATA) is the top level. The ATTACK menu is the
# rune carving picker. The WEAPON ACTION submenu gathers the equipped weapon's extras and its
# self-abilities. Adding a general verb touches the main menu; a weapon-specific one touches
# only show_weapon_action_menu -- see CLAUDE.md's new-action checklist.

var game   # the Game coordinator (Node2D); set by game._ready()

const MOVE := 0
const ATTACK := 1
const OTHER := 2
const CANCEL := 3
const WAIT := 4
const ENDTURN := 5
const SQUADUP := 6
const JOINSQUAD := 7
const LEAVESQUAD := 8
const DISBAND_SQUAD := 9
const INSPECT := 10
const EXECUTE_ORDERS := 11
const RESCUE := 12
const RALLY := 13
const GROUP_MOVE := 14
const INTIMIDATE := 15
const WEAPON_ACTION := 16

# Display data AND print order: declaration order here IS the menu's order (Godot
# dicts iterate in insertion order). One entry per item — nothing else to keep in sync.
const ACTION_DATA := {
	EXECUTE_ORDERS: {"name": "Execute Orders"},
	MOVE: {"name": "Move"},
	GROUP_MOVE: {"name": "Group Move"},
	ATTACK: {"name": "Attack"},
	WEAPON_ACTION: {"name": "Weapon Action"},
	RESCUE: {"name": "Rescue"},
	RALLY: {"name": "Rally"},
	INTIMIDATE: {"name": "Intimidate"},
	SQUADUP: {"name": "Squad Up"},
	JOINSQUAD: {"name": "Join Squad"},
	LEAVESQUAD: {"name": "Leave Squad"},
	DISBAND_SQUAD: {"name": "Disband Squad"},
	WAIT: {"name": "Wait"},
	CANCEL: {"name": "Cancel Actions"},
	INSPECT: {"name": "Inspect"},
	ENDTURN: {"name": "End Turn"},
}

const NOT_READY_TOOLTIP := "Not ready — reload the weapon first"

# ==============================================================================
#  Opening menus
# ==============================================================================

func show_main_menu(unit: Unit, pos: Vector2i) -> void:
	_open_menu(unit, populate(unit), ACTION_DATA, pos, on_pressed)

# Attack entry (weapons-only Weapon Action refactor, 2026-07-24): a WEAPON always fires its default
# (main) attack — no submenu; its extras + self-abilities live under Weapon Action now. A RUNE keeps
# the carving pick-menu (its carvings become an Ability Action category later, #88). Reset the pick
# so a stale one never leaks into a new aim.
func begin_attack(unit: Unit) -> void:
	unit.active_attack = null
	var rune := unit.get_equipped_weapon() as RuneData
	if rune != null:
		var choices := unit.get_selectable_attacks()
		if choices.size() > 1:
			show_attack_menu(unit, choices, game.get_viewport().get_mouse_position())
			return
		if not choices.is_empty():
			unit.active_attack = choices[0]
	game.enter_attack_mode(unit)

# Synthetic items: index -> {name}, so the Control-based ActionMenuController (#26) renders the
# attack list without a bespoke menu class. Works for either kind since display_name lives on
# the shared AttackData base (#72).
func show_attack_menu(unit: Unit, attacks: Array[AttackData], pos: Vector2i) -> void:
	var items := []
	var data := {}
	for i in range(attacks.size()):
		items.append(i)
		data[i] = _attack_entry(unit, attacks[i])

	_open_menu(unit, items, data, pos, func(idx, picking_unit): _pick_attack(picking_unit, attacks[idx]))

# Weapon Action submenu (2026-07-24): the equipped weapon's non-main attacks + its self-abilities
# (Reload / Rev / Burrow), gathered under one menu entry instead of a top-level slot each. A picked
# attack routes to targeting; a picked self-ability queues immediately. Purely a menu grouping — the
# queued orders stay ATTACK/RELOAD/REV/BURROW, so nothing downstream changes. Reload's LABEL is
# per-family (Springspear says "Spring Load", a Carbine says "Reload") while the order is one type.
func show_weapon_action_menu(unit: Unit) -> void:
	var items := []
	var data := {}
	var entries := []   # index -> {"attack": WeaponAttackData} OR {"self": BaseAction.ActionType}
	var idx := 0

	for atk in unit.get_weapon_secondary_attacks():
		items.append(idx)
		data[idx] = _attack_entry(unit, atk)
		entries.append({"attack": atk})
		idx += 1
	if unit.can_reload_weapon():
		items.append(idx)
		data[idx] = {"name": unit.reload_label()}
		entries.append({"self": BaseAction.ActionType.RELOAD})
		idx += 1
	if unit.can_rev_weapon():
		items.append(idx)
		data[idx] = {"name": "Rev"}
		entries.append({"self": BaseAction.ActionType.REV})
		idx += 1
	if unit.can_burrow_weapon():
		items.append(idx)
		data[idx] = {"name": "Burrow"}
		entries.append({"self": BaseAction.ActionType.BURROW})
		idx += 1

	_open_menu(unit, items, data, game.get_viewport().get_mouse_position(),
		func(sel_idx, picking_unit): _pick_weapon_action(picking_unit, entries[sel_idx]))

# Shared plumbing for all three menus: spin up a controller, wire it the same way, fill, place.
# `on_selected` takes (item_id, unit) — the ActionMenuController.action_selected signature.
func _open_menu(unit: Unit, items: Array, data: Dictionary, pos: Vector2i, on_selected: Callable) -> void:
	var controller := ActionMenuController.new()
	game.add_child(controller)
	controller.setup(unit)

	controller.action_selected.connect(on_selected)
	controller.cancelled.connect(_on_menu_cancelled)

	controller.populate(items, data)
	controller.setpos(pos)

# One attack's menu row. Law #2: an unfireable pick (a sprung weapon, #73; a dry magazine, #84)
# stays LISTED but disabled — the menu shows an unready attack, it never hides it.
func _attack_entry(unit: Unit, attack: AttackData) -> Dictionary:
	var entry := {"name": attack.display_name}
	if not unit.is_attack_fireable(attack):
		entry["disabled"] = true
		entry["tooltip"] = NOT_READY_TOOLTIP
	return entry

# ActionMenuController emits `cancelled` before `action_selected` even on a PICK, which is what
# pins the clear-then-act order (see its header). Both effects the old game.gd wired as two
# separate connections happen here, in that same order.
func _on_menu_cancelled(_controller) -> void:
	game.clear_selection()
	game.hover_presenter.refresh()

# ==============================================================================
#  Which options a unit has right now
# ==============================================================================

# Shared gate for every main-action menu entry: one main action per unit per turn, squad
# not spent, no other squad mid-activation. Per-action requirements chain onto this.
func _can_take_main_action(unit: Unit) -> bool:
	return not unit.has_main_action_queued() and not unit.squad.has_acted and not game.squad_manager.is_another_squad_active(unit.squad)

func populate(unit: Unit) -> Array:
	var options = []

	if not game.can_control(unit):
		options.append(INSPECT)
		if not game.squad_manager.any_squad_active():
			options.append(ENDTURN)
		return options

	if unit.squad.has_any_queued_actions() and unit.is_leader():
		options.append(EXECUTE_ORDERS)

	if not unit.has_action_type_queued(BaseAction.ActionType.MOVE) and not unit.has_main_action_queued() and not unit.squad.has_acted and not game.squad_manager.is_another_squad_active(unit.squad):
		options.append(MOVE)

	if unit.is_leader() and unit.has_squad() \
		and not unit.has_action_type_queued(BaseAction.ActionType.MOVE) \
		and not unit.squad.has_acted \
		and not game.squad_manager.is_another_squad_active(unit.squad):
		options.append(GROUP_MOVE)

	if _can_take_main_action(unit) and unit.has_equipped_weapon() and unit.can_wield_equipped() and unit.can_fire_default_attack():
		options.append(ATTACK)

	if _can_take_main_action(unit) and not RulesService.adjacent_downed_allies(unit, game._board()).is_empty() and unit.can_rescue_carry():
		options.append(RESCUE)

	if _can_take_main_action(unit) and unit.can_rally():
		options.append(RALLY)

	if _can_take_main_action(unit) and unit.unit_instance.has_live_ability(Abilities.Id.INTIMIDATION) and not RulesService.adjacent_enemies(unit, game._board()).is_empty():
		options.append(INTIMIDATE)

	if _can_take_main_action(unit) and unit.has_weapon_actions():
		options.append(WEAPON_ACTION)

		#Once Squad is active, squad state cannot change through actions
	if not unit.squad.has_any_queued_actions() and not unit.squad.has_acted and not game.squad_manager.any_squad_active():
		if game.squad_manager.can_create_any_squad(unit):
			options.append(SQUADUP)
		if game.squad_manager.can_join_any_squad(unit):
			options.append(JOINSQUAD)
		if unit.has_squad():
			options.append(LEAVESQUAD)
			if unit.squad.get_leader() == unit:
				options.append(DISBAND_SQUAD)

	if unit != null:
		options.append(INSPECT)

	if game.squad_manager.active_squad == null:
		options.append(WAIT)
		options.append(ENDTURN)

	if unit != null and unit.has_any_actions(): #TODO separate general cancel and cancel queued plans
		options.append(CANCEL)

	var ordered := []
	for id in ACTION_DATA:
		if options.has(id):
			ordered.append(id)
	return ordered

# ==============================================================================
#  Dispatch
# ==============================================================================

func on_pressed(action_id: int, unit: Unit) -> void:
	match action_id:
		MOVE:
			game.enter_move_mode(unit)
		ATTACK:
			begin_attack(unit)
		CANCEL:
			game.squad_manager.remove_actions_for_unit(unit)
			game.clear_selection()
		WAIT:
			game.squad_manager.set_has_acted(unit.squad, true)
			game.clear_selection()
		ENDTURN:
			game.end_turn()
		SQUADUP:
			game.create_squad(unit)
		JOINSQUAD:
			game.join_squad_mode(unit)
		DISBAND_SQUAD:
			game.squad_manager.disband_squad(unit.squad)
		LEAVESQUAD:
			game.squad_manager.leave_squad(unit)
		INSPECT:
			game.unit_info_panel.set_unit(unit, game.can_control(unit), game._board())
		EXECUTE_ORDERS:
			game.order_executor.execute_orders(unit)
		RESCUE:
			game.enter_target_pick_mode(RulesService.adjacent_downed_allies(unit, game._board()), func(target: Unit): game.queue_rescue(unit, target))
		RALLY:
			game.queue_rally(unit)
		INTIMIDATE:
			game.enter_target_pick_mode(RulesService.adjacent_enemies(unit, game._board()), func(target: Unit): game.queue_intimidate(unit, target))
		GROUP_MOVE:
			game.enter_group_move_mode(unit)
		WEAPON_ACTION:
			show_weapon_action_menu(unit)

func _pick_attack(unit: Unit, attack: AttackData) -> void:
	unit.active_attack = attack
	game.enter_attack_mode(unit)

func _pick_weapon_action(unit: Unit, entry: Dictionary) -> void:
	if entry.has("attack"):
		_pick_attack(unit, entry["attack"])
	else:
		match entry["self"]:
			BaseAction.ActionType.RELOAD:
				game.queue_reload(unit)
			BaseAction.ActionType.REV:
				game.queue_rev(unit)
			BaseAction.ActionType.BURROW:
				game.queue_burrow(unit)
