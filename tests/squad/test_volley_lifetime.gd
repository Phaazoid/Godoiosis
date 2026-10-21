# A resolve's derived volleys die with their plan (#1359). A volley is a RefCounted cycle -- each
# member holds the shared array that holds it -- so before the fix every resolve_plan, every hover's
# preview_aim and every AI hypothetical left its hits alive for the rest of the session. ResolvedPlan
# breaks the cycle as it frees, which is the one point every drop and replacement passes through.
#
# Through the REAL resolve and the real hover call, because the leak is a fact about who holds what
# after them. Each case takes WEAK handles in a helper frame of its own, so no local here keeps a hit
# alive by accident, then drops the plan's last holder and asks whether anything survived.
#
# The other half is the queue panel, which re-renders from the rows it cached without re-resolving:
# those rows hold their plan (ActionQueueDisplayEntry.plan), so a hover's resolve cannot split the
# fold of a volley the panel is showing.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")
const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const TOUGH := {Stats.Stat.MHP: 60}
const AIM := Vector2i(1, 0)

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)


# A three-cell line east over two tough foes: a two-member volley, and the near foe counters.
func _line_attacker() -> Unit:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.MHP: 60, Stats.Stat.LDR: 3})
	P.line((attacker.get_equipped_weapon() as WeaponInstance).template.main_attack, 3)
	H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), TOUGH)
	H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 0), TOUGH)
	_sm.active_squad = attacker.squad
	attacker.squad._queue_action(AttackAction.declare(attacker, attacker.movement.cell, AIM))
	return attacker


func _board() -> BoardContext:
	return _sm.board_source.call()


# Weak handles on every derived hit `plan` holds.
static func _handles(plan: ResolvedPlan) -> Array[WeakRef]:
	var refs: Array[WeakRef] = []
	for list: Array in [plan.attacks, plan.counters, plan.watch_shots]:
		for member: AttackAction in list:
			refs.append(weakref(member))
	return refs


static func _alive(refs: Array[WeakRef]) -> int:
	var count := 0
	for handle in refs:
		if handle.get_ref() != null:
			count += 1
	return count


# The real resolve, handed back as handles only. The plan stays cached on the manager until the next.
func _resolve_held(squad: Squad) -> Array[WeakRef]:
	var plan := _sm.resolve_plan(squad, _board())
	return _handles(plan)


# One hover over the aim cell, the way HoverPresenter asks it: the forecast and the candidate it was
# built from come back as handles, and the forecast is dropped as the frame ends.
func _hover_held(attacker: Unit) -> Array[WeakRef]:
	var candidate := AttackAction.declare(attacker, attacker.movement.cell, AIM)
	var forecast := _sm.preview_aim(attacker.squad, candidate, _board())
	var refs := _handles(forecast)
	assert_int(forecast.attacks.size()).override_failure_message(
			"fixture: the hover should forecast the two-member line volley").is_equal(2)
	refs.append(weakref(candidate))
	return refs


func _churn(attacker: Unit, times: int) -> void:
	for i in times:
		_sm.resolve_plan(attacker.squad, _board())
		var candidate := AttackAction.declare(attacker, attacker.movement.cell, AIM)
		_sm.preview_aim(attacker.squad, candidate, _board())


func test_a_replaced_plan_frees_its_volley_and_its_counter() -> void:
	var attacker := _line_attacker()
	var refs := _resolve_held(attacker.squad)
	assert_int(refs.size()).override_failure_message(
			"fixture: the line should derive two hits and a counter, got %d actions" % refs.size()).is_equal(3)

	_sm.resolve_plan(attacker.squad, _board())   # replaces the cache, the plan's last holder

	assert_int(_alive(refs)).override_failure_message(
			"%d of %d derived actions outlived their plan" % [_alive(refs), refs.size()]).is_equal(0)


func test_a_hover_leaves_nothing_behind() -> void:
	var attacker := _line_attacker()

	var refs := _hover_held(attacker)

	assert_int(_alive(refs)).override_failure_message(
			"%d of %d of a hover's actions outlived its forecast" % [_alive(refs), refs.size()]).is_equal(0)


func test_resolving_and_hovering_over_and_over_holds_the_object_count_flat() -> void:
	var attacker := _line_attacker()
	_churn(attacker, 2)   # every lazy cache warm before the count is read
	var before := int(Performance.get_monitor(Performance.OBJECT_COUNT))

	_churn(attacker, 25)

	var grown := int(Performance.get_monitor(Performance.OBJECT_COUNT)) - before
	assert_int(grown).override_failure_message(
			"25 resolves and 25 hovers left %d objects behind" % grown).is_equal(0)


