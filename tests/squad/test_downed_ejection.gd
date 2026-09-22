# A unit that goes DOWN must leave its squad — and the whole mechanism that makes that happen was
# never connected in the real game.
#
# `Unit.went_downed` is emitted by `_go_downed`, and `OrderExecutor.on_unit_downed` is written to
# receive it, fill `_downed_pending`, and let `_process_downed_pending` eject the body at the end of
# the pass. Nothing in `game.gd` ever connected the two: measured 2026-07-29, the only
# `went_downed.connect` in the repo is in `play/play_session.gd`. So in the game, `_downed_pending`
# is never written, which makes BOTH of its consumers dead code:
#
#   * `_process_downed_pending` — no ejection, so a downed unit stays a squad member. That is the
#     reported symptom: `RulesService.compute_move_range` drops cells held by NON-squadmates, so an
#     unejected downed ally's tile stays a legal destination and units walk onto the body.
#   * the old `_offer_pending_crisis` — it iterated `_downed_pending`, so the Crisis prompt could
#     never fire. (That whole path is gone since #158; Crisis now enters directly in take_damage,
#     and the case pinning it lives at the bottom of this suite.)
#
# Note what this suite does NOT test: "is standing on a downed unit legal?" is answered *indirectly*,
# through squad membership, as a side effect of ejection ordering — nothing anywhere asks "is this
# unit downed?" when deciding occupancy. It works once the wiring is fixed, but it is one lifecycle
# hop away from breaking again, so `test_a_squadmate_cannot_stand_on_a_downed_body` is deliberately
# written against the OBSERVABLE rule rather than against membership.
#
# Needs the real game scene, because `game.spawn_unit` is where the connection belongs (next to the
# existing `unit_died` one) and it is the single door every board-entry path uses. Fixture is
# tests/ui/test_game_scene_smoke.gd's — see tests/README.md → Testing the game scene.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(8):
		game.grid.set_cell(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).is_not_null()
	unit.equipped_weapon = H.make_weapon()
	return unit


# Exactly its remaining HP: damage == hp means overkill 0, so LethalityRules picks a would-be-down
# rung rather than KILLED whatever the weapon math is. Tuning a real attack to land on DOWNED makes
# the test hostage to damage numbers that are still placeholder.
func _down(unit: Unit) -> void:
	unit.take_damage(unit.get_current_hp())
	assert_bool(unit.is_downed()).override_failure_message("fixture failed to DOWN the unit").is_true()


# Ejection is deferred to the end of a resolution pass on purpose (restructuring squads mid-await
# was buggy), so nothing settles until a pass runs. An empty queue is a complete, legal pass.
func _settle(bystander: Unit) -> void:
	await game.order_executor.execute_orders(bystander)


# ==============================================================================

func test_spawn_wires_the_down_signal() -> void:
	var unit := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	assert_int(unit.went_downed.get_connections().size()) \
		.override_failure_message("nothing listens to went_downed, so _downed_pending is never written") \
		.is_greater(0)


func test_a_downed_unit_leaves_its_squad() -> void:
	var leader := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var member := _spawn(Team.Faction.PLAYER, Vector2i(2, 0))
	var bystander := _spawn(Team.Faction.ENEMY, Vector2i(6, 0))
	await await_idle_frame()
	game.squad_manager.join_squad(member, leader.squad)

	_down(member)
	await _settle(bystander)

	assert_bool(leader.squad.get_members().has(member)) \
		.override_failure_message("a downed unit is still a squad member").is_false()
	assert_int(game.order_executor._downed_pending.size()) \
		.override_failure_message("_downed_pending did not drain").is_equal(0)
	assert_bool(member.is_downed()).is_true()          # ejected, not removed from the board
	assert_that(member.movement.cell).is_equal(Vector2i(2, 0))


# The reported symptom (dev, 2026-07-29): "AI walking on their own downed units, which should be not
# allowed squares." Asserted through the move range every mover consults, not through membership.
func test_a_squadmate_cannot_stand_on_a_downed_body() -> void:
	var leader := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var member := _spawn(Team.Faction.PLAYER, Vector2i(2, 0))
	var bystander := _spawn(Team.Faction.ENEMY, Vector2i(6, 0))
	await await_idle_frame()
	game.squad_manager.join_squad(member, leader.squad)

	# Baseline: while it is up, a squadmate's tile IS a legal destination -- squads rotate through
	# each other, and that is the rule the downed case has been riding on by accident.
	var before: Dictionary = RulesService.compute_move_range(leader, game._board())
	assert_bool(before.reachable.has(Vector2i(2, 0))) \
		.override_failure_message("fixture is wrong: an ACTIVE squadmate's cell should be reachable").is_true()

	_down(member)
	await _settle(bystander)

	var after: Dictionary = RulesService.compute_move_range(leader, game._board())
	assert_bool(after.reachable.has(Vector2i(2, 0))) \
		.override_failure_message("a unit may still end its move on top of a downed ally").is_false()


