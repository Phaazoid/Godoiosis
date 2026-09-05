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
	# The CAST is who is in the scene; the tear-out set is what a MAIN ACTION touches, and those are
	# different questions (dev, 2026-08-26). The bystander squadmate never acts and is never hit, so
	# it is cast and its ground stays on the board -- bringing it along for context is #521's own
	# feels-test flag, deliberately not a fact of the sheet.
	assert_bool(sheet.cells.has(mate.movement.cell)).override_failure_message(
			"a bystander's ground is in the tear-out set").is_false()
	_break_volleys(plan)



# THE BLAST'S WHOLE FOOTPRINT IS ON STAGE, occupied or not (dev, 2026-09-05: "definitely B", #754).
# create_volley stamps every member with the ONE aim cell, so marking target_cell put a line's lead
# victim on stage and left the rest -- and the empty ground under the beam -- on the board forty
# cells below the camera. The report's shape: four hits down a column, staged 2.
func test_a_volley_puts_its_whole_footprint_on_stage() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	_give_a_line(attacker, 3)
	var near := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.LDR: 3})
	var far := H.spawn_solo(self, _sm, ENEMY, Vector2i(3, 0), {Stats.Stat.LDR: 3})
	_sm.active_squad = attacker.squad
	attacker.squad._queue_action(AttackAction.declare(attacker, attacker.movement.cell, Vector2i(1, 0)))

	var plan := _sm.resolve_plan(attacker.squad, _board_with([attacker, near, far]))
	var sheet := BeatSheet.read(attacker.squad, plan)

	# Non-vacuity: the line reached both of them, or the far cell proves nothing.
	assert_int(plan.attacks.size()).override_failure_message(
			"fixture drifted: the line did not hit both").is_equal(2)
	for cell: Vector2i in [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]:
		assert_bool(sheet.cells.has(cell)).override_failure_message(
				"%s is not on stage: %s" % [cell, sheet.cells]).is_true()
	_break_volleys(plan)


# A counter's footprint comes along too: the foe answers with a line, and the open ground its beam
# crosses past the attacker lifts with the fight.
func test_a_counters_footprint_is_on_stage() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 0), {Stats.Stat.LDR: 3})
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(3, 0), {Stats.Stat.LDR: 3})
	_give_a_line(foe, 2)
	_sm.active_squad = attacker.squad
	attacker.squad._queue_action(AttackAction.declare(attacker, attacker.movement.cell, Vector2i(3, 0)))

	var plan := _sm.resolve_plan(attacker.squad, _board_with([attacker, foe]))
	var sheet := BeatSheet.read(attacker.squad, plan)

	assert_array(plan.counters).override_failure_message(
			"fixture drifted: nobody countered").is_not_empty()
	# The foe fires back along -x: (2, 0) is the attacker, (1, 0) is open ground under the beam.
	assert_bool(sheet.cells.has(Vector2i(1, 0))).override_failure_message(
			"the counter's empty cell is not on stage: %s" % [sheet.cells]).is_true()
	_break_volleys(plan)


# A swing at open ground (#47) stages its footprint: the cell-attack branch is the one a volley
# case cannot reach, and it fires over the same ground.
func test_a_swing_at_open_ground_stages_its_footprint() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	_give_a_line(attacker, 3)
	_sm.active_squad = attacker.squad
	attacker.squad._queue_action(AttackAction.declare(attacker, attacker.movement.cell, Vector2i(1, 0)))

	var plan := _sm.resolve_plan(attacker.squad, _board_with([attacker]))
	var sheet := BeatSheet.read(attacker.squad, plan)

	assert_int(plan.attacks.size()).is_equal(1)
	assert_object(plan.attacks[0].target).override_failure_message(
			"fixture drifted: somebody was hit").is_null()
	for cell: Vector2i in [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]:
		assert_bool(sheet.cells.has(cell)).override_failure_message(
				"%s is not on stage: %s" % [cell, sheet.cells]).is_true()
	_break_volleys(plan)


# A line of the given length on the unit's own template, so declare() fires it.
func _give_a_line(unit: Unit, length: int) -> void:
	var line := ForwardLinePattern.new()
	line.length = length
	var weapon: WeaponInstance = unit.get_equipped_weapon() as WeaponInstance
	weapon.template.main_attack.attack_pattern = line
