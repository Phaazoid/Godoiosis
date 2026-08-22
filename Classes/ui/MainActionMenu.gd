extends Node
class_name MainActionMenu

# The player's action-menu system: menu item ids/display data, which options a unit can take
# right now, opening the menus, and dispatch when one is picked. Holds a back-ref to the Game
# coordinator (mirrors DevController/AIController/HoverPresenter) for everything it reads from
# or calls back into.
#
# Menu CONSTRUCTION moved here from game.gd 2026-07-26 to sit next to the gating and dispatch it
# belongs with; the coordinator only says "open the menu for this unit at this point".
#
# SINCE #467 the menu is a RADIAL of five CATEGORIES, and this file's job is the TREE behind it:
# build_tree() answers "what can this unit do, arranged how the ring draws it" in one pass, at
# open. One pass is not an optimisation -- a hovered category is GHOSTED before it is opened, so
# its contents must exist before the click, and a preview that re-queried could disagree with what
# commits. The game is modal while the ring is up, so nothing can change underneath the snapshot.
#
#   MOVE    -- Move, Group Move
#   ATTACK  -- every attack the unit owns, each by ITS OWN NAME: the weapon's main and its other
#              attacks, its self-verbs (Reload/Rev/Burrow), and the rune's carvings
#   ACT     -- the main actions that are not an attack (Guard, Rescue, Rally, Capture, the
#              ability-driven verbs) plus Wait, which spends the squad's turn the same way
#   SQUAD   -- Squad Up, Join, Leave, Disband
#   INSPECT -- itself, and therefore a top-level slice; see Group below
#
# THREE VERBS LEFT THE RING in round 2 because each already had a better door: Execute Orders (the
# queue panel's button, with three readiness states), Cancel Actions (that panel's per-row X, plus
# right-click's LIFO undo) and End Turn (the corner button, permanently on screen since this row
# went). The unit's menu is what the UNIT does; the turn is the HUD's business.
#
# #88 HELD WEAPON ACTION AND TRANSMUTATION APART and this file said so as settled law: "runes are
# equippables and a carving is not ability use". That was a HOLDING POSITION pending a menu rework,
# not a principle -- the dev overturned it on #467 ("I was going to get around to grouping attack
# and transmutation option in the old menu anyways"), so both now live under ATTACK. The grouping
# is still purely a menu-layer fact: the queued ActionType is unchanged, and resolver, queue panel
# and AI see nothing.
#
# A category is drawn only when it has live children, which is the ring's compaction rule one level
# up -- and it is also why has_weapon_actions()/has_transmutations()/ability_action_entries() are no
# longer read as menu gates. populate() still answers the flat "what can this unit do" and the
# grouping is applied on top of it; the only thing round 2 took out of it is the three verbs above,
# whose clauses went with their rows.
#
# Adding a general verb touches ACTION_DATA (name, term, group); a weapon-specific one touches only
# _weapon_children; an ability-driven one touches only ability_action_entries and its
# _pick_ability_action arm -- see CLAUDE.md's new-action checklist.

var game   # the Game coordinator (Node2D); set by game._ready()

# Explicit values, so removing a verb never renumbers the ones beside it. Three left the ring in
# #467 round 2 and their ids went with them: EXECUTE_ORDERS and CANCEL both have richer HUD doors
# (the queue panel's Execute button and its per-row X, plus right-click's LIFO undo), and END TURN
# has the corner button, which is now permanently on screen precisely because this row is gone.
const MOVE := 0
const ATTACK := 1
const OTHER := 2
const WAIT := 4
const SQUADUP := 6
const JOINSQUAD := 7
const LEAVESQUAD := 8
const DISBAND_SQUAD := 9
const INSPECT := 10
const RESCUE := 12
const RALLY := 13
const GROUP_MOVE := 14
const ABILITY_ACTION := 15
const WEAPON_ACTION := 16
const CAPTURE := 17
const TRANSMUTATION := 18
const GUARD := 19

# The ring's categories, and their order IS the inner ring's clockwise order.
#
# INSPECT_GROUP is a category of ONE, holding the verb of the same name, which means the collapse
# rule in build_tree hands it up as a plain terminal slice -- "Inspect is top level" (dev, #467
# round 2) costs no new mechanism, just a group nobody else joins.
enum Group { MOVE_GROUP, ATTACK_GROUP, ACT_GROUP, SQUAD_GROUP, INSPECT_GROUP }

