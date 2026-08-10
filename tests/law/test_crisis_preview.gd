# The CRISIS lethality preview (#57, Law #2; rebuilt by #158): Crisis is an EQUIPPED ability now,
# so the rung is armed, never decided -- a full-Will unit holding the ability previews CRISIS
# whatever its faction or archetype, and nobody else ever does. The per-archetype stance table this
# suite used to pin is deleted; the player previewing their OWN Crisis is the case that was
# impossible before (the old PLAYER fork existed to keep the live prompt unpredicted).
# Companion to tests/law/test_maim_preview.gd (which pins the fully-maimed case on this same seam).
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

# Arm the gambit the way content does: assign the Berserker job, whose pool carries the Crisis
# ability. Exercises the real path (jobs -> JobCatalog -> ability kit), not a hand-stamped flag.
func _arm(unit: Unit) -> void:
	unit.unit_instance.jobs.append("berserker")
	assert_bool(unit.has_live_ability(Abilities.Id.CRISIS)) \
		.override_failure_message("fixture: the Berserker job did not arm Crisis").is_true()

# One sub-overkill fatal hit: damage exactly equals HP (power 5 + fixture STR 5 = MHP 10) —
# same shape as test_maim_preview.gd's helper, so the two Law guards read as a matched pair.
func _fatal_attack(target: Unit) -> AttackAction:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 1), {}, true, 5)
	return H.stamped_attack(attacker, target)

func _resolve(attacks: Array[AttackAction]) -> void:
	var plan := ResolvedPlan.new()
	for a in attacks:
		plan.attacks.append(a)
	PlanResolver.resolve(plan)

# The case that was impossible before #158: the player's own unit previews its own Crisis.
func test_full_will_armed_player_unit_previews_crisis() -> void:
	var target := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), {Stats.Stat.MHP: 10, Stats.Stat.WIL: 20})
	_arm(target)
	var attack := _fatal_attack(target)
	_resolve([attack])
	assert_that(attack.resolved.lethality).is_equal(ResolvedOutcome.Lethality.CRISIS)
	assert_int(attack.resolved.target_hp_after).is_equal(Abilities.CRISIS_REVIVE_HP)

# HOLD is the archetype whose stance used to DECLINE the gambit -- an armed one crises anyway,
# which is what proves the stance table is really gone rather than merely bypassed.
func test_full_will_armed_enemy_previews_crisis_whatever_its_archetype() -> void:
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 10, Stats.Stat.WIL: 20})
	target.squad.archetype = AIArchetype.Type.HOLD
	_arm(target)
	var attack := _fatal_attack(target)
	_resolve([attack])
	assert_that(attack.resolved.lethality).is_equal(ResolvedOutcome.Lethality.CRISIS)

# RUSHDOWN used to auto-accept by personality. Unarmed, personality grants nothing -- Crisis
# access is authored content now (the ability on the unit), not code on the archetype.
func test_full_will_unarmed_unit_previews_downed_whatever_its_archetype() -> void:
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 10, Stats.Stat.WIL: 20})
	target.squad.archetype = AIArchetype.Type.RUSHDOWN
	var attack := _fatal_attack(target)
	_resolve([attack])
	assert_that(attack.resolved.lethality).is_equal(ResolvedOutcome.Lethality.DOWNED)

func test_sub_gate_will_still_maims_despite_the_ability() -> void:
	# Armed but Will below the full gate -> CRISIS never applies; the MAIMED/DOWNED rungs are
	# untouched by the ability.
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 10, Stats.Stat.WIL: 0})
	_arm(target)
	var attack := _fatal_attack(target)
	_resolve([attack])
	assert_that(attack.resolved.lethality).is_equal(ResolvedOutcome.Lethality.MAIMED)

func test_crisis_then_second_hit_previews_kill_no_safety_net() -> void:
	# The thread: hit 1 enters Crisis (up at revive HP, no net). A second hit in the SAME
	# pass, >= that revive HP, must preview KILLED -- dodging the first fatal counter doesn't
	# save you from the second (will-and-death.md: "no safety net for the rest of the battle").
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 10, Stats.Stat.WIL: 20})
	_arm(target)
	var first := _fatal_attack(target)
	var second := _fatal_attack(target)
	_resolve([first, second])
	assert_that(first.resolved.lethality).is_equal(ResolvedOutcome.Lethality.CRISIS)
	assert_that(second.resolved.lethality).is_equal(ResolvedOutcome.Lethality.KILLED)