# --- fact cases: hand-built plans -----------------------------------------------------------

# One blast is one shot however many it hits -- #410 rules an AoE striking three victims a single
# sweep, not three cuts. Grouping follows is_secondary_hit, the same read the resolver makes.
# THE TEAR-OUT'S GATE, and it lives in the SET rather than beside it (dev, 2026-08-26): *"there
# have to be main actions at play. Movement by itself doesn't do it."* A pass that only walks
# touches no main-action cell, so there is nothing to lift and no second predicate to keep in step.
#
# Found in play: the cast sweep this replaced tore a hole in the board at the end of every move.
func test_a_pass_that_only_walks_touches_no_ground() -> void:
	var leader := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	leader.squad._queue_action(_walk(leader, Vector2i(0, 1)))

	var sheet := BeatSheet.read(leader.squad, ResolvedPlan.new())
	assert_object(sheet.moves()).override_failure_message(
			"fixture drifted: this case needs a real move beat").is_not_null()
	assert_array(sheet.cells).override_failure_message(
			"walking tore out ground: %s" % [sheet.cells]).is_empty()


# ...and a MAIN ACTION does, whichever one it is. A rally is the cheapest to stage -- no target, no
# terrain -- and it is a side-channel verb, so this is the half an attack-shaped rule would miss.
func test_a_side_channel_main_action_puts_its_ground_on_stage() -> void:
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 3), {Stats.Stat.LDR: 3})
	var rally := RallyAction.new()
	rally.init(unit)
	assert_bool(rally.is_main_action()).override_failure_message(
			"fixture drifted: this case needs a MAIN action").is_true()
	unit.squad._queue_action(rally)

	var sheet := BeatSheet.read(unit.squad, ResolvedPlan.new())
	assert_array(sheet.cells).override_failure_message(
			"a main action tore out nothing").contains([unit.movement.cell])


func test_a_three_victim_volley_is_one_beat_in_strike_order() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	var a := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.LDR: 3})
	var b := H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 0), {Stats.Stat.LDR: 3})
	var c := H.spawn_solo(self, _sm, ENEMY, Vector2i(3, 0), {Stats.Stat.LDR: 3})

	var plan := ResolvedPlan.new()
	var victims: Array[Unit] = [a, b, c]
	plan.attacks.assign(AttackAction.create_volley(attacker, Vector2i(0, 0), Vector2i(1, 0),
			victims, attacker.get_equipped_weapon().template.main_attack, _cells_of(victims)))

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
	for counter in CounterAttackAction.create_counter_volley(foe, Vector2i(1, 0), victims, source, _cells_of(victims)):
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


# --- who the camera frames (#520) -------------------------------------------------------------

# The VICTIM, not the attacker: what the player needs to read is what is being done to whom, and
# reach is short enough that the attacker is usually in frame anyway.
func test_a_beat_frames_its_victim() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.LDR: 3})
	_sm.active_squad = attacker.squad
	attacker.squad._queue_action(AttackAction.declare(attacker, attacker.movement.cell, Vector2i(1, 0)))

	var plan := _sm.resolve_plan(attacker.squad, _board_with([attacker, foe]))
	var sheet := BeatSheet.read(attacker.squad, plan)
	assert_object(sheet.volleys(false)[0].subject()).is_same(foe)
	_break_volleys(plan)


# #47's swing at open ground has NO victim, and the camera still has to go somewhere -- the actor.
# Without the fallback a cell attack would play off-screen, which is the whole thing #520 fixes.
func test_a_swing_at_open_ground_frames_the_actor_instead() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	_sm.active_squad = attacker.squad
	attacker.squad._queue_action(AttackAction.declare(attacker, attacker.movement.cell, Vector2i(1, 0)))

	var plan := _sm.resolve_plan(attacker.squad, _board_with([attacker]))
	var beat: BeatSheet.Beat = BeatSheet.read(attacker.squad, plan).volleys(false)[0]
	assert_array(beat.victims).override_failure_message(
			"fixture drifted: this case needs the no-victim cell attack").is_empty()
	assert_object(beat.subject()).is_same(attacker)
	_break_volleys(plan)


# --- from which SIDE the camera frames it (#520 diff 2a) --------------------------------------