# A category is a row the player hovers, so it owes a readout like any other (#135's law reaches
# it, pinned by tests/law/test_glossary_coverage.gd). Move / Attack / Inspect reuse the verb terms
# of the same name; ACT and SQUAD_ACTIONS were authored for the ring.
const CATEGORIES := {
	Group.MOVE_GROUP: {"name": "Move", "term": Glossary.Term.MOVE},
	Group.ATTACK_GROUP: {"name": "Attack", "term": Glossary.Term.ATTACK},
	Group.ACT_GROUP: {"name": "Act", "term": Glossary.Term.ACT},
	Group.SQUAD_GROUP: {"name": "Squad", "term": Glossary.Term.SQUAD_ACTIONS},
	Group.INSPECT_GROUP: {"name": "Inspect", "term": Glossary.Term.INSPECT},
}

# Display data AND print order: declaration order here IS the order within a category (Godot
# dicts iterate in insertion order). One entry per item — nothing else to keep in sync.
# `term` names the row's Glossary entry (#135): its short text is the row's hover tooltip.
# `group` is which ring category the verb sits under (#467).
# `expands` marks the three ids that were only ever category headers: they contribute their
# CHILDREN to their group rather than a row of their own.
const ACTION_DATA := {
	MOVE: {"name": "Move", "term": Glossary.Term.MOVE, "group": Group.MOVE_GROUP},
	GROUP_MOVE: {"name": "Group Move", "term": Glossary.Term.GROUP_MOVE, "group": Group.MOVE_GROUP},
	ATTACK: {"name": "Attack", "term": Glossary.Term.ATTACK, "group": Group.ATTACK_GROUP, "expands": true},
	WEAPON_ACTION: {"name": "Weapon Action", "term": Glossary.Term.WEAPON_ACTION, "group": Group.ATTACK_GROUP, "expands": true},
	TRANSMUTATION: {"name": "Transmutation", "term": Glossary.Term.TRANSMUTATION, "group": Group.ATTACK_GROUP, "expands": true},
	ABILITY_ACTION: {"name": "Ability Action", "term": Glossary.Term.ABILITY_ACTION, "group": Group.ACT_GROUP, "expands": true},
	GUARD: {"name": "Guard", "term": Glossary.Term.GUARD, "group": Group.ACT_GROUP},
	RESCUE: {"name": "Rescue", "term": Glossary.Term.RESCUE, "group": Group.ACT_GROUP},
	RALLY: {"name": "Rally", "term": Glossary.Term.RALLY, "group": Group.ACT_GROUP},
	CAPTURE: {"name": "Capture Point", "term": Glossary.Term.CAPTURE, "group": Group.ACT_GROUP},
	WAIT: {"name": "Wait", "term": Glossary.Term.WAIT, "group": Group.ACT_GROUP},
	SQUADUP: {"name": "Squad Up", "term": Glossary.Term.SQUAD_UP, "group": Group.SQUAD_GROUP},
	JOINSQUAD: {"name": "Join Squad", "term": Glossary.Term.JOIN_SQUAD, "group": Group.SQUAD_GROUP},
	LEAVESQUAD: {"name": "Leave Squad", "term": Glossary.Term.LEAVE_SQUAD, "group": Group.SQUAD_GROUP},
	DISBAND_SQUAD: {"name": "Disband Squad", "term": Glossary.Term.DISBAND_SQUAD, "group": Group.SQUAD_GROUP},
	INSPECT: {"name": "Inspect", "term": Glossary.Term.INSPECT, "group": Group.INSPECT_GROUP},
}

# A child that is not an ACTION_DATA verb (a carving, a weapon's secondary, an ability verb) needs
# an id the controller can hand back. They are allocated NEGATIVE, per open, so they can never
# collide with a verb id and a stale one from a previous open is unmistakable. Cleared by
# build_tree, which is the same moment the tree is snapshotted.
var _pick_by_id: Dictionary = {}
var _next_synthetic_id := -1

# ==============================================================================
#  Opening menus
# ==============================================================================

