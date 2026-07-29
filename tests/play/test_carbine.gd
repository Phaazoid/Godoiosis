# Carbine magazine end-to-end (#84) on a REAL board, through the same queue -> resolve -> execute
# path the game runs. tests/weapons/test_carbine_magazine.gd pins the instance's state machine in
# isolation; this pins the wiring around it: a real fired shot spends ammo (not just a direct
# consume_readiness_for call), an empty magazine refuses to queue, the Reload command rearms, and
# — the call this issue actually turned on — a COUNTER spends a shot too, so a dry carbine stops
# shooting back.
extends GdUnitTestSuite

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
	var pattern := ManhattanRangePattern.new()
	pattern.max_range = 2
	pattern.min_range = 2
	shot.attack_pattern = pattern
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CARBINE
	t.main_attack = shot
	t.scaling_blend = {Stats.Stat.STR: 100}
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
	var reach := ManhattanRangePattern.new()
	reach.max_range = 2
	t.main_attack.attack_pattern = reach
	foe.add_item(WeaponInstance.make(t))

	sess.end_turn()   # hand the turn to ENEMY
	assert_bool(sess.queue_attack(sess.handle_for(foe), Vector2i(0, 0)).ok).is_true()
	sess.execute()
	assert_int(weapon.shots_remaining).is_equal(CarbineWeaponInstance.MAGAZINE_SIZE - 1)


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
	var reach := ManhattanRangePattern.new()
	reach.max_range = 2
	t.main_attack.attack_pattern = reach
	foe.add_item(WeaponInstance.make(t))
	var foe_hp := foe.get_current_hp()

	sess.end_turn()
	sess.queue_attack(sess.handle_for(foe), Vector2i(0, 0))
	sess.execute()

	assert_int(hero.get_current_hp()).is_less(200)          # the attack landed
	assert_int(foe.get_current_hp()).is_equal(foe_hp)       # nothing shot back