func test_a_downed_leader_hands_off_the_squad() -> void:
	var leader := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var member := _spawn(Team.Faction.PLAYER, Vector2i(2, 0))
	var bystander := _spawn(Team.Faction.ENEMY, Vector2i(6, 0))
	await await_idle_frame()
	game.squad_manager.join_squad(member, leader.squad)
	var squad: Squad = leader.squad

	_down(leader)
	await _settle(bystander)

	# Ejection routes through _detach_from_current_squad, which calls check_reassign_leader. Without
	# it the squad keeps a downed leader, and since every member's move range is leashed to
	# get_projected_destination() of that leader, the whole squad stays tethered to a body.
	assert_object(member.squad.leader) \
		.override_failure_message("the squad is still led by a downed unit").is_not_same(leader)
	assert_bool(member.squad.get_members().has(leader)).is_false()


# #124: a rescue queued in the SAME pass as the down it answers, as the WHOLE sequence -- authored
# through the production gate against a target that is still STANDING, the attack drops it mid-pass,
# the side channel picks it up, and the sweep still ejects it (revive does NOT re-enlist) and spends
# its turn. Falsified by forcing RulesService.is_rescueable to ignore the plan: the rescue can then
# never be authored and the queued assert goes red.
func test_a_same_pass_rescue_revives_ejects_and_spends() -> void:
	# LDR 10: the fixture default (3) feeds two members at MEMBER_LDR_COST 2 each.
	var leader: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.LDR: 10}, Team.Faction.PLAYER), Vector2i(1, 0))
	leader.equipped_weapon = H.make_weapon()
	var victim := _spawn(Team.Faction.PLAYER, Vector2i(2, 0))
	var rescuer := _spawn(Team.Faction.PLAYER, Vector2i(3, 0))
	var _bystander := _spawn(Team.Faction.ENEMY, Vector2i(6, 0))
	await await_idle_frame()
	game.squad_manager.join_squad(victim, leader.squad)
	game.squad_manager.join_squad(rescuer, leader.squad)
	assert_int(leader.squad.get_members().size()) \
		.override_failure_message("fixture failed to build the three-member squad").is_equal(3)

	victim.take_damage(victim.get_current_hp() - 1)   # bloodied: the NEXT hit is a would-be-down
	assert_bool(victim.is_active()).is_true()

	(leader.equipped_weapon as WeaponInstance).template.main_attack.hits_allies = true
	var aim := AttackAction.create(leader, Vector2i(1, 0), null, Vector2i(2, 0))
	aim.fired_attack = leader.get_fired_attack()
	assert_bool(game.squad_manager.queue_action(leader.squad, aim)) \
		.override_failure_message("fixture failed to queue the friendly-fire attack").is_true()
	game.refresh_action_queue(leader.squad)   # the real path: resolve -> store the plan the gate reads

	game.queue_rescue(rescuer, victim, victim.get_projected_destination())
	var rescue: RescueAction = null
	for action in leader.squad.action_queue:
		if action is RescueAction:
			rescue = action as RescueAction
	assert_object(rescue) \
		.override_failure_message("the gate refused a rescue against a predicted down (#124)").is_not_null()
	assert_bool(rescue.is_valid).is_true()

	var old_squad: Squad = leader.squad
	await game.order_executor.execute_orders(leader)

	assert_bool(victim.is_active()) \
		.override_failure_message("the same-pass rescue never revived the victim").is_true()
	assert_bool(old_squad.get_members().has(victim)) \
		.override_failure_message("revived mid-pass but never ejected -- revive must not re-enlist").is_false()
	assert_bool(victim.squad.has_acted) \
		.override_failure_message("a rescued unit is SPENT the turn it is rescued").is_true()
	assert_int(game.order_executor._downed_pending.size()) \
		.override_failure_message("_downed_pending did not drain").is_equal(0)


