# Squad lifecycle invariants I1-I7 from docs/design/squad-system.md.
#
# Driven through the real SquadManager (orphan instance — create/join/leave/detach/
# disband/reassign need neither overlay nor grid). Each test pins the observable
# contract of an invariant; where an invariant is partly enforced outside this layer
# (I2's disband drift, I7's game.gd spawn_unit) the comment says so.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

# I1 — a managed unit belongs to exactly one squad; a lone unit is a 1-member squad,
# not squadless.
func test_i1_unit_belongs_to_exactly_one_squad() -> void:
	var u := H.spawn_unit(self, ENEMY, Vector2i(0, 0))
	assert_object(u.squad).is_null()        # not yet managed
	_sm.create_squad(u)
	assert_object(u.squad).is_not_null()
	assert_array(u.squad.members).contains_exactly([u])
	assert_array(_sm.squads).contains([u.squad])

# I2 — _detach_from_current_squad is the member-removal path; its observable contract
# is "removed here, rehomed as solo." (Known drift: disband_squad also erases members
# directly — recorded in squad-system.md / BACKLOG, not fixed in gameplay code here.)
func test_i2_detach_removes_and_rehomes_member() -> void:
	var leader := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))
	var member := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	_sm.join_squad(member, leader.squad)
	assert_int(leader.squad.members.size()).is_equal(2)

	_sm.leave_squad(member)   # -> _detach_from_current_squad

	assert_array(leader.squad.members).contains_exactly([leader])
	assert_bool(member.squad != leader.squad).is_true()
	assert_int(member.squad.members.size()).is_equal(1)

# I3 — every live squad is in SquadManager.squads; an emptied squad is removed from it
# (no ghost squads). Merging two solo units destroys the vacated squad.
func test_i3_emptied_squad_leaves_the_registry() -> void:
	var a := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))
	var b := H.spawn_solo(self, _sm, ENEMY, Vector2i(5, 0))
	assert_int(_sm.squads.size()).is_equal(2)

	_sm.join_squad(b, a.squad)   # b's old solo squad empties -> destroyed

	assert_int(_sm.squads.size()).is_equal(1)
	assert_array(_sm.squads).contains_exactly([a.squad])

# I4 — has_squad() means "has squadmates" (members > 1), not "a squad object exists"
# (which is always true per I1).
func test_i4_has_squad_means_has_squadmates() -> void:
	var solo := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))
	assert_bool(solo.has_squad()).is_false()   # squad exists, but no mates

	var mate := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	_sm.join_squad(mate, solo.squad)

	assert_bool(solo.has_squad()).is_true()
	assert_bool(mate.has_squad()).is_true()

# I5 — when the leader leaves, leadership reassigns to the highest-LDR member; the new
# leader is a member of its own squad.
func test_i5_leadership_reassigns_to_highest_ldr() -> void:
	var leader := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0), {"LDR": 5})
	var low := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {"LDR": 2})
	var high := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 1), {"LDR": 4})
	_sm.join_squad(low, leader.squad)
	_sm.join_squad(high, leader.squad)

	_sm.leave_squad(leader)   # reassign among {low, high}

	assert_object(low.squad.leader).is_same(high)      # highest LDR wins
	assert_array(low.squad.members).contains(high)     # leader is a member
	assert_object(leader.squad).is_not_same(low.squad) # departed leader is elsewhere

# I5 (tie) — equal LDR breaks on member order: the earlier member keeps leadership.
func test_i5_leadership_tie_breaks_on_member_order() -> void:
	var leader := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0), {"LDR": 5})
	var first := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {"LDR": 3})
	var second := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 1), {"LDR": 3})
	_sm.join_squad(first, leader.squad)
	_sm.join_squad(second, leader.squad)

	_sm.leave_squad(leader)

	assert_object(first.squad.leader).is_same(first)   # tie -> first in member order

# I6 — members must stay within the leader's LDR range; after reassignment, out-of-range
# members are detached into solo squads. Tight LDR (1) pushes the distant member out.
func test_i6_out_of_range_members_detach_after_reassign() -> void:
	var leader := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0), {"LDR": 1})
	var near := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {"LDR": 1})
	var far := H.spawn_solo(self, _sm, ENEMY, Vector2i(4, 0), {"LDR": 1})
	_sm.join_squad(near, leader.squad)   # join doesn't range-check
	_sm.join_squad(far, leader.squad)

	_sm.leave_squad(leader)   # new leader = near (tie -> first); far is dist 3 > LDR 1

	assert_object(near.squad.leader).is_same(near)
	assert_bool(far.squad != near.squad).is_true()
	assert_int(far.squad.members.size()).is_equal(1)
	assert_array(near.squad.members).not_contains([far])

# I7 — spawning a unit creates its solo squad. The board-level spawn_unit lives in
# game.gd (full-scene, out of unit-test scope); we pin its core: create_squad yields a
# 1-member squad registered with the manager.
func test_i7_create_squad_yields_registered_solo_squad() -> void:
	var u := H.spawn_unit(self, ENEMY, Vector2i(2, 2))
	var before := _sm.squads.size()

	var squad := _sm.create_squad(u)

	assert_object(squad.leader).is_same(u)
	assert_array(squad.members).contains_exactly([u])
	assert_array(_sm.squads).contains([squad])
	assert_int(_sm.squads.size()).is_equal(before + 1)
