# The target-pick flow must resolve against PROJECTED cells, not live ones (#126 follow-up).
#
# This suite exists because the #126 build shipped green and did not work. Rescue's candidate query and
# its validator were both fixed to follow a shoved body; the generic "pick a highlighted unit" flow they
# feed was not, and it reads the board twice:
#
#   * game._unit_cells()          -> unit.movement.cell, so enter_target_pick_mode painted the target
#                                    overlay on the cell the body is about to VACATE.
#   * game._click_picking_target() -> get_unit_at_cell(), a raw live scan.
#
# Clicking the landing cell therefore failed the target_pick_cells guard and fell through to
# exit_current_mode() -- silently, which is the reported symptom ("nothing happens"). Clicking the
# vacated cell instead reached queue_rescue and was then refused by the validator, also silently.
#
# The reusable part is WHY the old tests could not see it: every one of them called the validator or the
# candidate query directly. Neither touches _unit_cells. So this suite drives the actual sequence a
# player performs -- populate the menu, press the row, click a tile -- on the real game scene, and
# asserts on the QUEUE at the end of it. Same lesson as #114 and #131: a test that skips the ordering is
# blind to ordering bugs.
#
# Fixture is tests/squad/test_downed_ejection.gd's -- see tests/README.md -> Testing the game scene.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

# The report's geometry (2026-08-08_11-14-26), flattened onto one row: the caster gusts the body two
# tiles down the line, and the rescuer waits beside where it LANDS, not where it lies.
const CASTER_CELL := Vector2i(0, 0)
const BODY_CELL := Vector2i(1, 0)
const LANDING_CELL := Vector2i(3, 0)
const RESCUER_CELL := Vector2i(4, 0)

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
		game.grid.set_cell(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).is_not_null()
	unit.equipped_weapon = H.make_weapon()
	return unit


func _gust() -> TransmutationData:
	var carving := TransmutationData.new()
	carving.sigils.assign([Elemental.Element.AIR])
	carving.deals_no_damage = true
	carving.hits_allies = true
	carving.knockback = 2
	return carving


# Caster and rescuer share a squad (as they did in the report), so one resolve publishes the shove AND
# validates the rescue. Returns the two of them with the body already downed, ejected, and shoved.
func _board_with_a_shoved_body() -> Dictionary:
	var caster := _spawn(Team.Faction.PLAYER, CASTER_CELL)
	var body := _spawn(Team.Faction.PLAYER, BODY_CELL)
	var rescuer := _spawn(Team.Faction.PLAYER, RESCUER_CELL)
	var bystander := _spawn(Team.Faction.ENEMY, Vector2i(7, 0))
	await await_idle_frame()
	game.squad_manager.join_squad(rescuer, caster.squad)

	body.take_damage(body.get_current_hp())
	assert_bool(body.is_downed()).override_failure_message("fixture failed to DOWN the body").is_true()
	await game.order_executor.execute_orders(bystander)   # an empty pass: settles the ejection

	var aim := AttackAction.create(caster, CASTER_CELL, null, BODY_CELL)
	aim.fired_attack = _gust()
	assert_bool(game.squad_manager.queue_action(caster.squad, aim)) \
		.override_failure_message("fixture failed to queue the gust").is_true()
	game.refresh_action_queue(caster.squad)   # the real path: resolve -> publish the shove -> validate

	assert_that(body.get_projected_destination()) \
		.override_failure_message("fixture failed to shove the body").is_equal(LANDING_CELL)
	return {"caster": caster, "body": body, "rescuer": rescuer}


func _queued_rescue(squad: Squad) -> RescueAction:
	for action in squad.action_queue:
		if action is RescueAction:
			return action as RescueAction
	return null


# ==============================================================================

# THE regression, as one sequence: the menu offers Rescue, pressing it enters pick mode, and clicking
# the LANDING cell queues a real order. Asserting on the queue is the point -- every earlier test stopped
# at is_valid, which is why this shipped broken.
func test_clicking_the_landing_cell_queues_the_rescue() -> void:
	var board: Dictionary = await _board_with_a_shoved_body()
	var rescuer: Unit = board["rescuer"]
	var body: Unit = board["body"]

	assert_array(game.main_action_menu.populate(rescuer)) \
		.override_failure_message("the Rescue row never appeared").contains([MainActionMenu.RESCUE])

	game.main_action_menu.on_pressed(MainActionMenu.RESCUE, rescuer)
	assert_array(game.target_pick_cells) \
		.override_failure_message("the pick overlay marks the cell the body is leaving") \
		.contains([LANDING_CELL])

	game._click_picking_target(LANDING_CELL)

	var rescue := _queued_rescue(rescuer.squad)
	assert_object(rescue).override_failure_message("the click queued nothing").is_not_null()
	assert_object(rescue.actor).is_same(rescuer)
	assert_object(rescue.target).is_same(body)
	assert_bool(rescue.is_valid).is_true()


# The other half: the cell the body VACATES is not a legal pick. Without it the first case passes against
# a version that simply highlights both cells.
func test_clicking_the_vacated_cell_queues_nothing() -> void:
	var board: Dictionary = await _board_with_a_shoved_body()
	var rescuer: Unit = board["rescuer"]

	game.main_action_menu.on_pressed(MainActionMenu.RESCUE, rescuer)
	game._click_picking_target(BODY_CELL)

	assert_object(_queued_rescue(rescuer.squad)) \
		.override_failure_message("a rescue was queued against a cell the body has left").is_null()


# The shove's arrow trail draws EVERY cell it crosses, not just its two ends. Blowback pushes one tile,
# so from and to are adjacent and the two-sprite version looked complete; Gust pushes two and left the
# middle blank. Counted on the overlay the real refresh built.
func test_a_two_tile_shove_draws_an_unbroken_arrow_trail() -> void:
	await _board_with_a_shoved_body()

	var drawn := {}
	for sprite in game.overlay_manager.knockback_preview_sprites:
		drawn[game.grid.local_to_map(game.grid.to_local(sprite.global_position))] = true

	for cell in [BODY_CELL, Vector2i(2, 0), LANDING_CELL]:
		assert_bool(drawn.has(cell)) \
			.override_failure_message("no arrow sprite on %s -- the trail has a gap" % cell).is_true()
