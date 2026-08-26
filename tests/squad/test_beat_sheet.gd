# BeatSheet (#524, umbrella #410): the cinematic's reading of one resolved pass. These cases pin
# the SHAPE of that reading -- what counts as one shot, what earns a beat at all, and the order the
# beats come in -- because every later slice (#519 timing, #520 camera, #521 tear-out) consumes it
# and none of them can see a mis-grouping until it is already on screen.
#
# Two fixture styles on purpose. The structural cases drive the REAL resolve_plan, so the sheet is
# checked against what the resolver actually emits rather than what this suite imagines. The fact
# cases hand-build a plan from create_volley / create_counter_volley (real stamping, throwaway
# outcomes), which is the only way to pin a fall or a skipped counter without standing up terrain.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)


# --- structural: driven by the real resolver ------------------------------------------------

func test_a_single_pair_is_one_volley_beat() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.LDR: 3})
	_sm.active_squad = attacker.squad
	attacker.squad._queue_action(AttackAction.declare(attacker, attacker.movement.cell, Vector2i(1, 0)))

	var plan := _sm.resolve_plan(attacker.squad, _board_with([attacker, foe]))
	var sheet := BeatSheet.read(attacker.squad, plan)

	var volleys := _of_kind(sheet, BeatSheet.Kind.VOLLEY)
	assert_int(volleys.size()).is_greater_equal(1)
	assert_object(volleys[0].actor).is_same(attacker)
	assert_int(volleys[0].victims.size()).is_equal(1)
	assert_object(volleys[0].victims[0]).is_same(foe)
	assert_bool(volleys[0].is_counter).is_false()
	_break_volleys(plan)


# #47's cell attack: a legal aim at empty ground resolves and PLAYS, so it earns a beat -- with no
# victim at all. The sheet must carry an empty victim list rather than dropping the swing, or the
# camera has nothing to cut to while terrain effects land there (#50).
func test_a_swing_at_empty_ground_is_a_beat_with_no_victim() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	_sm.active_squad = attacker.squad
	attacker.squad._queue_action(AttackAction.declare(attacker, attacker.movement.cell, Vector2i(1, 0)))

	var plan := _sm.resolve_plan(attacker.squad, _board_with([attacker]))
	assert_int(plan.attacks.size()).is_equal(1)
	assert_object(plan.attacks[0].target).is_null()

	var sheet := BeatSheet.read(attacker.squad, plan)
	var volleys := _of_kind(sheet, BeatSheet.Kind.VOLLEY)
	assert_int(volleys.size()).is_equal(1)
	assert_array(volleys[0].victims).is_empty()
	assert_array(volleys[0].lethalities).is_empty()
	assert_int(volleys[0].actions.size()).is_equal(1)
	_break_volleys(plan)


# The act break only exists when the defending line actually answers, and it must sit BEFORE the
# counters it introduces -- that ordering is the whole point of the beat (#410 counter turnover).
func test_a_countered_attack_puts_the_turnover_before_the_counters() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.LDR: 3})
	_sm.active_squad = attacker.squad
	attacker.squad._queue_action(AttackAction.declare(attacker, attacker.movement.cell, Vector2i(1, 0)))

	var plan := _sm.resolve_plan(attacker.squad, _board_with([attacker, foe]))
	assert_int(plan.counters.size()).is_greater(0)

	var sheet := BeatSheet.read(attacker.squad, plan)
	var turnover := _index_of_kind(sheet, BeatSheet.Kind.TURNOVER)
	assert_int(turnover).is_greater_equal(0)

	var first_counter := -1
	for i in sheet.beats.size():
		if sheet.beats[i].is_counter and sheet.beats[i].kind == BeatSheet.Kind.VOLLEY:
			first_counter = i
			break
	assert_int(first_counter).is_greater(turnover)
	_break_volleys(plan)