# The line is the RESOLVER's aim, origin_cell -> target_cell, not the two units' live positions.
# Asserted as the aim rather than as literal cells so the case survives the fixture moving.
func test_a_volley_beat_names_the_line_it_is_framed_across() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.LDR: 3})
	_sm.active_squad = attacker.squad
	attacker.squad._queue_action(AttackAction.declare(attacker, attacker.movement.cell, Vector2i(1, 0)))

	var plan := _sm.resolve_plan(attacker.squad, _board_with([attacker, foe]))
	var beat: BeatSheet.Beat = BeatSheet.read(attacker.squad, plan).volleys(false)[0]
	var opener: AttackAction = beat.actions[0]
	assert_array(beat.aim_line()).is_equal([opener.origin_cell, opener.target_cell])
	_break_volleys(plan)


# A swing at open ground HAS a direction even with nobody to hit -- the aim points somewhere. That
# is the whole reason the line comes off the attack rather than off actor-and-victim: the beat that
# frames its actor by fallback (see above) is still a beat with a side to be seen from.
func test_a_swing_at_open_ground_still_has_a_line() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	_sm.active_squad = attacker.squad
	attacker.squad._queue_action(AttackAction.declare(attacker, attacker.movement.cell, Vector2i(1, 0)))

	var plan := _sm.resolve_plan(attacker.squad, _board_with([attacker]))
	var beat: BeatSheet.Beat = BeatSheet.read(attacker.squad, plan).volleys(false)[0]
	assert_array(beat.victims).override_failure_message(
			"fixture drifted: this case needs the no-victim cell attack").is_empty()
	assert_array(beat.aim_line()).is_not_empty()
	_break_volleys(plan)


# A MOVES beat has no pair, so it has no line -- and absence is what the schedule reads as "leave
# the camera's angle where it is". A walk framed side-on to nothing would be an angle invented from
# whatever two cells happened to be reachable.
func test_a_move_beat_has_no_line_to_be_framed_across() -> void:
	var leader := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	leader.squad._queue_action(_walk(leader, Vector2i(0, 1)))

	var moves := BeatSheet.read(leader.squad, ResolvedPlan.new()).moves()
	assert_object(moves).override_failure_message(
			"fixture drifted: this case needs a real move beat").is_not_null()
	assert_array(moves.aim_line()).is_empty()


# --- the wire into the beat table (#519) ------------------------------------------------------

# The sheet's whole point downstream is that a beat KNOWS what it was before anything plays. Both
# ends were pinned separately -- the sheet builds beats, the table reads their facts -- and this is
# the case that fails if a REAL lethal blow reaches the table looking like a scratch. Asserted as a
# relationship (something to hold for vs nothing) rather than a rung, because whether a felled unit
# reads DOWNED or KILLED is the lifecycle rules' business, not this suite's.
# REWRITTEN for #520 2b slice 2: its second assertion pinned "a scratch earns exactly 0", which was
# the rule until HOLD_ATTACK became the ladder's floor. That was a real rule with a real fear behind
# it -- its own message said "every beat now reads as a big moment" -- and the fear is still worth
# guarding, so what replaces it is the RELATIONSHIP rather than the number: a felling blow must
# outlast a scratch. That survives any tuning of either, which the zero never could once the floor
# existed. (dev, 2026-08-27: "I don't see controls for holding the most common thing".)
func test_a_real_felling_blow_reaches_the_beat_table_as_one() -> void:
	var lethal := _hold_for_a_hit({Stats.Stat.STR: 60}, 1)
	var scratch := _hold_for_a_hit({Stats.Stat.STR: 0}, 99)

	assert_float(lethal).override_failure_message(
			"a blow that felled someone earned no hold -- the sheet's facts are not reaching Pacing").is_greater(0.0)
	assert_float(scratch).override_failure_message(
			"a scratch earned no hold at all -- the ladder lost its floor and the commonest beat in the game is bare again") \
		.is_greater(0.0)
	assert_float(lethal).override_failure_message(
			"a scratch is worth as much as a kill -- every beat reads as a big moment, which is what the floor must not do") \
		.is_greater(scratch)


