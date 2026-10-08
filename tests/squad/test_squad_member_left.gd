# squad_member_left (#367): every way a unit leaves a squad announces itself ONCE, says WHY, and is
# heard after the erase. The tether moments fork on the cause -- a voluntary leave reels in, a forced
# one breaks, a death or an undeploy is silent -- so each door is pinned to its own cause here.
#
# Driven through the real SquadManager (make_manager). A join out of a solo squad is itself a leave of
# that solo squad, so every case forgets what it heard while building its squad.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const ENEMY := Team.Faction.ENEMY
const Cause := SquadManager.LeaveCause

var _sm: SquadManager
var _heard: Array[Dictionary] = []


func before_test() -> void:
	_sm = H.make_manager(self)
	_heard = []
	_sm.squad_member_left.connect(_on_left)


func _on_left(squad: Squad, unit: Unit, cause: SquadManager.LeaveCause) -> void:
	_heard.append({"squad": squad, "unit": unit, "cause": cause, "still_listed": squad.members.has(unit)})


# A leader at the origin with `count` members beside it, and nothing heard yet.
func _squad(count: int, overrides: Dictionary = {}) -> Array[Unit]:
	var units: Array[Unit] = [H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0), overrides)]
	for i in count:
		var member: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(i + 1, 0))
		_sm.join_squad(member, units[0].squad)
		units.append(member)
	_heard = []
	return units


func _causes_of(unit: Unit) -> Array[int]:
	var causes: Array[int] = []
	for entry: Dictionary in _heard:
		if entry["unit"] == unit:
			causes.append(entry["cause"])
	return causes


func test_leave_squad_is_voluntary_and_heard_after_the_erase() -> void:
	var units := _squad(1)
	var squad := units[0].squad
	_sm.leave_squad(units[1])
	assert_int(_heard.size()).override_failure_message("a leave was announced %d times" % _heard.size()) \
			.is_equal(1)
	assert_int(int(_heard[0]["cause"])).is_equal(Cause.VOLUNTARY)
	assert_object(_heard[0]["squad"]).override_failure_message("the leave named the wrong squad").is_same(squad)
	assert_bool(bool(_heard[0]["still_listed"])).override_failure_message(
			"the signal fired before the unit was erased").is_false()


# Disband erased members directly, past the door the signal lives on, so it was the one loss nothing
# announced. Every member leaves, the leader too.
func test_disband_announces_every_member_including_the_leader() -> void:
	var units := _squad(2)
	_sm.disband_squad(units[0].squad)
	for unit in units:
		assert_array(_causes_of(unit)).override_failure_message(
				"a disbanded unit was not announced exactly once as voluntary").contains_exactly([Cause.VOLUNTARY])


func test_joining_another_squad_leaves_the_old_one_voluntarily() -> void:
	var units := _squad(1)
	var other: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 2))
	var old_squad := units[0].squad
	_heard = []
	_sm.join_squad(units[1], other.squad)
	assert_array(_causes_of(units[1])).contains_exactly([Cause.VOLUNTARY])
	assert_object(_heard[0]["squad"]).is_same(old_squad)


func test_losing_contact_is_forced() -> void:
	var units := _squad(1)
	units[1].movement.cell = Vector2i(12, 0)   # far past any cohesion range on open ground
	_sm.enforce_contact()
	assert_array(_causes_of(units[1])).contains_exactly([Cause.FORCED])


# I6's shape: the leader walks away, the new leader commands fewer, and the newest is ejected. The
# leader chose to go; the one ejected did not.
func test_a_new_leaders_ejection_is_forced_and_the_old_leaders_leave_is_not() -> void:
	var leader: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0), {Stats.Stat.LDR: 5})
	var near: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.LDR: 1})
	var newest: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 1), {Stats.Stat.LDR: 1})
	_sm.join_squad(near, leader.squad)
	_sm.join_squad(newest, leader.squad)
	_heard = []
	_sm.leave_squad(leader)
	assert_object(near.squad.leader).override_failure_message(
			"fixture: leadership did not pass to the near member").is_same(near)
	assert_array(_causes_of(leader)).contains_exactly([Cause.VOLUNTARY])
	assert_array(_causes_of(newest)).contains_exactly([Cause.FORCED])


func test_a_downing_is_downed() -> void:
	var units := _squad(1)
	_sm.handle_unit_downed(units[1])
	assert_array(_causes_of(units[1])).contains_exactly([Cause.DOWNED])


func test_a_death_is_death() -> void:
	var units := _squad(1)
	_sm.handle_unit_death(units[1])
	assert_array(_causes_of(units[1])).contains_exactly([Cause.DEATH])


func test_an_undeploy_is_a_release() -> void:
	var units := _squad(1)
	_sm.release(units[1])
	assert_array(_causes_of(units[1])).contains_exactly([Cause.RELEASE])


# A leader who dies DURING A WALK hands over at once but the reach check waits for the walk to end
# (#367): the walkers are mid-stride at the frame of the death, and animation must not decide who
# stays. OrderExecutor holds across the move phase; here the hold is driven directly.
func _held_handover_squad(members: Array[Vector2i], heir_cell: Vector2i) -> Array[Unit]:
	var leader: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0), {Stats.Stat.LDR: 10})
	var heir: Unit = H.spawn_solo(self, _sm, ENEMY, heir_cell, {Stats.Stat.LDR: 4})
	_sm.join_squad(heir, leader.squad)
	var units: Array[Unit] = [leader, heir]
	for cell in members:
		var member: Unit = H.spawn_solo(self, _sm, ENEMY, cell, {Stats.Stat.LDR: 1})
		_sm.join_squad(member, leader.squad)
		units.append(member)
	_heard = []
	return units


func test_a_handover_held_through_a_walk_judges_reach_where_the_walkers_end() -> void:
	var units := _held_handover_squad([Vector2i(0, 3), Vector2i(0, 4)], Vector2i(5, 0))
	var heir := units[1]
	var walker := units[2]
	var stays_out := units[3]

	_sm.hold_handovers()
	_sm.handle_unit_death(units[0])
	assert_object(heir.squad.leader).override_failure_message(
			"a held handover did not name its successor at once").is_same(heir)
	assert_array(_causes_of(walker) + _causes_of(stays_out)).override_failure_message(
			"a held handover judged reach mid-walk").is_empty()

	walker.movement.set_cell(Vector2i(4, 0))
	_sm.release_handovers()
	assert_array(_causes_of(walker)).override_failure_message(
			"the walker was judged where it stood at the death, not where its walk ended").is_empty()
	assert_array(_causes_of(stays_out)).contains_exactly([Cause.FORCED])


# Range, THEN capacity -- the order check_reassign_leader has always used. The heir holds three; the
# stranded member's leaving is what makes room for the newest, so a capacity check that ran at the
# death instead of the walk's end drops a member who should have stayed.
func test_a_held_handover_still_ejects_by_range_before_capacity() -> void:
	var units := _held_handover_squad([Vector2i(0, 6), Vector2i(4, 0), Vector2i(5, 1)], Vector2i(5, 0))
	assert_int(Squad.capacity_of(units[1])).override_failure_message(
			"fixture: the heir must hold exactly the three left once the stranded member goes").is_equal(3)
	var stranded := units[2]
	var newest := units[4]

	_sm.hold_handovers()
	_sm.handle_unit_death(units[0])
	_sm.release_handovers()
	assert_array(_causes_of(stranded)).contains_exactly([Cause.FORCED])
	assert_array(_causes_of(newest)).override_failure_message(
			"capacity was judged before range, and dropped the newest member").is_empty()