# Both squads are on stage, not just the two units trading blows (#410: "everyone in every
# participating squad"). The bystander squadmate is the case that separates cast from combatants.
func test_the_cast_holds_every_member_of_every_participating_squad() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	var mate := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 1), {Stats.Stat.LDR: 3})
	_sm.join_squad(mate, attacker.squad)
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.LDR: 3})
	var foe_mate := H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 0), {Stats.Stat.LDR: 3})
	_sm.join_squad(foe_mate, foe.squad)
	_sm.active_squad = attacker.squad
	attacker.squad._queue_action(AttackAction.declare(attacker, attacker.movement.cell, Vector2i(1, 0)))

	var plan := _sm.resolve_plan(attacker.squad, _board_with([attacker, mate, foe, foe_mate]))
	var sheet := BeatSheet.read(attacker.squad, plan)

	for unit in [attacker, mate, foe, foe_mate]:
		assert_bool(sheet.cast.has(unit)).override_failure_message(
				"cast is missing %s" % unit).is_true()
	# The bystander squadmate never acts and is never hit, so only the cast sweep puts its ground
	# in the tear-out set.
	assert_bool(sheet.cells.has(Vector2i(0, 1))).is_true()
	_break_volleys(plan)


# --- fact cases: hand-built plans -----------------------------------------------------------

# One blast is one shot however many it hits -- #410 rules an AoE striking three victims a single
# sweep, not three cuts. Grouping follows is_secondary_hit, the same read the resolver makes.
func test_a_three_victim_volley_is_one_beat_in_strike_order() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	var a := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.LDR: 3})
	var b := H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 0), {Stats.Stat.LDR: 3})
	var c := H.spawn_solo(self, _sm, ENEMY, Vector2i(3, 0), {Stats.Stat.LDR: 3})

	var plan := ResolvedPlan.new()
	var victims: Array[Unit] = [a, b, c]
	plan.attacks.assign(AttackAction.create_volley(attacker, Vector2i(0, 0), Vector2i(1, 0),
			victims, attacker.get_equipped_weapon().template.main_attack))

	var sheet := BeatSheet.read(attacker.squad, plan)
	var volleys := _of_kind(sheet, BeatSheet.Kind.VOLLEY)
	assert_int(volleys.size()).is_equal(1)
	assert_int(volleys[0].actions.size()).is_equal(3)
	assert_object(volleys[0].victims[0]).is_same(a)
	assert_object(volleys[0].victims[1]).is_same(b)
	assert_object(volleys[0].victims[2]).is_same(c)
	_break_volleys(plan)


# Two separate aims stay two beats -- the control for the case above. Without it, a grouping bug
# that merged everything into one beat would still pass the three-victim assertion.
func test_two_separate_aims_stay_two_beats() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	var a := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.LDR: 3})
	var b := H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 0), {Stats.Stat.LDR: 3})

	var plan := ResolvedPlan.new()
	plan.attacks.append(H.stamped_attack(attacker, a))
	plan.attacks.append(H.stamped_attack(attacker, b))

	var sheet := BeatSheet.read(attacker.squad, plan)
	assert_int(_of_kind(sheet, BeatSheet.Kind.VOLLEY).size()).is_equal(2)
	_break_volleys(plan)


# R7 skips a counter whose counter-er was downed earlier in the pass: it neither plays nor previews,
# so it gets no beat -- and a counter phase that is ENTIRELY skipped earns no turnover either.
func test_an_all_skipped_counter_phase_produces_no_beats_and_no_turnover() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.LDR: 3})

	var plan := ResolvedPlan.new()
	var source := H.stamped_attack(attacker, foe)
	plan.attacks.append(source)
	var victims: Array[Unit] = [attacker]
	for counter in CounterAttackAction.create_counter_volley(foe, Vector2i(1, 0), victims, source):
		counter.resolved = ResolvedOutcome.new()
		counter.resolved.skipped = true
		plan.counters.append(counter)

	var sheet := BeatSheet.read(attacker.squad, plan)
	assert_int(_index_of_kind(sheet, BeatSheet.Kind.TURNOVER)).is_equal(-1)
	for beat in sheet.beats:
		assert_bool(beat.is_counter).is_false()
	_break_volleys(plan)


