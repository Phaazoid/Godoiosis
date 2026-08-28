# A queued walk that crosses an armed watch grows a ROW for the shot (#413/#592), indented under the
# move that took it — the same shape an expanded volley's hits already use (dev, 2026-08-27: "we
# already draw indented rows for aoe attacks, please match that style").
#
# The hop under test is the one nothing covered: test_move_order_is_the_clock.gd proves
# plan.watch_shots is POPULATED, and the panel draws whatever entries it is handed. Between them
# sits ActionQueueDisplayEntry.build_for, and it was never asked whether the shot reaches a row.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

const WATCHED: Array[Vector2i] = [Vector2i(2, 0), Vector2i(2, 1)]

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)


func _main_of(unit: Unit) -> WeaponAttackData:
	return (unit.get_equipped_weapon() as WeaponInstance).template.main_attack


func _watcher(cell := Vector2i(2, 5), power := 6) -> Unit:
	var unit := H.spawn_solo(self, _sm, ENEMY, cell, {Stats.Stat.STR: 4}, true, power)
	unit.arm_watch(cell, WATCHED[0], WATCHED, _main_of(unit))
	return unit


func _walk(unit: Unit) -> MoveAction:
	var path: Array[Vector2i] = []
	for x in range(unit.movement.cell.x, 5):
		path.append(Vector2i(x, unit.movement.cell.y))
	var move := MoveAction.new()
	move.init(unit, path, null)
	return move


func _board_with(units_in: Array) -> BoardContext:
	var units: Array[Unit] = []
	units.assign(units_in)
	return BoardContext.new(_sm.grid, units, _sm)


func _break_volleys(plan: ResolvedPlan) -> void:
	var empty: Array[AttackAction] = []
	for atk in plan.attacks:
		atk.volley = empty
	for shot in plan.watch_shots:
		shot.volley = empty


func _entries(squad: Squad, plan: ResolvedPlan) -> Array:
	return ActionQueueDisplayEntry.build_for(squad, plan)


# ==============================================================================
#  The headline
# ==============================================================================

# The row exists, it is INDENTED under the move, and it carries the shot itself -- which is what
# lets it draw the firing unit, the attack icon and the unit getting hit with no new display code.
func test_a_walk_into_a_watch_grows_an_indented_row_for_the_shot() -> void:
	var watcher := _watcher()
	var crosser := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.MHP: 60}, false)
	crosser.squad._queue_action(_walk(crosser))

	var plan := _sm.resolve_plan(crosser.squad, _board_with([watcher, crosser]))
	assert_int(plan.watch_shots.size()).override_failure_message(
			"the watch never fired -- the fixture is not exercising the rule").is_equal(1)

	var nested: Array[ActionQueueDisplayEntry] = []
	for entry: ActionQueueDisplayEntry in _entries(crosser.squad, plan):
		if entry.entry_type == ActionQueueDisplayEntry.EntryType.ACTION and entry.indent_level > 0:
			nested.append(entry)

	assert_int(nested.size()).override_failure_message(
			"the queue grew no row for a walk that takes a watch shot -- the player is not told "
			+ "about a hit the plan already resolved (Law #2)").is_equal(1)
	assert_object(nested[0].action).override_failure_message(
			"the row carries something other than the derived shot").is_same(plan.watch_shots[0])
	_break_volleys(plan)


# The row's THREE faces, which is what the dev asked for: the firing unit, the attack, the unit
# getting hit. Asked of the action rather than of a built row, because the action is what the row
# reads -- and it is the same surface every other queue row uses.
func test_the_row_names_the_watcher_the_attack_and_the_victim() -> void:
	var watcher := _watcher()
	var crosser := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.MHP: 60}, false)
	crosser.squad._queue_action(_walk(crosser))

	var plan := _sm.resolve_plan(crosser.squad, _board_with([watcher, crosser]))
	var shot: AttackAction = plan.watch_shots[0]

	assert_object(shot.actor).override_failure_message(
			"the row would draw the wrong unit as the one firing").is_same(watcher)
	assert_object(shot.target).override_failure_message(
			"the row would draw the wrong unit as the one hit").is_same(crosser)
	assert_object(shot.get_actor_texture()).is_not_null()
	assert_object(shot.get_action_icon()).override_failure_message(
			"the row has no icon for the attack").is_not_null()
	assert_object(shot.get_target_texture()).is_not_null()
	_break_volleys(plan)


# It sits UNDER its own move, not loose in the section: the association is positional, exactly as an
# expanded volley's hits sit under their header.
func test_the_row_follows_the_crossers_move_and_not_a_squadmates() -> void:
	var watcher := _watcher()
	var crosser := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.MHP: 60}, false)
	var bystander := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 3), {Stats.Stat.MHP: 60}, false)
	_sm.join_squad(bystander, crosser.squad)
	crosser.squad._queue_action(_walk(crosser))
	crosser.squad._queue_action(_walk(bystander))

	var plan := _sm.resolve_plan(crosser.squad, _board_with([watcher, crosser, bystander]))
	var entries := _entries(crosser.squad, plan)

	var preceding: Unit = null
	for i in range(entries.size()):
		var entry: ActionQueueDisplayEntry = entries[i]
		if entry.entry_type != ActionQueueDisplayEntry.EntryType.ACTION:
			continue
		if entry.indent_level == 0:
			preceding = entry.action.actor
		else:
			assert_object(preceding).override_failure_message(
					"the shot row hangs off the wrong move").is_same(crosser)
	_break_volleys(plan)


# A derived row is nobody's order: it must not be draggable, or the player could sequence a
# consequence. BaseAction says yes by default, so this is a real answer AttackAction has to give.
func test_the_shot_row_is_not_reorderable() -> void:
	var watcher := _watcher()
	var crosser := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.MHP: 60}, false)
	crosser.squad._queue_action(_walk(crosser))

	var plan := _sm.resolve_plan(crosser.squad, _board_with([watcher, crosser]))

	assert_bool(plan.watch_shots[0].is_reorderable()).override_failure_message(
			"a watch shot is draggable -- it is derived, not an order anybody gave").is_false()
	_break_volleys(plan)
