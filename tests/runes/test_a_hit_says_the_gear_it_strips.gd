# #1659: a hit that takes a limb can cost an aura, and the rune that aura carried comes off. The
# resolver stamps the pieces a hit strips (ResolvedOutcome.gear_lost) off its copy of the body, the
# queue row and the matchup card draw it through OutcomeFacts, and the unit card marks a carried piece
# its holder cannot put on. Driven on the real game scene: an enemy's queued blow, then its real pass.
#
# Nothing is pinned: the blow is sized off LethalityRules' knob and every reason is the gate's own,
# asked of the same body the stamp was read off.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const FIRE := Elemental.Element.FIRE

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(8):
		for y in range(5):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


# A one-carving Fire rune: channelable iff the wielder has Fire aura (the #157 suite's fixture).
func _rune() -> RuneData:
	var carving := TransmutationData.new()
	carving.power = 5
	carving.recipe = "Push(F)"
	var rune := RuneData.new()
	rune.size = RuneData.Size.SMALL
	rune.display_name = "Test Rune"
	assert_bool(rune.inscribe(carving)).override_failure_message("fixture carving failed to inscribe").is_true()
	return rune


# A caster holding the rune, with headroom so a limb-sized blow leaves it standing.
func _caster(fire_aura: int, cell: Vector2i) -> Unit:
	var u: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.MHP: LethalityRules.LIMB_LOSS_DAMAGE * 6},
			Team.Faction.PLAYER), cell)
	u.unit_instance.aura = { FIRE: fire_aura } as Dictionary[Elemental.Element, int]
	u.unit_instance.affinity = [FIRE] as Array[Elemental.Element]
	u.set_current_hp(u.get_max_hp())
	assert_bool(u.add_item(_rune())).is_true()
	assert_object(u.get_equipped_weapon()).override_failure_message("fixture: the rune did not equip").is_not_null()
	return u


# An enemy's limb-sized blow on `target`, queued; the resolved hit it became.
func _queue_blow(target: Unit) -> AttackAction:
	var foe: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.ENEMY), target.movement.cell + Vector2i(1, 0))
	foe.equipped_weapon = H.make_weapon(LethalityRules.LIMB_LOSS_DAMAGE + 2)
	assert_bool(game.squad_manager.queue_action(foe.squad,
			AttackAction.declare(foe, foe.movement.cell, target.movement.cell))) \
		.override_failure_message("fixture failed to queue the blow").is_true()
	var plan: ResolvedPlan = game.squad_manager.resolved_plan_for(foe.squad)
	for atk in plan.attacks:
		if atk.actor == foe and atk.target == target:
			assert_int(atk.resolved.severed_limb) \
				.override_failure_message("fixture blow (%d) takes no limb" % atk.resolved.damage).is_not_equal(-1)
			assert_int(atk.resolved.lethality) \
				.override_failure_message("fixture blow did not leave the caster standing") \
				.is_equal(ResolvedOutcome.Lethality.NONE)
			return atk
	fail("the blow never resolved")
	return null


# THE case: the preview names the rune and the gate's reason, and the real pass strips exactly that.
func test_the_preview_names_the_rune_a_severing_hit_strips_and_the_pass_strips_it() -> void:
	var caster := _caster(1, Vector2i(1, 1))
	var rune := caster.get_equipped_weapon()
	var blow := _queue_blow(caster)
	if blow == null:
		return
	var r := blow.resolved
	assert_int(r.gear_lost.size()).override_failure_message("the preview stamped no stripped gear").is_equal(1)
	if r.gear_lost.is_empty():
		return
	assert_object(r.gear_lost[0]).is_same(rune)
	assert_str(r.gear_lost_reasons[0]).override_failure_message("the stamp carries no reason").is_not_empty()
	assert_object(caster.get_equipped_weapon()).override_failure_message("the preview stripped the LIVE hand") \
		.is_same(rune)

	await game.order_executor.execute_orders(blow.actor.squad.get_leader())

	assert_object(caster.get_equipped_weapon()).override_failure_message("the pass left the rune in hand") \
		.is_null()
	assert_bool(caster.inventory.has(rune)).is_true()
	assert_str((rune as EquippableData).can_equip_reason(caster.state)) \
		.override_failure_message("the previewed reason is not the live gate's") \
		.is_equal(r.gear_lost_reasons[0])


# A limb that costs aura the rune can spare strips nothing, so says nothing.
func test_a_severing_hit_that_leaves_the_rune_channelable_stamps_nothing() -> void:
	var caster := _caster(2, Vector2i(1, 1))
	var blow := _queue_blow(caster)
	if blow == null:
		return
	assert_int(blow.resolved.gear_lost.size()).is_equal(0)


# The row's chip and the card's pill: one fact, in the outcome's own words.
func test_the_queue_facts_carry_the_stripped_rune() -> void:
	var caster := _caster(1, Vector2i(1, 1))
	var blow := _queue_blow(caster)
	if blow == null or blow.resolved.gear_lost.is_empty():
		fail("fixture: nothing stripped")
		return
	var words: Array[String] = []
	for fact in OutcomeFacts.of(blow.resolved, blow.fired_attack):
		words.append(fact.word)
	assert_array(words).contains([blow.resolved.gear_lost_line(0)])


# The unit card marks a carried piece its holder cannot put on, and only that one.
func test_the_unit_card_marks_a_carried_rune_the_unit_cannot_equip() -> void:
	var caster := _caster(1, Vector2i(1, 1))
	var rune := caster.get_equipped_weapon()
	var sword := H.make_weapon(3)
	assert_bool(caster.add_item(sword)).is_true()
	caster.state.lose_next_limb()   # the real sever: the aura tax, then the wear gate
	assert_object(caster.get_equipped_weapon()).override_failure_message("fixture: the rune stayed in hand") \
		.is_null()
	game.inspect_unit(caster)
	await await_idle_frame()
	var inv = game.unit_info_panel.inventory_panel
	var rune_label: Label = inv.slots_container.get_child(caster.inventory.find(rune)).get_node("SlotHBox/ItemName")
	var sword_label: Label = inv.slots_container.get_child(caster.inventory.find(sword)).get_node("SlotHBox/ItemName")
	assert_str(rune_label.text).override_failure_message("the dead rune is not marked: '%s'" % rune_label.text) \
		.contains(inv.CANNOT_EQUIP_MARK)
	assert_str(sword_label.text).override_failure_message("a usable weapon is marked: '%s'" % sword_label.text) \
		.not_contains(inv.CANNOT_EQUIP_MARK)
