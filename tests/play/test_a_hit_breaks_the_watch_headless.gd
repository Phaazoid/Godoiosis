# The HEADLESS half of #810's cancel, and the reason it needs its own file: play_session._apply_attack
# is a HAND-COPIED TWIN of AttackAction.execute (it says so in its own comments), so a spend or a
# mark added to one and not the other hands the Play API -- which is what the AI drives, Law #3 -- a
# board the game does not have. #697 shipped exactly that bug and only a play-level case caught it.
#
# Also pins the Law #3 gate #810 part 1 left standing: play_session.overwatch checked only that the
# attack CAN watch, so a dry Carbine could arm a watch here that the menu greys out.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY


func _data(unit_name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, fac)


# A melee weapon whose main can stand watch -- one attack, so the watch and the swing are the same
# geometry and the fixture needs no submenu.
func _watch_weapon() -> WeaponInstance:
	var swing := WeaponAttackData.new()
	swing.display_name = "Swing"
	swing.power = 4
	swing.can_overwatch = true
	P.point(swing, 1, 1)
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.main_attack = swing
	return WeaponInstance.make(t)


func _carbine_dry() -> WeaponInstance:
	var shot := WeaponAttackData.new()
	shot.display_name = "Shot"
	shot.power = 4
	shot.requires_readiness = true
	shot.consumes_readiness = true
	shot.can_overwatch = true
	P.point(shot, 1, 1)
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CARBINE
	t.main_attack = shot
	return WeaponInstance.make(t)


func _board() -> Dictionary:
	var b := BoardBuilder.build(self, "WatchBreakRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 12, 12))
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	var foe: Unit = BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(1, 0))
	hero.add_item(_watch_weapon())
	foe.add_item(_watch_weapon())
	for u in [hero, foe]:
		u.unit_instance.stats[Stats.Stat.MHP] = 200
		u.set_current_hp(200)
	return {"sess": PlaySession.new(b), "hero": hero, "foe": foe}


# THE TWIN CASE. The headless executor must mark the live watch exactly as AttackAction.execute does.
func test_the_headless_executor_breaks_the_watch_too() -> void:
	var s := _board()
	var sess = s.sess
	var foe: Unit = s.foe
	foe.arm_watch(foe.movement.cell, Vector2i(1, 1), [Vector2i(1, 1)] as Array[Vector2i],
			(foe.get_equipped_weapon() as WeaponInstance).template.main_attack)
	assert_bool(foe.watch.is_armed()).is_true()

	assert_bool(sess.queue_attack(sess.handle_for(s.hero), Vector2i(1, 0)).ok).is_true()
	sess.execute()

	assert_bool(foe.watch.cancelled).is_true()
	assert_bool(foe.watch.is_armed()).is_false()
	assert_bool(foe.is_standing_watch()).is_true()   # marked, never lapsed -- the reaction stays spent


# Law #3: the Play API must not be able to arm a watch the game refuses.
func test_the_play_api_refuses_a_dry_carbines_watch() -> void:
	var b := BoardBuilder.build(self, "DryWatchRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 12, 12))
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(3, 3))
	hero.add_item(_carbine_dry())
	var sess = PlaySession.new(b)

	var full: Dictionary = sess.overwatch(sess.handle_for(hero), Vector2i(1, 0))
	assert_bool(full.ok).is_true()          # a loaded carbine may watch...

	sess.cancel(sess.handle_for(hero))   # free the main action so the dry attempt is a fresh one
	(hero.get_equipped_weapon() as CarbineWeaponInstance).shots_remaining = 0
	var dry: Dictionary = sess.overwatch(sess.handle_for(hero), Vector2i(1, 0))
	assert_bool(dry.ok).is_false()           # ...a dry one may not
