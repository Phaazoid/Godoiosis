# The CRISIS lethality preview (#57, Law #2): a would-be-down on a Crisis-ELIGIBLE enemy
# whose archetype stance is ALWAYS must preview CRISIS, not DOWNS — the resolver predicts
# it EXACTLY (deterministic, R9: enemy Crisis is never a BREAK). Companion to
# tests/law/test_maim_preview.gd (which pins the fully-maimed case on this same seam).
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

# One sub-overkill fatal hit: damage exactly equals HP (power 5 + fixture STR 5 = MHP 10) —
# same shape as test_maim_preview.gd's helper, so the two Law guards read as a matched pair.
func _fatal_attack(target: Unit) -> AttackAction:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 1), {}, true, 5)
	return AttackAction.create(attacker, attacker.movement.cell, target, target.movement.cell)

func _resolve(attacks: Array[AttackAction]) -> void:
	var plan := ResolvedPlan.new()
	for a in attacks:
		plan.attacks.append(a)
	PlanResolver.resolve(plan)

func test_full_will_rushdown_enemy_previews_crisis() -> void:
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 10, Stats.Stat.WIL: 20})
	target.squad.archetype = AIArchetype.Type.RUSHDOWN
	var attack := _fatal_attack(target)
	_resolve([attack])
	assert_that(attack.resolved.lethality).is_equal(ResolvedOutcome.Lethality.CRISIS)
	assert_int(attack.resolved.target_hp_after).is_equal(Unit.CRISIS_REVIVE_HP)

func test_full_will_hold_enemy_previews_downed_not_crisis() -> void:
	# Same eligibility (full Will), different stance -> the gambit is declined, deterministically.
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 10, Stats.Stat.WIL: 20})
	target.squad.archetype = AIArchetype.Type.HOLD
	var attack := _fatal_attack(target)
	_resolve([attack])
	assert_that(attack.resolved.lethality).is_equal(ResolvedOutcome.Lethality.DOWNED)

func test_full_will_sentry_enemy_previews_downed_not_crisis() -> void:
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 10, Stats.Stat.WIL: 20})
	target.squad.archetype = AIArchetype.Type.SENTRY
	var attack := _fatal_attack(target)
	_resolve([attack])
	assert_that(attack.resolved.lethality).is_equal(ResolvedOutcome.Lethality.DOWNED)

func test_full_will_player_unit_previews_downed() -> void:
	# The PLAYER faction keeps the live prompt (an assumed branch, R9) -- never previews CRISIS
	# even at full Will, since the archetype stance never applies to the player's own units.
	var target := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), {Stats.Stat.MHP: 10, Stats.Stat.WIL: 20})
	var attack := _fatal_attack(target)
	_resolve([attack])
	assert_that(attack.resolved.lethality).is_equal(ResolvedOutcome.Lethality.DOWNED)

func test_sub_gate_will_still_maims_despite_accepting_stance() -> void:
	# Stance ALWAYS but Will below the full gate -> CRISIS never applies; old MAIMED/DOWNED
	# rungs are untouched by #57.
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 10, Stats.Stat.WIL: 0})
	target.squad.archetype = AIArchetype.Type.RUSHDOWN
	var attack := _fatal_attack(target)
	_resolve([attack])
	assert_that(attack.resolved.lethality).is_equal(ResolvedOutcome.Lethality.MAIMED)

func test_crisis_then_second_hit_previews_kill_no_safety_net() -> void:
	# The thread: hit 1 enters Crisis (up at revive HP, no net). A second hit in the SAME
	# pass, >= that revive HP, must preview KILLED -- dodging the first fatal counter doesn't
	# save you from the second (will-and-death.md: "no safety net for the rest of the battle").
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 10, Stats.Stat.WIL: 20})
	target.squad.archetype = AIArchetype.Type.RUSHDOWN
	var first := _fatal_attack(target)
	var second := _fatal_attack(target)
	_resolve([first, second])
	assert_that(first.resolved.lethality).is_equal(ResolvedOutcome.Lethality.CRISIS)
	assert_that(second.resolved.lethality).is_equal(ResolvedOutcome.Lethality.KILLED)
