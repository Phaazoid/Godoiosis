# The hovered unit flashes white (#1251, dev: "a white flash... any hovered unit"), on its body or on
# the ghost standing in for it, at full alpha -- and a tint brighter than the art reaches the 3D view,
# which until #1251 clamped every tint at 1.0 and so showed none of the brightening cues.
#
# Fixture is test_queued_strikes': one shared Battle3D, a cleared board, units spawned per case, the
# hover pointer borrowed through pointer_source (the 3D picker's own seam) and handed back. The flash's
# PEAK is reached by stepping its own tween, never by sleeping, so no case waits on a clock -- and the
# fixture gives the flash a plateau at each end, so a step lands on one whatever frames ran first.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const ART := preload("res://Art/Units/MapSprites/Knight Templar.png")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _board := SharedBoard.new(SCENE_PATH)
var _scene: Node3D
var game: Node2D
var _unit_mirror: UnitMirror
var _pointer: Callable
var _pointed := GridUtils.NO_CELL
var _knobs := {}

# Seconds the fixture holds the flash at each end: wider than the frames a settle lets the tween run.
const PLATEAU := 0.5


func before() -> void:
	await _board.open(self, _clear_the_board)


func _clear_the_board() -> void:
	_board.game.scenario_manager.clear_board()
	_board.game.game_state = _board.game.GameState.IDLE


func before_test() -> void:
	await _board.reset(self)
	_scene = _board.scene
	game = _board.game
	_unit_mirror = _scene.get_node("UnitMirror") as UnitMirror
	_pointer = game.hover_presenter.pointer_source
	_knobs = {"modulate": UnitVisuals.HOVER_FLASH_MODULATE, "ramp": UnitVisuals.HOVER_FLASH_RAMP,
			"hold": UnitVisuals.HOVER_FLASH_HOLD, "rest": UnitVisuals.HOVER_FLASH_REST}
	UnitVisuals.HOVER_FLASH_HOLD = PLATEAU
	UnitVisuals.HOVER_FLASH_REST = PLATEAU


func after_test() -> void:
	game.hover_presenter.pointer_source = _pointer
	UnitVisuals.HOVER_FLASH_MODULATE = _knobs["modulate"]
	UnitVisuals.HOVER_FLASH_RAMP = _knobs["ramp"]
	UnitVisuals.HOVER_FLASH_HOLD = _knobs["hold"]
	UnitVisuals.HOVER_FLASH_REST = _knobs["rest"]
	game.game_state = game.GameState.IDLE
	await _board.check(self)


func after() -> void:
	_board.close()


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


func _om() -> OverlayManager:
	return game.overlay_manager


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).is_not_null()   # fixture setup, not the claim under test
	return unit


func _point_at(cell: Vector2i) -> void:
	_pointed = cell
	game.hover_presenter.pointer_source = func() -> Vector2i: return _pointed
	await _settle()


# A queued move, so a ghost stands in for the unit at `to` (test_overlay_mirror's idiom).
func _ghost_for_move(unit: Unit, to: Vector2i) -> void:
	game.enter_move_mode(unit)
	game.selected_unit = unit
	game._on_left_click(to)
	await _settle()
	assert_object(_om()._ghost_for(unit)).override_failure_message(
			"fixture: the move stood no ghost in").is_not_null()


# Steps a running pulse to the end of its first ramp, where the sprite sits at the peak.
func _to_peak(tween: Tween) -> void:
	tween.custom_step(UnitVisuals.HOVER_FLASH_RAMP + 0.001)


# ...and on from the peak, down, into the rest.
func _to_rest(tween: Tween) -> void:
	tween.custom_step(UnitVisuals.HOVER_FLASH_HOLD + UnitVisuals.HOVER_FLASH_RAMP)


# --- The flash ---------------------------------------------------------------------------------------

func test_hovering_a_unit_flashes_it_white_and_leaving_puts_it_back() -> void:
	var hero := _spawn(PLAYER, Vector2i(2, 2))
	_spawn(PLAYER, Vector2i(6, 6))
	await _point_at(hero.movement.cell)
	var tween: Tween = hero.visuals.hover_tween
	assert_object(tween).override_failure_message("hovering a unit started no flash").is_not_null()
	_to_peak(tween)
	assert_that(hero.visuals.sprite.modulate).is_equal(UnitVisuals.HOVER_FLASH_MODULATE)

	await _point_at(Vector2i(6, 6))
	assert_object(hero.visuals.hover_tween).override_failure_message(
			"the flash outlived the hover").is_null()
	assert_that(hero.visuals.sprite.modulate).is_equal(hero.visuals.base_modulate)