# The PAUSE SCHEDULE itself: one hold per volley, keyed on the action that opens it, valued by the
# table. Pinned here because a schedule that came back empty would silently restore the old
# per-action pacing and nothing headless could see it -- Pacing.beat costs a headless run nothing
# by design, so the await it feeds is invisible. This closes everything up to that await.
func test_a_volley_gets_ONE_hold_on_the_action_that_opens_it() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	var a := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.LDR: 3})
	var b := H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 0), {Stats.Stat.LDR: 3})
	var c := H.spawn_solo(self, _sm, ENEMY, Vector2i(3, 0), {Stats.Stat.LDR: 3})

	var plan := ResolvedPlan.new()
	var victims: Array[Unit] = [a, b, c]
	plan.attacks.assign(AttackAction.create_volley(attacker, Vector2i(0, 0), Vector2i(1, 0),
			victims, attacker.get_equipped_weapon().template.main_attack, _cells_of(victims)))

	var sheet := BeatSheet.read(attacker.squad, plan)
	var executor := OrderExecutor.new()
	auto_free(executor)
	# No profile handed in since #647 -- _beat_holds asks Pacing.profile_for per beat, because under
	# COMBAT_ONLY a volley and the walk before it are paced differently.
	var holds: Dictionary = executor._beat_holds(sheet.volleys(false), false)

	# One entry for three hits: the blast is one moment, not three.
	assert_int(holds.size()).override_failure_message(
			"three hits took three pauses -- a volley is one moment (#410)").is_equal(1)
	assert_bool(holds.has(plan.attacks[0])).override_failure_message(
			"the hold is not on the action that OPENS the volley").is_true()
	# Asked through profile_for rather than against a named profile, so this case pins the WIRE (the
	# schedule uses the one collapse) and stays silent about which mode the run happens to be in.
	var volley := sheet.volleys(false)[0]
	assert_float(holds[plan.attacks[0]]).is_equal_approx(
			Pacing.duration_for(volley, Pacing.profile_for(volley), false), 0.0001)
	_break_volleys(plan)


# ...and its TWIN on the other side of the beat (#520 2b slice 2). Same one-entry-per-volley rule,
# keyed on the OPPOSITE END: the camera pans and holds at the action that opens the blast, and stays
# once its LAST member has played. Keying both on [0] would put the linger between the first hit and
# the second, which is dead air in the middle of one moment rather than a beat after it.
#
# This is the half that closes the wire up to the await, for the reason the case above states: the
# await itself is invisible headless, so what can be pinned is that the schedule reaches it correct.
func test_a_volley_lingers_ONCE_after_the_action_that_closes_it() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	var a := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.LDR: 3})
	var b := H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 0), {Stats.Stat.LDR: 3})
	var c := H.spawn_solo(self, _sm, ENEMY, Vector2i(3, 0), {Stats.Stat.LDR: 3})

	var plan := ResolvedPlan.new()
	var victims: Array[Unit] = [a, b, c]
	plan.attacks.assign(AttackAction.create_volley(attacker, Vector2i(0, 0), Vector2i(1, 0),
			victims, attacker.get_equipped_weapon().template.main_attack, _cells_of(victims)))

	var sheet := BeatSheet.read(attacker.squad, plan)
	var executor := OrderExecutor.new()
	auto_free(executor)
	var beats := sheet.volleys(false)
	var lingers: Dictionary = executor._beat_lingers(beats)

	assert_int(lingers.size()).override_failure_message(
			"three hits took three lingers -- a volley is one moment (#410)").is_equal(1)
	# Non-vacuous: the beat really does have several members, so first and last are different
	# actions and the assertion below can tell them apart.
	assert_int(beats[0].actions.size()).override_failure_message(
			"the volley collapsed to one member; the case cannot tell the two ends apart").is_greater(1)
	assert_bool(lingers.has(beats[0].actions[-1])).override_failure_message(
			"the linger is not on the action that CLOSES the volley").is_true()
	assert_bool(lingers.has(beats[0].actions[0])).override_failure_message(
			"the linger sits on the volley's OPENING action -- it would play between the first hit and the second") \
		.is_false()
	assert_float(lingers[beats[0].actions[-1]]).is_equal_approx(Pacing.linger_for(beats[0]), 0.0001)
	_break_volleys(plan)


