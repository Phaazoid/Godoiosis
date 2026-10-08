# Carbine magazine end-to-end (#84) on a REAL board, through the same queue -> resolve -> execute
# path the game runs. tests/weapons/test_carbine_magazine.gd pins the instance's state machine in
# isolation; this pins the wiring around it: a real fired shot spends ammo (not just a direct
# consume_readiness_for call), an empty magazine refuses to queue, the Reload command rearms, and
# — the call this issue actually turned on — a COUNTER spends a shot too, so a dry carbine stops
# shooting back.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY


func _data(unit_name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, fac)


# The real Carbine shape: one main attack, requires + consumes a shot, Manhattan min/max 2.
func _carbine() -> WeaponInstance:
	var shot := WeaponAttackData.new()
	shot.display_name = "Shot"
	shot.power = 4
	shot.requires_readiness = true
	shot.consumes_readiness = true
	P.point(shot, 2, 2)
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CARBINE
	t.main_attack = shot
	return WeaponInstance.make(t)


# Hero with a carbine at hero_cell, a tanky foe at foe_cell (default: exactly 2 away, in range).
func _board(hero_cell: Vector2i = Vector2i(0, 0), foe_cell: Vector2i = Vector2i(2, 0)) -> Dictionary:
	var b := BoardBuilder.build(self, "CarbineRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 12, 12))
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), hero_cell)
	var foe: Unit = BoardBuilder.spawn(b, _data("Foe", ENEMY), foe_cell)
	hero.add_item(_carbine())
	for u in [hero, foe]:
		u.unit_instance.stats[Stats.Stat.MHP] = 200
		u.set_current_hp(200)
	return {"sess": PlaySession.new(b), "hero": hero, "foe": foe,
			"weapon": hero.get_equipped_weapon() as CarbineWeaponInstance}


func test_firing_a_real_shot_spends_one_round() -> void:
	var s := _board()
	var sess = s.sess
	var weapon: CarbineWeaponInstance = s.weapon
	assert_bool(sess.queue_attack(sess.handle_for(s.hero), Vector2i(2, 0)).ok).is_true()
	sess.execute()
	assert_int(weapon.shots_remaining).is_equal(CarbineWeaponInstance.MAGAZINE_SIZE - 1)


func test_the_magazine_runs_dry_and_then_refuses_to_queue() -> void:
	var s := _board()
	var sess = s.sess
	var handle: String = sess.handle_for(s.hero)
	for _i in range(CarbineWeaponInstance.MAGAZINE_SIZE):
		sess.end_turn()
		sess.end_turn()   # back around to the player
		assert_bool(sess.queue_attack(handle, Vector2i(2, 0)).ok).is_true()
		sess.execute()
	assert_int((s.weapon as CarbineWeaponInstance).shots_remaining).is_equal(0)

	sess.end_turn()
	sess.end_turn()
	var dry: Dictionary = sess.queue_attack(handle, Vector2i(2, 0))
	assert_bool(dry.ok).is_false()   # Law #3: the queue refuses it, menu or no menu


func test_reload_command_rearms_the_carbine() -> void:
	var s := _board()
	var sess = s.sess
	var handle: String = sess.handle_for(s.hero)
	var weapon: CarbineWeaponInstance = s.weapon
	weapon.shots_remaining = 0

	var res: Dictionary = sess.reload(handle)
	assert_bool(res.ok).is_true()
	sess.execute()
	assert_int(weapon.shots_remaining).is_equal(CarbineWeaponInstance.MAGAZINE_SIZE)

	# Full again: nothing left to reload.
	sess.end_turn()
	sess.end_turn()
	assert_bool(sess.reload(handle).ok).is_false()


func test_a_counter_spends_a_shot() -> void:
	# Dev call 2026-07-25: a shot is a shot. The foe closes to exactly 2 and swings; the carbine
	# counters from standoff range and pays for it.
	var s := _board(Vector2i(0, 0), Vector2i(2, 0))
	var sess = s.sess
	var foe: Unit = s.foe
	var weapon: CarbineWeaponInstance = s.weapon
	# Give the foe a reaching weapon so it can attack from 2 away and draw the counter.
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.main_attack = WeaponAttackData.new()
	t.main_attack.power = 3
	P.point(t.main_attack, 2)
	foe.add_item(WeaponInstance.make(t))

	sess.end_turn()   # hand the turn to ENEMY
	assert_bool(sess.queue_attack(sess.handle_for(foe), Vector2i(0, 0)).ok).is_true()
	sess.execute()
	assert_int(weapon.shots_remaining).is_equal(CarbineWeaponInstance.MAGAZINE_SIZE - 1)