func test_a_ghost_flashes_at_full_alpha_and_goes_back_to_a_ghost() -> void:
	var hero := _spawn(PLAYER, Vector2i(2, 2))
	_spawn(PLAYER, Vector2i(6, 6))
	await _ghost_for_move(hero, Vector2i(3, 2))
	game.exit_current_mode()
	await _point_at(Vector2i(3, 2))
	# Re-read every time: an ordinary hover can rebuild the ghosts, which is the reconcile's reason.
	var ghost := _om()._ghost_for(hero)
	assert_object(_om()._ghost_hover_tween(ghost)).override_failure_message(
			"hovering a unit's ghost started no flash on it").is_not_null()
	assert_float(ghost.modulate.a).override_failure_message(
			"the hovered ghost stayed see-through").is_equal(1.0)
	assert_object(hero.visuals.hover_tween).override_failure_message(
			"the flash went to the hidden body instead of the ghost").is_null()

	await _point_at(Vector2i(6, 6))
	ghost = _om()._ghost_for(hero)
	assert_object(_om()._ghost_hover_tween(ghost)).is_null()
	assert_that(ghost.modulate).is_equal(OverlayManager.PROJECTED_MODULATE)


# Between flashes the unit sits at its NORMAL colour for HOVER_FLASH_REST (#1253, dev: "inverse the
# timing on how long it is glowing vs normal"), body and ghost alike.
func test_the_flash_rests_at_normal_between_flashes() -> void:
	var hero := _spawn(PLAYER, Vector2i(2, 2))
	var mover := _spawn(PLAYER, Vector2i(2, 5))
	_spawn(PLAYER, Vector2i(6, 6))
	await _point_at(hero.movement.cell)
	var tween: Tween = hero.visuals.hover_tween
	_to_peak(tween)
	_to_rest(tween)
	assert_that(hero.visuals.sprite.modulate).override_failure_message(
			"the flash went straight back up instead of resting at normal").is_equal(hero.visuals.base_modulate)
	assert_bool(tween.is_valid()).override_failure_message("the flash stopped instead of resting").is_true()

	await _ghost_for_move(mover, Vector2i(3, 5))
	game.exit_current_mode()
	await _point_at(Vector2i(3, 5))
	var ghost := _om()._ghost_for(mover)
	var ghost_tween := _om()._ghost_hover_tween(ghost)
	assert_object(ghost_tween).override_failure_message("fixture: the ghost is not flashing").is_not_null()
	_to_peak(ghost_tween)
	_to_rest(ghost_tween)
	assert_that(ghost.modulate).override_failure_message(
			"the ghost's flash went straight back up instead of resting").is_equal(OverlayManager.GHOST_FLASH_REST)


# A ghost rebuilt under a still pointer is a NEW node; the flash has to find it.
func test_the_flash_follows_a_ghost_rebuilt_under_the_pointer() -> void:
	var hero := _spawn(PLAYER, Vector2i(2, 2))
	await _ghost_for_move(hero, Vector2i(3, 2))
	game.exit_current_mode()
	await _point_at(Vector2i(3, 2))
	_om().redraw_projected_units()
	await _settle()
	var rebuilt := _om()._ghost_for(hero)
	assert_object(rebuilt).is_not_null()
	assert_object(_om()._ghost_hover_tween(rebuilt)).override_failure_message(
			"the rebuilt ghost lost the hover flash").is_not_null()


# --- The precedence ladder ---------------------------------------------------------------------------

