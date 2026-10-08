# SquadTetherPresenter (#367): which membership changes become tether MOMENTS. It diffs member->leader
# links once per operation, so these cases drive whole operations through the real SquadManager and
# read what landed in the store (OverlayManager.squad_tether_moments) -- never a signal count, since
# one operation can emit several.
#
# A stand-in Game carries what the presenter reaches for -- an order executor only while a case plays a
# pass. The reel-in time is SET here and restored, so the re-point delay is pinned as a relationship
# and never as the tuned number; so are the death look and the light's run (#1104).
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const Moment := SquadLines2D.Moment


class FakeGame extends Node:
	var squad_manager: SquadManager
	var overlay_manager: OverlayManager
	var order_executor: OrderExecutor

	func _board() -> BoardContext:
		return squad_manager.board_source.call()


var _sm: SquadManager
var _om: OverlayManager
var _presenter: SquadTetherPresenter
var _saved_reel := 0.0
var _saved_look := 0
var _saved_pulse := 0.0
var _saved_photo := false
var _game: FakeGame


func before_test() -> void:
	_saved_reel = SquadLines2D.REEL_IN_SECONDS
	SquadLines2D.REEL_IN_SECONDS = 0.5
	_saved_look = SquadLines2D.DEATH_LOOK
	_saved_pulse = SquadLines2D.PULSE_SECONDS
	_saved_photo = PlayerSettings.is_on(PlayerSettings.Setting.PHOTOSENSITIVITY)
	SquadLines2D.DEATH_LOOK = 0
	SquadLines2D.PULSE_SECONDS = 0.2
	_sm = H.make_manager(self)
	_om = _sm.get_node("../OverlayManager")
	_game = auto_free(FakeGame.new())
	_game.squad_manager = _sm
	_game.overlay_manager = _om
	add_child(_game)
	_presenter = SquadTetherPresenter.new()
	_presenter.game = _game
	_game.add_child(_presenter)


func after_test() -> void:
	SquadLines2D.REEL_IN_SECONDS = _saved_reel
	SquadLines2D.DEATH_LOOK = _saved_look
	SquadLines2D.PULSE_SECONDS = _saved_pulse
	PlayerSettings.set_on(PlayerSettings.Setting.PHOTOSENSITIVITY, _saved_photo)


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


# #367 part 2B: a forced exit -- a DISPLACEMENT -- BREAKS the tether. A down no longer does (#1104, dev
# 2026-09-27: the snap is kept for displacement); it plays one of the death looks, from the downed end.
func test_a_forced_exit_breaks_the_tether_and_a_down_plays_a_death_look() -> void:
	var leader := _solo(Vector2i(0, 0), 5)
	var thrown := _solo(Vector2i(1, 0))
	var downed := _solo(Vector2i(0, 1))
	_sm.join_squad(thrown, leader.squad)
	_sm.join_squad(downed, leader.squad)
	_presenter.arm()
	thrown.movement.cell = Vector2i(12, 0)
	_sm.enforce_contact()
	_sm.handle_unit_downed(downed)
	_presenter.flush()
	assert_int(_moments(Moment.BREAK, thrown, leader).size()).override_failure_message(
			"a unit thrown out of range did not break its tether").is_equal(1)
	assert_int(_moments(Moment.BREAK, downed, leader).size()).override_failure_message(
			"a downed unit still snapped its tether").is_equal(0)
	var looks := _death_moments()
	assert_int(looks.size()).override_failure_message("a downed unit played no death look").is_equal(1)
	if looks.is_empty():
		return
	assert_that(looks[0]["from"]).is_equal(downed.movement.cell)
	assert_bool(bool(looks[0]["leader_died"])).override_failure_message(
			"the downed member was taken for the leader").is_false()


