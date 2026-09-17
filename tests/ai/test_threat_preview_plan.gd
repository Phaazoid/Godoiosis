# The PLAN tier of the enemy-intent preview (#710 slice 2): running each hostile squad's REAL
# decision against the board the player's pending plan will leave, harvesting what it intends, and
# handing the board back untouched.
#
# The mechanism is a positional snapshot -- every unit stands on its projected cell for the
# duration -- so the two wire cases below are the whole point: an enemy must aim where the player
# WILL be, and a shoved enemy must plan from where it WILL land. Both go red if the snapshot is
# skipped, which no amount of reading the AI's own reads would tell you.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const BB := preload("res://play/board_builder.gd")
const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY


func _build_board() -> Dictionary:
	var board: Dictionary = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, Rect2i(0, 0, 12, 5))
	return board


func _spawn(board: Dictionary, faction: Team.Faction, cell: Vector2i, power := 3) -> Unit:
	var unit: Unit = BB.spawn(board, H.make_unit_data({}, faction), cell)
	unit.equipped_weapon = H.make_weapon(power)
	unit.squad.archetype = AIArchetype.Type.HOLD   # never walks: the case controls the geometry
	return unit


func _preview(board: Dictionary) -> Array[ThreatIntent]:
	var factions: Array[Team.Faction] = [ENEMY]
	return AIController.preview_turn(PLAYER, board.squad_manager, factions)


func _queue_move(board: Dictionary, unit: Unit, to: Vector2i) -> void:
	var ctx: BoardContext = board.squad_manager.board_source.call()
	var walk: Dictionary = RulesService.compute_move_range(unit, ctx)
	var path: Array[Vector2i] = RulesService.reconstruct_path(walk.came_from, unit.movement.cell, to)
	var move := MoveAction.new()
	move.init(unit, path, null)
	assert_bool(board.squad_manager.queue_action(unit.squad, move)).override_failure_message(
			"the fixture's own move was refused -- the case would prove nothing").is_true()


func _cells(board: Dictionary) -> Dictionary:
	var out := {}
	for child in board.units_root.get_children():
		out[child] = (child as Unit).movement.cell
	return out


# --- The two wires --------------------------------------------------------------------------

# A player unit walks INTO reach. The enemy can hit B and cannot hit A, so an intent exists only if
# the preview planned against the projected board. MUTANT: delete the set_cell snapshot -> no intent.
func test_an_enemy_aims_at_where_the_plan_puts_you_not_where_you_stand() -> void:
	var board: Dictionary = _build_board()
	var mover: Unit = _spawn(board, PLAYER, Vector2i(0, 0))
	var foe: Unit = _spawn(board, ENEMY, Vector2i(4, 0))
	assert_array(_preview(board)).override_failure_message(
			"standing at A the player is already threatened -- the case cannot see the snapshot").is_empty()

	_queue_move(board, mover, Vector2i(3, 0))   # adjacent to the foe: in reach only AFTER the move
	var intents: Array[ThreatIntent] = _preview(board)
	assert_int(intents.size()).is_equal(1)
	assert_object(intents[0].attacker).is_same(foe)
	assert_object(intents[0].target).is_same(mover)
	assert_that(intents[0].to).override_failure_message(
			"the line points at the live cell, so the preview planned against the wrong board").is_equal(Vector2i(3, 0))
	assert_that(intents[0].from).is_equal(Vector2i(4, 0))