# The one door: build the whole tree, hand it to one controller, place it at the cursor. The
# controller owns every level from here -- there is no second open for a submenu, which is what
# lets the ring survive a category pick.
func show_main_menu(unit: Unit, pos: Vector2i) -> void:
	var controller := ActionMenuController.new()
	game.add_child(controller)
	controller.setup(unit)

	controller.action_selected.connect(on_pressed)
	controller.cancelled.connect(_on_menu_cancelled)

	controller.open(build_tree(unit), Vector2(pos))


# THE snapshot (#467): every ring the player can reach this open, built now. Categories in
# CATEGORIES order, verbs within one in ACTION_DATA order, and a category with no live children is
# simply absent -- the ring's compaction rule, applied one level up.
func build_tree(unit: Unit) -> Array:
	_pick_by_id = {}
	_next_synthetic_id = -1

	var by_group := {}
	for id: int in populate(unit):
		var entry: Dictionary = ACTION_DATA[id]
		var group: int = entry["group"]
		if not by_group.has(group):
			by_group[group] = []
		var bucket: Array = by_group[group]
		if bool(entry.get("expands", false)):
			for child: Dictionary in _expanded_children(unit, id):
				_append_unique(bucket, child)
		else:
			_append_unique(bucket, _verb_node(id))

	var ring: Array = []
	for group: int in CATEGORIES:
		var children: Array = by_group.get(group, [])
		if children.is_empty():
			continue
		var category: Dictionary = CATEGORIES[group]
		# A category whose ONE child is its own verb is the same question asked twice -- Move
		# holding nothing but Move (dev, #467 round 2: "there is no reason to put Move under
		# Move"). Hand the child up as a terminal slice. Deliberately NOT "collapse whenever
		# there is one child": Squad holding only Squad Up names something the category does not,
		# so it keeps its ring -- drawn small, which is what MAX_WEDGE_DEGREES is for.
		if children.size() == 1 and String(children[0].get("name", "")) == String(category["name"]):
			ring.append(children[0])
			continue
		var node := _entry(category["name"], "", Glossary.short(category["term"]))
		node["children"] = children
		ring.append(node)
	return ring


# Two slices with one name is a bug however it arose -- and it arises HERE by construction: a
# rune's default attack is also one of its carvings, so the ATTACK and TRANSMUTATION expanders
# both offer it. First listing wins, so ACTION_DATA's order decides which.
func _append_unique(bucket: Array, node: Dictionary) -> void:
	var node_name := String(node.get("name", ""))
	for existing: Dictionary in bucket:
		if String(existing.get("name", "")) == node_name:
			return
	bucket.append(node)


# An ACTION_DATA verb as a leaf. Its id IS the ACTION_DATA id, so on_pressed's match is reached
# exactly as it was from the dropdown.
func _verb_node(id: int) -> Dictionary:
	var entry: Dictionary = ACTION_DATA[id]
	var node := _entry(entry["name"], "", Glossary.short(entry["term"]))
	node["id"] = id
	return node


# A leaf that is not a verb: it gets a negative id and its own Callable, both dropped at the next
# build_tree. Keeping ONE signal out of the controller is why these route through ids at all.
func _synthetic_leaf(node: Dictionary, pick: Callable) -> Dictionary:
	node["id"] = _next_synthetic_id
	_pick_by_id[_next_synthetic_id] = pick
	_next_synthetic_id -= 1
	return node


func _expanded_children(unit: Unit, id: int) -> Array:
	match id:
		ATTACK:
			return _default_attack_children(unit)
		WEAPON_ACTION:
			return _weapon_children(unit)
		TRANSMUTATION:
			return _transmutation_children(unit)
		ABILITY_ACTION:
			return _ability_children(unit)
	push_error("MainActionMenu: no children builder for expander %s" % id)
	return []


# Every attack is a leaf that routes to targeting. Law #2 still holds here and this is now the
# surface it holds ON: an unfireable pick (a sprung weapon #73, a dry magazine #84, an
# unchannelable carving #166) stays LISTED and greyed with its reason. The ring COMPACTS at the
# category level and must never compact here.
func _attack_leaf(unit: Unit, attack: AttackData) -> Dictionary:
	return _synthetic_leaf(_attack_entry(unit, attack),
		func(picking_unit: Unit) -> void: _pick_attack(picking_unit, attack))