# An ENEMY squad's break carries its side into the store, so it plays in the enemy colour (#1109); a
# player's beside it does not. Two squads thrown apart in one operation, one of each side.
func test_a_moment_knows_whose_squad_it_was() -> void:
	var leader := _solo(Vector2i(0, 0), 5)
	var thrown := _solo(Vector2i(1, 0))
	_sm.join_squad(thrown, leader.squad)
	var their_leader: Unit = H.spawn_solo(self, _sm, Team.Faction.ENEMY, Vector2i(0, 4), {Stats.Stat.LDR: 5})
	var their_thrown: Unit = H.spawn_solo(self, _sm, Team.Faction.ENEMY, Vector2i(1, 4), {Stats.Stat.LDR: 3})
	_sm.join_squad(their_thrown, their_leader.squad)
	_presenter.arm()
	thrown.movement.cell = Vector2i(12, 0)
	their_thrown.movement.cell = Vector2i(12, 4)
	_sm.enforce_contact()
	_presenter.flush()
	var ours := _moments(Moment.BREAK, thrown, leader)
	var theirs := _moments(Moment.BREAK, their_thrown, their_leader)
	assert_int(ours.size() + theirs.size()).override_failure_message(
			"fixture: the two squads did not both break").is_equal(2)
	assert_bool(bool(theirs[0].get("hostile", false))).override_failure_message(
			"an enemy squad's break was stored as the player's").is_true()
	assert_bool(bool(ours[0].get("hostile", false))).override_failure_message(
			"the player's own break was stored as an enemy's").is_false()


# A downed LEADER's links all play ONE look (#1104), THEN the heir's draw in -- the "then" waits for it.
func test_a_downed_leaders_links_play_one_look_then_the_heir_draws_in() -> void:
	var leader := _solo(Vector2i(0, 0), 5)
	var heir := _solo(Vector2i(1, 0), 4)
	var other := _solo(Vector2i(0, 1), 2)
	_sm.join_squad(heir, leader.squad)
	_sm.join_squad(other, leader.squad)
	_presenter.arm()
	_sm.handle_unit_downed(leader)
	_presenter.flush()
	assert_object(other.squad.leader).override_failure_message(
			"fixture: leadership did not pass to the heir").is_same(heir)
	assert_int(_moments(Moment.BREAK).size()).override_failure_message(
			"the downed leader's links snapped").is_equal(0)
	var looks := _death_moments()
	assert_int(looks.size()).override_failure_message("the downed leader's links did not all play") \
			.is_equal(2)
	if looks.size() < 2:
		return
	var look := int(looks[0]["moment"])
	assert_int(int(looks[1]["moment"])).override_failure_message(
			"the downed leader's links played different looks").is_equal(look)
	for entry: Dictionary in looks:
		assert_bool(bool(entry["leader_died"])).override_failure_message(
				"the leader's fall was taken for a member's").is_true()
	var draws := _moments(Moment.DRAW_IN, other, heir)
	assert_int(draws.size()).is_equal(1)
	if draws.is_empty():
		return
	var waited := int(draws[0]["start_msec"]) - int(looks[0]["start_msec"])
	assert_int(waited).override_failure_message(
			"the heir's tether did not wait for the look (waited %d ms)" % waited) \
			.is_equal(int(SquadLines2D.moment_seconds(look) * 1000.0))


# The blow's link changes, spelled as the forecast stamps them.
func _outcome(changes: Array, lethality := ResolvedOutcome.Lethality.NONE, removed := false) -> ResolvedOutcome:
	var outcome := ResolvedOutcome.new()
	outcome.lethality = lethality
	outcome.removed = removed
	for change: Dictionary in changes:
		var link := ResolvedOutcome.Relink.new()
		link.member = change["member"]
		link.leader = change["leader"]
		link.ends = change["ends"]
		link.cause = change.get("cause", -1)
		link.member_cell = link.member.movement.cell
		link.leader_cell = link.leader.movement.cell
		outcome.relinks.append(link)
	return outcome


# At the blow: the forecast's break plays NOW, and says how long it needs; when the pass settles and
# the ejection really happens, the flush finds it in the ledger and plays it no second time.
func test_a_foretold_break_plays_at_the_blow_and_not_again_at_the_settle() -> void:
	var leader := _solo(Vector2i(0, 0))
	var member := _solo(Vector2i(1, 0))
	_sm.join_squad(member, leader.squad)
	_presenter.arm()
	var shown := _presenter.foretell(_outcome([{"member": member, "leader": leader, "ends": true,
			"cause": SquadManager.LeaveCause.FORCED}]), member)
	assert_int(_moments(Moment.BREAK, member, leader).size()).override_failure_message(
			"the foretold break did not play at the blow").is_equal(1)
	assert_float(shown).override_failure_message("the blow was not told how long its break needs") \
			.is_greater_equal(SquadLines2D.moment_seconds(Moment.BREAK))

	_om.clear_tether_moments()
	member.movement.cell = Vector2i(12, 0)
	_sm.enforce_contact()
	_presenter.flush()
	_presenter.end_pass()
	assert_bool(member.squad == leader.squad).override_failure_message(
			"fixture: the settle did not eject the member").is_false()
	assert_int(_om.squad_tether_moments.size()).override_failure_message(
			"the settle played the break a second time").is_equal(0)


