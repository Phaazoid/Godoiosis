# SquadTetherPresenter (#367): which membership changes become tether MOMENTS. It diffs member->leader
# links once per operation, so these cases drive whole operations through the real SquadManager and
# read what landed in the store (OverlayManager.squad_tether_moments) -- never a signal count, since
# one operation can emit several.
#
# A stand-in Game carries the three things the presenter reaches for. The reel-in time is SET here and
# restored, so the re-point delay is pinned as a relationship and never as the tuned number.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const Moment := SquadLines2D.Moment


class FakeGame extends Node:
	var squad_manager: SquadManager
	var overlay_manager: OverlayManager

	func _board() -> BoardContext:
		return squad_manager.board_source.call()


var _sm: SquadManager
var _om: OverlayManager
var _presenter: SquadTetherPresenter
var _saved_reel := 0.0


func before_test() -> void:
	_saved_reel = SquadLines2D.REEL_IN_SECONDS
	SquadLines2D.REEL_IN_SECONDS = 0.5
	_sm = H.make_manager(self)
	_om = _sm.get_node("../OverlayManager")
	var game: FakeGame = auto_free(FakeGame.new())
	game.squad_manager = _sm
	game.overlay_manager = _om
	add_child(game)
	_presenter = SquadTetherPresenter.new()
	_presenter.game = game
	game.add_child(_presenter)


func after_test() -> void:
	SquadLines2D.REEL_IN_SECONDS = _saved_reel


func _solo(cell: Vector2i, ldr := 3) -> Unit:
	var unit: Unit = H.spawn_solo(self, _sm, PLAYER, cell, {Stats.Stat.LDR: ldr})
	return unit


# The moments now in the store that match, from and to by where the two bodies stand.
func _moments(moment: int, member: Unit = null, leader: Unit = null) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry: Dictionary in _om.squad_tether_moments:
		if entry["moment"] != moment:
			continue
		if member != null and entry["from"] != member.movement.cell:
			continue
		if leader != null and entry["to"] != leader.movement.cell:
			continue
		found.append(entry)
	return found


func test_a_join_draws_the_new_tether_in_at_once() -> void:
	var leader := _solo(Vector2i(0, 0))
	var recruit := _solo(Vector2i(1, 0))
	_presenter.arm()
	_sm.join_squad(recruit, leader.squad)
	# No flush: a join settles the moment it is emitted, which is what lets Squad Up's redraw, one line
	# later in the same frame, find the tether already held back.
	assert_int(_om.squad_tether_moments.size()).override_failure_message(
			"a join played %d moments" % _om.squad_tether_moments.size()).is_equal(1)
	assert_int(_moments(Moment.DRAW_IN, recruit, leader).size()).override_failure_message(
			"the join did not draw the recruit's tether in to its leader").is_equal(1)
	assert_int(int(_om.squad_tether_moments[0]["start_msec"])).override_failure_message(
			"a plain join waited before drawing in").is_less_equal(Time.get_ticks_msec())


func test_a_voluntary_leave_reels_the_tether_in() -> void:
	var leader := _solo(Vector2i(0, 0))
	var member := _solo(Vector2i(1, 0))
	_sm.join_squad(member, leader.squad)
	_presenter.arm()
	_sm.leave_squad(member)
	_presenter.flush()
	assert_int(_om.squad_tether_moments.size()).is_equal(1)
	assert_int(_moments(Moment.REEL_IN, member, leader).size()).override_failure_message(
			"Leave Squad did not reel the member's tether into its leader").is_equal(1)


func test_a_disband_reels_every_tether_in() -> void:
	var leader := _solo(Vector2i(0, 0))
	var a := _solo(Vector2i(1, 0))
	var b := _solo(Vector2i(0, 1))
	_sm.join_squad(a, leader.squad)
	_sm.join_squad(b, leader.squad)
	_presenter.arm()
	_sm.disband_squad(leader.squad)
	_presenter.flush()
	assert_int(_om.squad_tether_moments.size()).is_equal(2)
	assert_int(_moments(Moment.REEL_IN, a, leader).size()).is_equal(1)
	assert_int(_moments(Moment.REEL_IN, b, leader).size()).is_equal(1)


