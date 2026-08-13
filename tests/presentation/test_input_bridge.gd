# The stage-4b input bridge (#220): 3D clicks/hover drive the REAL game through
# synthetic input fed to Input.parse_input_event — the OS-driver entry, so the
# events ride the same pipeline as physical input (root GUI -> the PiP container
# forwards into GameView -> game.gd:192) and every gate fires natively. These are
# the repo's first true click-through wire tests: events enter at the top of the
# pipeline and must survive the whole chain; calling the dispatch directly would
# test both ends and not the wire. (Viewport.push_input is a dead door against
# handle_input_locally=false — measured; parse_input_event is what gdUnit's own
# SceneRunner uses for headless GUI, so the engine behavior is load-bearing there.)
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const PROLOG := "res://Scenarios/missions/Prolog.tres"

var _scene: Node3D
var _game: Node2D
var _camera3d: Camera3D
var _overlays: BoardOverlays
var _game_view: SubViewport
var _container: SubViewportContainer


func before_test() -> void:
	get_tree().root.size = Vector2i(1280, 720)   # the project window; headless defaults can be tiny
	var packed := load(SCENE_PATH) as PackedScene
	_scene = packed.instantiate() as Node3D
	_scene.auto_play = false   # no _start: the board loads explicitly below
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	_game = _scene.game
	_camera3d = _scene.get_node("CameraRig/Pitch/Camera") as Camera3D
	_overlays = _scene.get_node("BoardOverlays") as BoardOverlays
	_game_view = _scene.get_node("Main/GameContainer/GameView") as SubViewport
	_container = _scene.get_node("Main/GameContainer") as SubViewportContainer
	_scene.load_mission(PROLOG)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_scene)
	_scene.free()


# --- Helpers ---------------------------------------------------------------------------

func _live_units() -> Array[Unit]:
	var live: Array[Unit] = []
	for child in _game.units_root.get_children():
		var unit := child as Unit
		if unit != null:
			live.append(unit)
	return live


# A player unit whose 3D screen position is clear of the PiP rect (the PiP sits on
# top of the 3D view by design, so a click there belongs to the PiP, not the board).
func _pickable_player_unit() -> Unit:
	var pip: Rect2 = _container.get_global_rect()
	for unit in _live_units():
		if unit.get_faction() != Team.Faction.PLAYER:
			continue
		if not pip.has_point(_screen_of(unit.movement.cell)):
			return unit
	return null


func _screen_of(cell: Vector2i) -> Vector2:
	return _camera3d.unproject_position(BoardSpace.standing_point(Vector3i(cell.x, 0, cell.y)))


