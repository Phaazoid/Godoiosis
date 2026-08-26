# The end-of-turn burn, pinned for the first time (#174 -- it had zero coverage): a unit standing
# in fire when ITS faction's turn ends takes Terrain.BURNING_TILE_DAMAGE. "Fire" is
# Terrain.FIRE_STATES, so BURNING and BLAZE burn identically and a cell holding both burns ONCE.
# Damage asserts derive from the constant, never a literal (the tuning-value law).
#
# Needs the real game scene: apply_burning_tile_damage reads game.get_unit_at_cell and settles
# through _process_downed_pending. Fixture is tests/ui/test_game_scene_smoke.gd's.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const CELL := Vector2i(1, 0)

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
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()

func _spawn(cell: Vector2i, faction: Team.Faction) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).is_not_null()
	return unit

func _deposit(cell: Vector2i, state: Terrain.TileState) -> void:
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.assign([state])
	game.terrain_states.apply(effect)

func test_burning_damages_the_occupant_when_its_faction_turn_ends() -> void:
	var unit := _spawn(CELL, Team.Faction.PLAYER)
	_deposit(CELL, Terrain.TileState.BURNING)
	var hp_before: int = unit.get_current_hp()

	await game.order_executor.apply_burning_tile_damage(Team.Faction.PLAYER)

	assert_int(unit.get_current_hp()).is_equal(hp_before - Terrain.BURNING_TILE_DAMAGE)

func test_blaze_burns_exactly_like_burning() -> void:
	var unit := _spawn(CELL, Team.Faction.PLAYER)
	_deposit(CELL, Terrain.TileState.BLAZE)
	var hp_before: int = unit.get_current_hp()

	await game.order_executor.apply_burning_tile_damage(Team.Faction.PLAYER)

	assert_int(unit.get_current_hp()).is_equal(hp_before - Terrain.BURNING_TILE_DAMAGE)

func test_a_cell_holding_both_fire_states_burns_once() -> void:
	var unit := _spawn(CELL, Team.Faction.PLAYER)
	_deposit(CELL, Terrain.TileState.BLAZE)
	_deposit(CELL, Terrain.TileState.BURNING)   # a fireball over an authored blaze
	var hp_before: int = unit.get_current_hp()

	await game.order_executor.apply_burning_tile_damage(Team.Faction.PLAYER)

	assert_int(unit.get_current_hp()).is_equal(hp_before - Terrain.BURNING_TILE_DAMAGE)

func test_fire_spares_the_faction_whose_turn_is_not_ending() -> void:
	var unit := _spawn(CELL, Team.Faction.PLAYER)
	_deposit(CELL, Terrain.TileState.BLAZE)
	var hp_before: int = unit.get_current_hp()

	await game.order_executor.apply_burning_tile_damage(Team.Faction.ENEMY)

	assert_int(unit.get_current_hp()).is_equal(hp_before)

func test_burning_finishes_a_downed_unit_standing_on_the_fire() -> void:
	# Fork 3 (#33): a downed body takes any damaging hit as a kill. Burn is a damage source like
	# any other -- it must not be the one thing on the board that lets a downed unit sit in fire
	# forever (#191).
	var unit := _spawn(CELL, Team.Faction.PLAYER)
	unit.force_down()
	_deposit(CELL, Terrain.TileState.BURNING)

	await game.order_executor.apply_burning_tile_damage(Team.Faction.PLAYER)

	assert_bool(unit.is_dead()) \
		.override_failure_message("a downed unit standing in fire survived its faction's turn end") \
		.is_true()


# --- the phase is SHOWN, not settled between frames (#534) --------------------------------------

# The camera visits EACH burning unit, not the phase once. Before this the whole thing resolved in
# one frame: a unit could burn, go down and be ejected from its squad with nothing on screen between
# any of it. Asserted on the 2D camera's follow target -- what pan_to hands over to, and what the 3D
# rig mirrors -- so this is #520's seam at a shorter duration rather than a second one.
#
# Run inside a CLAIMED camera, and that is not incidental: releasing the lock clears follow_unit,
# so on the player's own turn the evidence is gone by the time the phase returns. The claim also
# has to survive, which is the second assertion -- an AI turn owns the camera for its whole length
# and calls end_turn INSIDE it, so a blind release would unlock the board mid-turn.
func test_the_post_turn_pass_takes_the_camera_to_each_burning_unit() -> void:
	var first := _spawn(CELL, Team.Faction.PLAYER)
	var second := _spawn(Vector2i(3, 0), Team.Faction.PLAYER)
	_deposit(CELL, Terrain.TileState.BURNING)
	_deposit(Vector2i(3, 0), Terrain.TileState.BURNING)
	game.camera_controller.set_playback_locked(true)

	await game.order_executor.apply_burning_tile_damage(Team.Faction.PLAYER)

	assert_object(game.camera_controller.follow_unit) \
		.override_failure_message("the phase panned once, or not at all -- the camera did not reach the LAST burning unit") \
		.is_same(second)
	assert_bool(game.camera_controller.playback_locked) \
		.override_failure_message("the phase released a camera an AI turn still owns").is_true()
	assert_int(first.get_current_hp()).is_equal(first.get_max_hp() - Terrain.BURNING_TILE_DAMAGE)
	assert_int(second.get_current_hp()).is_equal(second.get_max_hp() - Terrain.BURNING_TILE_DAMAGE)
	game.camera_controller.set_playback_locked(false)


# ...and the mirror image: on the player's own turn the phase hands the camera back, which is what
# fires the view return (#520 follow-up).
func test_a_post_turn_pass_on_the_players_own_turn_gives_the_camera_back() -> void:
	_spawn(CELL, Team.Faction.PLAYER)
	_deposit(CELL, Terrain.TileState.BURNING)
	assert_bool(game.camera_controller.playback_locked) \
		.override_failure_message("precondition: nothing should own the camera here").is_false()

	await game.order_executor.apply_burning_tile_damage(Team.Faction.PLAYER)

	assert_bool(game.camera_controller.playback_locked) \
		.override_failure_message("the phase kept the camera it borrowed").is_false()


# A phase with NOTHING to show claims nothing at all. Load-bearing rather than an optimisation:
# releasing the camera is what hands the player their view back, so a claim-and-release here would
# fire that return at the end of every single turn, burning or not. The camera is parked on a unit
# first, because a claim would CLEAR that on its way out -- without it the assertion is vacuous.
func test_a_turn_end_with_nothing_burning_never_claims_the_camera() -> void:
	var bystander := _spawn(CELL, Team.Faction.PLAYER)
	game.camera_controller.follow(bystander)

	await game.order_executor.apply_burning_tile_damage(Team.Faction.PLAYER)

	assert_object(game.camera_controller.follow_unit) \
		.override_failure_message("an empty post-turn phase claimed the camera and dropped what it was watching") \
		.is_same(bystander)