# The dev's ruling: the tethers to the old leader play their exit, THEN each remaining member draws a
# tether to the new leader. The new leader's own old link reels in too; it leads nobody's tether.
func test_a_leader_leaving_reels_the_old_links_in_then_draws_the_new_leaders() -> void:
	var leader := _solo(Vector2i(0, 0), 5)
	var heir := _solo(Vector2i(1, 0), 4)
	var other := _solo(Vector2i(0, 1), 2)
	_sm.join_squad(heir, leader.squad)
	_sm.join_squad(other, leader.squad)
	_presenter.arm()
	_sm.leave_squad(leader)
	_presenter.flush()
	assert_object(other.squad.leader).override_failure_message(
			"fixture: leadership did not pass to the heir").is_same(heir)

	var reels := _moments(Moment.REEL_IN)
	assert_int(reels.size()).override_failure_message("the old leader's links did not all reel in") \
			.is_equal(2)
	assert_int(_moments(Moment.REEL_IN, heir, leader).size()).is_equal(1)
	assert_int(_moments(Moment.REEL_IN, other, leader).size()).is_equal(1)
	var draws := _moments(Moment.DRAW_IN)
	assert_int(draws.size()).override_failure_message("the new leader's links did not draw in") \
			.is_equal(1)
	assert_int(_moments(Moment.DRAW_IN, other, heir).size()).is_equal(1)
	var waited := int(draws[0]["start_msec"]) - int(reels[0]["start_msec"])
	assert_int(waited).override_failure_message(
			"the new leader's tether did not wait for the old ones to reel in (waited %d ms)" % waited) \
			.is_equal(int(SquadLines2D.REEL_IN_SECONDS * 1000.0))


# A member the new leader cannot hold is ejected in the same call. Its old link ended because IT was
# thrown out, not because its leader walked -- so no reel-in, and no tether to a leader it never had.
func test_a_member_ejected_by_the_reassignment_is_not_reeled_or_drawn() -> void:
	var leader := _solo(Vector2i(0, 0), 5)
	var near := _solo(Vector2i(1, 0), 1)
	var newest := _solo(Vector2i(0, 1), 1)
	_sm.join_squad(near, leader.squad)
	_sm.join_squad(newest, leader.squad)
	_presenter.arm()
	_sm.leave_squad(leader)
	_presenter.flush()
	assert_bool(newest.squad == near.squad).override_failure_message(
			"fixture: the newest member was not ejected by the new leader's capacity").is_false()
	assert_int(_moments(Moment.REEL_IN, newest).size()).override_failure_message(
			"an ejected member's tether reeled in as if it had chosen to go").is_equal(0)
	assert_int(_moments(Moment.DRAW_IN).size()).override_failure_message(
			"a tether drew in to a leader the member never had").is_equal(0)
	assert_int(_moments(Moment.REEL_IN, near, leader).size()).is_equal(1)


func test_a_forced_exit_does_not_reel_in() -> void:
	var leader := _solo(Vector2i(0, 0))
	var member := _solo(Vector2i(1, 0))
	_sm.join_squad(member, leader.squad)
	_presenter.arm()
	member.movement.cell = Vector2i(12, 0)
	_sm.enforce_contact()
	_presenter.flush()
	assert_int(_moments(Moment.REEL_IN).size()).override_failure_message(
			"a unit thrown out of range reeled in like a voluntary leave").is_equal(0)


func test_a_death_and_an_undeploy_play_nothing() -> void:
	var leader := _solo(Vector2i(0, 0))
	var dies := _solo(Vector2i(1, 0))
	var leaves_the_board := _solo(Vector2i(0, 1))
	_sm.join_squad(dies, leader.squad)
	_sm.join_squad(leaves_the_board, leader.squad)
	_presenter.arm()
	_sm.handle_unit_death(dies)
	_sm.release(leaves_the_board)
	_presenter.flush()
	assert_int(_om.squad_tether_moments.size()).override_failure_message(
			"a death or an undeploy played a tether moment").is_equal(0)


# Loading is inert: arm() takes what stands as the baseline, so a change still waiting to settle when
# the board is armed -- a leader's re-point here -- is part of the load, not a moment.
func test_arming_makes_what_came_before_it_the_baseline() -> void:
	var leader := _solo(Vector2i(0, 0), 5)
	var heir := _solo(Vector2i(1, 0), 4)
	var other := _solo(Vector2i(0, 1), 2)
	_sm.join_squad(heir, leader.squad)
	_sm.join_squad(other, leader.squad)
	_sm.leave_squad(leader)   # queues a flush that has not landed yet
	_presenter.arm()
	_presenter.flush()
	assert_int(_om.squad_tether_moments.size()).override_failure_message(
			"a change from before the board was armed played as a moment").is_equal(0)


func test_nothing_plays_before_the_board_is_armed_or_after_it_is_reset() -> void:
	var leader := _solo(Vector2i(0, 0))
	var early := _solo(Vector2i(1, 0))
	_sm.join_squad(early, leader.squad)
	assert_int(_om.squad_tether_moments.size()).override_failure_message(
			"a join before the board was armed played").is_equal(0)

	_presenter.arm()
	var late := _solo(Vector2i(0, 1))
	_sm.join_squad(late, leader.squad)
	assert_int(_om.squad_tether_moments.size()).override_failure_message(
			"fixture: an armed join played nothing").is_equal(1)

	_presenter.reset()
	assert_int(_om.squad_tether_moments.size()).override_failure_message(
			"reset left a moment in the store").is_equal(0)
	var after := _solo(Vector2i(2, 0))
	_sm.join_squad(after, leader.squad)
	assert_int(_om.squad_tether_moments.size()).override_failure_message(
			"a join after reset played").is_equal(0)