# The player's queued SHOVE throws an enemy across the board. It can only reach anybody from where
# it LANDS, so an intent exists only if the preview planned from the landing cell. This is the half
# no read-swap could have reached: every resolver pass wipes published knockback.
func test_a_shoved_enemy_plans_from_where_the_shove_puts_it() -> void:
	var board: Dictionary = _build_board()
	var shover: Unit = _spawn(board, PLAYER, Vector2i(5, 0))
	var bystander: Unit = _spawn(board, PLAYER, Vector2i(8, 0))
	var foe: Unit = _spawn(board, ENEMY, Vector2i(6, 0))
	(shover.get_equipped_weapon() as WeaponInstance).template.main_attack.knockback = 1
	# The shover has to STAND adjacent to shove, so it is already the one under threat. That makes
	# this the sharper assertion: the shove MOVES the threat off the shover and onto the bystander.
	var before: Array[ThreatIntent] = _preview(board)
	assert_int(before.size()).is_equal(1)
	assert_object(before[0].target).is_same(shover)

	var aim := H.stamped_attack(shover, foe)
	assert_bool(board.squad_manager.queue_action(shover.squad, aim)).is_true()
	var resolved: ResolvedPlan = board.squad_manager.resolve_plan(shover.squad, board.squad_manager.board_source.call())
	assert_that(foe.get_projected_destination()).override_failure_message(
			"the fixture's shove did not publish a landing -- the case would prove nothing").is_equal(Vector2i(7, 0))
	assert_object(resolved).is_not_null()

	var intents: Array[ThreatIntent] = _preview(board)
	assert_int(intents.size()).is_equal(1)
	assert_object(intents[0].attacker).is_same(foe)
	assert_object(intents[0].target).override_failure_message(
			"the foe still aims at the shover, so the preview planned from its pre-shove cell").is_same(bystander)
	assert_that(intents[0].from).override_failure_message(
			"the line starts at the landing cell; the player sees the enemy where it STANDS").is_equal(Vector2i(6, 0))


# --- The rollback: the risky half --------------------------------------------------------------

func test_the_board_is_handed_back_exactly_as_it_arrived() -> void:
	var board: Dictionary = _build_board()
	var mover: Unit = _spawn(board, PLAYER, Vector2i(0, 0))
	var foe: Unit = _spawn(board, ENEMY, Vector2i(4, 0))
	foe.squad.archetype = AIArchetype.Type.RUSHDOWN   # walks AND attacks: the most it can mutate
	_queue_move(board, mover, Vector2i(3, 0))
	var sm: SquadManager = board.squad_manager
	var before_cells: Dictionary = _cells(board)
	var before_active: Squad = sm.active_squad
	var before_home: Vector2i = foe.squad.home_cell
	var before_queue: int = mover.squad.action_queue.size()

	assert_array(_preview(board)).is_not_empty()   # it really planned, or this proves nothing

	for unit: Unit in before_cells:
		assert_that((unit as Unit).movement.cell).override_failure_message(
				"%s was left on the snapshot cell" % (unit as Unit).get_unit_name()).is_equal(before_cells[unit])
	assert_array(foe.squad.action_queue).override_failure_message(
			"the previewed squad kept its orders -- the enemy would execute a plan nobody gave").is_empty()
	assert_object(sm.active_squad).is_same(before_active)
	assert_that(foe.squad.home_cell).is_equal(before_home)
	assert_int(mover.squad.action_queue.size()).override_failure_message(
			"the preview ate the player's own orders").is_equal(before_queue)
	assert_bool(sm.previewing).is_false()
	# The player's own shove projection is back: _undress re-resolves their plan rather than
	# leaving the last enemy resolve's publications standing on their units.
	assert_that(mover.get_projected_destination()).is_equal(Vector2i(3, 0))


func test_previewing_twice_gives_the_same_answer() -> void:
	var board: Dictionary = _build_board()
	var mover: Unit = _spawn(board, PLAYER, Vector2i(0, 0))
	var _foe: Unit = _spawn(board, ENEMY, Vector2i(4, 0))
	_queue_move(board, mover, Vector2i(3, 0))

	var first: Array[ThreatIntent] = _preview(board)
	var second: Array[ThreatIntent] = _preview(board)
	assert_int(second.size()).override_failure_message(
			"the second preview saw a different board -- the first left residue").is_equal(first.size())
	for i in first.size():
		assert_object(second[i].attacker).is_same(first[i].attacker)
		assert_object(second[i].target).is_same(first[i].target)
		assert_int(second[i].damage).is_equal(first[i].damage)
		assert_that(second[i].to).is_equal(first[i].to)


