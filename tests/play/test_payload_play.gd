# A PAYLOAD through the headless Play API (#1058). play_session._apply_attack is the hand-copied twin
# of AttackAction.execute and the play path never runs execute() at all, so the payload's blow
# landing -- and its spending nothing -- has to be asked of the twin separately.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")
const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY


func _data(unit_name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, fac)


func test_the_play_api_lands_a_payload_and_spends_nothing_for_it() -> void:
	var b := BoardBuilder.build(self, "PayloadRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 8, 8))
	var hero: Unit = BoardBuilder.spawn(b, _data("Thrower", PLAYER), Vector2i(0, 0))
	var foe: Unit = BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(1, 0))
	foe.unit_instance.stats[Stats.Stat.MHP] = 200
	foe.set_current_hp(200)

	# The payload is a Spring that would spend the spear's readiness if it were FIRED.
	var spring := WeaponAttackData.new()
	spring.display_name = "Spring"
	spring.power = 3
	spring.consumes_readiness = true
	P.point(spring, 1)
	var tap := WeaponAttackData.new()
	tap.display_name = "Tap"
	tap.power = 1
	P.point(tap, 1)
	tap.payload = spring
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.SPRINGSPEAR
	template.main_attack = tap
	hero.add_item(WeaponInstance.make(template))
	var spear := hero.get_equipped_weapon() as SpringspearWeaponInstance
	assert_object(spear).override_failure_message("fixture: the hero is not holding the spear").is_not_null()

	var sess = PlaySession.new(b)
	assert_bool(sess.queue_attack(sess.handle_for(hero), Vector2i(1, 0)).ok).is_true()
	var result: Dictionary = sess.execute()
	var events: Array = result.get("events", [])
	var landed := events.filter(func(line: String) -> bool: return line.ends_with("(payload)"))
	assert_int(landed.size()).override_failure_message(
			"the headless twin never landed the payload: %s" % [events]).is_equal(1)
	assert_bool(spear.ready).override_failure_message(
			"the headless twin spent readiness on a payload nobody fired").is_true()
