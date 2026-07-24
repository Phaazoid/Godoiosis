# Kinetic Mace Blowback displacement (#84), proven on a REAL board (BoardBuilder paints a
# walkable grid, so is_walkable/unit_at_cell mean something here — a unit-only PlanResolver
# fixture has no painted tiles). Covers: a charged blowback shoves the target 1 tile directly
# away from the attacker; the shove stops at the board edge and at an occupied cell; firing it
# spends a charge; and preview == execution (the target lands exactly where the resolver said).
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY


func _data(name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), name, fac)


# Arm `unit` with a Kinetic Mace carrying a Blowback extra (knockback 1, null pattern = adjacent
# reach), pre-charged and pre-picked so a single queue_attack fires the shove. Returns the session.
func _mace_board(hero_cell: Vector2i, foe_cell: Vector2i, extra_blocker: Vector2i = Vector2i(999, 999)) -> Dictionary:
	var b := BoardBuilder.build(self, "KnockbackRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 10, 10))   # walkable x,y in [-2, 7]
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), hero_cell)
	var foe: Unit = BoardBuilder.spawn(b, _data("Foe", ENEMY), foe_cell)
	if extra_blocker != Vector2i(999, 999):
		BoardBuilder.spawn(b, _data("Wall", ENEMY), extra_blocker)

	var blowback := WeaponAttackData.new()
	blowback.display_name = "Blowback"
	blowback.knockback = 1
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.KINETIC_MACE
	template.main_attack = WeaponAttackData.new()
	var extras: Array[WeaponAttackData] = [blowback]
	template.extra_attacks = extras
	hero.add_item(WeaponInstance.make(template))
	(hero.get_equipped_weapon() as KineticMaceWeaponInstance).charge = 1
	hero.active_attack = blowback

	var sess = PlaySession.new(b)
	return {"sess": sess, "hero": hero, "foe": foe}


func test_blowback_shoves_target_one_tile_away() -> void:
	var s := _mace_board(Vector2i(0, 0), Vector2i(1, 0))
	var sess = s.sess
	var foe: Unit = s.foe
	var res: Dictionary = sess.queue_attack(sess.handle_for(s.hero), Vector2i(1, 0))
	assert_bool(res.ok).is_true()
	sess.execute()
	# Hero at x=0, foe at x=1 -> shoved to x=2 (directly away), y unchanged.
	assert_int(foe.movement.cell.x).is_equal(2)
	assert_int(foe.movement.cell.y).is_equal(0)


func test_firing_blowback_spends_a_charge() -> void:
	var s := _mace_board(Vector2i(0, 0), Vector2i(1, 0))
	var sess = s.sess
	var mace := s.hero.get_equipped_weapon() as KineticMaceWeaponInstance
	sess.queue_attack(sess.handle_for(s.hero), Vector2i(1, 0))
	sess.execute()
	assert_int(mace.charge).is_equal(0)   # started at 1, the shove spent it


func test_shove_stops_at_the_board_edge() -> void:
	# Foe on the last walkable column (x=7); the push target (x=8) is unpainted -> blocked.
	var s := _mace_board(Vector2i(6, 0), Vector2i(7, 0))
	var sess = s.sess
	var foe: Unit = s.foe
	sess.queue_attack(sess.handle_for(s.hero), Vector2i(7, 0))
	sess.execute()
	assert_int(foe.movement.cell.x).is_equal(7)   # nowhere to go — stays put
	assert_int(foe.movement.cell.y).is_equal(0)


func test_shove_stops_at_an_occupied_cell() -> void:
	# A blocker sits directly behind the foe (x=2); the foe can't be pushed into it.
	var s := _mace_board(Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0))
	var sess = s.sess
	var foe: Unit = s.foe
	sess.queue_attack(sess.handle_for(s.hero), Vector2i(1, 0))
	sess.execute()
	assert_int(foe.movement.cell.x).is_equal(1)   # blocked by the unit behind it
	assert_int(foe.movement.cell.y).is_equal(0)


# Arm `unit` with a melee weapon that can counter (default can_counter, null pattern = adjacent),
# and give it enough HP to survive a hit and swing back.
func _arm_chainsword(unit: Unit) -> void:
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.main_attack = WeaponAttackData.new()
	t.main_attack.power = 4
	unit.add_item(WeaponInstance.make(t))
	unit.unit_instance.stats[Stats.Stat.MHP] = 50
	unit.unit_instance.set_current_hp(50)


# Control: an armed, adjacent foe DOES counter a non-shoving attack — so the setup can produce a
# counter, isolating the shove as the thing that suppresses it in the next test.
func test_armed_enemy_counters_a_non_shoving_attack() -> void:
	var s := _mace_board(Vector2i(0, 0), Vector2i(1, 0))
	var attacker: Unit = s.hero
	var foe: Unit = s.foe
	_arm_chainsword(foe)
	attacker.active_attack = null   # fire the mace's main (Smash) — no knockback
	var attacker_hp := attacker.get_current_hp()
	s.sess.queue_attack(s.sess.handle_for(attacker), Vector2i(1, 0))
	s.sess.execute()
	assert_int(foe.movement.cell.x).is_equal(1)                        # not shoved
	assert_int(attacker.get_current_hp()).is_less(attacker_hp)         # foe countered

# The fix (#84, approach B): a foe shoved out of its reach must NOT counter — the reach check reads
# the LANDING cell (via get_projected_destination), not where it stood. Before the fix it countered
# from its original adjacent cell.
func test_shoved_enemy_out_of_range_does_not_counter() -> void:
	var s := _mace_board(Vector2i(0, 0), Vector2i(1, 0))
	var attacker: Unit = s.hero
	var foe: Unit = s.foe
	_arm_chainsword(foe)   # same armed, adjacent foe as the control — only difference is the shove
	var attacker_hp := attacker.get_current_hp()
	s.sess.queue_attack(s.sess.handle_for(attacker), Vector2i(1, 0))
	s.sess.execute()
	assert_int(foe.movement.cell.x).is_equal(2)                        # shoved to x=2, out of reach
	assert_int(attacker.get_current_hp()).is_equal(attacker_hp)        # no counter landed