# A counter the pass SKIPS spends nothing (#46). The foe's swing fells the hero first, so the hero's
# counter is marked skipped (R7) and never fires. The headless executor spent firing costs ABOVE its
# skipped check, so a felled carbine paid a round for a shot it never took; AttackAction.execute has
# always returned before any spend, and both hosts now pass the same open_playback.
func test_a_counter_the_pass_skips_spends_no_round() -> void:
	var s := _board(Vector2i(0, 0), Vector2i(2, 0))
	var sess = s.sess
	var hero: Unit = s.hero
	var foe: Unit = s.foe
	var weapon: CarbineWeaponInstance = s.weapon
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.main_attack = WeaponAttackData.new()
	t.main_attack.power = 3
	P.point(t.main_attack, 2)
	foe.add_item(WeaponInstance.make(t))
	hero.set_current_hp(1)   # any blow fells it before it can answer

	sess.end_turn()   # hand the turn to ENEMY
	assert_bool(sess.queue_attack(sess.handle_for(foe), hero.movement.cell).ok).is_true()
	var prev: Dictionary = sess.preview()
	assert_int(prev.plan.counters.size()).override_failure_message(
			"fixture: the carbine drew no counter, so there is nothing for the pass to skip").is_greater(0)
	assert_bool(prev.plan.counters[0].skipped).override_failure_message(
			"fixture: the felled hero's counter was not skipped").is_true()

	sess.execute()
	assert_int(weapon.shots_remaining).override_failure_message(
			"a counter the pass skipped spent a round headlessly -- the game spends nothing for it").is_equal(
			CarbineWeaponInstance.MAGAZINE_SIZE)


# ...and the other side of that gate: a shot at open ground has no victim and STILL spends (#97,
# kept by #46). A cell attack (target null, #47) passes open_playback and lands on nobody, and what
# firing costs is paid hit or whiff.
func test_a_shot_at_open_ground_still_spends_a_round() -> void:
	var s := _board()
	var sess = s.sess
	var hero: Unit = s.hero
	var weapon: CarbineWeaponInstance = s.weapon
	weapon.template.main_attack.targets = EquippableData.TargetMode.BOTH   # may be aimed at the ground
	var ground := Vector2i(0, 2)

	assert_bool(sess.queue_attack(sess.handle_for(hero), ground).ok).override_failure_message(
			"fixture: the shot at open ground was refused").is_true()
	var plan: ResolvedPlan = sess.squad_manager.resolve_plan(hero.squad, sess._board())
	assert_object((plan.attacks[0] as AttackAction).target).override_failure_message(
			"fixture: the shot found a victim, so this is not a cell attack").is_null()

	sess.execute()
	assert_int(weapon.shots_remaining).override_failure_message(
			"a shot at open ground spent nothing headlessly -- a cell attack rearmed itself for free").is_equal(
			CarbineWeaponInstance.MAGAZINE_SIZE - 1)


func test_an_empty_carbine_does_not_counter() -> void:
	var s := _board(Vector2i(0, 0), Vector2i(2, 0))
	var sess = s.sess
	var hero: Unit = s.hero
	var foe: Unit = s.foe
	(s.weapon as CarbineWeaponInstance).shots_remaining = 0

	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.main_attack = WeaponAttackData.new()
	t.main_attack.power = 3
	P.point(t.main_attack, 2)
	foe.add_item(WeaponInstance.make(t))
	var foe_hp := foe.get_current_hp()

	sess.end_turn()
	sess.queue_attack(sess.handle_for(foe), Vector2i(0, 0))
	sess.execute()

	assert_int(hero.get_current_hp()).is_less(200)          # the attack landed
	assert_int(foe.get_current_hp()).is_equal(foe_hp)       # nothing shot back