# The weapon's MAIN attack, under its own name. There is no generic "Attack" row any more (dev,
# #467 round 2): the ring already lists every alternative by name, so a row saying "Attack" was a
# second door to one of them, and its only virtue -- saving a click -- was spent the moment the
# ring made you navigate anyway. Note what this makes newly visible: a weapon family whose main
# attack is unnamed now says so on screen.
func _default_attack_children(unit: Unit) -> Array:
	var atk := unit.get_default_attack()
	if atk == null:
		return []
	return [_attack_leaf(unit, atk)]


# The equipped weapon's non-main attacks plus its self-verbs. Reload's LABEL is per-family
# (a Springspear says "Spring Load", a Carbine says "Reload") while the order is one type.
func _weapon_children(unit: Unit) -> Array:
	var children: Array = []
	for atk: AttackData in unit.get_weapon_secondary_attacks():
		children.append(_attack_leaf(unit, atk))
	if unit.can_reload_weapon():
		children.append(_self_verb_leaf(unit.reload_label(), BaseAction.ActionType.RELOAD))
	if unit.can_rev_weapon():
		children.append(_self_verb_leaf("Rev", BaseAction.ActionType.REV))
	if unit.can_burrow_weapon():
		children.append(_self_verb_leaf("Burrow", BaseAction.ActionType.BURROW))
	return children


func _self_verb_leaf(label: String, type: BaseAction.ActionType) -> Dictionary:
	return _synthetic_leaf(_entry(label),
		func(picking_unit: Unit) -> void: game.queue_simple_action(picking_unit, type))


# A rune has NO authored main attack, so its carvings are interchangeable equals and all of them
# list; the ATTACK verb beside them fires whichever is default (the first channelable).
func _transmutation_children(unit: Unit) -> Array:
	var children: Array = []
	for atk: AttackData in unit.get_transmutation_choices():
		children.append(_attack_leaf(unit, atk))
	return children


func _ability_children(unit: Unit) -> Array:
	var children: Array = []
	for ability_entry: Dictionary in ability_action_entries(unit):
		var type: BaseAction.ActionType = ability_entry["type"]
		children.append(_synthetic_leaf(_entry(ability_entry["name"]),
			func(picking_unit: Unit) -> void: _pick_ability_action(picking_unit, type)))
	return children

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
		# Wrapped HERE, not at draw time: the stored string is what the player reads, so wrapping
		# it later would leave the row holding one form and showing another. Godot's own tooltips
		# never autowrapped either, which is why this call has always had to exist somewhere.
		entry["tooltip"] = UiText.wrap("\n".join(lines))
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

# Shared gate for BOTH movement entries. Same three clauses, and the main-action one carries the
# rule from the other side: move-before-main, so a unit that locked its main cannot move after it
# (MoveAction.actor_can_perform is the chokepoint that enforces it). Group Move used to carry its
# own hand-copy of this, which had drifted -- missing the main-action clause, so the menu offered a
# formation queue_group_move would then refuse the leader half of (#443). One gate now, so the next
# clause added here reaches both rows.
#
# An ALREADY-QUEUED move is deliberately NOT a clause here (#417/#461): both rows re-enter planning
# over their own queued order. Move stays a PER-UNIT question -- it must never start reading
# squadmates, which is why #461's member clause sits on _can_group_move rather than here.
func _can_move(unit: Unit) -> bool:
	return _can_take_main_action(unit)

# Group Move asks _can_move of the whole SQUAD, not just of the leader (#461). The batch authors a
# move for every member, and queue_action refuses a member who has locked a main -- which fires
# queue_group_move's all-or-nothing rollback and cancels everyone's moves. #443 closed exactly this
# hole for the leader and stopped there, because _can_move only ever sees the unit whose menu is
# open. The menu is one door: the AI and the Play API reach queue_group_move directly, so the
# rollback stays their backstop rather than being replaced by this.
func _can_group_move(unit: Unit) -> bool:
	if not (_can_move(unit) and unit.is_leader() and unit.has_squad()):
		return false
	for member in unit.squad.get_members():
		if not _can_move(member):
			return false
	return true

