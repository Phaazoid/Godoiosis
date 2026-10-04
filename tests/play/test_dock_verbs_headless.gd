# The inspect dock's six verbs, headlessly (#46 slice 2b): equip, unequip, wear, remove_armor, use and
# toss through PlaySession.gear, which asks GearVerbs -- the rule the dock's buttons ask -- and
# RulesService.command_block_reason, game.can_control's own rule for who may use the dock.
#
# A programmatic board, so this is the battle phase; the pre-mission half (a reserve unit refused,
# a deployed one served) is in test_pre_mission_headless.gd beside its phase fixture. Every piece of
# gear is authored here.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sess
var _hero: Unit
var _foe: Unit


func before_test() -> void:
	var b := BoardBuilder.build(self, "DockVerbsRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 8, 8))
	_hero = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))   # -> A
	_foe = BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(1, 0))      # -> a
	BoardBuilder.arm(_hero, 3)   # auto-equips
	BoardBuilder.arm(_foe, 3)
	_sess = PlaySession.new(b)


func _data(unit_name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, fac)


func _carry(item: Item) -> int:
	_hero.add_item(item)
	return _hero.inventory.find(item)


static func _plate(con_floor := 0) -> ArmorData:
	var plate := ArmorData.new()
	plate.display_name = "Dock Test Plate"
	if con_floor > 0:
		plate.stat_minimums = {Stats.Stat.CON: con_floor}
	return plate


func test_wear_then_remove() -> void:
	var plate := _plate()
	var worn: Dictionary = _sess.gear("A", "wear", _carry(plate))
	assert_bool(worn.ok).override_failure_message(str(worn.get("error", ""))).is_true()
	assert_object(_hero.worn_armor).is_same(plate)
	var off: Dictionary = _sess.gear("A", "remove_armor", -1)
	assert_bool(off.ok).override_failure_message(str(off.get("error", ""))).is_true()
	assert_object(_hero.worn_armor).is_null()


func test_unequip_then_equip() -> void:
	var weapon := _hero.get_equipped_weapon()
	assert_bool((_sess.gear("A", "unequip", -1) as Dictionary).ok).is_true()
	assert_bool(_hero.has_equipped_weapon()).is_false()
	assert_bool((_sess.gear("A", "equip", _hero.inventory.find(weapon)) as Dictionary).ok).is_true()
	assert_object(_hero.get_equipped_weapon()).is_same(weapon)


func test_use_and_toss() -> void:
	var vial := VialData.new()
	vial.display_name = "Dock Test Vial"
	vial.element = Elemental.Element.FIRE
	assert_bool((_sess.gear("A", "use", _carry(vial)) as Dictionary).ok).is_true()
	assert_object(_hero.attunement).is_same(vial)

	var spare := _plate()
	assert_bool((_sess.gear("A", "toss", _carry(spare)) as Dictionary).ok).is_true()
	assert_bool(_hero.inventory.has(spare)).is_false()


func test_a_refusal_arrives_in_the_gates_own_words() -> void:
	var heavy := _plate(999)
	var refused: Dictionary = _sess.gear("A", "wear", _carry(heavy))
	assert_bool(refused.ok).override_failure_message("a plate nobody can wear was worn").is_false()
	assert_str(str(refused.get("error", ""))).is_equal(heavy.can_equip_reason(_hero))
	assert_bool((_sess.gear("A", "polish", 0) as Dictionary).ok).is_false()


func test_a_unit_off_the_active_side_is_refused_by_the_command_rule() -> void:
	var expected := RulesService.command_block_reason(_foe, _sess.turn_manager.active_faction())
	assert_str(expected).override_failure_message("fixture: the enemy is commandable on the player's turn").is_not_empty()
	var refused: Dictionary = _sess.gear("a", "unequip", -1)
	assert_bool(refused.ok).is_false()
	assert_str(str(refused.get("error", ""))).is_equal(expected)
	assert_bool(_foe.has_equipped_weapon()).override_failure_message("the enemy's weapon came off").is_true()


func test_a_gear_change_re_resolves_the_open_plan() -> void:
	# The twin of game.gd's loadout_changed wire: Equip swaps which weapon a queued attack fires with,
	# so the plan the queue shows has to be the one after the change.
	assert_bool((_sess.queue_attack("A", Vector2i(1, 0)) as Dictionary).ok).is_true()
	assert_bool((_sess.preview() as Dictionary).ok).is_true()
	var squad: Squad = _hero.squad
	var before: ResolvedPlan = _sess.squad_manager.resolved_plan_for(squad)
	assert_object(before).override_failure_message("fixture: the preview stored no plan").is_not_null()
	assert_bool((_sess.gear("A", "wear", _carry(_plate())) as Dictionary).ok).is_true()
	var after: ResolvedPlan = _sess.squad_manager.resolved_plan_for(squad)
	assert_object(after).override_failure_message(
		"the gear change left the plan the queue shows from before it").is_not_same(before)