# A watch shot is a volley of its own, in its own list.
func test_a_watch_shot_frees_with_its_plan() -> void:
	var watched: Array[Vector2i] = [Vector2i(2, 0), Vector2i(2, 1)]
	var watcher := H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 5), {Stats.Stat.STR: 4})
	watcher.arm_watch(watcher.movement.cell, watched[0], watched,
			(watcher.get_equipped_weapon() as WeaponInstance).template.main_attack)
	var crosser := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), TOUGH, false)
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]
	var move := MoveAction.new()
	move.init(crosser, path, null)
	crosser.squad._queue_action(move)
	var refs := _shots_held(crosser.squad)

	_sm.resolve_plan(crosser.squad, _board())

	assert_int(_alive(refs)).override_failure_message(
			"%d of %d derived actions outlived their plan" % [_alive(refs), refs.size()]).is_equal(0)


func _shots_held(squad: Squad) -> Array[WeakRef]:
	var plan := _sm.resolve_plan(squad, _board())
	assert_int(plan.watch_shots.size()).override_failure_message(
			"fixture: the walk should cross the watch and take its shot").is_equal(1)
	assert_bool(plan.watch_shots[0].volley.is_empty()).override_failure_message(
			"fixture: the shot should be a volley, the shape that cycles").is_false()
	return _handles(plan)


# A payload's volley hangs off its parent by dropped_by, in the same list.
func test_a_payload_frees_with_its_plan() -> void:
	var carrier := WeaponAttackData.new()
	P.point(carrier, 1)
	carrier.power = 1
	var bomb := WeaponAttackData.new()
	P.point(bomb, 1)
	bomb.power = 1
	bomb.targets = EquippableData.TargetMode.BOTH
	carrier.payload = bomb
	var thrower := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), TOUGH)
	(thrower.get_equipped_weapon() as WeaponInstance).template.main_attack = carrier
	H.spawn_solo(self, _sm, ENEMY, Vector2i(0, -1), TOUGH)
	_sm.active_squad = thrower.squad
	thrower.squad._queue_action(AttackAction.declare(thrower, thrower.movement.cell, Vector2i(0, -1)))
	var refs := _payload_held(thrower.squad)

	_sm.resolve_plan(thrower.squad, _board())

	assert_int(_alive(refs)).override_failure_message(
			"%d of %d derived actions outlived their plan" % [_alive(refs), refs.size()]).is_equal(0)


func _payload_held(squad: Squad) -> Array[WeakRef]:
	var plan := _sm.resolve_plan(squad, _board())
	var dropped := 0
	for atk in plan.attacks:
		if atk.dropped_by != null:
			dropped += 1
	assert_int(dropped).override_failure_message("fixture: the hit should drop its bomb").is_equal(1)
	return _handles(plan)


# The panel caches the rows build_for made and re-renders from them (a volley toggle, a restyle)
# without re-resolving, while every hover replaces the manager's cached plan. The rows hold the plan.
func test_the_rows_the_panel_shows_keep_their_volley_through_a_hover() -> void:
	var attacker := _line_attacker()
	var entries := ActionQueueDisplayEntry.build_for(attacker.squad, _sm.resolve_plan(attacker.squad, _board()))
	var hits := _attack_rows(entries)
	assert_int(hits.size()).override_failure_message(
			"fixture: the panel should show the line's two hits").is_equal(2)

	_hover_held(attacker)   # the manager's cache moves on: the rows are the plan's last holder

	assert_bool(AttackAction.same_volley(hits[0], hits[1])).override_failure_message(
			"a hover's resolve split the volley the panel re-renders from").is_true()

	# ...and the plan still goes once the panel lets its rows go.
	var refs := _row_handles(entries)
	hits.clear()
	entries.clear()
	assert_int(_alive(refs)).override_failure_message(
			"%d of %d rows outlived the panel releasing them" % [_alive(refs), refs.size()]).is_equal(0)


static func _attack_rows(entries: Array[ActionQueueDisplayEntry]) -> Array[AttackAction]:
	var hits: Array[AttackAction] = []
	for entry in entries:
		if entry.action is AttackAction and not entry.action is CounterAttackAction:
			hits.append(entry.action as AttackAction)
	return hits


static func _row_handles(entries: Array[ActionQueueDisplayEntry]) -> Array[WeakRef]:
	var refs: Array[WeakRef] = []
	for entry in entries:
		if entry.action is AttackAction:
			refs.append(weakref(entry.action))
	return refs
