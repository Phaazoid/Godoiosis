# The Battle3D shell (#176 stages 4a-4c): the hidden-2D-game-as-authority
# architecture. Hosts the REAL Main.tscn — the full sim runs untouched — while
# BoardMirror/UnitMirror/OverlayMirror render it as an HD-2D diorama.
#
# Stage 4c's hosting (#222): the 2D game IS the UI surface. Its container covers
# the window at native scale with a TRANSPARENT viewport and its board visuals
# hidden, so every Control — menus, cards, the queue panel, the HUD — draws over
# the 3D world and takes PHYSICAL clicks natively: real tooltips, real menu
# placement at the real cursor, the ModalLock click path untouched. Only BOARD
# clicks need translating, and those skip events entirely — the picker calls
# game._on_left_click / _on_right_click, which ARE the dispatchers (game.gd's
# _unhandled_input only derives a cell and calls them). Its own derivation would
# double-act on the same physical click, so game.board_input_delegated silences
# it: one bool, the arc's only game.gd input edit. 4b's whole synthetic-event
# bridge (parse_input_event, the echo tag, the PiP-rect guard) is retired.
#
# corner_view is the dev-facing debug toggle (F4): the 4b picture-in-picture, 2D
# board visuals and all. Board input is container-independent, so 3D play works
# in either mode.
#
# demo_mode = stage-4a behavior: both factions AI, hidden 2D, watch-only.
extends Node3D

@export var auto_play := true    # start mission_path on launch (test fixtures set false)
@export var demo_mode := false   # true = the 4a diorama demo: AI-vs-AI, hidden 2D, no bridge
@export var mission_path := "res://Scenarios/missions/Prolog.tres"
# The corner debug view's knobs (aesthetics get a knob, not a guess):
@export var corner_view := false   # F4 in dev builds; the 4b PiP with the 2D board showing
@export var pip_scale := 0.35
@export var pip_margin := Vector2(12.0, 12.0)

@onready var _main: Node = $Main
@onready var _board_mirror: BoardMirror = $BoardMirror
@onready var _unit_mirror: UnitMirror = $UnitMirror
@onready var _overlay_mirror: OverlayMirror = $OverlayMirror
@onready var _overlays: BoardOverlays = $BoardOverlays
@onready var _rig: Node3D = $CameraRig
@onready var _camera: Camera3D = $CameraRig/Pitch/Camera
@onready var _help: Label = $UI/Help

var game: Node2D
var _game_container: SubViewportContainer
var _game_view: SubViewport
var _tops: Dictionary[Vector2i, int] = {}
var _pointer_cell: Vector3i = BoardSpace.NO_CELL
# The 2D game's native resolution, read in _ready off the container's authored
# custom_minimum_size (Main.tscn) — the one source of that fact. The PiP pins the
# container SIZE to it (GameView keeps full resolution under stretch) and shrinks
# only the display via scale.
var _pip_native: Vector2 = Vector2(1280.0, 720.0)


func _ready() -> void:
	game = _main.get_node("GameContainer/GameView/Game")
	_game_container = _main.get_node("GameContainer") as SubViewportContainer
	_game_view = _main.get_node("GameContainer/GameView") as SubViewport
	_pip_native = _game_container.custom_minimum_size
	var dev_overlay: Node = _main.get_node_or_null("DevOverlay")
	if dev_overlay is Window:
		(dev_overlay as Window).visible = false
	if demo_mode:
		_game_container.visible = false
		_help.text = "Battle3D mirror (demo mode, read-only)  |  Q/E orbit  |  wheel zoom  |  WASD pan  |  R reset"
	else:
		_apply_hosting()
		get_viewport().size_changed.connect(_position_pip)
		# The 3D pick IS the pointer (#222): HoverPresenter reads it instead of the
		# hidden viewport's mouse, so hover works for every cell — not just the ones
		# the hidden camera happens to show. flat(NO_CELL) == GridUtils.NO_CELL.
		game.hover_presenter.pointer_source = func() -> Vector2i: return BoardSpace.flat(_pointer_cell)
		# The 2D game stops deriving board clicks from its own viewport mouse — this
		# node delivers the picked cell instead (see the header).
		game.board_input_delegated = true
		_help.text = "Battle3D (stage 4c)  |  LMB act  |  RMB cancel  |  Q/E orbit  |  wheel zoom  |  WASD pan  |  R reset  |  F4 corner view"
	_board_mirror.board = $Board
	_unit_mirror.units_root = game.units_root
	_overlay_mirror.game = game
	_overlay_mirror.overlays = _overlays
	_overlay_mirror.unit_mirror = _unit_mirror
	game.turn_manager.turn_started.connect(_on_turn_started)
	game.scenario_manager.board_loaded.connect(_on_board_loaded)
	if auto_play:
		_start.call_deferred()


