# Every kind of real resolve pass, on every saved board (#1480 stage 4): the walk the two body laws
# share, tests/law/test_a_pass_reads_no_live_body.gd and tests/law/test_a_pass_writes_no_live_body.gd.
# Boards are iterated, never named (the content razor), so a new board is covered for free.
#
# Each pass is handed to `around` as (board label, kind, a Callable that runs it), so each law wraps
# the same passes in its own check and can fail on its own.
extends RefCounted

const AI_TURN := "AI turn"
const PLAYER_PLAN := "player plan"
const HOVER := "hover"
const HOVER_ALT := "hover, alternate source"
const KINDS: Array[String] = [AI_TURN, PLAYER_PLAN, HOVER, HOVER_ALT]


# Drives the passes; answers how many ran of each kind, for the laws' non-vacuity messages.
static func walk(game: Node, around: Callable) -> Dictionary:
	var ran := {}
	for kind in KINDS:
		ran[kind] = 0
	for path: String in game.scenario_manager.get_saved_scenarios():
		game.scenario_manager.load_scenario(path)
		for _i in range(3):
			await game.get_tree().process_frame
		var label := path.get_file()
		var sm: SquadManager = game.squad_manager
		for faction: Team.Faction in Team.Faction.values():
			for squad in AIController.actable_squads(faction, sm):
				if not AIController.is_squad_actable(squad, faction):
					continue
				around.call(label, AI_TURN, func() -> void:
					AIController.plan_squad(squad, game._board(), sm))
				ran[AI_TURN] += 1
		for child in game.units_root.get_children():
			_aim_with(game, child as Unit, label, around, ran)
	return ran


# A unit's first aim at a hostile, through the real gate and then the plan; its hover; and a hover
# from another carried source, when it holds one that can aim.
static func _aim_with(game: Node, unit: Unit, label: String, around: Callable, ran: Dictionary) -> void:
	if unit == null or not is_instance_valid(unit) or unit.squad == null or not unit.is_active():
		return
	var sm: SquadManager = game.squad_manager
	var board: BoardContext = game._board()
	var in_hand := false
	var other := false
	for option: Unit.AimOption in unit.aim_options(false, board):
		var held := option.source == unit.equipped_weapon
		if (held and in_hand) or (not held and other):
			continue
		var aim := _declare_at_a_foe(unit, option, board)
		if aim == null:
			continue
		var squad := unit.squad
		if held:
			in_hand = true
			if sm.try_queue_action(squad, aim) == "":
				around.call(label, PLAYER_PLAN, func() -> void: sm.resolve_plan(squad, game._board()))
				ran[PLAYER_PLAN] += 1
			around.call(label, HOVER, func() -> void: sm.preview_aim(squad, aim, game._board()))
			ran[HOVER] += 1
		else:
			other = true
			around.call(label, HOVER_ALT, func() -> void:
				sm.preview_aim(squad, aim, game._board(), option.source))
			ran[HOVER_ALT] += 1


# An aim with `option` at the first cell it can reach that holds a hostile unit, or null for none.
static func _declare_at_a_foe(unit: Unit, option: Unit.AimOption, board: BoardContext) -> AttackAction:
	var origin := unit.get_projected_destination()
	return unit.with_weapon_in_hand(option.source, func() -> AttackAction:
		for cell in Reach.get_all_attack_cells_from(unit, origin, option.attack):
			if not Reach.can_aim_at(unit, origin, cell, option.attack, board):
				continue
			var foe := board.projected_unit_at_cell(cell)
			if foe == null or not RulesService.can_target(unit, foe):
				continue
			var held := unit.active_attack
			unit.active_attack = option.attack
			var aim := AttackAction.declare(unit, origin, cell)
			unit.active_attack = held
			return aim
		return null)