# Resolve one real hit and report what the beat it produces is worth to the table.
func _hold_for_a_hit(attacker_stats: Dictionary, target_mhp: int) -> float:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), attacker_stats)
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.LDR: 3, Stats.Stat.MHP: target_mhp})
	_sm.active_squad = attacker.squad
	attacker.squad._queue_action(AttackAction.declare(attacker, attacker.movement.cell, Vector2i(1, 0)))

	var plan := _sm.resolve_plan(attacker.squad, _board_with([attacker, foe]))
	var sheet := BeatSheet.read(attacker.squad, plan)
	var hold := Pacing.hold_for(sheet.volleys(false)[0])
	_break_volleys(plan)
	return hold


func _armor_granting(id: Abilities.Id) -> ArmorData:
	var armor := ArmorData.new()
	armor.display_name = "Test Armor"
	var ability := AbilityData.new()
	ability.id = id
	ability.kind = AbilityData.AbilityKind.PASSIVE
	armor.granted_abilities = [ability]
	return armor


# --- the move phase (#520 follow-up) ----------------------------------------------------------

# The MOVES beat is what the camera frames before anybody walks, and it opens on the LEADER when
# the leader is walking -- a squad's move is read from the unit the rest are following. The mate's
# move is queued FIRST here on purpose, so queue order alone would name the wrong unit.
func test_the_move_beat_opens_on_the_leader_when_the_leader_walks() -> void:
	var leader := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	var mate := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), {Stats.Stat.LDR: 3})
	_sm.join_squad(mate, leader.squad)

	leader.squad._queue_action(_walk(mate, Vector2i(1, 1)))
	leader.squad._queue_action(_walk(leader, Vector2i(0, 1)))

	var sheet := BeatSheet.read(leader.squad, ResolvedPlan.new())
	var beat := sheet.moves()
	assert_object(beat).override_failure_message("two real moves produced no MOVES beat").is_not_null()
	assert_int(beat.actions.size()).is_equal(2)
	assert_object(beat.subject()) \
		.override_failure_message("the walk framed queue order instead of the leader") \
		.is_same(leader)


# A hold-position filler is inserted by a game.gd signal handler for every member that is NOT
# moving, so almost every real squad move carries some. They are not moves: nobody ordered one and
# nothing travels, so framing one parks the camera on a unit standing still.
func test_a_hold_position_filler_is_not_a_mover() -> void:
	var leader := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	var mate := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), {Stats.Stat.LDR: 3})
	_sm.join_squad(mate, leader.squad)

	leader.squad._queue_action(_hold(leader))
	leader.squad._queue_action(_walk(mate, Vector2i(1, 1)))

	var beat := BeatSheet.read(leader.squad, ResolvedPlan.new()).moves()
	assert_object(beat).is_not_null()
	assert_int(beat.actions.size()).override_failure_message(
			"the leader's hold-position filler was counted as a move").is_equal(1)
	assert_object(beat.subject()).is_same(mate)


# ... and a queue of NOTHING but fillers is a phase in which the board does not change, so it earns
# no beat at all -- which is what keeps the camera still instead of panning to a stationary unit.
func test_a_queue_of_nothing_but_holds_has_no_move_beat() -> void:
	var leader := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	leader.squad._queue_action(_hold(leader))

	assert_object(BeatSheet.read(leader.squad, ResolvedPlan.new()).moves()) \
		.override_failure_message("a hold-only queue produced a MOVES beat -- the camera would pan to nothing") \
		.is_null()


# --- the heal, as a fact (#519's table reads it) -----------------------------------------------

# A heal is something that HAPPENED, and the sheet has to say so or #519's table cannot hold on it.
# Read off the resolver's own heal_amount, never a re-read of fired_attack.heals -- same discipline
# as every other fact here.
func test_a_heal_is_a_beat_fact_and_a_damaging_hit_is_not() -> void:
	assert_bool(_beat_of_a_hit_on_an_ally(true).has_heal) \
		.override_failure_message("a heal landed and the beat did not know it").is_true()
	assert_bool(_beat_of_a_hit_on_an_ally(false).has_heal) \
		.override_failure_message("a damaging hit reads as a heal").is_false()


# --- the side-channel tail --------------------------------------------------------------------

