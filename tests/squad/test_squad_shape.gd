# Squad shape (#63): the cohesion range + the LDR capacity budget
# (squad-system.md banner, numbers ratified 2026-07-14). Range is decoupled from LDR
# entirely; capacity = leader + floor(effective LDR / MEMBER_LDR_COST); the hard gate
# lives in the can_* predicates ONLY — direct join_squad stays permissive so scenario
# loads grandfather overfull authored squads.
#
# Range stopped being a static const in #142 — it is the LEADER's COH stat, so it is per-unit
# and job/gear/effect-modifiable. #63's actual call survives: COH is still decoupled from LDR.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

func _leader_with_ldr(ldr: int, cell: Vector2i) -> Unit:
	return H.spawn_solo(self, _sm, ENEMY, cell, {Stats.Stat.LDR: ldr})

func test_squad_range_is_independent_of_ldr() -> void:
	# #63's invariant, unchanged by #142: LDR buys capacity, never leash length.
	var low := _leader_with_ldr(1, Vector2i(0, 0))
	var high := _leader_with_ldr(9, Vector2i(8, 0))
	assert_int(low.squad.get_max_squad_range()).is_equal(Stats.STAT_DEFAULTS[Stats.Stat.COH])
	assert_int(high.squad.get_max_squad_range()).is_equal(Stats.STAT_DEFAULTS[Stats.Stat.COH])

func test_squad_range_is_the_leaders_coh() -> void:
	var leader := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0), {Stats.Stat.COH: 6})
	assert_int(leader.squad.get_max_squad_range()).is_equal(6)

func test_a_members_coh_does_not_widen_the_squad() -> void:
	# Leader-derived, not max-of-members: a long-leashed recruit under a short-leashed captain
	# is held to the captain's bubble.
	var leader := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0), {Stats.Stat.LDR: 5, Stats.Stat.COH: 2})
	var member := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.COH: 9})
	_sm.join_squad(member, leader.squad)
	assert_int(leader.squad.get_max_squad_range()).is_equal(2)
	assert_int(member.squad.get_max_squad_range()).is_equal(2)   # same squad, same answer

func test_squad_range_follows_leader_reassignment() -> void:
	# The leash is re-derived from whoever leads now — the same way max_size() already was.
	var captain := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0), {Stats.Stat.LDR: 8, Stats.Stat.COH: 7})
	var heir := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.LDR: 3, Stats.Stat.COH: 4})
	_sm.join_squad(heir, captain.squad)
	var squad := captain.squad
	assert_int(squad.get_max_squad_range()).is_equal(7)

	_sm.leave_squad(captain)

	assert_object(squad.leader).is_same(heir)
	assert_int(squad.get_max_squad_range()).is_equal(4)

func test_max_size_follows_the_capacity_rungs() -> void:
	# capacity = leader + floor(eLDR / MEMBER_LDR_COST), probed across six rungs. Expected values
	# derive from the constant (2026-08-10 sweep -- MEMBER_LDR_COST is playtest-tunable, and the
	# same symbolic form test_derived_stat_chain already uses): the shape being pinned is that
	# capacity STEPS with LDR, at whatever the cost is that day. Default PER -> band 0.
	for ldr in [1, 3, 5, 7, 9, 11]:
		var leader := _leader_with_ldr(ldr, Vector2i(ldr * 2, 0))
		assert_int(leader.squad.max_size()) \
			.override_failure_message("capacity at LDR %d does not follow the ladder" % ldr) \
			.is_equal(1 + ldr / Squad.MEMBER_LDR_COST)