# A break the forecast foretold but the pass never delivered must not swallow a later, real leave of
# that link: end_pass forgets it.
func test_a_foretold_link_the_pass_never_changed_does_not_swallow_a_later_leave() -> void:
	var leader := _solo(Vector2i(0, 0))
	var member := _solo(Vector2i(1, 0))
	_sm.join_squad(member, leader.squad)
	_presenter.arm()
	_presenter.foretell(_outcome([{"member": member, "leader": leader, "ends": true,
			"cause": SquadManager.LeaveCause.FORCED}]), member)
	_presenter.flush()
	_presenter.end_pass()
	_om.clear_tether_moments()
	_sm.leave_squad(member)
	_presenter.flush()
	assert_int(_moments(Moment.REEL_IN, member, leader).size()).override_failure_message(
			"a later Leave Squad was swallowed by a break the pass never delivered").is_equal(1)


# A down at the BLOW (#1104): the forecast's DOWNED relink plays the victim's look now, and says how long
# it needs; when the pass settles and the down's ejection really happens, the flush plays nothing more.
func test_a_foretold_down_plays_its_look_at_the_blow_and_not_again() -> void:
	var leader := _solo(Vector2i(0, 0))
	var member := _solo(Vector2i(1, 0))
	_sm.join_squad(member, leader.squad)
	_presenter.arm()
	var shown := _presenter.foretell(_outcome([{"member": member, "leader": leader, "ends": true,
			"cause": SquadManager.LeaveCause.DOWNED}], ResolvedOutcome.Lethality.DOWNED), member)
	assert_int(_moments(Moment.BREAK).size()).override_failure_message("the down snapped").is_equal(0)
	var looks := _death_moments()
	assert_int(looks.size()).override_failure_message("the down played no look at the blow").is_equal(1)
	if looks.is_empty():
		return
	assert_float(shown).override_failure_message("the blow was not told how long the look needs") \
			.is_equal_approx(SquadLines2D.shown_seconds(int(looks[0]["moment"])), 0.0001)
	_sm.handle_unit_downed(member)
	_presenter.flush()
	_presenter.end_pass()
	assert_int(_om.squad_tether_moments.size()).override_failure_message(
			"the settle played the down a second time").is_equal(1)


# A link the blow cannot decide -- here a down foretold without its victim -- is LEFT for the settle,
# which reads the cause itself, rather than put in the ledger and swallowed (#1104).
func test_a_down_foretold_without_its_victim_is_left_for_the_settle() -> void:
	var leader := _solo(Vector2i(0, 0))
	var member := _solo(Vector2i(1, 0))
	_sm.join_squad(member, leader.squad)
	_presenter.arm()
	_presenter.foretell(_outcome([{"member": member, "leader": leader, "ends": true,
			"cause": SquadManager.LeaveCause.DOWNED}], ResolvedOutcome.Lethality.DOWNED), null)
	assert_int(_om.squad_tether_moments.size()).override_failure_message(
			"fixture: the blow decided the down without its victim").is_equal(0)
	_sm.handle_unit_downed(member)
	_presenter.flush()
	assert_int(_death_moments().size()).override_failure_message(
			"the undecided down was swallowed by the ledger and never played").is_equal(1)


# A downed leader's member its heir cannot hold leaves FORCED in the same settle -- and still plays the
# leader's look rather than a snap: the link ended as the leader fell (#1104).
func test_a_downed_leaders_dropped_member_plays_the_same_look() -> void:
	var leader := _solo(Vector2i(0, 0), 5)
	var heir := _solo(Vector2i(1, 0), 4)
	var dropped := _solo(Vector2i(0, 1), 2)
	_sm.join_squad(heir, leader.squad)
	_sm.join_squad(dropped, leader.squad)
	_presenter.arm()
	_presenter.foretell(_outcome([
			{"member": heir, "leader": leader, "ends": true, "cause": SquadManager.LeaveCause.DOWNED},
			{"member": dropped, "leader": leader, "ends": true, "cause": SquadManager.LeaveCause.FORCED}],
			ResolvedOutcome.Lethality.DOWNED), leader)
	assert_int(_moments(Moment.BREAK).size()).override_failure_message(
			"the dropped member snapped instead of playing its leader's fall").is_equal(0)
	var looks := _death_moments()
	assert_int(looks.size()).override_failure_message(
			"%d of the downed leader's 2 links played its look" % looks.size()).is_equal(2)
	if looks.size() < 2:
		return
	assert_int(int(looks[1]["moment"])).is_equal(int(looks[0]["moment"]))
	for entry: Dictionary in looks:
		assert_bool(bool(entry["leader_died"])).override_failure_message(
				"the leader's fall was taken for a member's").is_true()