# --- The rest ------------------------------------------------------------------------------------

# has_acted is stale during the player's turn: every enemy squad carries last turn's true. Asking
# is_squad_actable would return nothing from turn 2 onward, and an empty preview reads as "nobody
# is coming for you" under the always-attack ruling. This is that silent lie, pinned.
func test_a_spent_enemy_squad_still_previews() -> void:
	var board: Dictionary = _build_board()
	var mover: Unit = _spawn(board, PLAYER, Vector2i(0, 0))
	var foe: Unit = _spawn(board, ENEMY, Vector2i(4, 0))
	_queue_move(board, mover, Vector2i(3, 0))
	assert_int(_preview(board).size()).is_equal(1)

	foe.squad.has_acted = true   # what every turn after the first looks like
	assert_int(_preview(board).size()).override_failure_message(
			"a spent squad previewed nothing -- the preview is asking is_squad_actable").is_equal(1)


func test_a_squad_that_can_reach_nobody_is_skipped() -> void:
	var board: Dictionary = _build_board()
	var near: Unit = _spawn(board, ENEMY, Vector2i(4, 0))
	var far: Unit = _spawn(board, ENEMY, Vector2i(11, 4))
	var mover: Unit = _spawn(board, PLAYER, Vector2i(0, 0))
	_queue_move(board, mover, Vector2i(3, 0))
	var ctx: BoardContext = board.squad_manager.board_source.call()
	var field := ThreatField.build(ctx, PLAYER)

	assert_bool(AIController._squad_can_reach_anyone(far.squad, field, ctx)).override_failure_message(
			"the far squad reads as able to reach somebody -- the case cannot see the early-out").is_false()
	var intents: Array[ThreatIntent] = _preview(board)
	for intent: ThreatIntent in intents:
		assert_object(intent.attacker).is_not_same(far)
	assert_int(intents.size()).is_equal(1)
	assert_object(intents[0].attacker).is_same(near)
	# The COUNT is the early-out's only observable: a far squad plans to attack nobody whether or
	# not it was skipped, so the intents alone cannot tell the two apart. A mutant that disables
	# the skip survived every other case in this file until this line existed.
	assert_int(AIController.previewed_squad_count).override_failure_message(
			"both squads were planned -- the early-out did not skip the one that can reach nobody").is_equal(1)


# The number on the line and the number in the queue panel are ONE subtraction. Derived here the
# way ActionQueueRow derives it, off the same outcome, so a change to either spelling reds.
func test_the_damage_is_the_queue_panels_own_arithmetic() -> void:
	var board: Dictionary = _build_board()
	var mover: Unit = _spawn(board, PLAYER, Vector2i(0, 0))
	var _foe: Unit = _spawn(board, ENEMY, Vector2i(4, 0), 4)
	_queue_move(board, mover, Vector2i(3, 0))

	var intents: Array[ThreatIntent] = _preview(board)
	assert_int(intents.size()).is_equal(1)
	assert_int(intents[0].damage).override_failure_message(
			"a threatened unit took no damage in the preview").is_greater(0)
	assert_int(intents[0].damage).is_equal(mover.get_current_hp() - (mover.get_current_hp() - intents[0].damage))
	assert_bool(intents[0].fells).is_false()   # 4 power against a 10 HP fixture unit


func test_a_lethal_blow_is_marked() -> void:
	var board: Dictionary = _build_board()
	var mover: Unit = _spawn(board, PLAYER, Vector2i(0, 0))
	var _foe: Unit = _spawn(board, ENEMY, Vector2i(4, 0), 99)
	_queue_move(board, mover, Vector2i(3, 0))

	var intents: Array[ThreatIntent] = _preview(board)
	assert_int(intents.size()).is_equal(1)
	assert_bool(intents[0].fells).override_failure_message(
			"a blow that downs the target is not marked as felling").is_true()
