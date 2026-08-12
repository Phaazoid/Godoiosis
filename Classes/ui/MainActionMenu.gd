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
# The MAIN menu (ACTION_DATA) is the top level; below it sit THREE submenu categories, and Attack
# itself is submenu-free for every kind of equipped item (#88, 2026-07-29):
#   WEAPON ACTION  -- the equipped weapon's non-main attacks plus its self-abilities (Reload/Rev/
#                     Burrow). A weapon HAS an authored main_attack, so Attack fires that.
#   TRANSMUTATION  -- a rune's carvings. A rune has NO authored main, so they're interchangeable
#                     equals and all of them list; Attack fires whichever is default (first
#                     channelable). Built on show_attack_menu, the shared attack picker.
#   ABILITY ACTION -- ability-driven verbs (Intimidate today; Fortitude/Guard later).
# Transmutation is deliberately NOT folded under Ability Action even though #88's own text proposed
# it: runes are equippables and a carving is not ability use (dev call). All three are purely a
# menu-layer grouping -- the queued ActionType is unchanged, so resolver/queue panel/AI see nothing.
#
# Adding a general verb touches the main menu; a weapon-specific one touches only
# show_weapon_action_menu; an ability-driven one touches only ability_action_entries and its
# _pick_ability_action arm -- see CLAUDE.md's new-action checklist.

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
const ABILITY_ACTION := 15
const WEAPON_ACTION := 16
const CAPTURE := 17
const TRANSMUTATION := 18

# Display data AND print order: declaration order here IS the menu's order (Godot
# dicts iterate in insertion order). One entry per item — nothing else to keep in sync.
# `term` names the row's Glossary entry (#135): its short text is the row's hover tooltip,
# pinned complete by tests/law/test_glossary_coverage.gd.
const ACTION_DATA := {
	EXECUTE_ORDERS: {"name": "Execute Orders", "term": Glossary.Term.EXECUTE_ORDERS},
	MOVE: {"name": "Move", "term": Glossary.Term.MOVE},
	GROUP_MOVE: {"name": "Group Move", "term": Glossary.Term.GROUP_MOVE},
	ATTACK: {"name": "Attack", "term": Glossary.Term.ATTACK},
	WEAPON_ACTION: {"name": "Weapon Action", "term": Glossary.Term.WEAPON_ACTION},
	TRANSMUTATION: {"name": "Transmutation", "term": Glossary.Term.TRANSMUTATION},
	ABILITY_ACTION: {"name": "Ability Action", "term": Glossary.Term.ABILITY_ACTION},
	RESCUE: {"name": "Rescue", "term": Glossary.Term.RESCUE},
	RALLY: {"name": "Rally", "term": Glossary.Term.RALLY},
	CAPTURE: {"name": "Capture Point", "term": Glossary.Term.CAPTURE},
	SQUADUP: {"name": "Squad Up", "term": Glossary.Term.SQUAD_UP},
	JOINSQUAD: {"name": "Join Squad", "term": Glossary.Term.JOIN_SQUAD},
	LEAVESQUAD: {"name": "Leave Squad", "term": Glossary.Term.LEAVE_SQUAD},
	DISBAND_SQUAD: {"name": "Disband Squad", "term": Glossary.Term.DISBAND_SQUAD},
	WAIT: {"name": "Wait", "term": Glossary.Term.WAIT},
	CANCEL: {"name": "Cancel Actions", "term": Glossary.Term.CANCEL_ACTIONS},
	INSPECT: {"name": "Inspect", "term": Glossary.Term.INSPECT},
	ENDTURN: {"name": "End Turn", "term": Glossary.Term.END_TURN},
}

# ==============================================================================
#  Opening menus
# ==============================================================================

# Rows go through _entry like every other menu's (#166's law, applied here by #135): the
# glossary short text is the hover readout on every option. Nothing is greyed at this level —
# populate() still hides what a unit can't do, a deliberate per-menu policy (#166).
func show_main_menu(unit: Unit, pos: Vector2i) -> void:
	var data := {}
	for id in ACTION_DATA:
		data[id] = _entry(ACTION_DATA[id]["name"], "", Glossary.short(ACTION_DATA[id]["term"]))
	_open_menu(unit, populate(unit), data, pos, on_pressed)

# Attack entry (weapons-only Weapon Action refactor, 2026-07-24): a WEAPON always fires its default
# (main) attack — no submenu; its extras + self-abilities live under Weapon Action now. A RUNE keeps
# the carving pick-menu (its carvings become an Ability Action category later, #88). Reset the pick
# so a stale one never leaks into a new aim.
func begin_attack(unit: Unit) -> void:
	unit.active_attack = null
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