# execute_orders plays the tail ONE ORDER AT A TIME, each awaiting its own completion, so two
# rescues are two moments. A beat per TYPE (which is what #524 shipped) would leave the second
# rescuer acting off-camera and unheld, since the schedule keys on each beat's first action.
func test_two_rescues_are_two_coda_beats() -> void:
	var leader := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	var mate := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), {Stats.Stat.LDR: 3})
	_sm.join_squad(mate, leader.squad)
	var body_a := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 1), {Stats.Stat.LDR: 3})
	var body_b := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 1), {Stats.Stat.LDR: 3})

	leader.squad._queue_action(_rescue(leader, body_a))
	leader.squad._queue_action(_rescue(mate, body_b))

	var codas := BeatSheet.read(leader.squad, ResolvedPlan.new()).codas(BaseAction.ActionType.RESCUE)
	assert_int(codas.size()).override_failure_message(
			"two rescues collapsed into one beat -- the second plays off-camera").is_equal(2)
	assert_object(codas[0].subject()).is_same(body_a)
	assert_object(codas[1].subject()).is_same(body_b)


# What a coda frames is what the verb is done TO, which is the same rule a volley follows -- and it
# is the ORDER that answers, because only the order knows. A rescue has a body; a rally has nobody
# but the unit doing it, and falls back to the actor.
#
# TWO actors, because rescue and rally are both MAIN actions: queued on one unit the second
# displaces the first, which is the queue's own rule working rather than a fixture detail.
func test_a_coda_frames_what_its_verb_is_done_to() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	var rallier := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), {Stats.Stat.LDR: 3})
	_sm.join_squad(rallier, rescuer.squad)
	var body := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 1), {Stats.Stat.LDR: 3})
	rescuer.squad._queue_action(_rescue(rescuer, body))

	var rally := RallyAction.new()
	rally.init(rallier)
	rescuer.squad._queue_action(rally)

	var sheet := BeatSheet.read(rescuer.squad, ResolvedPlan.new())
	assert_object(sheet.codas(BaseAction.ActionType.RESCUE)[0].subject()) \
		.override_failure_message("a rescue framed the rescuer, not the body coming up").is_same(body)
	assert_object(sheet.codas(BaseAction.ActionType.RALLY)[0].subject()) \
		.override_failure_message("a rally has no target -- it must fall back to the unit rallying").is_same(rallier)


# --- helpers ---------------------------------------------------------------------------------

func _walk(unit: Unit, to: Vector2i) -> MoveAction:
	var move := MoveAction.new()
	var path: Array[Vector2i] = [to]
	move.init(unit, path, null)
	return move


func _hold(unit: Unit) -> MoveAction:
	var move := MoveAction.new()
	move.init_hold_position(unit, null)
	return move


func _rescue(rescuer: Unit, body: Unit) -> RescueAction:
	var action := RescueAction.new()
	# The landing is the body's own cell: these beats are all DRY-GROUND rescues, so #116's haul
	# never fires and nothing here is about where a body comes out.
	action.init(rescuer, body, body.movement.cell)
	return action


# One real resolve of a hit aimed at a SQUADMATE, healing or damaging, and the beat it produces.
# The ally is the victim either way, so the only thing that differs is what the resolver did to it.
func _beat_of_a_hit_on_an_ally(healing: bool) -> BeatSheet.Beat:
	var actor := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	var ally := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), {Stats.Stat.LDR: 3})
	_sm.join_squad(ally, actor.squad)
	var weapon := H.make_weapon(4)
	weapon.template.main_attack.hits_allies = true
	weapon.template.main_attack.heals = healing
	actor.equipped_weapon = weapon
	_sm.active_squad = actor.squad
	actor.squad._queue_action(H.stamped_attack(actor, ally))

	var plan := _sm.resolve_plan(actor.squad, _board_with([actor, ally]))
	var beat: BeatSheet.Beat = BeatSheet.read(actor.squad, plan).volleys(false)[0]
	assert_array(beat.victims).override_failure_message(
			"fixture drifted: the aim at the ally found nobody").is_not_empty()
	_break_volleys(plan)
	return beat


# A hand-built volley's footprint: the ground its victims stand on, which is all a fictional blast
# can honestly claim.
func _cells_of(units: Array[Unit]) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for unit in units:
		cells.append(unit.movement.cell)
	return cells


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


# --- the emphasis schedule (#520 diff 2c) --------------------------------------------------------

