# #97's tank end to end on a REAL board, through the same queue -> resolve -> execute path the game
# runs. tests/weapons/test_spitter_tank.gd pins the rule in isolation; this pins the WIRING, and it
# exists because of what #697's own play suite found: play_session._apply_attack is a declared
# HAND-COPIED TWIN of AttackAction.execute, so a spend written in one place only leaves the headless
# path handing back a stronger unit than the game does. No unit test can see that.
#
# The two mutants this file is falsified against are therefore DIFFERENT mutants:
#   - delete the twin's spend  -> test_a_fired_charged_shot_empties_one_tank_slot reds HERE;
#   - delete execute()'s spend -> this file stays GREEN, because the play path never calls
#     execute() at all. That half needs a real-scene case, which is why one lives in
#     tests/ui/test_game_scene_smoke.gd rather than here.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const CORROSION := Elemental.Element.CORROSION


func _data(unit_name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, fac)


# A spitter whose Spray authors a stronger charged form. Both forms reach two cells, because what
# this suite is about is the SPEND -- a charged form that could not reach the same foe would be
# testing the geometry instead, and that geometry is #808's to author.
func _spitter_template() -> WeaponData:
	var charged := WeaponAttackData.new()
	charged.display_name = "Pressurised Spray"
	charged.elemental_damage_type = CORROSION
	charged.power = 20
	P.point(charged, 2)

	var spray := WeaponAttackData.new()
	spray.display_name = "Spray"
	spray.elemental_damage_type = CORROSION
	spray.power = 4
	P.point(spray, 2)
	spray.empowered_form = charged

	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHEMICAL_SPITTER
	t.main_attack = spray
	return t


func _board() -> Dictionary:
	var b := BoardBuilder.build(self, "TankRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 12, 12))
	var hero: Unit = BoardBuilder.spawn(b, _data("Mechanist", PLAYER), Vector2i(0, 0))
	var foe: Unit = BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(2, 0))

	hero.equipped_weapon = WeaponInstance.make(_spitter_template())
	var vial := VialData.new()
	vial.element = CORROSION
	vial.display_name = "Vial of Vitriol"
	hero.add_item(vial)

	for u in [hero, foe]:
		u.unit_instance.stats[Stats.Stat.MHP] = 200
		u.set_current_hp(200)
	return {"sess": PlaySession.new(b), "hero": hero, "foe": foe}


func _tank(hero: Unit) -> ChemicalSpitterWeaponInstance:
	return hero.get_equipped_weapon() as ChemicalSpitterWeaponInstance


func test_the_injection_command_fills_the_tank_and_costs_the_vial() -> void:
	# The Play API drives the same generic seam the menu does (Law #3), so the headless command and
	# the player's Tank Injection are one order.
	var s := _board()
	var sess = s.sess
	var hero: Unit = s.hero
	assert_int(_tank(hero).charges).is_equal(0)

	assert_bool(sess.reload(sess.handle_for(hero)).ok).is_true()
	sess.execute()

	assert_int(_tank(hero).charges).is_equal(ChemicalSpitterWeaponInstance.TANK_SIZE)
	assert_bool(hero.inventory.any(func(i): return i is VialData)).override_failure_message(
			"the headless injection filled the tank without consuming the vial").is_false()


func test_the_injection_command_reports_the_familys_own_refusal() -> void:
	# The refusal is READ off the family rather than restated by the command, so the headless error
	# and the greyed menu row cannot word the same rule differently.
	var s := _board()
	var sess = s.sess
	var hero: Unit = s.hero
	# Set directly rather than by injecting first: executing an injection spends the squad's turn,
	# so the command would then refuse for the WRONG reason and this case would pass vacuously.
	_tank(hero).charges = ChemicalSpitterWeaponInstance.TANK_SIZE

	var refused: Dictionary = sess.reload(sess.handle_for(hero))
	assert_bool(refused.ok).is_false()
	assert_str(str(refused.error)).contains("The tank is full.")

	# ...and the OTHER refusal is a different sentence, which is the whole reason the command reads
	# the family's reason instead of restating one of its own.
	_tank(hero).charges = 0
	hero.remove_item(hero.inventory.find_custom(func(i): return i is VialData))
	assert_str(str(sess.reload(sess.handle_for(hero)).error)).contains("No matching vial to inject.")


