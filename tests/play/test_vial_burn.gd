# #697 end to end on a REAL board, through the same queue -> resolve -> execute path the game runs.
# tests/runes/test_vial_empowerment.gd pins the rule in isolation; this pins the WIRING around it:
# a fired cast actually spends the charge, and -- the case the whole design turns on -- a plan that
# is queued and then CANCELLED spends nothing.
#
# WHY CANCELLING IS FREE: nothing is spent until AttackAction.execute(), the readiness precedent
# (#73/#84). The resolver runs on every queue edit and mutates no live state, so re-aiming,
# displacing, undoing and clearing all leave the charge alone. A design that reserved at plan time
# would need a release path on every one of those edges; this one needs none, and these two cases
# are what say so.
extends GdUnitTestSuite

const P := preload("res://tests/support/pattern_fixtures.gd")

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const FIRE := Elemental.Element.FIRE

func _data(unit_name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, fac)

func _vial() -> VialData:
	var v := VialData.new()
	v.element = FIRE
	v.display_name = "Vial of Sulfur"
	return v

func _fireball() -> TransmutationData:
	var t := TransmutationData.new()
	t.display_name = "Fireball"
	t.power = 4
	t.sigils.assign([FIRE])
	t.targets = EquippableData.TargetMode.UNIT
	t.attack_pattern = P.point(2)
	return t

# An alchemist with fire aura, a rune carrying one fireball, and a foe two cells away. No water,
# rock or fire anywhere on the board, so the CHARGE is the only empowerment available.
func _board() -> Dictionary:
	var b := BoardBuilder.build(self, "VialRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 12, 12))
	var hero: Unit = BoardBuilder.spawn(b, _data("Alchemist", PLAYER), Vector2i(0, 0))
	var foe: Unit = BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(2, 0))

	hero.unit_instance.aura = { FIRE: 4 }
	var affinity: Array[Elemental.Element] = [FIRE]
	hero.unit_instance.affinity = affinity

	var rune := RuneData.new()
	rune.size = RuneData.Size.LARGE
	rune.inscriptions.assign([_fireball()])
	hero.add_item(rune)

	for u in [hero, foe]:
		u.unit_instance.stats[Stats.Stat.MHP] = 200
		u.set_current_hp(200)
	return {"sess": PlaySession.new(b), "hero": hero, "foe": foe}


# Carry a vial and pop it, through the same door the inventory panel's Use button calls.
func _attune(hero: Unit) -> VialData:
	var vial := _vial()
	assert_bool(hero.add_item(vial)).is_true()
	assert_str(hero.use_vial(hero.inventory.find(vial))).is_equal("")
	assert_object(hero.attunement).is_same(vial)
	return vial


func test_a_fired_cast_spends_the_charge() -> void:
	var s := _board()
	var sess = s.sess
	var hero: Unit = s.hero
	_attune(hero)

	assert_bool(sess.queue_attack(sess.handle_for(hero), Vector2i(2, 0)).ok).is_true()
	sess.execute()
	assert_object(hero.attunement).override_failure_message(
			"the cast drew on the charge and never spent it").is_null()


# THE case the whole shape exists for. Nothing is reserved at plan time, so a cancelled plan is a
# plan that never touched the charge -- no release path, nothing to get wrong.
func test_queueing_then_cancelling_spends_nothing() -> void:
	var s := _board()
	var sess = s.sess
	var hero: Unit = s.hero
	var vial := _attune(hero)

	assert_bool(sess.queue_attack(sess.handle_for(hero), Vector2i(2, 0)).ok).is_true()

	# RESOLVE FIRST, and that is the whole case rather than a setup line. queue_attack alone stamps
	# no outcome headless, so a cancel test that skipped this would pass for the wrong reason -- it
	# would prove only that nothing resolved, not that resolving spends nothing. The game resolves on
	# EVERY queue edit (refresh_action_queue), so this is what the player's plan-time path actually
	# does, and it is what a spend moved into the resolver would be caught by.
	var plan: ResolvedPlan = sess.squad_manager.resolve_plan(hero.squad, sess._board())
	assert_object((plan.attacks[0] as AttackAction).resolved.burned_vial).override_failure_message(
			"fixture: the resolve recorded no burn, so this case could not see a plan-time spend"
			).is_same(vial)
	assert_object(hero.attunement).override_failure_message(
			"RESOLVING spent the charge -- the resolver must mutate no live state").is_same(vial)

	assert_bool(sess.cancel(sess.handle_for(hero)).ok).is_true()
	assert_object(hero.attunement).override_failure_message(
			"a cancelled plan spent the charge").is_same(vial)


# Law #2: the burn is visible in the resolved plan BEFORE Execute, not discovered afterwards.
func test_the_queue_previews_the_burn_before_it_is_spent() -> void:
	var s := _board()
	var sess = s.sess
	var hero: Unit = s.hero
	var vial := _attune(hero)

	assert_bool(sess.queue_attack(sess.handle_for(hero), Vector2i(2, 0)).ok).is_true()

	# Resolve the way the game's own refresh does — queueing alone stamps no outcome headless. The
	# QUEUE holds the aim; resolve_plan expands it into per-victim actions and stamps those, so the
	# preview the player reads is the plan's, not the queue entry's.
	var plan: ResolvedPlan = sess.squad_manager.resolve_plan(hero.squad, sess._board())
	assert_array(plan.attacks).is_not_empty()

	var cast: AttackAction = plan.attacks[0]
	assert_object(cast.resolved.burned_vial).override_failure_message(
			"the plan does not show the burn, so the player would spend a vial unannounced").is_same(vial)
	assert_object(hero.attunement).is_same(vial)   # previewed, NOT yet spent


# The charge is what moved the number, end to end through the real path -- not just a field the
# resolver happens to set.
func test_the_charge_raises_the_damage_the_foe_actually_takes() -> void:
	var bare := _board()
	assert_bool(bare.sess.queue_attack(bare.sess.handle_for(bare.hero), Vector2i(2, 0)).ok).is_true()
	bare.sess.execute()
	var unempowered: int = 200 - (bare.foe as Unit).get_current_hp()

	var lit := _board()
	_attune(lit.hero)
	assert_bool(lit.sess.queue_attack(lit.sess.handle_for(lit.hero), Vector2i(2, 0)).ok).is_true()
	lit.sess.execute()
	var empowered: int = 200 - (lit.foe as Unit).get_current_hp()

	assert_int(empowered).is_equal(unempowered + 1)