# A unit downed and then killed in the same pass plays ONCE -- its down's look -- and the killing blow
# owes no second wait for it (#1104).
func test_a_unit_downed_then_killed_plays_once() -> void:
	var leader := _solo(Vector2i(0, 0))
	var member := _solo(Vector2i(1, 0))
	_sm.join_squad(member, leader.squad)
	_presenter.arm()
	_mid_pass()
	_presenter.foretell(_outcome([{"member": member, "leader": leader, "ends": true,
			"cause": SquadManager.LeaveCause.DOWNED}], ResolvedOutcome.Lethality.DOWNED), member)
	_sm.handle_unit_death(member)
	_presenter.flush()
	assert_int(_death_moments().size()).override_failure_message(
			"the kill played its fall a second time").is_equal(1)
	assert_float(_presenter.foretell(_outcome([]), null)).override_failure_message(
			"the killing blow waited again for a fall that had already played").is_equal_approx(0.0, 0.0001)


# A blow that shoves its victim into a hole, as the forecast stamps it: a removal, and a kill.
func _removal(attacker: Unit, victim: Unit, changes: Array) -> AttackAction:
	var attack := H.stamped_attack(attacker, victim)
	attack.resolved = _outcome(changes, ResolvedOutcome.Lethality.KILLED, true)
	return attack


# At the LEDGE (#1104, the dev's ruling): a blow shoving its victim into a hole breaks the victim's links
# at the blow -- a BREAK, the distance's snap, strung from the cell it was struck on, riding the body and
# HELD until the attack stamps the hang's end -- and the death that follows plays nothing more and holds
# the blow for nothing.
func test_a_removal_breaks_at_the_ledge_and_its_death_plays_nothing_more() -> void:
	var leader := _solo(Vector2i(0, 0))
	var member := _solo(Vector2i(1, 0))
	var shover: Unit = H.spawn_solo(self, _sm, Team.Faction.ENEMY, Vector2i(1, 1))
	_sm.join_squad(member, leader.squad)
	_presenter.arm()
	_mid_pass()
	var struck := member.movement.cell
	var attack := _removal(shover, member, [{"member": member, "leader": leader, "ends": true,
			"cause": SquadManager.LeaveCause.DEATH}])
	var held := _presenter.foretell_removal(attack)
	var breaks := _moments(Moment.BREAK, member, leader)
	assert_int(breaks.size()).override_failure_message("the removal did not break at the ledge").is_equal(1)
	assert_bool(held).override_failure_message("the body was not told a tether is holding it").is_true()
	if breaks.is_empty():
		return
	assert_that(breaks[0]["from"]).override_failure_message(
			"the break was not strung from where the body was struck").is_equal(struck)
	assert_int(int(breaks[0].get("follow", 0))).override_failure_message(
			"the break does not ride the body to the ledge").is_equal(member.get_instance_id())
	assert_int(int(breaks[0].get("held_by", 0))).override_failure_message(
			"the break does not wait for its attack's snap").is_equal(attack.get_instance_id())
	assert_bool(is_inf(SquadLines2D.snap_seconds(breaks[0]))).override_failure_message(
			"the break has a snap before the body has even arrived").is_true()
	_sm.handle_unit_death(member)
	_presenter.flush()
	assert_int(_om.squad_tether_moments.size()).override_failure_message(
			"the death after the ledge played a second moment").is_equal(1)
	assert_float(_presenter.foretell(attack.resolved_outcome(), null)).override_failure_message(
			"the killing blow waited for a look that never played").is_equal_approx(0.0, 0.0001)


