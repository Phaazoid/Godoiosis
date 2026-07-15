# Squad shape (#63): static cohesion range + the LDR capacity budget
# (squad-system.md banner, numbers ratified 2026-07-14). Range is decoupled from LDR
# entirely; capacity = leader + floor(effective LDR / MEMBER_LDR_COST); the hard gate
# lives in the can_* predicates ONLY — direct join_squad stays permissive so scenario
# loads grandfather overfull authored squads.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

func _leader_with_ldr(ldr: int, cell: Vector2i) -> Unit:
	return H.spawn_solo(self, _sm, ENEMY, cell, {Stats.Stat.LDR: ldr})

func test_squad_range_is_static_regardless_of_ldr() -> void:
	var low := _leader_with_ldr(1, Vector2i(0, 0))
	var high := _leader_with_ldr(9, Vector2i(8, 0))
	assert_int(low.squad.get_max_squad_range()).is_equal(Squad.SQUAD_RANGE)
	assert_int(high.squad.get_max_squad_range()).is_equal(Squad.SQUAD_RANGE)

func test_max_size_follows_the_ratified_rungs() -> void:
	# eLDR 0-1 loner · 2-3 pair · 4-5 trio · 6-7 four · 8-9 five · 10-11 six (PER 5 -> band 0).
	assert_int(_leader_with_ldr(1, Vector2i(0, 0)).squad.max_size()).is_equal(1)
	assert_int(_leader_with_ldr(3, Vector2i(4, 0)).squad.max_size()).is_equal(2)
	assert_int(_leader_with_ldr(5, Vector2i(8, 0)).squad.max_size()).is_equal(3)
	assert_int(_leader_with_ldr(7, Vector2i(12, 0)).squad.max_size()).is_equal(4)
	assert_int(_leader_with_ldr(9, Vector2i(16, 0)).squad.max_size()).is_equal(5)
	assert_int(_leader_with_ldr(11, Vector2i(20, 0)).squad.max_size()).is_equal(6)

func test_per_band_shifts_capacity_across_rung_boundaries() -> void:
	# The PER shadow with teeth: LDR 5 + PER 9 -> eLDR 6 -> four; LDR 4 + PER 2 -> eLDR 3 -> pair.
	var sharp := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 4), {Stats.Stat.LDR: 5, Stats.Stat.PER: 9})
	assert_int(sharp.squad.max_size()).is_equal(4)
	var dull := H.spawn_solo(self, _sm, ENEMY, Vector2i(4, 4), {Stats.Stat.LDR: 4, Stats.Stat.PER: 2})
	assert_int(dull.squad.max_size()).is_equal(2)

func test_negative_effective_ldr_clamps_to_loner() -> void:
	# LDR 0 + PER 2 -> eLDR -1; capacity floors at "just yourself", never negative.
	var husk := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0), {Stats.Stat.LDR: 0, Stats.Stat.PER: 2})
	assert_int(husk.squad.max_size()).is_equal(1)

func test_join_predicate_refuses_at_capacity() -> void:
	# eLDR 4 leader -> trio cap. Fill it via direct joins; the PREDICATE refuses the fourth.
	var leader := _leader_with_ldr(4, Vector2i(0, 0))
	var m1 := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	var m2 := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 1))
	var late := H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 0))
	_sm.join_squad(m1, leader.squad)
	assert_bool(_sm.can_join_squad(m2, leader.squad)).is_true()    # 2/3 -> room
	_sm.join_squad(m2, leader.squad)
	assert_bool(_sm.can_join_squad(late, leader.squad)).is_false() # 3/3 -> full

func test_loner_cannot_form_a_squad() -> void:
	# The ratified 0-1 rung: capacity 0 members means the create option greys out entirely.
	var loner := _leader_with_ldr(1, Vector2i(0, 0))
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