func test_the_aim_pulse_outranks_the_flash_and_the_flash_outranks_a_pin() -> void:
	var foe := _spawn(ENEMY, Vector2i(3, 2))
	game.pinned_enemies[foe.get_instance_id()] = true   # the store the pin sweep reads
	foe.visuals.set_pinned(true)
	await _point_at(foe.movement.cell)
	assert_object(foe.visuals.hover_tween).is_not_null()
	assert_object(foe.visuals.pin_tween).override_failure_message(
			"a hovered pinned enemy ran both flashes on one sprite").is_null()

	foe.visuals.start_pulse()
	assert_object(foe.visuals.hover_tween).override_failure_message(
			"the hover flash did not yield to the aim pulse").is_null()
	foe.visuals.stop_pulse()
	await _settle()
	assert_object(foe.visuals.hover_tween).override_failure_message(
			"the hover flash never came back after the aim let go").is_not_null()

	await _point_at(Vector2i(6, 6))
	assert_object(foe.visuals.pin_tween).override_failure_message(
			"the pin flash never came back after the hover moved off").is_not_null()
	game.pinned_enemies.clear()
	foe.visuals.set_pinned(false)


func test_a_refusal_flash_is_not_stomped_by_the_hover() -> void:
	var hero := _spawn(PLAYER, Vector2i(2, 2))
	await _point_at(hero.movement.cell)
	hero.visuals.play_invalid_flash()
	await _settle()
	assert_object(hero.visuals.hover_tween).override_failure_message(
			"the hover flash restarted over a running refusal flash").is_null()


func test_nothing_flashes_while_the_board_is_not_the_players() -> void:
	var foe := _spawn(ENEMY, Vector2i(3, 2))
	game.game_state = game.GameState.AI_TURN
	await _point_at(foe.movement.cell)
	assert_object(foe.visuals.hover_tween).override_failure_message(
			"a unit flashed under the pointer during an AI turn").is_null()


# --- The 3D view -------------------------------------------------------------------------------------

# The wire: the hovered unit's 3D sprite wears its brightness, through the material, at the peak.
func test_the_peak_reaches_the_3d_sprite_and_rest_drops_the_material() -> void:
	var hero := _spawn(PLAYER, Vector2i(2, 2))
	_spawn(PLAYER, Vector2i(6, 6))
	await _point_at(hero.movement.cell)
	_to_peak(hero.visuals.hover_tween)
	_unit_mirror.reconcile()
	var sprite: UnitSprite3D = _unit_mirror.sprite_for(hero)
	var material := sprite.status_material()
	assert_object(material).override_failure_message(
			"a tint above 1.0 left the 3D sprite on the engine material, which clamps it").is_not_null()
	var over: Vector3 = material.get_shader_parameter("overbright")
	assert_float(over.x).is_greater(1.0)
	assert_that(sprite.tint()).is_equal(hero.modulate * UnitVisuals.HOVER_FLASH_MODULATE)

	await _point_at(Vector2i(6, 6))
	_unit_mirror.reconcile()
	assert_object(sprite.material_override).override_failure_message(
			"a sprite back at rest kept the status material").is_null()


# The split, on a bare sprite: the vertex colour keeps what it can hold, the material the rest.
func test_a_bright_tint_splits_between_the_vertex_colour_and_the_material() -> void:
	var sprite := UnitSprite3D.new()
	sprite.show_still(ART)
	auto_free(sprite)
	sprite.set_tint(Color(2.0, 1.0, 0.5, 0.8))
	assert_that(sprite.modulate).is_equal(Color(1.0, 1.0, 0.5, 0.8))
	assert_that(sprite.tint()).is_equal(Color(2.0, 1.0, 0.5, 0.8))
	assert_object(sprite.material_override).is_not_null()
	sprite.set_tint(Color(0.5, 0.5, 0.5))
	assert_object(sprite.material_override).override_failure_message(
			"a tint the vertex colour can hold still swapped the material in").is_null()


# --- Knobs -------------------------------------------------------------------------------------------

func test_the_flash_knob_reaches_a_running_flash() -> void:
	var hero := _spawn(PLAYER, Vector2i(2, 2))
	await _point_at(hero.movement.cell)
	var brighter := Color(3.0, 3.0, 3.0)
	GameKnobs.write_static(_scene, "HOVER_FLASH_MODULATE", brighter)
	await _settle()
	var tween: Tween = hero.visuals.hover_tween
	assert_object(tween).override_failure_message("the knob left no flash running").is_not_null()
	_to_peak(tween)
	assert_that(hero.visuals.sprite.modulate).override_failure_message(
			"a running flash kept the brightness it started with").is_equal(brighter)