# The ledge break RIDES THE BODY and HOLDS (#1104, the dev's mockup and his wile e coyote hang): past its
# strain it is still whole and still riding, because the hang has not ended; the attack's stamp snaps
# it on the next frame, and from then moving the body moves nothing. The other end stays put throughout.
# Driven through the moments' own clock, aged by hand.
func test_a_ledge_break_holds_and_rides_the_body_until_its_attack_lets_go() -> void:
	var saved := [SquadLines2D.BREAK_STRAIN_SECONDS, SquadLines2D.BREAK_SHATTER_SECONDS]
	SquadLines2D.BREAK_STRAIN_SECONDS = 0.5
	SquadLines2D.BREAK_SHATTER_SECONDS = 5.0
	var leader := _solo(Vector2i(0, 0))
	var member := _solo(Vector2i(1, 0))
	var shover: Unit = H.spawn_solo(self, _sm, Team.Faction.ENEMY, Vector2i(1, 1))
	_sm.join_squad(member, leader.squad)
	_presenter.arm()
	var attack := _removal(shover, member, [{"member": member, "leader": leader,
			"ends": true, "cause": SquadManager.LeaveCause.DEATH}])
	_presenter.foretell_removal(attack)
	var breaks := _moments(Moment.BREAK, member, leader)
	var leader_before := Vector3.ZERO
	var leader_after := Vector3.ZERO
	var riding := Vector3.ZERO
	var at := Vector2.ZERO
	var whole_past_strain := false
	var snapped_on_stamp := false
	var snapped := Vector3.ZERO
	var after_snap := Vector3.ZERO
	var shattered := false
	if not breaks.is_empty():
		var entry: Dictionary = breaks[0]
		leader_before = (entry["chord"] as PackedVector3Array)[1]
		entry["start_msec"] = Time.get_ticks_msec() - roundi(SquadLines2D.BREAK_STRAIN_SECONDS * 1000.0) - 200
		_om._process(0.0)
		var held := SquadLines2D.moment_drawing(entry, Time.get_ticks_msec(), true)
		whole_past_strain = (held["pieces"] as Array).is_empty() and not (held["shaft"] as PackedVector3Array).is_empty()
		member.position += Vector2(GridUtils.TILE_SIZE, GridUtils.TILE_SIZE)
		_om._process(0.0)
		riding = (entry["chord"] as PackedVector3Array)[0]
		leader_after = (entry["chord"] as PackedVector3Array)[1]
		at = UnitMirror.board_xz(member)
		attack.tether_snap_msec = Time.get_ticks_msec() - 1
		_om._process(0.0)
		snapped_on_stamp = not entry.has("held_by") and not is_inf(SquadLines2D.snap_seconds(entry))
		snapped = (entry["chord"] as PackedVector3Array)[0]
		member.position += Vector2(GridUtils.TILE_SIZE, 0)
		_om._process(0.0)
		after_snap = (entry["chord"] as PackedVector3Array)[0]
		var shatter := SquadLines2D.moment_drawing(entry, Time.get_ticks_msec() + 50, true)
		shattered = not (shatter["pieces"] as Array).is_empty()
	SquadLines2D.BREAK_STRAIN_SECONDS = saved[0]
	SquadLines2D.BREAK_SHATTER_SECONDS = saved[1]

	assert_int(breaks.size()).override_failure_message("fixture: the removal did not break").is_equal(1)
	assert_bool(whole_past_strain).override_failure_message(
			"the break snapped at its strain's end while the body still hung").is_true()
	assert_float(riding.x).override_failure_message("the held break's end did not ride the body") \
			.is_equal_approx(at.x, 0.0001)
	assert_float(riding.z).override_failure_message("the held break's end did not ride the body") \
			.is_equal_approx(at.y, 0.0001)
	assert_vector(leader_after).override_failure_message("the living end moved with the body") \
			.is_equal_approx(leader_before, Vector3(0.0001, 0.0001, 0.0001))
	assert_bool(snapped_on_stamp).override_failure_message(
			"the attack's let-go never reached the break").is_true()
	assert_bool(shattered).override_failure_message("the break did not shatter after its snap").is_true()
	assert_vector(after_snap).override_failure_message("the break kept riding the body past the snap") \
			.is_equal_approx(snapped, Vector3(0.0001, 0.0001, 0.0001))


