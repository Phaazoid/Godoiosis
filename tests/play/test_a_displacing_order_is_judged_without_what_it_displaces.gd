# AN ORDER THAT DISPLACES A QUEUED MAIN IS JUDGED ON THE QUEUE IT JOINS (#1529): the queue without the
# order it replaces (Squad.displaces), never the cache, which still holds it. The ring hides every main
# while one is queued (#417) and the AI skips a unit holding one, so the Play API is the door that gets
# here: a re-aim. Both directions -- a carving whose fire is the order it replaces is refused, and an aim
# at a foe only that order shoves away is taken -- through the listing and the queue alike, and the
# cache is left on the real queue afterwards.
#
# The door is SquadManager.judge_candidate. Fixture is tests/squad/test_a_candidate_meets_the_planned_ground.gd's
# headless half.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const P := preload("res://tests/support/shape_fixtures.gd")
const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const WIDTH := 8
const HEIGHT := 5
const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const FIRE := Elemental.Element.FIRE

const CASTER := Vector2i(2, 2)
const FOE := Vector2i(4, 2)
const BESIDE := Vector2i(2, 1)      # within Materia.REACH of CASTER

const SHOVER := Vector2i(2, 2)
const SHOVED := Vector2i(3, 2)      # beside SHOVER; a shove sends it a cell on


func _headless(root_name: String) -> Dictionary:
	var b := BoardBuilder.build(self, root_name)
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(0, 0, WIDTH, HEIGHT))
	return b


func _unit(b: Dictionary, faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = BoardBuilder.spawn(b, H.make_unit_data({Stats.Stat.MHP: 200}, faction), cell)
	unit.set_current_hp(unit.get_max_hp())
	return unit


static func _carving(carving_name: String, recipe: String) -> TransmutationData:
	var t := TransmutationData.new()
	t.display_name = carving_name
	t.power = 4
	t.recipe = recipe
	t.targets = EquippableData.TargetMode.UNIT
	P.point(t, 2)
	return t


static func _queued_attack_of(squad: Squad, actor: Unit) -> AttackAction:
	for action in squad.action_queue:
		if action.actor == actor and action is AttackAction:
			return action as AttackAction
	return null


# The caster's own queued Ember lights the grass beside it; Ignite, which needs that fire, would REPLACE
# Ember, so there is no fire for it: not listed, refused at the queue, and Ember stays queued.
func test_a_carving_whose_fire_is_the_order_it_displaces_is_refused() -> void:
	var b := _headless("DisplacedFire")
	var caster := _unit(b, PLAYER, CASTER)
	caster.unit_instance.aura = {FIRE: 4, Elemental.Element.AIR: 4}
	var affinity: Array[Elemental.Element] = [FIRE, Elemental.Element.AIR]
	caster.unit_instance.affinity = affinity
	var ember := _carving("Ember", "Break(F, A) + Push(F2)")   # makes its own fire: never fizzles
	ember.targets = EquippableData.TargetMode.MAP
	var ignite := _carving("Ignite", "Push(F2)")
	var rune := RuneData.new()
	rune.size = RuneData.Size.LARGE
	assert_bool(rune.inscribe(ember) and rune.inscribe(ignite)).override_failure_message(
			"fixture: the carvings did not inscribe").is_true()
	assert_bool(caster.add_item(rune)).override_failure_message("fixture: the rune did not fit").is_true()
	caster.equipped_weapon = rune
	_unit(b, ENEMY, FOE)
	var sess = PlaySession.new(b)
	var sm: SquadManager = sess.squad_manager
	var handle: String = sess.handle_for(caster)

	var lit: Dictionary = sess.queue_attack(handle, BESIDE, "Ember")
	assert_bool(lit.ok).override_failure_message("fixture: Ember was refused: %s" % str(lit.get("error", ""))).is_true()
	assert_str(CellSubstances.fizzle_reason(ignite, CASTER, sm.candidate_board(caster.squad), caster.state)) \
		.override_failure_message("fixture: Ember's fire must feed Ignite on the queue that holds it").is_equal("")

	var listed: Dictionary = sess.legal_targets(handle, "Ignite")
	assert_bool(listed.ok).override_failure_message(
			"the Play API lists aims for a carving whose only fire is the order it would replace").is_false()
	var cast: Dictionary = sess.queue_attack(handle, FOE, "Ignite")
	assert_bool(cast.ok).override_failure_message(
			"the Play API queues a carving whose only fire is the order it replaces").is_false()
	assert_str(str(cast.get("error", ""))).contains("Fizzles")

	var kept := _queued_attack_of(caster.squad, caster)
	assert_object(kept.fired_attack if kept != null else null).override_failure_message(
			"a refused re-aim took Ember off the queue").is_same(ember)
	assert_str(CellSubstances.fizzle_reason(ignite, CASTER, sm.candidate_board(caster.squad), caster.state)) \
		.override_failure_message("the judge left the cache on the queue without Ember").is_equal("")


# A squad's queued shove publishes the foe a cell on. Aiming at the foe where it stands REPLACES that
# shove, so it is still there to hit: listed, taken at the queue, and the plan shoves it again.
func test_an_aim_at_a_foe_only_the_order_it_displaces_shoves_away_is_taken() -> void:
	var b := _headless("DisplacedShove")
	var shover := _unit(b, PLAYER, SHOVER)
	var hit := WeaponAttackData.new()
	hit.display_name = "Shove"
	hit.power = 1
	hit.knockback = 1
	P.point(hit, 1, 1)
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.main_attack = hit
	assert_bool(shover.add_item(WeaponInstance.make(t))).override_failure_message("fixture: the weapon did not fit").is_true()
	var foe := _unit(b, ENEMY, SHOVED)
	var sess = PlaySession.new(b)
	var handle: String = sess.handle_for(shover)

	var first: Dictionary = sess.queue_attack(handle, SHOVED)
	assert_bool(first.ok).override_failure_message("fixture: the shove was refused: %s" % str(first.get("error", ""))).is_true()
	var shoved_to := foe.get_projected_destination()
	assert_that(shoved_to).override_failure_message("fixture: the queued shove must publish the foe a cell on") \
		.is_not_equal(SHOVED)

	var listed: Dictionary = sess.legal_targets(handle)
	var cells: Array[Vector2i] = []
	for aim: Dictionary in listed.get("aims", []):
		cells.append(aim.cell)
	assert_array(cells).override_failure_message(
			"the Play API reads the foe where the order a re-aim replaces would shove it").contains([SHOVED])
	var again: Dictionary = sess.queue_attack(handle, SHOVED)
	assert_bool(again.ok).override_failure_message(
			"the Play API refuses a re-aim at a foe only the order it replaces shoves away: %s" % str(again.get("error", ""))).is_true()
	assert_that(foe.get_projected_destination()).override_failure_message(
			"the plan no longer shoves the foe the re-aim hits").is_equal(shoved_to)