func test_per_band_shifts_capacity_across_rung_boundaries() -> void:
	# The PER shadow with teeth: a band edge in PER moves eLDR, and eLDR moves capacity. Expected
	# derives from the band + the cost, so it pins the WIRE (PER reaches capacity), not the numbers.
	var high_per: int = Stats.BAND_MID_MAX + 2
	var sharp := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 4), {Stats.Stat.LDR: 5, Stats.Stat.PER: high_per})
	assert_int(sharp.squad.max_size()) \
		.is_equal(1 + (5 + Stats.per_ldr_band(high_per)) / Squad.MEMBER_LDR_COST)
	# The guaranteed-visible direction: LDR sitting exactly on a rung multiple, dull PER dragging
	# eLDR one below it. floor((2c-1)/c) < 2 for every cost >= 1, so this drop survives ANY retune;
	# the upward twin does not (a +1 shift only crosses a boundary at some costs), hence this side.
	var rung_ldr: int = 2 * Squad.MEMBER_LDR_COST
	var plain := _leader_with_ldr(rung_ldr, Vector2i(8, 4))
	var dull := H.spawn_solo(self, _sm, ENEMY, Vector2i(12, 4), {Stats.Stat.LDR: rung_ldr, Stats.Stat.PER: 0})
	assert_int(dull.squad.max_size()).is_less(plain.squad.max_size())

func test_negative_effective_ldr_clamps_to_loner() -> void:
	# LDR 0 + PER 2 -> eLDR -1; capacity floors at "just yourself", never negative.
	var husk := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0), {Stats.Stat.LDR: 0, Stats.Stat.PER: 2})
	assert_int(husk.squad.max_size()).is_equal(1)

func test_join_predicate_refuses_at_capacity() -> void:
	# Capacity authored AS two-members-beyond-the-leader (LDR = 2 x the cost), so the fill below
	# and the refusal stay aligned with the knob at any retune (2026-08-10 sweep). The PREDICATE
	# refuses the member past capacity; direct joins stay permissive.
	var leader := _leader_with_ldr(2 * Squad.MEMBER_LDR_COST, Vector2i(0, 0))
	var m1 := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	var m2 := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 1))
	var late := H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 0))
	_sm.join_squad(m1, leader.squad)
	assert_bool(_sm.can_join_squad(m2, leader.squad)).is_true()    # 2/3 -> room
	_sm.join_squad(m2, leader.squad)
	assert_bool(_sm.can_join_squad(late, leader.squad)).is_false() # 3/3 -> full

func test_loner_cannot_form_a_squad() -> void:
	# The bottom rung: capacity 0 members means the create option greys out entirely. LDR authored
	# one short of the first member's cost, so the rung holds at any retune.
	var loner := _leader_with_ldr(Squad.MEMBER_LDR_COST - 1, Vector2i(0, 0))
	var buddy := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	assert_bool(_sm.can_squad_up(buddy, loner.squad)).is_false()
	assert_bool(_sm.can_create_any_squad(loner)).is_false()

func test_direct_join_grandfathers_over_capacity() -> void:
	# Scenario loads call join_squad directly — it must admit over cap (warn, never eject).
	var leader := _leader_with_ldr(1, Vector2i(0, 0))   # cap: loner
	var extra := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	_sm.join_squad(extra, leader.squad)
	assert_int(leader.squad.members.size()).is_equal(2)

func test_leader_departure_overflow_detaches_newest_first() -> void:
	# Big captain (eLDR 8 -> five) with three members; captain leaves; the strongest
	# remainer leads (eLDR 3 -> pair cap) -> the NEWEST member detaches, join order wins.
	var captain := _leader_with_ldr(8, Vector2i(0, 0))
	var oldest := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.LDR: 3})
	var middle := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 1), {Stats.Stat.LDR: 2})
	var newest := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 1), {Stats.Stat.LDR: 2})
	_sm.join_squad(oldest, captain.squad)
	_sm.join_squad(middle, captain.squad)
	_sm.join_squad(newest, captain.squad)
	var squad := captain.squad

	_sm.leave_squad(captain)

	assert_object(squad.leader).is_same(oldest)      # highest eLDR among the remainers
	assert_int(squad.members.size()).is_equal(2)     # oldest's cap: pair
	assert_bool(squad.members.has(middle)).is_true() # older bond survives
	assert_bool(newest.squad != squad).is_true()     # newest detached into a solo squad
	assert_bool(newest.squad.members.has(newest)).is_true()