# #158, through the REAL executor: an armed berserker dropped mid-pass enters Crisis inside the
# hit itself -- no prompt, no poll, no down -- and is therefore NEVER ejected: it keeps its squad,
# which is the observable difference between the gambit and a down-then-rescue. Falsified by
# reverting take_damage's CRISIS arm: the unit downs, gets ejected, and the membership assert reds.
func test_an_armed_squadmate_enters_crisis_mid_pass_and_keeps_its_squad() -> void:
	var leader: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.LDR: 10}, Team.Faction.PLAYER), Vector2i(1, 0))
	leader.equipped_weapon = H.make_weapon()
	var victim: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.WIL: 20}, Team.Faction.PLAYER), Vector2i(2, 0))
	victim.unit_instance.jobs.append("berserker")
	var _bystander := _spawn(Team.Faction.ENEMY, Vector2i(6, 0))
	await await_idle_frame()
	game.squad_manager.join_squad(victim, leader.squad)

	victim.take_damage(victim.get_current_hp() - 1)   # bloodied: the queued hit is a would-be-down
	(leader.equipped_weapon as WeaponInstance).template.main_attack.hits_allies = true
	var aim := AttackAction.create(leader, Vector2i(1, 0), null, Vector2i(2, 0))
	aim.fired_attack = leader.get_fired_attack()
	assert_bool(game.squad_manager.queue_action(leader.squad, aim)) \
		.override_failure_message("fixture failed to queue the friendly-fire attack").is_true()

	await game.order_executor.execute_orders(leader)

	assert_bool(victim.in_crisis).override_failure_message("the armed gambit never fired").is_true()
	assert_bool(victim.is_active()).is_true()
	assert_int(victim.get_current_hp()).is_equal(Abilities.CRISIS_REVIVE_HP)
	assert_bool(leader.squad.get_members().has(victim)) \
		.override_failure_message("a Crisis unit must keep its squad -- it never went down").is_true()
	assert_int(game.order_executor._downed_pending.size()).is_equal(0)


# THE REPORTED BUG, end to end through the real executor (#1005). The dev's words: "The overwatch
# shot then downed the priest mid combat, and then while downed, the priest healed himself, thus
# being down but with health."
#
# Driven as the real sequence rather than by downing the priest by hand, because the ORDERING is
# the whole fault: the watch fires in the MOVE phase and the heal is resolved in the ATTACK phase,
# so the only gate that can catch it is one reading the pass's own threaded lifecycle. The two
# assertions are the dev's two sentences -- the body stays down, and it stays at the 1 HP a down
# clings at. A heal on a downed unit is legal and will MEAN something (#1002); what is refused
# here is the body ACTING.
func test_a_priest_the_watch_downs_mid_pass_does_not_heal_itself() -> void:
	var leader: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.LDR: 10}, Team.Faction.PLAYER), Vector2i(2, 0))
	leader.equipped_weapon = H.make_weapon()
	var priest := _spawn(Team.Faction.PLAYER, Vector2i(4, 0))
	var watcher := _spawn(Team.Faction.ENEMY, Vector2i(7, 0))
	await await_idle_frame()
	game.squad_manager.join_squad(priest, leader.squad)

	var mend: WeaponAttackData = (priest.equipped_weapon as WeaponInstance).template.main_attack
	mend.heals = true
	mend.hits_self = true

	# The watch spans the cell the leader walks onto AND the one the priest is standing on, which
	# is the board the report was made on, and the bystander eats a shot somebody else set off. The
	# report predates #1040, when the shot swept its whole footprint; a line now takes one target,
	# so the two cells are two one-tile PATHS (#1054 ruling 7) and each takes its own.
	var watched: Array[Vector2i] = [Vector2i(3, 0), Vector2i(4, 0)]
	var one_tile_each: Array[int] = [1, 1]
	watcher.arm_watch(watcher.movement.cell, Vector2i(3, 0), watched,
			(watcher.equipped_weapon as WeaponInstance).template.main_attack, false, false, one_tile_each)

	priest.take_damage(priest.get_current_hp() - 1)   # one hit from going down
	var walk: Array[Vector2i] = [Vector2i(2, 0), Vector2i(3, 0)]
	var move := MoveAction.new()
	move.init(leader, walk, null)
	assert_bool(game.squad_manager.queue_action(leader.squad, move)) \
		.override_failure_message("fixture failed to queue the walk into the watch").is_true()
	var heal := H.stamped_attack(priest, priest)
	assert_bool(game.squad_manager.queue_action(leader.squad, heal)) \
		.override_failure_message("fixture failed to queue the self-heal").is_true()

	await game.order_executor.execute_orders(leader)

	assert_bool(priest.is_downed()) \
		.override_failure_message("fixture: the watch shot did not DOWN the priest").is_true()
	assert_int(priest.get_current_hp()) \
		.override_failure_message("the downed priest healed itself -- down, but with health (#1005)") \
		.is_equal(1)