func test_the_emphasis_schedule_keys_on_the_action_that_OPENS_a_beat() -> void:
	# The pan and the hold key there too, and for the same reason: the camera leans in as the shot
	# is SET UP, not after the last hit lands. Deliberately not the linger's [-1] key.
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	var a := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.LDR: 3})
	var b := H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 0), {Stats.Stat.LDR: 3})
	var plan := ResolvedPlan.new()
	var victims: Array[Unit] = [a, b]
	plan.attacks.assign(AttackAction.create_volley(attacker, Vector2i(0, 0), Vector2i(1, 0),
			victims, attacker.get_equipped_weapon().template.main_attack, _cells_of(victims)))

	var sheet := BeatSheet.read(attacker.squad, plan)
	var executor := OrderExecutor.new()
	auto_free(executor)
	var beats := sheet.volleys(false)
	# Marked lethal by hand, so this case is about WHERE the emphasis is keyed and nothing else.
	# Left as an ordinary hit it would earn 0 and die alongside the publish-zero case below, which
	# is two cases pinning one property -- and a mutant reddening both tells you nothing about
	# either. Shaping the beat is fair here: the ladder that reads this field has its own suite.
	beats[0].has_removal = true
	var emphases: Dictionary = executor._beat_emphases(beats)

	assert_int(beats[0].actions.size()).override_failure_message(
			"the volley collapsed to one member; the case cannot tell the two ends apart").is_greater(1)
	assert_bool(emphases.has(beats[0].actions[0])).override_failure_message(
			"the emphasis is not on the action that OPENS the volley").is_true()
	assert_bool(emphases.has(beats[0].actions[-1])).override_failure_message(
			"the emphasis sits on the CLOSING action -- the camera would lean in after the blow"
	).is_false()


func test_every_beat_publishes_an_emphasis_INCLUDING_zero() -> void:
	# Absence would mean "hold what you had" -- directed_line's idiom, and wrong here: the camera
	# would stay pushed in from a kill through every quiet beat after it and the pass would never
	# breathe. A beat worth nothing must say so out loud.
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	var victim := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.LDR: 3})
	var plan := ResolvedPlan.new()
	var victims: Array[Unit] = [victim]
	plan.attacks.assign(AttackAction.create_volley(attacker, Vector2i(0, 0), Vector2i(1, 0),
			victims, attacker.get_equipped_weapon().template.main_attack, _cells_of(victims)))

	var sheet := BeatSheet.read(attacker.squad, plan)
	var executor := OrderExecutor.new()
	auto_free(executor)
	var beats := sheet.volleys(false)
	var emphases: Dictionary = executor._beat_emphases(beats)

	assert_int(emphases.size()).override_failure_message(
			"an ordinary beat published nothing at all, so the camera would never relax"
	).is_equal(beats.size())
	assert_float(float(emphases[beats[0].actions[0]])).override_failure_message(
			"an ordinary hit was scheduled as a big moment").is_equal(0.0)


# --- triggered shots are beats too (#567) --------------------------------------------------------

# A watch over one cell (no pattern means the footprint is the aimed cell alone), armed on a unit
# standing off the walked row. The FACTION matters: a watch only fires on the other side, so the
# shove-combo case below arms a squadmate of the shover rather than another enemy.
func _watcher_over(cell: Vector2i, at := Vector2i(3, 4), faction := ENEMY) -> Unit:
	var unit := H.spawn_solo(self, _sm, faction, at, {Stats.Stat.STR: 4}, true, 5)
	var footprint: Array[Vector2i] = [cell]
	unit.arm_watch(at, cell, footprint, (unit.get_equipped_weapon() as WeaponInstance).template.main_attack)
	return unit


# The shot the walk walks into is its own VOLLEY beat, sitting after the MOVES beat -- which is
# where the move phase now plays it. Before #567 it was on no sheet at all, and the executor
# hand-built a subject and a flat linger for it.
func test_a_mid_walk_shot_is_a_volley_beat_of_its_own_after_the_moves_beat() -> void:
	var watcher := _watcher_over(Vector2i(2, 0))
	var crosser := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.MHP: 60}, false)
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	var move := MoveAction.new()
	move.init(crosser, path, null)
	crosser.squad._queue_action(move)

	var plan := _sm.resolve_plan(crosser.squad, _board_with([watcher, crosser]))
	assert_int(plan.watch_shots.size()).override_failure_message(
			"the walk crossed no watch -- the fixture is not exercising the rule").is_equal(1)
	var sheet := BeatSheet.read(crosser.squad, plan)

	var volleys := sheet.volleys(false)
	assert_int(volleys.size()).is_equal(1)
	assert_object(volleys[0].actions[0]).is_same(plan.watch_shots[0])
	assert_int(_index_of_kind(sheet, BeatSheet.Kind.VOLLEY)).override_failure_message(
			"the triggered shot's beat does not follow the walk it interrupts") \
		.is_greater(_index_of_kind(sheet, BeatSheet.Kind.MOVES))
	# The camera goes to the CROSSER: the moment is somebody walking into a line. Here they are the
	# same unit; test_a_splashed_bystander_does_not_steal_the_shot_s_subject is where they differ.
	assert_object(volleys[0].subject()).is_same(crosser)
	_break_shots(plan)