func populate(unit: Unit) -> Array:
	var options = []

	if not game.can_control(unit):
		options.append(INSPECT)
		return options

	if _can_move(unit):
		options.append(MOVE)

	if _can_group_move(unit):
		options.append(GROUP_MOVE)

	if _can_take_main_action(unit) and unit.has_equipped_weapon() and unit.can_wield_equipped() and unit.can_fire_default_attack():
		options.append(ATTACK)

	# A basic main action everyone has (#414) — no ability gate, no verb lock; what kit grants is the
	# brace bonus, not the verb. Listed only when there is somebody in range to stand in front of.
	if _can_take_main_action(unit) and not RulesService.guard_candidates(unit, game._board()).is_empty():
		options.append(GUARD)

	if _can_take_main_action(unit) and not RulesService.adjacent_downed_allies(unit, game._board(), game.squad_manager.resolved_plan_for(unit.squad)).is_empty() and unit.can_rescue_carry():
		options.append(RESCUE)

	if _can_take_main_action(unit) and unit.can_rally():
		options.append(RALLY)

	if _can_take_main_action(unit) and not ability_action_entries(unit).is_empty():
		options.append(ABILITY_ACTION)

	if _can_take_main_action(unit) and unit.has_transmutations():
		options.append(TRANSMUTATION)

	if _can_take_main_action(unit) and game.mission_controller.capturable_zone_at(unit.get_projected_destination()) != "":
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

	# Wait is a choice a squad makes ONCE; an acted squad has nothing left to end (#190).
	if game.squad_manager.active_squad == null and not unit.squad.has_acted:
		options.append(WAIT)

	var ordered := []
	for id in ACTION_DATA:
		if options.has(id):
			ordered.append(id)
	return ordered

# ==============================================================================
#  Dispatch
# ==============================================================================

func on_pressed(action_id: int, unit: Unit) -> void:
	# A NEGATIVE id is one of this open's synthetic leaves (a carving, a weapon secondary, an
	# ability verb). One signal out of the controller, two kinds of leaf behind it.
	if action_id < 0:
		var pick: Callable = _pick_by_id.get(action_id, Callable())
		if pick.is_valid():
			pick.call(unit)
		else:
			push_error("MainActionMenu: no pick for synthetic id %s" % action_id)
		return

	match action_id:
		MOVE:
			# The gesture, not the bare mode: re-planning spends the queued move (#417). One
			# answer, because right-click reaches the same gesture from the other side.
			game.begin_move_planning(unit)
		WAIT:
			game.squad_manager.set_has_acted(unit.squad, true)
			game.refresh_end_turn_button()
			game.clear_selection()
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
		RESCUE:
			# Same query as the populate gate above, plan included -- a predicted-down squadmate
			# (#124) must be pickable exactly where the row said it would be.
			game.enter_target_pick_mode(RulesService.adjacent_downed_allies(unit, game._board(), game.squad_manager.resolved_plan_for(unit.squad)), func(target: Unit): game.queue_rescue(unit, target))
		GUARD:
			# Same query as the populate gate above — the pick layer must agree with the rule layer
			# (the #126 lesson pinned by tests/ui/test_target_pick_projection.gd).
			game.enter_target_pick_mode(RulesService.guard_candidates(unit, game._board()), func(target: Unit): game.queue_guard(unit, target))
		RALLY:
			game.queue_simple_action(unit, BaseAction.ActionType.RALLY)
		CAPTURE:
			game.queue_capture(unit)
		GROUP_MOVE:
			# The gesture, not the bare mode: re-planning spends the queued formation (#461).
			game.begin_group_move_planning(unit)

func _pick_attack(unit: Unit, attack: AttackData) -> void:
	unit.active_attack = attack
	game.enter_attack_mode(unit)

# Every ability-driven main action this unit could take RIGHT NOW (#88). ONE list, two readers:
# populate() gates ABILITY_ACTION on it being non-empty, and _ability_children builds the ring's
# leaves from it — so the group can never carry an option that was not live. Each entry is
# {name, type}; the queued ActionType is unchanged, which is what keeps the resolver, the queue
# panel and the AI untouched by the menu rework.
func ability_action_entries(unit: Unit) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if unit.has_live_ability(Abilities.Id.INTIMIDATION) and not RulesService.adjacent_enemies(unit, game._board()).is_empty():
		entries.append({"name": "Intimidate", "type": BaseAction.ActionType.INTIMIDATE})
	return entries

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
