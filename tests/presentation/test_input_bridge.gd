# The Battle3D input bridge (#220 then #222): physical events enter at the top of
# the real pipeline (Input.parse_input_event — the OS-driver entry, which is what
# gdUnit's own SceneRunner uses for headless GUI) and must survive the whole chain.
# These are the repo's true click-through wire tests: calling the dispatch directly
# would test both ends and not the wire.
#
# Under 4c hosting the chain forks by WHAT was clicked. UI: root -> the full-screen
# container -> GameView -> the Control, consumed natively. Board: nothing consumes
# it, so it bubbles back OUT to the root (measured) and this node picks the cell and
# calls game._on_left_click / _on_right_click. game.board_input_delegated silences
# the 2D side's own cell derivation — without it the same physical click acts twice,
# which test_the_delegation_gate_stops_the_2d_board_acting_twice pins.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const PROLOG := "res://Scenarios/missions/Prolog.tres"
const LEVEL_1 := "res://Scenarios/missions/Level_1.tres"

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


# A player unit the 3D pointer can actually reach: under 4c the 2D game covers the
# window, so what a board click must dodge is a VISIBLE UI Control (the inspect
# column, the queue panel), not the retired PiP rect.
func _pickable_player_unit() -> Unit:
	for unit in _live_units():
		if unit.get_faction() != Team.Faction.PLAYER:
			continue
		if not _under_ui(_screen_of(unit.movement.cell)):
			return unit
	return null


func _under_ui(screen_pos: Vector2) -> bool:
	for node in _game.ui_layer.get_children():
		var control := node as Control
		if control == null or not control.is_visible_in_tree():
			continue
		if control.mouse_filter != Control.MOUSE_FILTER_IGNORE \
				and control.get_global_rect().has_point(screen_pos):
			return true
	return false


func _screen_of(cell: Vector2i) -> Vector2:
	return _camera3d.unproject_position(BoardSpace.standing_point(BoardSpace.of_cell(cell, 0)))


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


# Deliver everything. The flush drain re-checks its queue, so the bridge's synthetics
# (parsed mid-dispatch) are delivered by the SAME flush as the test's own events; the
# second flush is belt-and-braces for anything a frame boundary buffered. Two trailing
# frames let _process polls observe the result (process_frame resumes coroutines
# BEFORE node _process — one frame is stale).
func _pump() -> void:
	Input.flush_buffered_events()
	await await_idle_frame()
	Input.flush_buffered_events()
	await await_idle_frame()
	await await_idle_frame()