func _parse_motion(screen_pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = screen_pos
	motion.global_position = screen_pos
	Input.parse_input_event(motion)


func _parse_click(screen_pos: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	_parse_motion(screen_pos)
	var press := InputEventMouseButton.new()
	press.position = screen_pos
	press.global_position = screen_pos
	press.button_index = button
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	Input.parse_input_event(press)
	var release := InputEventMouseButton.new()
	release.position = screen_pos
	release.global_position = screen_pos
	release.button_index = button
	release.pressed = false
	Input.parse_input_event(release)


# Deliver everything: the test's own events flush first (dispatch runs the bridge,
# which PARSES its synthetics but never flushes mid-dispatch), then a second flush
# delivers the bridge's events; two trailing frames let _process polls observe the
# result (process_frame resumes coroutines BEFORE node _process — one frame is stale).
func _pump() -> void:
	Input.flush_buffered_events()
	await await_idle_frame()
	Input.flush_buffered_events()
	await await_idle_frame()
	await await_idle_frame()


func _selected() -> Unit:
	# Typed read on purpose: a freed stored selection only trips a TYPED assignment (#149).
	var unit: Unit = _game.selected_unit
	return unit


# --- The click wire --------------------------------------------------------------------

func test_a_3d_click_selects_the_unit_it_lands_on() -> void:
	var unit := _pickable_player_unit()
	assert_object(unit).is_not_null()
	_parse_click(_screen_of(unit.movement.cell))
	await _pump()
	assert_bool(_selected() == unit).is_true()


func test_the_bridge_snaps_the_hidden_camera_to_the_clicked_cell() -> void:
	var unit := _pickable_player_unit()
	var cam: CameraController = _game.camera_controller
	var grid: TileMapLayer = _game.grid
	var world: Vector2 = grid.to_global(grid.map_to_local(unit.movement.cell))
	# Derive the clamped truth through the same seam, then park the camera far away.
	cam.snap_to_position(world)
	var expected: Vector2 = cam.global_position
	cam.snap_to_position(Vector2(-100000.0, -100000.0))
	assert_bool(cam.global_position.distance_to(expected) > 1.0).is_true()

	_parse_click(_screen_of(unit.movement.cell))
	await _pump()
	assert_that(cam.global_position).is_equal(expected)
	assert_bool(_selected() == unit).is_true()


# --- The gates -------------------------------------------------------------------------

func test_a_modal_freeze_stops_3d_clicks_cold() -> void:
	# Open the pause menu through the real wire: ESC parsed at the top of the pipeline.
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await _pump()
	assert_bool(ModalLock.any_open(get_tree())).is_true()
	assert_bool(_game.can_process()).is_false()

	var unit := _pickable_player_unit()
	_parse_click(_screen_of(unit.movement.cell))
	await _pump()
	# The sharp clause: a gate that held never let the bridge read the click at all,
	# so its pointer state stays virgin. The end-state asserts below are blind on
	# their own — a pierced click grazes the pause card's button gaps (measured, twice:
	# the gate-removed mutant survived them, and the viewport-mouse comparison is
	# equally blind because the snap maps every click to the exact center a fresh
	# SubViewport already reports as its mouse position).
	assert_that(_scene._pointer_cell).is_equal(BoardSpace.NO_CELL)
	assert_object(_selected()).is_null()
	assert_bool(ModalLock.any_open(get_tree())).is_true()   # nothing pressed Resume
	assert_bool(_game.can_process()).is_false()


func test_the_board_lock_refuses_bridge_clicks_natively() -> void:
	_game.game_state = _game.GameState.AI_TURN
	var unit := _pickable_player_unit()
	_parse_click(_screen_of(unit.movement.cell))
	# RMB is the sharp clause: without game.gd's _board_locked_for_player gate an
	# RMB would run exit_current_mode and flip the state to IDLE mid-AI-turn.
	_parse_click(_screen_of(unit.movement.cell), MOUSE_BUTTON_RIGHT)
	await _pump()
	assert_object(_selected()).is_null()
	assert_int(_game.game_state).is_equal(_game.GameState.AI_TURN)


# --- Hover -----------------------------------------------------------------------------

func test_3d_hover_drives_the_real_hover_presenter() -> void:
	var unit := _pickable_player_unit()
	var cell: Vector2i = unit.movement.cell
	var seen: Array[Vector2i] = []
	_game.hover_presenter.hovered_cell_changed.connect(func(c: Vector2i) -> void: seen.append(c))

	_parse_motion(_screen_of(cell))
	await _pump()

	assert_that(_game.hover_presenter.last_hovered_cell).is_equal(cell)
	assert_bool(seen.has(cell)).is_true()
	assert_that(_overlays.cells_of(BoardOverlays.Layer.HOVER)).is_equal([Vector3i(cell.x, 0, cell.y)])


# --- The PiP ---------------------------------------------------------------------------

func test_the_pip_keeps_native_resolution() -> void:
	assert_bool(_container.visible).is_true()
	assert_that(Vector2(_game_view.size)).is_equal(Vector2(1280.0, 720.0))
	assert_that(_container.scale).is_equal(Vector2(_scene.pip_scale, _scene.pip_scale))
	var view: Vector2 = _scene.get_viewport().get_visible_rect().size
	var expected_pos: Vector2 = view - Vector2(1280.0, 720.0) * _scene.pip_scale - _scene.pip_margin
	assert_that(_container.position).is_equal(expected_pos)


func test_the_pip_serves_a_real_button_click() -> void:
	var end_turn: Control = _game.get_node("UILayer/EndTurnButton")
	end_turn.set_active(true)   # visibility is #189's own tested rule; the claim here is the wire
	await await_idle_frame()
	var presses: Array[bool] = []
	end_turn.end_turn_requested.connect(func() -> void: presses.append(true))

	var button: Button = end_turn.get_node("Button")
	var inside: Vector2 = button.get_global_rect().get_center()
	var root_pos: Vector2 = _container.get_global_transform() * inside
	_parse_click(root_pos)
	await _pump()

	assert_int(presses.size()).is_equal(1)
	assert_object(_selected()).is_null()   # the PiP consumed it — nothing leaked to the 3D picker


func test_a_pip_board_click_stays_in_the_pip() -> void:
	# A board click on the PiP is UNCONSUMED by the game and bubbles back out to the
	# root (measured) — the bridge's PiP-rect guard must never re-read it as 3D
	# pointing, or every PiP board click double-acts as a 3D pick.
	var unit := _pickable_player_unit()
	var grid: TileMapLayer = _game.grid
	_game.camera_controller.snap_to_position(grid.to_global(grid.map_to_local(unit.movement.cell)))
	var view_pos: Vector2 = _scene._cell_view_pos(unit.movement.cell)
	var root_pos: Vector2 = _container.get_global_transform() * view_pos
	_parse_click(root_pos)
	await _pump()
	assert_bool(_selected() == unit).is_true()                       # the 2D game acted on it
	assert_that(_scene._pointer_cell).is_equal(BoardSpace.NO_CELL)   # the bridge never did
	await await_idle_frame()   # the action menu's deferred _place_panel runs against a live panel


# --- Cancel + driver -------------------------------------------------------------------

func test_rmb_cancels_the_current_mode() -> void:
	var unit := _pickable_player_unit()
	_game.selected_unit = unit
	_game.enter_move_mode(unit)
	assert_int(_game.game_state).is_equal(_game.GameState.CHOOSING_MOVE)

	_parse_click(_screen_of(unit.movement.cell), MOUSE_BUTTON_RIGHT)
	await _pump()
	assert_int(_game.game_state).is_equal(_game.GameState.IDLE)
	assert_object(_selected()).is_null()


func test_demo_mode_forces_both_factions_ai_and_playable_does_not() -> void:
	var ai: AIController = _game.ai_controller
	await _scene._start()
	await await_idle_frame()   # each reload clear_boards the standing roster — flush the deferred frees
	assert_bool(ai.is_ai_faction(Team.Faction.PLAYER)).is_false()
	assert_bool(ai.is_ai_faction(Team.Faction.ENEMY)).is_true()

	_scene.demo_mode = true
	await _scene._start()
	await await_idle_frame()
	assert_bool(ai.is_ai_faction(Team.Faction.PLAYER)).is_true()
	assert_bool(ai.is_ai_faction(Team.Faction.ENEMY)).is_true()
