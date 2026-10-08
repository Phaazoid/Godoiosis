# The CRISIS lethality preview (#57, Law #2; rebuilt by #158): Crisis is an EQUIPPED ability now,
# so the rung is armed, never decided -- an unwounded unit holding the ability previews CRISIS
# whatever its faction or archetype, and nobody else ever does (the Wounded gate, #1174). The per-archetype stance table this
# suite used to pin is deleted; the player previewing their OWN Crisis is the case that was
# impossible before (the old PLAYER fork existed to keep the live prompt unpredicted).
# Companion to tests/law/test_maim_preview.gd, which pins the limb a Crisis entry also takes.
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
func test_an_armed_player_unit_previews_crisis() -> void:
	var target := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), {Stats.Stat.MHP: 10})
	_arm(target)
	var attack := _fatal_attack(target)
	_resolve([attack])
	assert_that(attack.resolved.lethality).is_equal(ResolvedOutcome.Lethality.CRISIS)
	assert_int(attack.resolved.target_hp_after).is_equal(Abilities.CRISIS_REVIVE_HP)

# HOLD is the archetype whose stance used to DECLINE the gambit -- an armed one crises anyway,
# which is what proves the stance table is really gone rather than merely bypassed.
func test_an_armed_enemy_previews_crisis_whatever_its_archetype() -> void:
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 10})
	target.squad.archetype = AIArchetype.Type.HOLD
	_arm(target)
	var attack := _fatal_attack(target)
	_resolve([attack])
	assert_that(attack.resolved.lethality).is_equal(ResolvedOutcome.Lethality.CRISIS)

# RUSHDOWN used to auto-accept by personality. Unarmed, personality grants nothing -- Crisis
# access is authored content now (the ability on the unit), not code on the archetype.
func test_an_unarmed_unit_previews_downed_whatever_its_archetype() -> void:
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 10})
	target.squad.archetype = AIArchetype.Type.RUSHDOWN
	var attack := _fatal_attack(target)
	_resolve([attack])
	assert_that(attack.resolved.lethality).is_equal(ResolvedOutcome.Lethality.DOWNED)

# The gate since #1174: a unit that has gone down this battle cannot fire the gambit, armed or not.
# Wounded for REAL -- downed through take_damage and stood back up -- never by setting the flag. Armed
# only AFTER that first down, or the first down would have been the gambit instead.
func test_a_wounded_unit_downs_despite_the_ability() -> void:
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 10})
	target.take_damage(target.get_current_hp())
	assert_bool(target.is_downed()).override_failure_message("fixture: the first down failed").is_true()
	target.revive()
	target.set_current_hp(target.get_max_hp())
	_arm(target)
	var attack := _fatal_attack(target)
	_resolve([attack])
	assert_that(attack.resolved.lethality).is_equal(ResolvedOutcome.Lethality.DOWNED)

func test_crisis_then_second_hit_previews_kill_no_safety_net() -> void:
	# The thread: hit 1 enters Crisis (up at revive HP, no net). A second hit in the SAME
	# pass, >= that revive HP, must preview KILLED -- dodging the first fatal counter doesn't
	# save you from the second (will-and-death.md: "no safety net for the rest of the battle").
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 10})
	_arm(target)
	var first := _fatal_attack(target)
	var second := _fatal_attack(target)
	_resolve([first, second])
	assert_that(first.resolved.lethality).is_equal(ResolvedOutcome.Lethality.CRISIS)
	assert_that(second.resolved.lethality).is_equal(ResolvedOutcome.Lethality.KILLED)


# The SECOND writer of target_hp_after (#419's tile hit) reaching the same answer as the first.
# It threaded its own subtraction until #1002, so a burn that fired the gambit previewed the unit
# at zero while execution stood them up at CRISIS_REVIVE_HP -- one map, both writers, no clamp.
func test_a_tile_burn_that_fires_the_gambit_previews_the_revive_hp() -> void:
	var target := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), {Stats.Stat.MHP: 10})
	_arm(target)

	var hit := TileHitAction.make(target, Terrain.TileState.BURNING,
			target.get_current_hp(), LethalityRules.situation_for(target))

	assert_that(hit.resolved.lethality).override_failure_message(
			"the burn did not fire the gambit, so this case is not about the Crisis rung") \
			.is_equal(ResolvedOutcome.Lethality.CRISIS)
	assert_int(hit.resolved.target_hp_after).is_equal(Abilities.CRISIS_REVIVE_HP)
