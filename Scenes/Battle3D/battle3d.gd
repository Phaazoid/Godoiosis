# The Battle3D shell (#215/#220 / #176 stage 4a+4b): the hidden-2D-game-as-authority
# architecture. Hosts the REAL Main.tscn — the full sim runs untouched — while
# BoardMirror/UnitMirror render it as an HD-2D diorama.
#
# Stage 4b makes it PLAYABLE: the bridge translates the 3D pointer to 2D-viewport
# coordinates and feeds ordinary mouse events through Input.parse_input_event,
# positioned over the PiP — the OS-driver entry, so the container forwards them
# into GameView exactly like physical clicks and every gate (the board lock, the
# modal freeze, menu placement) fires natively; game.gd needs no edits. (Measured:
# Viewport.push_input dies against handle_input_locally=false — the container is
# the only live door, and unconsumed events BUBBLE back out to the root.)
# The 2D UI stays usable as a corner picture-in-picture: the container keeps its
# native 1280x720 SIZE (so GameView keeps full resolution under stretch) and only
# the display shrinks via scale; input maps through the container transform.
#
# demo_mode = stage-4a behavior: both factions AI, no PiP, watch-only.
extends Node3D

@export var auto_play := true    # start mission_path on launch (test fixtures set false)
@export var demo_mode := false   # true = the 4a diorama demo: AI-vs-AI, no PiP, no bridge
@export var mission_path := "res://Scenarios/missions/Prolog.tres"
# PiP knobs (aesthetics get a knob, not a guess):
@export var pip_scale := 0.35
@export var pip_margin := Vector2(12.0, 12.0)
# Bring-up diagnostic (4b): the bridge narrates each link on the help label —
# pointer pick, click mapping, refusals — so a live run pinpoints which link is
# dead without a debugger. Untick to silence; drop the mechanism at 4c.
@export var debug_readout := true

# Stamped on every synthetic event so the bridge never mistakes its own echo for
# 3D pointing (InputEvent is a Resource — meta survives in-process delivery).
const BRIDGE_EVENT_META := &"iosis_3d_bridge"

@onready var _main: Node = $Main
@onready var _board_mirror: BoardMirror = $BoardMirror
@onready var _unit_mirror: UnitMirror = $UnitMirror
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
var _base_help: String = ""


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
		_setup_pip()
		get_viewport().size_changed.connect(_position_pip)
		_help.text = "Battle3D (stage 4b, playable)  |  LMB act  |  RMB cancel  |  UI in the corner PiP  |  Q/E orbit  |  wheel zoom  |  WASD pan  |  R reset"
	_base_help = _help.text
	_board_mirror.board = $Board
	_unit_mirror.units_root = game.units_root
	game.turn_manager.turn_started.connect(_on_turn_started)
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
	game.mission_controller.begin_mission(path)
	rebuild()
	_fit_camera()


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


# --- The PiP (stage 4b) --------------------------------------------------------------

func _setup_pip() -> void:
	_game_container.visible = true
	_game_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_game_container.size = _pip_native
	_game_container.scale = Vector2(pip_scale, pip_scale)
	_position_pip()


func _position_pip() -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	_game_container.position = view - _pip_native * pip_scale - pip_margin


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
	if demo_mode or not game.can_process():
		return
	var mouse := event as InputEventMouse
	if mouse == null:
		return
	# The bridge's own synthetics BUBBLE back here when the game leaves them unconsumed
	# (measured). Re-reading one as 3D pointing forges a self-sustaining event loop that
	# never lets a flush drain — the tag is the loop-breaker, not hygiene.
	if mouse.has_meta(BRIDGE_EVENT_META):
		return
	# Real events over the PiP belong to the 2D game — the container forwards them
	# itself, and they too bubble back when unconsumed. Never read them as 3D pointing.
	# Load-bearing BESIDE the meta tag, not redundant with it: accumulated input can
	# MERGE a synthetic motion into a pending physical one, which drops the tag — the
	# rect test still catches the merged event.
	if _game_container.get_global_rect().has_point(mouse.position):
		return
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
		# Cancel is position-blind (game.gd:279 takes no cell), so push at the viewport
		# center, which ALWAYS forwards — a far-cell hover's mapped position can fall
		# outside the container rect and would be silently dropped, leaving the player
		# stuck in a mode with a dead cancel.
		_push_click(MOUSE_BUTTON_RIGHT, _pip_native * 0.5)
		_diag("RMB cancel pushed at the viewport center")