# ...and the subject rule is not "the first victim". Splash is gathered CELL-FIRST over the
# footprint, so a bystander standing on an earlier cell leads the volley while the crosser is the
# one the moment is about.
func test_a_splashed_bystander_does_not_steal_the_shot_s_subject() -> void:
	var watched: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0)]
	var watcher := H.spawn_solo(self, _sm, ENEMY, Vector2i(3, 4), {Stats.Stat.STR: 4}, true, 5)
	var attack := (watcher.get_equipped_weapon() as WeaponInstance).template.main_attack
	watcher.arm_watch(Vector2i(3, 4), watched[0], watched, attack)
	var bystander := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), {Stats.Stat.MHP: 60}, false)
	var crosser := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 1), {Stats.Stat.MHP: 60}, false)
	_sm.join_squad(bystander, crosser.squad)
	var path: Array[Vector2i] = [Vector2i(2, 1), Vector2i(2, 0)]
	var move := MoveAction.new()
	move.init(crosser, path, null)
	crosser.squad._queue_action(move)

	var plan := _sm.resolve_plan(crosser.squad, _board_with([watcher, bystander, crosser]))
	assert_int(plan.watch_shots.size()).override_failure_message(
			"the shot did not splash both cells -- the fixture proves nothing").is_equal(2)
	var sheet := BeatSheet.read(crosser.squad, plan)

	var volleys := sheet.volleys(false)
	assert_int(volleys.size()).is_equal(1)
	assert_object(volleys[0].actions[0].aimed_at()).override_failure_message(
			"fixture: the crosser leads the volley, so the subject rule is not under test") \
		.is_same(bystander)
	assert_object(volleys[0].subject()).override_failure_message(
			"the camera framed the splashed bystander instead of the unit that walked into the line") \
		.is_same(crosser)
	_break_shots(plan)


# The other half (#567): a shove-triggered shot follows the volley that threw somebody into it, and
# its cells are ON STAGE -- it fires inside the tear-out diorama, and the watcher's anchor cell is
# nobody's attacker origin, so unswept it would fire standing on a hole.
func test_a_shove_triggered_shot_follows_its_volley_and_is_staged() -> void:
	var watcher := _watcher_over(Vector2i(2, 0), Vector2i(2, 4), PLAYER)
	var shover := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4}, true, 4)
	var victim := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 60}, false)
	(shover.get_equipped_weapon() as WeaponInstance).template.main_attack.knockback = 1
	_sm.active_squad = shover.squad
	shover.squad._queue_action(H.stamped_attack(shover, victim))

	var plan := _sm.resolve_plan(shover.squad, _board_with([watcher, shover, victim]))
	assert_int(plan.watch_shots.size()).override_failure_message(
			"the shove did not land the victim in the watched cell -- fixture, not mechanic").is_equal(1)
	var sheet := BeatSheet.read(shover.squad, plan)

	var volleys := sheet.volleys(false)
	assert_int(volleys.size()).is_equal(2)
	assert_object(volleys[0].actions[0]).is_same(plan.attacks[0])
	assert_object(volleys[1].actions[0]).override_failure_message(
			"the triggered shot's beat does not follow the blow that caused it").is_same(plan.watch_shots[0])
	assert_array(sheet.cells).override_failure_message(
			"the watcher's ground is not on stage, so the shot fires standing on a hole") \
		.contains([watcher.movement.cell])
	_break_shots(plan)


func _break_shots(plan: ResolvedPlan) -> void:
	_break_volleys(plan)
	var empty: Array[AttackAction] = []
	for shot in plan.watch_shots:
		shot.volley = empty