# ONE menu row, and the catalogue law in one place (#166): an option the unit OWNS is listed
# whether or not it can be used right now, and a greyed row always says why. A non-empty
# `blocked_reason` disables the row AND explains it; `detail` is the hover readout for what the row
# does. Every menu builder here goes through this — the reasons themselves belong to the data layer
# (EquippableData.attack_block_reason), never to this file.
func _entry(name: String, blocked_reason: String = "", detail: String = "") -> Dictionary:
	var entry := {"name": name}
	var lines: Array[String] = []
	if detail != "":
		lines.append(detail)
	if blocked_reason != "":
		entry["disabled"] = true
		lines.append(blocked_reason)
	if not lines.is_empty():
		entry["tooltip"] = "\n".join(lines)
	return entry

# One attack's menu row. Law #2: an unfireable pick (a sprung weapon, #73; a dry magazine, #84; an
# unchannelable carving, #166) stays LISTED but disabled — the menu shows it, it never hides it.
func _attack_entry(unit: Unit, attack: AttackData) -> Dictionary:
	return _entry(attack.display_name, unit.attack_block_reason(attack), unit.attack_detail(attack))

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

	if _can_take_main_action(unit) and not RulesService.adjacent_downed_allies(unit, game._board(), game.squad_manager.resolved_plan_for(unit.squad)).is_empty() and unit.can_rescue_carry():
		options.append(RESCUE)

	if _can_take_main_action(unit) and unit.can_rally():
		options.append(RALLY)

	if _can_take_main_action(unit) and not ability_action_entries(unit).is_empty():
		options.append(ABILITY_ACTION)

	if _can_take_main_action(unit) and unit.has_transmutations():
		options.append(TRANSMUTATION)

	if _can_take_main_action(unit) and game.mission_controller.is_capture_zone_at(unit.get_projected_destination()) \
		and not game.mission_controller.is_zone_captured(game.zone_manager.zone_at(unit.get_projected_destination())):
		options.append(CAPTURE)

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
		# Wait is a choice a squad makes ONCE; an acted squad has nothing left to end (#190).
		# End Turn stays unconditional -- it's about the faction's turn, not this squad's state.
		if not unit.squad.has_acted:
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
			game.refresh_end_turn_button()
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
			# Same query as the populate gate above, plan included -- a predicted-down squadmate
			# (#124) must be pickable exactly where the row said it would be.
			game.enter_target_pick_mode(RulesService.adjacent_downed_allies(unit, game._board(), game.squad_manager.resolved_plan_for(unit.squad)), func(target: Unit): game.queue_rescue(unit, target))
		RALLY:
			game.queue_simple_action(unit, BaseAction.ActionType.RALLY)
		ABILITY_ACTION:
			show_ability_action_menu(unit)
		TRANSMUTATION:
			show_attack_menu(unit, unit.get_transmutation_choices(), game.get_viewport().get_mouse_position())
		CAPTURE:
			game.queue_capture(unit)
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
		game.queue_simple_action(unit, entry["self"])

# Every ability-driven main action this unit could take RIGHT NOW (#88). ONE list, two readers:
# populate() gates the top-level entry on it being non-empty, and show_ability_action_menu builds
# the submenu from it — so the category can never open empty, nor hide an option that was live.
# Each entry is {name, type}; the queued ActionType is unchanged, which is what keeps the resolver,
# the queue panel and the AI untouched by this refactor.
func ability_action_entries(unit: Unit) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if unit.has_live_ability(Abilities.Id.INTIMIDATION) and not RulesService.adjacent_enemies(unit, game._board()).is_empty():
		entries.append({"name": "Intimidate", "type": BaseAction.ActionType.INTIMIDATE})
	return entries

func show_ability_action_menu(unit: Unit) -> void:
	var entries := ability_action_entries(unit)
	var items := []
	var data := {}
	for i in range(entries.size()):
		items.append(i)
		data[i] = {"name": entries[i]["name"]}

	_open_menu(unit, items, data, game.get_viewport().get_mouse_position(),
		func(idx, picking_unit): _pick_ability_action(picking_unit, entries[idx]["type"]))

# Per-type dispatch, not one uniform queue call: an ability action can need a TARGET pick where a
# weapon self-ability never does. Same reasoning that keeps queue_intimidate separate from
# queue_simple_action — one signature would just move the branching into a parameter bag. An
# unmatched type is loud, mirroring AITactics' builders.
func _pick_ability_action(unit: Unit, type: BaseAction.ActionType) -> void:
	match type:
		BaseAction.ActionType.INTIMIDATE:
			game.enter_target_pick_mode(RulesService.adjacent_enemies(unit, game._board()), func(target: Unit): game.queue_intimidate(unit, target))
		_:
			push_error("MainActionMenu: no dispatch for ability action %s" % BaseAction.ActionType.keys()[type])