# The camera pans ALONG a knockback and follows a drop all the way down (#520), and #521 tears out
# every cell the flight crosses -- so the whole path lands in the cell set, not just its ends.
func test_a_knockback_puts_its_whole_flight_in_the_cell_set() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.LDR: 3})

	var plan := ResolvedPlan.new()
	var attack := H.stamped_attack(attacker, foe)
	attack.origin_cell = Vector2i(0, 0)
	attack.target_cell = Vector2i(1, 0)
	var out := ResolvedOutcome.new()
	out.knockback_applied = true
	out.knockback_from = Vector2i(1, 0)
	out.knockback_path.assign([Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)])
	out.knockback_to = Vector2i(4, 0)
	out.fall_levels = 2
	attack.resolved = out
	plan.attacks.append(attack)

	var sheet := BeatSheet.read(attacker.squad, plan)
	var beat: BeatSheet.Beat = _of_kind(sheet, BeatSheet.Kind.VOLLEY)[0]
	assert_bool(beat.has_knockback).is_true()
	assert_bool(beat.has_fall).is_true()
	for cell in [Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]:
		assert_bool(sheet.cells.has(cell)).override_failure_message(
				"flight cell %s missing from the tear-out set" % cell).is_true()
	_break_volleys(plan)


# --- the resolver's new record --------------------------------------------------------------

# iron_will_held means the cap BIT, not that the target wears the ability -- the held-breath beat
# is "that should have killed them and did not", which a hit landing under the cap never was.
func test_iron_will_records_the_clamp_only_when_it_actually_bites() -> void:
	var big := _held_damage({Stats.Stat.STR: 60}, true)
	assert_bool(big).is_true()

	# Control 1: the same crushing hit with no Iron Will.
	assert_bool(_held_damage({Stats.Stat.STR: 60}, false)).is_false()
	# Control 2: Iron Will worn, but the hit lands under the cap -- nothing was held.
	assert_bool(_held_damage({Stats.Stat.STR: 0}, true)).is_false()


# Resolve one hit and report whether the Iron Will clamp recorded itself.
func _held_damage(attacker_stats: Dictionary, wears_iron_will: bool) -> bool:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), attacker_stats)
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.LDR: 3, Stats.Stat.MHP: 99})
	if wears_iron_will:
		foe.worn_armor = _armor_granting(Abilities.Id.IRON_WILL)
	_sm.active_squad = attacker.squad
	attacker.squad._queue_action(AttackAction.declare(attacker, attacker.movement.cell, Vector2i(1, 0)))

	var plan := _sm.resolve_plan(attacker.squad, _board_with([attacker, foe]))
	var held: bool = plan.attacks[0].resolved.iron_will_held
	_break_volleys(plan)
	return held


func _armor_granting(id: Abilities.Id) -> ArmorData:
	var armor := ArmorData.new()
	armor.display_name = "Test Armor"
	var ability := AbilityData.new()
	ability.id = id
	ability.kind = AbilityData.AbilityKind.PASSIVE
	armor.granted_abilities = [ability]
	return armor


# --- helpers ---------------------------------------------------------------------------------

func _board_with(units_in: Array) -> BoardContext:
	var units: Array[Unit] = []
	units.assign(units_in)
	return BoardContext.new(_sm.grid, units, _sm)


func _of_kind(sheet: BeatSheet, kind: BeatSheet.Kind) -> Array:
	var found: Array = []
	for beat in sheet.beats:
		if beat.kind == kind:
			found.append(beat)
	return found


func _index_of_kind(sheet: BeatSheet, kind: BeatSheet.Kind) -> int:
	for i in sheet.beats.size():
		if sheet.beats[i].kind == kind:
			return i
	return -1


# create_volley links siblings into a shared self-referential array (a RefCounted cycle, #35).
func _break_volleys(plan: ResolvedPlan) -> void:
	var empty: Array[AttackAction] = []
	for atk in plan.attacks:
		atk.volley = empty
	for ctr in plan.counters:
		ctr.volley = empty