func _update_pointer(screen_pos: Vector2) -> void:
	var cell := _pick(screen_pos)
	if cell == _pointer_cell:
		return
	_pointer_cell = cell
	if cell == BoardSpace.NO_CELL:
		_overlays.clear(BoardOverlays.Layer.HOVER)
		return
	_overlays.set_cells(BoardOverlays.Layer.HOVER, [cell])
	_push_motion(_cell_view_pos(_flat(cell)))
	_diag("pointer %s" % cell)


func _click_pointer_cell() -> void:
	if _pointer_cell == BoardSpace.NO_CELL:
		_diag("LMB ignored: no cell under the pointer")
		return
	# The game refuses clicks while the board is locked (AI turn / mission over / menu
	# — game.gd's one predicate; read it, don't re-derive it). Without this, a refused
	# click would still yank the hidden camera off the AI's pan_to/follow. It also
	# covers the MENU case the can_process() gate above cannot: Mission Select opts
	# OUT of the modal lock deliberately, so the game is unfrozen behind it.
	if game._board_locked_for_player():
		_diag("LMB refused: board locked (state %d)" % game.game_state)
		return
	var cell := _flat(_pointer_cell)
	# The pushed position maps back to a cell through the LIVE 2D camera transform
	# (game.gd:192), so the hidden camera must be showing the cell first. Side
	# effect, by design: the PiP recenters on every 3D click the game can act on.
	var cam: CameraController = game.camera_controller
	cam.snap_to_position(_cell_world_2d(cell))
	var view_pos := _cell_view_pos(cell)
	_push_motion(view_pos)
	_push_click(MOUSE_BUTTON_LEFT, view_pos)
	_diag("LMB cell %s -> view %s -> root %s  (state %d)" % [
		cell, view_pos.round(), (_game_container.get_global_transform() * view_pos).round(), game.game_state])


func _pick(screen_pos: Vector2) -> Vector3i:
	return BoardPicker.pick_cell(
		_camera.project_ray_origin(screen_pos),
		_camera.project_ray_normal(screen_pos),
		_tops
	)


func _flat(cell: Vector3i) -> Vector2i:
	return Vector2i(cell.x, cell.z)  # boards are flat; the mirror paints (x, 0, y)


# A cell's center in the 2D game's canvas (world) coordinates.
func _cell_world_2d(cell: Vector2i) -> Vector2:
	var grid: TileMapLayer = game.grid
	return grid.to_global(grid.map_to_local(cell))


# A cell's center in GameView's viewport coordinates — the space pushed events use.
func _cell_view_pos(cell: Vector2i) -> Vector2:
	var canvas: Transform2D = _game_view.get_canvas_transform()
	return canvas * _cell_world_2d(cell)


func _push_motion(view_pos: Vector2) -> void:
	_send_to_game(InputEventMouseMotion.new(), view_pos)


func _push_click(button: MouseButton, view_pos: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = button
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	_send_to_game(press, view_pos)
	var release := InputEventMouseButton.new()
	release.button_index = button
	release.pressed = false
	_send_to_game(release, view_pos)


func _diag(msg: String) -> void:
	if debug_readout:
		_help.text = _base_help + "\n[bridge] " + msg


# One door, the same one real input uses: OS-level parse, positioned over the PiP,
# so the container forwards into GameView exactly like a physical click there.
# Parse only, never flush — this runs INSIDE input dispatch (a re-entrant flush is
# not safe). The drain loop re-checks its queue, so events parsed during dispatch
# are delivered by the SAME flush — no frame boundary and no _process between the
# camera snap and delivery, which is what makes reading the live transform at
# parse time exact.
func _send_to_game(ev: InputEventMouse, view_pos: Vector2) -> void:
	var root_pos: Vector2 = _game_container.get_global_transform() * view_pos
	ev.position = root_pos
	ev.global_position = root_pos
	ev.set_meta(BRIDGE_EVENT_META, true)
	Input.parse_input_event(ev)