# A held break whose attack is gone snaps at once (#1104): whatever freed it, nothing is left to stamp it,
# and a break must never hold the moments' clock open for ever.
func test_a_break_held_by_a_freed_attack_snaps_at_once() -> void:
	var leader := _solo(Vector2i(0, 0))
	var member := _solo(Vector2i(1, 0))
	var shover: Unit = H.spawn_solo(self, _sm, Team.Faction.ENEMY, Vector2i(1, 1))
	_sm.join_squad(member, leader.squad)
	_presenter.arm()
	var attack := _removal(shover, member, [{"member": member, "leader": leader,
			"ends": true, "cause": SquadManager.LeaveCause.DEATH}])
	_presenter.foretell_removal(attack)
	var breaks := _moments(Moment.BREAK, member, leader)
	attack = null
	_om._process(0.0)
	assert_int(breaks.size()).override_failure_message("fixture: the removal did not break").is_equal(1)
	if breaks.is_empty():
		return
	assert_bool(breaks[0].has("held_by")).override_failure_message(
			"a break held by a freed attack is still holding").is_false()
	assert_bool(is_inf(SquadLines2D.snap_seconds(breaks[0]))).override_failure_message(
			"a break held by a freed attack never snaps").is_false()


func test_an_undeploy_plays_nothing() -> void:
	var leader := _solo(Vector2i(0, 0))
	var leaves_the_board := _solo(Vector2i(0, 1))
	_sm.join_squad(leaves_the_board, leader.squad)
	_presenter.arm()
	_sm.release(leaves_the_board)
	_presenter.flush()
	assert_int(_om.squad_tether_moments.size()).override_failure_message(
			"an undeploy played a tether moment").is_equal(0)


func _death_moments() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry: Dictionary in _om.squad_tether_moments:
		if SquadLines2D.DEATH_LOOKS.has(int(entry["moment"])):
			found.append(entry)
	return found


# A death plays one of the four looks, strung from where the body stood to its leader, and says the
# member is the end that died and the leader the one left.
func test_a_death_plays_a_death_look() -> void:
	var leader := _solo(Vector2i(0, 0))
	var dies := _solo(Vector2i(1, 0))
	_sm.join_squad(dies, leader.squad)
	var stood := dies.movement.cell
	_presenter.arm()
	_sm.handle_unit_death(dies)
	_presenter.flush()
	assert_int(_om.squad_tether_moments.size()).override_failure_message(
			"a death played %d moments" % _om.squad_tether_moments.size()).is_equal(1)
	var deaths := _death_moments()
	assert_int(deaths.size()).override_failure_message("a death played no death look").is_equal(1)
	if deaths.is_empty():
		return
	assert_that(deaths[0]["from"]).is_equal(stood)
	assert_that(deaths[0]["to"]).is_equal(leader.movement.cell)
	assert_bool(bool(deaths[0]["leader_died"])).override_failure_message(
			"the dead member was taken for the leader").is_false()
	assert_int(int(deaths[0]["survivor"])).override_failure_message(
			"the one left was not the leader").is_equal(leader.get_instance_id())


# A REAL death frees the body before the deferred flush can ask where it stood, so the moment is strung
# from what the death captured: where it fell and whose it was. An ENEMY leader, so the captured side is
# what picks the colour -- and every link it led plays the SAME look, the member its successor could not
# hold (ejected, a FORCED leave of its own) included.
func test_a_real_death_plays_from_where_the_body_fell() -> void:
	var leader: Unit = H.spawn_solo(self, _sm, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.LDR: 5})
	var heir: Unit = H.spawn_solo(self, _sm, Team.Faction.ENEMY, Vector2i(1, 0), {Stats.Stat.LDR: 1})
	var ejected: Unit = H.spawn_solo(self, _sm, Team.Faction.ENEMY, Vector2i(0, 1), {Stats.Stat.LDR: 1})
	_sm.join_squad(heir, leader.squad)
	_sm.join_squad(ejected, leader.squad)
	leader.unit_died.connect(_sm.handle_unit_death)   # game._on_unit_died's hop
	var fell := leader.movement.cell
	_presenter.arm()
	leader.die()
	assert_bool(leader.is_queued_for_deletion()).override_failure_message(
			"fixture: the body was not on its way out").is_true()
	assert_bool(ejected.squad == heir.squad).override_failure_message(
			"fixture: the successor held every member, so nobody was ejected").is_false()
	_presenter.flush()
	var deaths := _death_moments()
	assert_int(deaths.size()).override_failure_message(
			"%d of the dead leader's 2 links played its look" % deaths.size()).is_equal(2)
	for entry: Dictionary in deaths:
		assert_that(entry["to"]).override_failure_message(
				"a link was not strung to where the leader fell").is_equal(fell)
		assert_bool(bool(entry["hostile"])).override_failure_message(
				"the dead enemy's side was lost with its body").is_true()
		assert_bool(bool(entry["leader_died"])).is_true()
		assert_int(int(entry["moment"])).override_failure_message(
				"the leader's links played different looks").is_equal(int(deaths[0]["moment"]))
	assert_int(_moments(Moment.BREAK).size()).override_failure_message(
			"the ejected member broke its tether instead of playing its leader's death").is_equal(0)


