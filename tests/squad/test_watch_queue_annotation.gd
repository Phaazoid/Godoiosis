# A queued walk that crosses an armed watch says so ON ITS OWN ROW (#413/#592,
# docs/design/standing-reactions.md): "triggers Bern's watch — takes 12 from Overwatch", stacking
# when one route crosses several.
#
# Law #2 is what makes this a defect rather than a polish item: the shot resolves, lands, and moves
# HP, so a queue that does not mention it is previewing less than execution delivers. And #412's
# whole payoff is dragging a move row and watching who eats the shot change -- feedback that has to
# be on the row being dragged.
#
# The hop under test is the one nothing covered: test_move_order_is_the_clock.gd proves
# plan.watch_shots is POPULATED, and the render end appends whatever it is handed. Between them sits
# ActionQueueDisplayEntry.build_for, and it was never asked whether the note reaches the row.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

# The watched column, and the row the crosser walks along.
const WATCHED: Array[Vector2i] = [Vector2i(2, 0), Vector2i(2, 1)]

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)


func _main_of(unit: Unit) -> WeaponAttackData:
	return (unit.get_equipped_weapon() as WeaponInstance).template.main_attack


# An enemy standing off to the side with a live watch over WATCHED. Its own cell is the anchor.
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


# The resolver hands back live volley arrays; the suite's teardown is happier without the cycles.
func _break_volleys(plan: ResolvedPlan) -> void:
	var empty: Array[AttackAction] = []
	for atk in plan.attacks:
		atk.volley = empty
	for shot in plan.watch_shots:
		shot.volley = empty


# Every annotation the panel would draw, across every row, flattened -- the question is "does the
# player read this anywhere", not which row index it lands on.
func _annotations(entries: Array) -> Array[String]:
	var out: Array[String] = []
	for entry: ActionQueueDisplayEntry in entries:
		for note: String in entry.annotations:
			out.append(note)
	return out


func _rows_for(squad: Squad, plan: ResolvedPlan) -> Array:
	return ActionQueueDisplayEntry.build_for(squad, plan)


# ==============================================================================
#  The headline
# ==============================================================================

func test_a_walk_into_a_watch_annotates_its_own_move_row() -> void:
	var watcher := _watcher()
	var crosser := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.MHP: 60}, false)
	crosser.squad._queue_action(_walk(crosser))

	var plan := _sm.resolve_plan(crosser.squad, _board_with([watcher, crosser]))
	assert_int(plan.watch_shots.size()).override_failure_message(
			"the watch never fired -- the fixture is not exercising the rule").is_equal(1)

	var entries := _rows_for(crosser.squad, plan)
	var notes := _annotations(entries)

	assert_array(notes).override_failure_message(
			"the queue drew no annotation for a walk that takes a watch shot -- the player is not "
			+ "told about a hit the plan already resolved (Law #2)").is_not_empty()
	assert_str(notes[0]).contains("watch")
	_break_volleys(plan)


# The note rides the CROSSER's own row, not some other row in the section: #412's payoff is watching
# it move as you drag that row, so landing it on a squadmate's would be worse than nothing.
func test_the_note_lands_on_the_crossers_row_and_not_a_squadmates() -> void:
	var watcher := _watcher()
	var crosser := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.MHP: 60}, false)
	var bystander := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 3), {Stats.Stat.MHP: 60}, false)
	_sm.join_squad(bystander, crosser.squad)
	crosser.squad._queue_action(_walk(crosser))
	crosser.squad._queue_action(_walk(bystander))

	var plan := _sm.resolve_plan(crosser.squad, _board_with([watcher, crosser, bystander]))

	var carried: Array[Unit] = []
	for entry: ActionQueueDisplayEntry in _rows_for(crosser.squad, plan):
		if not entry.annotations.is_empty() and entry.action != null:
			carried.append(entry.action.actor)

	assert_array(carried).override_failure_message(
			"no row carried the note at all").is_not_empty()
	assert_object(carried[0]).override_failure_message(
			"the note landed on a row whose walk crosses nothing").is_same(crosser)
	_break_volleys(plan)