# HALF a click. _parse_click always sends both edges, which is precisely why it cannot see a
# missing release arm — the drag it strands is closed by its own next press.
func _parse_button(screen_pos: Vector2, button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = screen_pos
	event.global_position = screen_pos
	event.button_index = button
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	Input.parse_input_event(event)


func _arm_brush() -> void:
	_game.set_dev_mode(true)
	_game.dev_overlay.tile_brush.brush_active = true


# The brush is HOLD-to-drag, so the 3D arm has to forward the button's RELEASE as well as its
# press. Forwarding presses only leaves _brush_painting TRUE with no event left that can clear
# it, and the brush then paints every cell the cursor crosses for the rest of the session, with
# nothing held down. Invisible to any case that only fires whole clicks — hence the halves.
func test_releasing_the_button_ends_the_brush_drag() -> void:
	var unit := _pickable_player_unit()
	assert_object(unit).override_failure_message("no reachable player unit to aim at").is_not_null()
	_arm_brush()
	await _pump()

	_parse_button(_screen_of(unit.movement.cell), MOUSE_BUTTON_LEFT, true)
	await _pump()
	assert_bool(_game.dev_controller._brush_painting).override_failure_message(
			"precondition: the press never armed the drag, so the release proves nothing"
	).is_true()

	_parse_button(_screen_of(unit.movement.cell), MOUSE_BUTTON_LEFT, false)
	await _pump()
	assert_bool(_game.dev_controller._brush_painting).override_failure_message(
			"the drag outlived its button — the brush paints wherever the cursor goes now"
	).is_false()


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


func test_pointing_snaps_the_hidden_camera_to_the_hovered_cell() -> void:
	# The hidden 2D camera has one live consumer left: the hover card parks itself by
	# mapping a world position through the 2D canvas transform, so the camera must be
	# showing whatever the 3D pointer is on. (4b snapped on CLICK because the click's
	# cell was derived from the viewport mouse; delivery is direct now, so the snap
	# moved to the pointer write and serves only the card.)
	var unit := _pickable_player_unit()
	var cam: CameraController = _game.camera_controller
	var world: Vector2 = GridUtils.cell_world(_game.grid, unit.movement.cell)
	# Derive the clamped truth through the same seam, then park the camera far away.
	cam.snap_to_position(world)
	var expected: Vector2 = cam.global_position
	cam.snap_to_position(Vector2(-100000.0, -100000.0))
	assert_bool(cam.global_position.distance_to(expected) > 1.0).is_true()

	_parse_motion(_screen_of(unit.movement.cell))
	await _pump()
	assert_that(cam.global_position).is_equal(expected)


# --- The gates -------------------------------------------------------------------------

func test_a_modal_freeze_stops_3d_clicks_cold() -> void:
	# Picked BEFORE the card opens: a modal is a full-rect Control on the UI layer, so
	# _pickable_player_unit correctly finds nothing clickable once one is up.
	var unit := _pickable_player_unit()
	assert_object(unit).is_not_null()
	# Open the pause menu through the real wire: ESC parsed at the top of the pipeline.
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await _pump()
	assert_bool(ModalLock.any_open(get_tree())).is_true()
	assert_bool(_game.can_process()).is_false()

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
	var cam: CameraController = _game.camera_controller
	var cam_before: Vector2 = cam.global_position
	_parse_click(_screen_of(unit.movement.cell))
	# RMB is the sharp clause: without game.gd's _board_locked_for_player gate an
	# RMB would run exit_current_mode and flip the state to IDLE mid-AI-turn.
	_parse_click(_screen_of(unit.movement.cell), MOUSE_BUTTON_RIGHT)
	await _pump()
	assert_object(_selected()).is_null()
	assert_int(_game.game_state).is_equal(_game.GameState.AI_TURN)
	# A refused click must not yank the camera either — the bridge reads the same
	# lock before snapping, or a stray click drags the PiP off the AI's pan.
	assert_that(cam.global_position).is_equal(cam_before)


# --- Hover -----------------------------------------------------------------------------

func test_3d_hover_drives_the_real_hover_presenter() -> void:
	var unit := _pickable_player_unit()
	var cell: Vector2i = unit.movement.cell
	# Park the pointer on a different cell first: the global Input mouse position
	# leaks across cases, and a fresh fixture synthesizes an enter-motion at it —
	# if that pre-hovers the target cell, the presenter's dedup would swallow the
	# signal this case exists to observe.
	var grid: TileMapLayer = _game.grid
	_parse_motion(_screen_of(grid.get_used_rect().position))
	await _pump()
	var seen: Array[Vector2i] = []
	_game.hover_presenter.hovered_cell_changed.connect(func(c: Vector2i) -> void: seen.append(c))

	_parse_motion(_screen_of(cell))
	await _pump()

	assert_that(_game.hover_presenter.last_hovered_cell).is_equal(cell)
	assert_bool(seen.has(cell)).is_true()
	assert_that(_overlays.cells_of(BoardOverlays.Layer.HOVER)).is_equal([Vector3i(cell.x, 0, cell.y)])


func test_hover_reaches_cells_the_hidden_camera_cannot_see() -> void:
	# The 4b gap made native (#222): the old mechanism pushed a synthetic motion at
	# the cell's mapped viewport position, so any cell outside the hidden camera's
	# window was silently dropped. The injected pointer source has no window.
	var grid: TileMapLayer = _game.grid
	var far: Vector2i = grid.get_used_rect().position   # the corner the pinned camera never shows
	var near := _pickable_player_unit()
	_parse_motion(_screen_of(near.movement.cell))   # park elsewhere first (cross-case Input leak)
	await _pump()
	var seen: Array[Vector2i] = []
	_game.hover_presenter.hovered_cell_changed.connect(func(c: Vector2i) -> void: seen.append(c))

	_parse_motion(_screen_of(far))
	await _pump()

	assert_that(_game.hover_presenter.last_hovered_cell).is_equal(far)
	assert_bool(seen.has(far)).is_true()
	assert_that(_overlays.cells_of(BoardOverlays.Layer.HOVER)).is_equal([BoardSpace.of_cell(far, 0)])


# --- Camera ownership (#176 stage 4d) ---------------------------------------------------

func test_delegated_board_input_also_stands_the_2d_camera_down() -> void:
	# WASD is bound to cam_* AND polled directly by the 3D rig, so before 4d one keypress
	# panned both cameras. Asserted on keyboard_direction — the poll's own output — which
	# a clamped or lerping camera position cannot mask.
	var cam: CameraController = _game.camera_controller
	assert_bool(_game.board_input_delegated).is_true()   # HD_2D, the fixture's default
	Input.action_press("cam_right")
	await _pump()
	assert_that(cam.keyboard_direction).override_failure_message(
			"the 2D camera still reads WASD while the 3D host owns it").is_equal(Vector2.ZERO)

	# FLAT_2D hands it back, or the flat game would have no camera at all.
	_scene.view = _scene.View.FLAT_2D
	_scene._apply_hosting()
	await _pump()
	assert_that(cam.keyboard_direction).override_failure_message(
			"the flat game never got its camera keys back").is_not_equal(Vector2.ZERO)
	Input.action_release("cam_right")
	_scene.view = _scene.View.HD_2D
	_scene._apply_hosting()


func test_delegating_input_does_not_break_the_ai_camera_follow() -> void:
	# The survivor set. Only the KEYBOARD branch may be gated: follow() tracks its unit
	# from the same _process, and the 3D camera mirror rides on the result — gating the
	# whole loop would kill the feature this stage exists to build.
	var unit := _pickable_player_unit()
	assert_object(unit).is_not_null()
	assert_bool(_game.board_input_delegated).is_true()
	var cam: CameraController = _game.camera_controller
	cam.follow(unit)
	unit.global_position = Vector2(600.0, 400.0)
	await _pump()
	assert_that(cam.target_position).override_failure_message(
			"follow() died with the keyboard poll").is_equal(unit.global_position)


# --- board_loaded (#222) ---------------------------------------------------------------

func test_a_board_swap_rebuilds_the_mirror_through_the_load_funnel() -> void:
	# Load Game / Mission Select from ANOTHER mission is the real failure this seam
	# closes: turn_started never fires on menu arrivals (#144), so before #222 the
	# mirror, picker and pointer state stayed aimed at the dead board.
	_scene._pointer_cell = Vector3i(0, 0, 0)   # stale pointer state aimed at Prolog
	_overlays.set_cells(BoardOverlays.Layer.MOVE, [Vector3i(0, 0, 0)])
	_game.mission_controller.begin_mission(LEVEL_1)
	await await_idle_frame()   # the swap's clear_board queue_frees the old roster
	await await_idle_frame()
	var board: GridMap = _scene.get_node("Board")
	# COLUMNS, not cells. This case asks whether the mirror is aimed at the NEW board; how tall
	# each column is belongs to test_board_mirror. It compared raw cells against every cell at
	# level 0 until 2026-08-15, which silently depended on Level_1 being FLAT -- painting
	# elevation into it (b057f6e) turned #273's correct multi-cell columns into a red case.
	var mirrored: Array[Vector2i] = []
	for cell: Vector3i in board.get_used_cells():
		var column := BoardSpace.flat(cell)
		if not mirrored.has(column):
			mirrored.append(column)
	mirrored.sort()
	var expected: Array[Vector2i] = []
	expected.assign(_game.grid.get_used_cells())
	expected.sort()
	assert_that(mirrored).is_equal(expected)   # the 3D board IS the new 2D board
	assert_that(_scene._tops).is_equal(BoardPicker.column_tops_from(board))
	assert_that(_scene._pointer_cell).is_equal(BoardSpace.NO_CELL)
	assert_int(_overlays.marker_count(BoardOverlays.Layer.MOVE)).is_equal(0)


func test_spawn_sandbox_emits_the_same_rebuild() -> void:
	# The one board build outside apply_scenario — reachable from the 3D view via the
	# hidden Mission Select's Sandbox row, so it must speak the same signal.
	_scene._pointer_cell = Vector3i(0, 0, 0)
	_overlays.set_cells(BoardOverlays.Layer.MOVE, [Vector3i(0, 0, 0)])
	_game.spawn_sandbox()
	await await_idle_frame()
	await await_idle_frame()
	assert_that(_scene._pointer_cell).is_equal(BoardSpace.NO_CELL)
	assert_int(_overlays.marker_count(BoardOverlays.Layer.MOVE)).is_equal(0)
	assert_that(_scene._tops).is_equal(BoardPicker.column_tops_from(_scene.get_node("Board")))


# --- Hosting the 2D game as the UI layer (#222) ----------------------------------------

func test_the_2d_game_hosts_full_screen_and_transparent() -> void:
	# The whole mechanism in one place: the container covers the window at NATIVE
	# scale (so Controls keep their real size and take physical clicks at real
	# coordinates), the viewport clears transparent so the 3D world shows through,
	# the board visuals are down, and the 2D side has stood down from board input.
	assert_bool(_container.visible).is_true()
	assert_that(_container.scale).is_equal(Vector2.ONE)
	assert_that(_container.anchor_right).is_equal(1.0)
	assert_that(_container.anchor_bottom).is_equal(1.0)
	assert_that(_container.get_global_rect().size).is_equal(_scene.get_viewport().get_visible_rect().size)
	assert_bool(_game_view.transparent_bg).is_true()
	assert_bool(_game.board_input_delegated).is_true()
	assert_bool((_game.grid as TileMapLayer).is_visible_in_tree()).is_false()


func test_the_board_hide_spares_the_ui_and_the_authoring_layer() -> void:
	# The probe this mechanism stands on. MEASURED (#222): `game.visible = false` is
	# NOT the switch — OverlayManager is a plain Node, which breaks CanvasItem
	# visibility propagation to the overlay layers (they stayed drawn), while the
	# CanvasLayer UI went dark WITH it. Hence the per-node helper.
	var unit := _pickable_player_unit()
	var end_turn: Control = _game.get_node("UILayer/EndTurnButton")
	end_turn.set_active(true)   # its own visibility is #189's rule, not this claim's
	await await_idle_frame()

	assert_bool(unit.visuals.sprite.is_visible_in_tree()).is_false()
	assert_bool((_game.overlay_manager.move_overlay as TileMapLayer).is_visible_in_tree()).is_false()
	assert_bool(end_turn.is_visible_in_tree()).is_true()

	_scene._set_board_visible(true)
	assert_bool((_game.grid as TileMapLayer).is_visible_in_tree()).is_true()
	# The restore must not reveal the authoring-only zone layer (set_zone_visibility owns it).
	assert_bool((_game.overlay_manager.zone_overlay as TileMapLayer).visible).is_false()


func test_a_ui_click_over_the_3d_board_stays_in_the_ui() -> void:
	# The payoff: a Control is clicked at its REAL screen rect (identity transform —
	# no container math), the 2D consumes it, and nothing leaks to the 3D picker.
	var end_turn: Control = _game.get_node("UILayer/EndTurnButton")
	end_turn.set_active(true)
	await await_idle_frame()
	var presses: Array[bool] = []
	end_turn.end_turn_requested.connect(func() -> void: presses.append(true))

	var button: Button = end_turn.get_node("Button")
	_parse_click(button.get_global_rect().get_center())
	await _pump()

	assert_int(presses.size()).is_equal(1)
	assert_object(_selected()).is_null()   # the UI consumed it; the picker never acted


func test_the_delegation_gate_stops_the_2d_board_acting_twice() -> void:
	# THE gate regression. A board click is unconsumed by the 2D game, so it bubbles
	# back out to the root and this node picks the cell — but game.gd's own
	# _unhandled_input saw the SAME physical event first, and its cell derivation
	# reads the viewport mouse against the hidden 2D camera, which is aimed somewhere
	# else entirely. Without board_input_delegated the click acts twice, and the 2D's
	# wrong cell wins because it runs FIRST and consumes the mode.
	#
	# Asserted on the QUEUE, never on the end-state selection: a second dispatch would
	# simply overwrite the selection and the case would read green through the bug.
	var unit := _pickable_player_unit()
	var destination := unit.movement.cell + Vector2i(1, 0)
	assert_bool(_game.grid.get_cell_tile_data(destination) != null).is_true()   # fixture sanity
	_game.selected_unit = unit
	_game.enter_move_mode(unit)

	_parse_click(_screen_of(destination))
	await _pump()

	var move: MoveAction = _game.overlay_manager.planned_move_by_unit.get(unit)
	assert_object(move).override_failure_message("the 3D click queued no move at all").is_not_null()
	assert_that(move.destination) \
		.override_failure_message("the move went to the 2D camera's cell, not the clicked one") \
		.is_equal(destination)


func test_the_corner_debug_view_restores_the_2d_board() -> void:
	# Shift+F4's view, kept for debugging: the 4b geometry with the 2D board drawn
	# again. Board input stays container-independent (direct cell calls), so the 3D
	# keeps driving and play survives it.
	_scene.view = _scene.View.CORNER
	_scene._apply_hosting()
	assert_that(_container.scale).is_equal(Vector2(_scene.pip_scale, _scene.pip_scale))
	assert_that(Vector2(_game_view.size)).is_equal(Vector2(1280.0, 720.0))
	assert_bool(_game_view.transparent_bg).is_false()
	assert_bool((_game.grid as TileMapLayer).is_visible_in_tree()).is_true()
	assert_bool(_game.board_input_delegated).is_true()
	var size: Vector2 = _scene.get_viewport().get_visible_rect().size
	assert_that(_container.position).is_equal(size - _scene._pip_native * _scene.pip_scale - _scene.pip_margin)

	_scene.view = _scene.View.HD_2D
	_scene._apply_hosting()
	assert_that(_container.scale).is_equal(Vector2.ONE)
	assert_bool((_game.grid as TileMapLayer).is_visible_in_tree()).is_false()


func test_flat_2d_shows_the_whole_board_and_hands_input_back() -> void:
	# F4's escape hatch, and the point of it: FLAT_2D is not a picture of the 2D game,
	# it IS the 2D game. Showing the board while the 3D still owned clicks, hover and
	# WASD would be a fallback you cannot actually play.
	_scene.view = _scene.View.FLAT_2D
	_scene._apply_hosting()
	await await_idle_frame()
	await await_idle_frame()

	# Full-screen and opaque — the 3D world is covered, not torn down.
	assert_that(_container.scale).is_equal(Vector2.ONE)
	assert_that(_container.get_global_rect().size).is_equal(_scene.get_viewport().get_visible_rect().size)
	assert_bool(_game_view.transparent_bg).is_false()
	assert_bool((_game.grid as TileMapLayer).is_visible_in_tree()).is_true()
	# ...and every input owner handed back.
	assert_bool(_game.board_input_delegated) \
		.override_failure_message("the flat game still cannot derive its own board clicks").is_false()
	assert_bool((_game.hover_presenter.pointer_source as Callable).is_valid()) \
		.override_failure_message("hover still reads the 3D pick, not the real mouse").is_false()
	assert_bool((_scene.get_node("CameraRig") as Node3D).is_processing()) \
		.override_failure_message("the hidden 3D rig still pans on WASD alongside the 2D camera").is_false()

	# And back: HD_2D restores 3D ownership, so the toggle is round-trippable.
	_scene.view = _scene.View.HD_2D
	_scene._apply_hosting()
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(_game.board_input_delegated).is_true()
	assert_bool((_game.hover_presenter.pointer_source as Callable).is_valid()).is_true()
	assert_bool((_scene.get_node("CameraRig") as Node3D).is_processing()).is_true()


func test_flat_2d_stops_the_3d_picker_acting_on_the_same_click() -> void:
	# The mirror image of the delegation gate: with the 2D game deriving its own
	# clicks again, this node must NOT also pick, or every click acts twice.
	var unit := _pickable_player_unit()
	_scene.view = _scene.View.FLAT_2D
	_scene._apply_hosting()
	await await_idle_frame()

	_parse_click(_screen_of(unit.movement.cell))
	await _pump()
	assert_that(_scene._pointer_cell) \
		.override_failure_message("the 3D picker read a click the flat game owns").is_equal(BoardSpace.NO_CELL)


# --- Cancel + driver -------------------------------------------------------------------

func test_rmb_cancels_the_current_mode() -> void:
	var unit := _pickable_player_unit()
	_game.selected_unit = unit
	_game.enter_move_mode(unit)
	assert_int(_game.game_state).is_equal(_game.GameState.CHOOSING_MOVE)

	# Cancel while POINTING AT A FAR CELL is the sharp form: the far cell's mapped 2D
	# position falls outside the container rect (the hidden camera isn't showing it),
	# so a cancel that reuses the pointer's mapped position is silently dropped and
	# the player is stuck in the mode — RMB must push at a position that always
	# forwards, because game.gd's _on_right_click is position-blind anyway.
	var grid: TileMapLayer = _game.grid
	_parse_click(_screen_of(grid.get_used_rect().position), MOUSE_BUTTON_RIGHT)
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


func test_demo_mode_boots_watch_only() -> void:
	# demo_mode must be set BEFORE the scene enters the tree — _ready is where the
	# fork lives, which the shared fixture (playable) can never exercise.
	var packed := load(SCENE_PATH) as PackedScene
	var demo := packed.instantiate() as Node3D
	demo.auto_play = false
	demo.demo_mode = true
	get_tree().root.add_child(demo)
	await await_idle_frame()
	var container: SubViewportContainer = demo.get_node("Main/GameContainer")
	assert_bool(container.visible).is_false()
	get_tree().root.remove_child(demo)
	demo.free()


func test_demo_mode_keeps_the_rig_alive_behind_a_frozen_game() -> void:
	# 4a parity: the end-of-mission banner freezes the hidden game forever in demo
	# mode (it is invisible and unclickable there), and the diorama's camera must
	# survive it. The freeze is simulated at its real seam — ModalLock's whole
	# mechanism IS game.process_mode = DISABLED.
	var packed := load(SCENE_PATH) as PackedScene
	var demo := packed.instantiate() as Node3D
	demo.auto_play = false
	demo.demo_mode = true
	get_tree().root.add_child(demo)
	await await_idle_frame()
	var demo_game: Node2D = demo.game
	demo_game.process_mode = Node.PROCESS_MODE_DISABLED
	await await_idle_frame()
	await await_idle_frame()
	var rig: Node3D = demo.get_node("CameraRig")
	assert_bool(rig.is_processing()).is_true()
	get_tree().root.remove_child(demo)
	demo.free()


func test_the_playable_rig_freezes_with_the_game() -> void:
	# The other half of the pair: in playable mode the rig's global Input polls must
	# die with the modal freeze (typing into the report card must not pan the rig).
	_game.process_mode = Node.PROCESS_MODE_DISABLED
	await await_idle_frame()
	await await_idle_frame()
	var rig: Node3D = _scene.get_node("CameraRig")
	assert_bool(rig.is_processing()).is_false()
	_game.process_mode = Node.PROCESS_MODE_INHERIT


func test_the_dev_overlay_resolves_while_the_game_is_hosted_in_3d() -> void:
	# Boot-into-3D: Battle3D is the main_scene now, so Main is mounted at /root/Battle3D/Main
	# and game.gd's old ABSOLUTE "/root/Main/DevOverlay" resolved to nothing — F1 silently did
	# nothing in the 3D build, and every dev affordance behind game.dev_overlay went inert.
	# Non-vacuous by construction: the node is looked up through the real @onready field.
	assert_bool(DevTools.enabled()).override_failure_message(
			"devtools are off in this run; the lookup never even runs and the case proves nothing").is_true()
	var overlay: DevOverlay = _game.dev_overlay
	assert_object(overlay).override_failure_message(
			"game.dev_overlay is null while hosted under Battle3D — the lookup is mount-dependent again").is_not_null()
	# It really is the one hanging off the hosted Main, not some other tree's.
	assert_object(overlay).is_same(_scene.get_node("Main/DevOverlay"))