# The dev's "then", for a death: the heir's tethers draw in once the dead leader's look has played.
func test_a_leaders_death_plays_its_look_then_the_heir_draws_in() -> void:
	var leader := _solo(Vector2i(0, 0), 5)
	var heir := _solo(Vector2i(1, 0), 4)
	var other := _solo(Vector2i(0, 1), 2)
	_sm.join_squad(heir, leader.squad)
	_sm.join_squad(other, leader.squad)
	_presenter.arm()
	_sm.handle_unit_death(leader)
	_presenter.flush()
	assert_object(other.squad.leader).override_failure_message(
			"fixture: leadership did not pass to the heir").is_same(heir)
	var deaths := _death_moments()
	assert_int(deaths.size()).override_failure_message("the dead leader's links did not all play") \
			.is_equal(2)
	if deaths.is_empty():
		return
	var look := int(deaths[0]["moment"])
	var draws := _moments(Moment.DRAW_IN, other, heir)
	assert_int(draws.size()).is_equal(1)
	var waited := int(draws[0]["start_msec"]) - int(deaths[0]["start_msec"])
	assert_int(waited).override_failure_message(
			"the heir's tether did not wait for the death (waited %d ms)" % waited) \
			.is_equal(int(SquadLines2D.moment_seconds(look) * 1000.0))


# A pass running, as OrderExecutor holds one while it plays a plan.
func _mid_pass() -> void:
	var executor: OrderExecutor = auto_free(OrderExecutor.new())
	executor.executing_plan = ResolvedPlan.new()
	_game.order_executor = executor


# A KILL settles mid-blow (handle_unit_death), so its look plays from the ordinary flush -- but the blow
# that killed waits for it like a break, and for the heir's draw-in after it (the dev: "waits, like a
# break"). The wait is paid once, and foretell itself plays none of it.
func test_a_kill_mid_pass_holds_its_blow_for_the_look_and_the_handover() -> void:
	var leader := _solo(Vector2i(0, 0), 5)
	var heir := _solo(Vector2i(1, 0), 4)
	var other := _solo(Vector2i(0, 1), 2)
	_sm.join_squad(heir, leader.squad)
	_sm.join_squad(other, leader.squad)
	_presenter.arm()
	_mid_pass()
	_sm.handle_unit_death(leader)
	var shown := _presenter.foretell(_outcome([
			{"member": heir, "leader": leader, "ends": true, "cause": SquadManager.LeaveCause.DEATH},
			{"member": other, "leader": leader, "ends": true, "cause": SquadManager.LeaveCause.DEATH},
			{"member": other, "leader": heir, "ends": false}]), null)
	assert_int(_om.squad_tether_moments.size()).override_failure_message(
			"foretell played the kill itself").is_equal(0)
	_presenter.flush()
	var deaths := _death_moments()
	assert_int(deaths.size()).override_failure_message("the kill's look did not play once per link") \
			.is_equal(2)
	if deaths.is_empty():
		return
	assert_int(_moments(Moment.DRAW_IN, other, heir).size()).override_failure_message(
			"the kill's handover did not draw in exactly once").is_equal(1)
	var owed := SquadLines2D.moment_seconds(int(deaths[0]["moment"])) \
			+ SquadLines2D.shown_seconds(Moment.DRAW_IN)
	assert_float(shown).override_failure_message(
			"the blow did not wait for the look and the draw-in after it").is_equal_approx(owed, 0.0001)
	assert_float(_presenter.foretell(_outcome([]), null)).override_failure_message(
			"the next blow waited for a death it did not cause").is_equal_approx(0.0, 0.0001)