func _start() -> void:
	await get_tree().process_frame  # let the hidden Mission Select finish its deferred open
	load_mission(mission_path)
	if demo_mode:
		var both: Array[Team.Faction] = [Team.Faction.PLAYER, Team.Faction.ENEMY]
		game.ai_controller.set_ai_factions(both)  # AI-vs-AI: the diorama plays itself
	# Playable mode leaves the scenario's own ai_factions standing (#150) — the
	# player faction is human, so squadding up is the player's own opening move.


func load_mission(path: String) -> void:
	game.mission_controller.begin_mission(path)  # board_loaded does the rest


# Every board swap lands here via ScenarioManager.board_loaded (#222): mission load,
# Load Game (any mission), F2/Restart, Mission Select, sandbox. Rebuild the mirror
# world and drop pointer state aimed at the dead board — _update_pointer's dedup
# would otherwise eat the first repaint on a same-coordinate cell.
func _on_board_loaded() -> void:
	rebuild()
	_fit_camera()
	_pointer_cell = BoardSpace.NO_CELL
	_overlays.clear_all()


func rebuild() -> void:
	_board_mirror.rebuild(game.grid, game.terrain_states.to_state_dict())
	_tops = BoardPicker.column_tops_from($Board)


func _on_turn_started(_faction: int) -> void:
	_board_mirror.refresh_states(game.terrain_states.to_state_dict())


func _fit_camera() -> void:
	var rect: Rect2i = game.grid.get_used_rect()
	var center := Vector2(rect.position) + Vector2(rect.size) * 0.5
	_rig.position = Vector3(center.x, 1.0, center.y)
	_rig.set_zoom(maxf(float(rect.size.x), float(rect.size.y)) * 1.05)


# --- Hosting the 2D game (stage 4c) ---------------------------------------------------

# All of this is RUNTIME, never authored into Main.tscn: the flat 2D game is a
# shipping target of its own and must open exactly as it always has (#176's
# presentation-effects ruling).
func _apply_hosting() -> void:
	_game_container.visible = true
	if corner_view:
		_setup_corner()
	else:
		_setup_fullscreen()


# The real hosting: the 2D game covers the window at native scale over a
# transparent viewport, with its board visuals hidden — so what shows through is
# the 3D world with the 2D UI on top, and Controls take physical clicks directly.
func _setup_fullscreen() -> void:
	_game_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game_container.scale = Vector2.ONE
	_game_view.transparent_bg = true
	_set_board_visible(false)


# The 4b picture-in-picture, kept as a dev debug view: the 2D board renders again,
# shrunk into the corner. The container keeps its native SIZE (GameView keeps full
# resolution under stretch) and only the display shrinks via scale.
func _setup_corner() -> void:
	_game_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_game_container.size = _pip_native
	_game_container.scale = Vector2(pip_scale, pip_scale)
	_game_view.transparent_bg = false
	_set_board_visible(true)
	_position_pip()


func _position_pip() -> void:
	if not corner_view:
		return
	var view: Vector2 = get_viewport().get_visible_rect().size
	_game_container.position = view - _pip_native * pip_scale - pip_margin


# The board-visual set, hidden as a unit so the 2D layer reads as pure UI.
# MEASURED (#222): `game.visible = false` is NOT the switch — OverlayManager is a
# plain Node, which breaks CanvasItem visibility propagation to the overlay layers
# (they stayed drawn), while the CanvasLayer UI went dark with it. Hence per-node.
# ZoneOverlay and its highlight are skipped: they are authoring-only, owned by
# set_zone_visibility, and a blanket restore would reveal PATROL zones in play.
func _set_board_visible(shown: bool) -> void:
	game.grid.visible = shown
	game.units_root.visible = shown
	game.cursor_controller.visible = shown
	var overlays: OverlayManager = game.overlay_manager
	for child in overlays.get_children():
		var item := child as CanvasItem
		if item == null or item == overlays.zone_overlay or item == overlays.zone_highlight_overlay:
			continue
		item.visible = shown


