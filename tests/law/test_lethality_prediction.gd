# Will/death stage of the resolver (docs/design/resolution-pipeline.md R7/R8,
# will-and-death.md "Law #2 requirement"). PlanResolver predicts whether a hit DOWNS or
# KILLS its target, stored on ResolvedOutcome.lethality, so the action queue can preview
# the rung (the down/skull icons). The prediction MUST mirror Unit.take_damage +
# _select_lethal_rung exactly — Law #2 (the queue never lies): the rung shown at plan time
# is the rung execution lands on. STUB era: the rung keys off Unit.OVERKILL_CEILING, not
# spent Will; these tests pin the down/kill math so the Will stage can't silently regress it.
#
# Damage is made exact by spawning attackers with STR 0 + a known weapon power
# (PlanResolver._source_base_damage = main-attack power + scaling), and resolving with an empty
# reactions list so the elemental stage is a no-op and HP-vs-damage is the only variable.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

# STR 0 so base damage == weapon power exactly (PlanResolver._base_damage).
func _attacker(power: int) -> Unit:
	return H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 0}, true, power)

func _target(hp: int) -> Unit:
	return H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: hp})

# Resolve a single attack with NO reactions (damage == base) and hand back its outcome.
func _resolve_attack(attacker: Unit, target: Unit) -> ResolvedOutcome:
	var attack := AttackAction.create(attacker, attacker.movement.cell, target, target.movement.cell)
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions)
	return attack.resolved

# --- the three rungs (survive / down / overkill-kill) ---

# damage < HP -> the unit lives, no lifecycle change.
func test_survivable_hit_is_not_lethal() -> void:
	var outcome := _resolve_attack(_attacker(5), _target(20))
	assert_int(outcome.lethality).is_equal(ResolvedOutcome.Lethality.NONE)

# damage == HP (zero overkill) is the safe down, not a kill.
func test_exactly_lethal_hit_downs() -> void:
	var outcome := _resolve_attack(_attacker(20), _target(20))
	assert_int(outcome.lethality).is_equal(ResolvedOutcome.Lethality.DOWNED)

# overkill within the ceiling -> still a down.
func test_overkill_within_the_ceiling_downs() -> void:
	var outcome := _resolve_attack(_attacker(25), _target(20))   # overkill 5
	assert_int(outcome.lethality).is_equal(ResolvedOutcome.Lethality.DOWNED)

# overkill > ceiling -> dead outright (so low-HP units aren't immortal, rung 3).
func test_overkill_past_the_ceiling_kills() -> void:
	var outcome := _resolve_attack(_attacker(40), _target(20))   # overkill 20
	assert_int(outcome.lethality).is_equal(ResolvedOutcome.Lethality.KILLED)

# --- OVERKILL_CEILING boundary (read from the constant so a tuning change can't rot it) ---

# overkill == ceiling exactly is still DOWN (the kill test is `overkill > ceiling`).
func test_overkill_at_the_ceiling_still_downs() -> void:
	var hp := 20
	var outcome := _resolve_attack(_attacker(hp + Unit.OVERKILL_CEILING), _target(hp))
	assert_int(outcome.lethality).is_equal(ResolvedOutcome.Lethality.DOWNED)

# one point past the ceiling flips to KILL.
func test_one_past_the_ceiling_kills() -> void:
	var hp := 20
	var outcome := _resolve_attack(_attacker(hp + Unit.OVERKILL_CEILING + 1), _target(hp))
	assert_int(outcome.lethality).is_equal(ResolvedOutcome.Lethality.KILLED)

# --- already-downed target (Fork 3: a hit on a downed unit kills it, any damage) ---

func test_hitting_a_downed_unit_is_predicted_killed() -> void:
	var target := _target(20)
	target.take_damage(target.get_current_hp())   # exactly-lethal -> DOWNED, clings at 1 HP
	assert_bool(target.is_downed()).is_true()
	var outcome := _resolve_attack(_attacker(1), target)   # even a 1-damage poke
	assert_int(outcome.lethality).is_equal(ResolvedOutcome.Lethality.KILLED)

# --- Law #2: the previewed rung is the rung execution actually lands on ---

func test_predicted_down_matches_execution() -> void:
	var target := _target(20)
	var outcome := _resolve_attack(_attacker(25), target)   # overkill 5 -> DOWN
	assert_int(outcome.lethality).is_equal(ResolvedOutcome.Lethality.DOWNED)
	target.take_damage(outcome.damage)                      # run the same hit for real
	assert_bool(target.is_downed()).is_true()

func test_predicted_kill_matches_execution() -> void:
	var target := _target(20)
	var outcome := _resolve_attack(_attacker(20 + Unit.OVERKILL_CEILING + 5), target)   # past ceiling -> KILL
	assert_int(outcome.lethality).is_equal(ResolvedOutcome.Lethality.KILLED)
	target.take_damage(outcome.damage)
	assert_bool(target.is_dead()).is_true()