# A death outside a pass -- the dev kill, a load -- holds no blow: there is none to hold. It still plays.
# The game's executor is always there; between passes it has no plan running, which is the state here.
func test_a_death_outside_a_pass_holds_nothing() -> void:
	var leader := _solo(Vector2i(0, 0))
	var dies := _solo(Vector2i(1, 0))
	_sm.join_squad(dies, leader.squad)
	_game.order_executor = auto_free(OrderExecutor.new())
	_presenter.arm()
	_sm.handle_unit_death(dies)
	assert_float(_presenter.foretell(_outcome([]), null)).override_failure_message(
			"a death outside a pass held a blow").is_equal_approx(0.0, 0.0001)
	_presenter.flush()
	assert_int(_death_moments().size()).is_equal(1)


# A PULSE's light arrives at whoever is left, and THEY flash as it does -- fired off the moments' own
# clock (OverlayManager._process), so the case moves the moment's start back rather than waiting.
func test_the_one_a_pulse_runs_to_flashes_as_it_arrives() -> void:
	SquadLines2D.DEATH_LOOK = SquadLines2D.DEATH_LOOKS.find(Moment.PULSE) + 1
	PlayerSettings.set_on(PlayerSettings.Setting.PHOTOSENSITIVITY, false)
	var leader := _solo(Vector2i(0, 0))
	var dies := _solo(Vector2i(1, 0))
	_sm.join_squad(dies, leader.squad)
	_presenter.arm()
	_sm.handle_unit_death(dies)
	_presenter.flush()
	var pulses := _moments(Moment.PULSE)
	assert_int(pulses.size()).override_failure_message("fixture: the pinned look was not a PULSE") \
			.is_equal(1)
	_om._process(0.0)
	assert_object(leader.visuals.visual_tween).override_failure_message(
			"the survivor flashed before the light reached it").is_null()
	pulses[0]["start_msec"] = Time.get_ticks_msec() - roundi(SquadLines2D.PULSE_SECONDS * 1000.0) - 1
	_om._process(0.0)
	assert_bool(leader.visuals.visual_tween != null and leader.visuals.visual_tween.is_running()) \
			.override_failure_message("the survivor did not flash as the light reached it").is_true()


# #217: the light is stilled by the photosensitivity setting, and so is the flash it would bring.
func test_the_photosensitivity_setting_stills_the_survivors_flash() -> void:
	SquadLines2D.DEATH_LOOK = SquadLines2D.DEATH_LOOKS.find(Moment.PULSE) + 1
	PlayerSettings.set_on(PlayerSettings.Setting.PHOTOSENSITIVITY, true)
	var leader := _solo(Vector2i(0, 0))
	var dies := _solo(Vector2i(1, 0))
	_sm.join_squad(dies, leader.squad)
	_presenter.arm()
	_sm.handle_unit_death(dies)
	_presenter.flush()
	var pulses := _moments(Moment.PULSE)
	pulses[0]["start_msec"] = Time.get_ticks_msec() - roundi(SquadLines2D.PULSE_SECONDS * 1000.0) - 1
	_om._process(0.0)
	assert_object(leader.visuals.visual_tween).override_failure_message(
			"the survivor flashed with the setting on").is_null()


# The loss flash is the LOWEST tier on sprite.modulate: it yields to a pin flash (a pinned survivor is
# already white), to an aim pulse, and to a lunge or shake already running on the one-shot tween.
func test_the_loss_flash_yields_to_the_pin_the_aim_and_a_running_one_shot() -> void:
	var unit := _solo(Vector2i(0, 0))
	var visuals: UnitVisuals = unit.visuals
	visuals.set_pinned(true)
	visuals.play_loss_flash()
	assert_object(visuals.visual_tween).override_failure_message("the flash stomped a pin flash").is_null()
	assert_bool(visuals.pin_tween != null and visuals.pin_tween.is_valid()).override_failure_message(
			"the pin flash did not survive the loss flash").is_true()
	visuals.set_pinned(false)
	visuals.start_pulse()
	visuals.play_loss_flash()
	assert_object(visuals.visual_tween).override_failure_message("the flash stomped an aim pulse").is_null()
	visuals.stop_pulse()
	var lunge := visuals.create_tween()
	lunge.tween_property(visuals.sprite, "position", visuals.base_position + Vector2(8, 0), 1.0)
	visuals.visual_tween = lunge
	visuals.play_loss_flash()
	assert_object(visuals.visual_tween).override_failure_message("the flash cut a running lunge") \
			.is_same(lunge)
	visuals.reset_visuals()
	visuals.play_loss_flash()
	assert_bool(visuals.visual_tween != lunge and visuals.visual_tween.is_running()) \
			.override_failure_message("fixture: with nothing running, no flash played").is_true()


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
