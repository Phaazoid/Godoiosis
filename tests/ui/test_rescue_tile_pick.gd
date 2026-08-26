# Rescuing from deep water is a TWO-STEP order (#116, dev 2026-08-26): *"once rescue is chosen, I
# would like all of the valid tiles to flash, and the user to select the tile to rescue to, and only
# once chosen does the rescue action queue."*
#
# It is tested at the MENU layer for the reason test_target_pick_projection.gd exists at all: the
# rule half of this (RulesService.rescue_landings, the stamp, the publication) is pinned in
# tests/squad/test_rescue_haul.gd and every one of those cases would stay green against a build where
# picking the body still queued immediately. What can only be seen from here is the SEQUENCE — press
# the row, click the body, land in a second pick, click a tile — and specifically that the middle
# step queues nothing.
#
# The trap it guards is `game._click_picking_target` tearing down the mode it just chained: the
# callback opens the tile pick, and an unconditional exit_current_mode() after it kills that pick the
# instant it opens, with both halves correct in isolation (#103's shape). game._pick_generation is
# what sees the chain; this suite is what would notice if it stopped.
#
# Fixture is tests/squad/test_downed_ejection.gd's — see tests/README.md -> Testing the game scene.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const DEEP_WATER := Vector2i(5, 6)   # the authored tile with no `walkable` flag, which is what deep means

const RESCUER_CELL := Vector2i(0, 0)
const BODY_CELL := Vector2i(1, 0)      # painted water, so the body cannot stand where it lies
# Deliberately the LAST landing in NEIGHBOURS declaration order (UP, DOWN, LEFT, RIGHT), so a build
# that still let the rule choose would put the body on (0,-1) and every case below would notice.
const CHOSEN_BANK := Vector2i(-1, 0)
const NOT_A_BANK := Vector2i(2, 0)     # dry, reachable, and not beside the rescuer

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
	for x in range(-2, 4):
		for y in range(-2, 3):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).is_not_null()
	unit.equipped_weapon = H.make_weapon()
	return unit


# A rescuer on dry ground beside a body that is UNDER. The body is spawned on grass and the water is
# painted after — spawn refuses to place a standing unit on a cell nothing may stand on, which is the
# same reason #116 gave it an `is_body` exception for the LOAD path.
func _board_with_a_body_in_the_water() -> Dictionary:
	var rescuer := _spawn(Team.Faction.PLAYER, RESCUER_CELL)
	var body := _spawn(Team.Faction.PLAYER, BODY_CELL)
	var bystander := _spawn(Team.Faction.ENEMY, Vector2i(3, 2))
	await await_idle_frame()

	body.take_damage(body.get_current_hp())
	assert_bool(body.is_downed()).override_failure_message("fixture failed to DOWN the body").is_true()
	await game.order_executor.execute_orders(bystander)   # an empty pass: settles the ejection

	game.grid.paint(BODY_CELL, GRASS_SOURCE, DEEP_WATER)
	assert_bool(game._board().is_walkable(BODY_CELL)) \
		.override_failure_message("fixture assumption broke: the body's cell is still standable") \
		.is_false()
	return {"rescuer": rescuer, "body": body}


# A rescuer beside a body lying on ordinary ground — the case that must NOT gain a second step.
func _board_with_a_body_on_dry_ground() -> Dictionary:
	var rescuer := _spawn(Team.Faction.PLAYER, RESCUER_CELL)
	var body := _spawn(Team.Faction.PLAYER, BODY_CELL)
	var bystander := _spawn(Team.Faction.ENEMY, Vector2i(3, 2))
	await await_idle_frame()

	body.take_damage(body.get_current_hp())
	await game.order_executor.execute_orders(bystander)
	return {"rescuer": rescuer, "body": body}


func _queued_rescue(squad: Squad) -> RescueAction:
	for action in squad.action_queue:
		if action is RescueAction:
			return action as RescueAction
	return null


func _open_the_tile_pick(rescuer: Unit) -> void:
	assert_array(game.main_action_menu.populate(rescuer)) \
		.override_failure_message("the Rescue row never appeared").contains([MainActionMenu.RESCUE])
	game.main_action_menu.on_pressed(MainActionMenu.RESCUE, rescuer)
	game._click_picking_target(BODY_CELL)