# --- The input bridge (stage 4b) -------------------------------------------------------

# The modal freeze must stop the bridge exactly as it stops engine input delivery:
# ModalLock freezes the game subtree, and a freeze stops callbacks, not method calls
# (#154) — so the bridge checks can_process() itself, and the 3D rig's global Input
# polls are frozen alongside (typing into the report card must not pan the rig).
# demo_mode is the carve-out: the bridge is off there, and the end-of-mission banner
# (a modal inside the HIDDEN container) would otherwise freeze the diorama's camera
# forever — 4a kept the rig alive after the battle ended, and so does demo mode.
func _process(_delta: float) -> void:
	var live: bool = demo_mode or game.can_process()
	_rig.set_process(live)
	_rig.set_process_unhandled_input(live)


func _unhandled_input(event: InputEvent) -> void:
	if demo_mode:
		return
	# The view toggle sits ABOVE the freeze gate on purpose — it is a dev control,
	# and dev controls are a layer above ModalLock (#154). This node lives outside
	# the frozen subtree, so its callbacks run regardless.
	if DevTools.enabled() and event.is_pressed() and event is InputEventKey \
			and (event as InputEventKey).keycode == KEY_F4:
		corner_view = not corner_view
		_apply_hosting()
		return
	if not game.can_process():
		return
	# UI consumed the event before it reached here (the container forwards physical
	# clicks into the 2D game natively). What arrives is board pointing.
	var motion := event as InputEventMouseMotion
	if motion != null:
		_update_pointer(motion.position)
		return
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	if click.button_index == MOUSE_BUTTON_LEFT:
		_update_pointer(click.position)  # a click is also a point — robust when no motion preceded it
		_click_pointer_cell()
	elif click.button_index == MOUSE_BUTTON_RIGHT:
		_cancel()


func _update_pointer(screen_pos: Vector2) -> void:
	var cell := _pick(screen_pos)
	if cell == _pointer_cell:
		return
	_pointer_cell = cell
	if cell == BoardSpace.NO_CELL:
		_overlays.clear(BoardOverlays.Layer.HOVER)
		return
	_overlays.set_cells(BoardOverlays.Layer.HOVER, [cell])
	# The hidden 2D camera still has one live consumer: the hover card parks itself
	# by mapping a WORLD position through the 2D canvas transform, so the camera has
	# to be showing the hovered cell or the card parks against a stale view. Skipped
	# while the board is locked — an AI turn owns the camera (pan_to/follow).
	if not game._board_locked_for_player():
		game.camera_controller.snap_to_position(GridUtils.cell_world(game.grid, BoardSpace.flat(cell)))


# game._on_left_click / _on_right_click ARE the dispatchers — game.gd's own
# _unhandled_input just derives a cell and calls them, and every test in the repo
# drives them this way (tests/README.md). Delivering the picked cell directly is
# both simpler and exact: no viewport-mouse round trip to get wrong.
func _click_pointer_cell() -> void:
	if _pointer_cell == BoardSpace.NO_CELL:
		return
	# The game refuses clicks while the board is locked (AI turn / mission over /
	# menu — game.gd's one predicate; read it, don't re-derive it). Calling the
	# dispatcher directly bypasses game.gd's own copy of this gate, so it moves here
	# rather than disappearing. It also covers the MENU case the can_process() gate
	# cannot: Mission Select opts OUT of the modal lock, so the game is unfrozen.
	if game._board_locked_for_player():
		return
	game._on_left_click(BoardSpace.flat(_pointer_cell))


func _cancel() -> void:
	if game._board_locked_for_player():
		return
	# Mirrors game.gd's own RMB arm: cancel is position-blind, and DEV_MODE keeps
	# right-click for the tile brush.
	if game.game_state != game.GameState.DEV_MODE:
		game._on_right_click()


func _pick(screen_pos: Vector2) -> Vector3i:
	return BoardPicker.pick_at(_camera, screen_pos, _tops)