func test_a_fired_charged_shot_empties_one_tank_slot() -> void:
	# THE case the twin exists to catch. Deleting play_session's tank spend reds exactly here.
	var s := _board()
	var sess = s.sess
	var hero: Unit = s.hero
	_tank(hero).charges = ChemicalSpitterWeaponInstance.TANK_SIZE
	var before := _tank(hero).charges

	assert_bool(sess.queue_attack(sess.handle_for(hero), Vector2i(2, 0)).ok).is_true()
	sess.execute()

	assert_int(_tank(hero).charges).override_failure_message(
			"the shot fired the charged form and never spent a charge -- the headless twin is"
			+ " handing back a stronger spitter than the game does").is_equal(before - 1)


func test_the_charged_form_is_what_actually_fires() -> void:
	# Anti-vacuity for the case above: if the substitution were not reaching the stamped attack, the
	# spend case would be asserting about a shot that was never charged in the first place.
	var s := _board()
	var sess = s.sess
	var hero: Unit = s.hero
	var charged := _tank(hero).template.main_attack.empowered_form

	_tank(hero).charges = ChemicalSpitterWeaponInstance.TANK_SIZE
	assert_bool(sess.queue_attack(sess.handle_for(hero), Vector2i(2, 0)).ok).is_true()
	var plan: ResolvedPlan = sess.squad_manager.resolve_plan(hero.squad, sess._board())
	assert_object((plan.attacks[0] as AttackAction).fired_attack).override_failure_message(
			"a full tank did not reach the declared stamp").is_same(charged)


func test_a_dry_tank_still_fires_the_baseline() -> void:
	# The one law, at the level that matters: an empty tank refuses nothing. It fires the ordinary
	# Spray -- a regular attack, not a diminished one (dev, 2026-09-06).
	var s := _board()
	var sess = s.sess
	var hero: Unit = s.hero
	var foe: Unit = s.foe
	var base := _tank(hero).template.main_attack

	assert_bool(sess.queue_attack(sess.handle_for(hero), Vector2i(2, 0)).ok).is_true()
	var plan: ResolvedPlan = sess.squad_manager.resolve_plan(hero.squad, sess._board())
	assert_object((plan.attacks[0] as AttackAction).fired_attack).is_same(base)

	var before := foe.get_current_hp()
	sess.execute()
	assert_int(foe.get_current_hp()).override_failure_message(
			"a dry spitter dealt no damage -- the tank is gating function, which is the one thing"
			+ " materia may never do").is_less(before)


func test_the_resolve_previews_the_spend_and_does_not_take_it() -> void:
	# Law #2, and the readiness precedent it rides: the resolver runs on every queue edit and
	# mutates no live state, so the chip is visible before Execute and cancelling costs nothing.
	var s := _board()
	var sess = s.sess
	var hero: Unit = s.hero
	_tank(hero).charges = ChemicalSpitterWeaponInstance.TANK_SIZE

	assert_bool(sess.queue_attack(sess.handle_for(hero), Vector2i(2, 0)).ok).is_true()
	var plan: ResolvedPlan = sess.squad_manager.resolve_plan(hero.squad, sess._board())
	assert_bool((plan.attacks[0] as AttackAction).resolved.charge_spent).override_failure_message(
			"the resolve recorded no spend, so the queue row has nothing to show and this case"
			+ " could not see a plan-time one either").is_true()
	assert_int(_tank(hero).charges).override_failure_message(
			"RESOLVING drained the tank -- the resolver must mutate no live state").is_equal(
			ChemicalSpitterWeaponInstance.TANK_SIZE)

	assert_bool(sess.cancel(sess.handle_for(hero)).ok).is_true()
	assert_int(_tank(hero).charges).is_equal(ChemicalSpitterWeaponInstance.TANK_SIZE)


func test_one_charge_is_claimed_once_however_many_shots_a_pass_resolves() -> void:
	# Reactive fire resolves BEFORE anything executes, so a live read would let a counter and a
	# planned shot each see the same last charge and each preview a charged hit. The count is
	# threaded on the hypo, so the pass can spend only what it has.
	var s := _board()
	var sess = s.sess
	var hero: Unit = s.hero
	_tank(hero).charges = 1

	assert_bool(sess.queue_attack(sess.handle_for(hero), Vector2i(2, 0)).ok).is_true()
	var plan: ResolvedPlan = sess.squad_manager.resolve_plan(hero.squad, sess._board())

	var claims := 0
	for a: AttackAction in plan.attacks:
		if a.resolved != null and a.resolved.charge_spent:
			claims += 1
	for a: AttackAction in plan.counters:
		if a.resolved != null and a.resolved.charge_spent:
			claims += 1
	assert_int(claims).override_failure_message(
			"%d shots in one pass each claimed the single charge in the tank" % claims
			).is_less_equal(1)