# ==============================================================================

# THE sequence, and the half that can only be seen from here: picking the body opens a SECOND pick and
# commits nothing. A build that queued on the body-click passes every rule case in
# tests/squad/test_rescue_haul.gd and fails this one.
func test_picking_the_body_opens_a_tile_pick_and_queues_nothing() -> void:
	var board: Dictionary = await _board_with_a_body_in_the_water()
	var rescuer: Unit = board["rescuer"]

	_open_the_tile_pick(rescuer)

	assert_that(game.game_state) \
		.override_failure_message("the chained pick was torn down as it opened — the generation "
			+ "guard in _click_picking_target is what stops that (#103's shape)") \
		.is_equal(game.GameState.PICKING_TARGET)
	assert_object(_queued_rescue(rescuer.squad)) \
		.override_failure_message("the body-click queued an order — 'only once chosen does the "
			+ "rescue action queue' is the whole ask").is_null()


func test_the_offered_tiles_are_exactly_the_legal_banks() -> void:
	var board: Dictionary = await _board_with_a_body_in_the_water()
	var rescuer: Unit = board["rescuer"]
	var body: Unit = board["body"]

	_open_the_tile_pick(rescuer)

	# Derived from the rule, never listed by hand: the flash and the click guard must offer exactly
	# what a rescue may actually do, or one of them is lying about the other.
	var expected := RulesService.rescue_landings(rescuer, body, game._board())
	assert_array(game.target_pick_cells).contains_exactly_in_any_order(expected)
	assert_bool(game.target_pick_cells.has(BODY_CELL)) \
		.override_failure_message("the water itself is not a place to put the body").is_false()


func test_clicking_a_bank_queues_the_rescue_carrying_THAT_cell() -> void:
	var board: Dictionary = await _board_with_a_body_in_the_water()
	var rescuer: Unit = board["rescuer"]
	var body: Unit = board["body"]

	_open_the_tile_pick(rescuer)
	game._click_picking_target(CHOSEN_BANK)

	var rescue := _queued_rescue(rescuer.squad)
	assert_object(rescue).override_failure_message("the tile click queued nothing").is_not_null()
	assert_object(rescue.target).is_same(body)
	# The player's own cell, not the rule's first answer — which is the entire point of the ticket.
	assert_bool(rescue.haul_to == CHOSEN_BANK) \
		.override_failure_message("the order carries a cell the player did not pick").is_true()


func test_a_click_off_the_banks_cancels_and_queues_nothing() -> void:
	var board: Dictionary = await _board_with_a_body_in_the_water()
	var rescuer: Unit = board["rescuer"]

	_open_the_tile_pick(rescuer)
	game._click_picking_target(NOT_A_BANK)

	# Dev's call: a stray click cancels, the same as every other pick mode in the game.
	assert_object(_queued_rescue(rescuer.squad)).is_null()
	assert_that(game.game_state) \
		.override_failure_message("a click off the highlighted set must leave the pick") \
		.is_not_equal(game.GameState.PICKING_TARGET)


# The twin that keeps the second step from becoming universal: a body on ordinary ground has exactly
# one landing — its own cell — so it queues in ONE step, exactly as it did before this ticket.
func test_a_dry_land_rescue_still_queues_in_one_step() -> void:
	var board: Dictionary = await _board_with_a_body_on_dry_ground()
	var rescuer: Unit = board["rescuer"]
	var body: Unit = board["body"]

	_open_the_tile_pick(rescuer)

	var rescue := _queued_rescue(rescuer.squad)
	assert_object(rescue) \
		.override_failure_message("an ordinary rescue must still commit on the body-click — the "
			+ "second step exists for the haul, not for every rescue").is_not_null()
	assert_bool(rescue.haul_to == BODY_CELL) \
		.override_failure_message("a dry-land rescue must leave the body where it lies").is_true()
	assert_that(game.game_state) \
		.override_failure_message("a one-step rescue must not leave the board in a pick") \
		.is_not_equal(game.GameState.PICKING_TARGET)
	assert_object(body).is_not_null()
