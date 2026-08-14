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
# Three hosting VIEWS, switched live (F4 / Shift+F4 in dev builds). FLAT_2D is the
# real escape hatch and the embryo of #176's 2D/3D chooser: it does not merely show
# the 2D board, it hands INPUT BACK — un-delegates board clicks, drops the injected
# pointer source, silences this node's picker and stops the rig — because a flat 2D
# game that cannot take its own clicks (or that pans an invisible 3D camera with
# WASD) is not a playable fallback. CORNER is the 4b picture-in-picture, kept only
# as a debug view.
#
# demo_mode = stage-4a behavior: both factions AI, hidden 2D, watch-only.
extends Node3D

enum View {
	HD_2D,    # the 2D game as transparent full-screen UI over the 3D diorama
	FLAT_2D,  # the flat 2D game, full-screen and opaque; the 3D stands down
	CORNER,   # dev debug: the 4b PiP, 2D board visuals and all, 3D still driving
}

# FALSE is the shipping boot: this scene is the game's main_scene now, and the hidden 2D game
# opens Mission Select for itself. Forcing mission_path here would skip the title screen, the
# mission list and Load Game. True is a dev shortcut — jump straight into mission_path.
@export var auto_play := false
@export var demo_mode := false   # true = the 4a diorama demo: AI-vs-AI, hidden 2D, no bridge
@export var mission_path := "res://Scenarios/missions/Prolog.tres"
@export var view: View = View.HD_2D
# How wide the OPENING shot is, in cells, centred on the player's own units. The whole
# board is what the view is BOUNDED by, not what it opens at (dev feel-check 2026-08-14:
# fitting all 64x40 of Prolog opened the game too far out to play from).
@export var opening_view_cells := 18.0
# How far PAST the painted board a click still resolves to a cell (#231). The 2D game
# lets you paint outside the board to grow it, and CameraController.EDIT_MARGIN_CELLS is
# how far it already lets you pan out to do so — this is that same authoring margin, in
# the view that now has to support the same act. Not a new number: match them or say why.
@export var paint_apron_cells: int = CameraController.EDIT_MARGIN_CELLS
# The corner debug view's knobs (aesthetics get a knob, not a guess):
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
# The painted footprint, cached beside _tops and written wherever it is (#231): the
# picker needs it grown by the apron on every motion event, and deriving it per pick
# would walk every column of the board each time the mouse moves.
var _board_rect := Rect2i()
var _pointer_cell: Vector3i = BoardSpace.NO_CELL
# The 2D game's native resolution, read in _ready off the container's authored
# custom_minimum_size (Main.tscn) — the one source of that fact. The PiP pins the
# container SIZE to it (GameView keeps full resolution under stretch) and shrinks
# only the display via scale.
var _pip_native: Vector2 = Vector2(1280.0, 720.0)
# Last frame's ai_locked, so the square-on realign fires once per AI turn, not per frame.
var _ai_owned_camera := false


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
		# _apply_hosting also assigns input ownership: the 3D pick becomes the pointer
		# source HoverPresenter reads (so hover reaches every cell, not just the ones
		# the hidden camera shows) and the 2D game stops deriving its own board clicks.
		_apply_hosting()
		get_viewport().size_changed.connect(_position_pip)
		# The orbit button is a knob, so the label READS it instead of restating it — this
		# line still said MMB after the binding was flipped. And the cancel verb is "aim":
		# right-click exits the current mode, it has never touched the queued orders.
		var orbit_button: int = _rig.orbit_button
		var orbit := "RMB" if orbit_button == MOUSE_BUTTON_RIGHT else "MMB"
		_help.text = "Battle3D  |  LMB act  |  RMB cancel aim  |  %s-drag orbit  |  Q/E realign  |  wheel zoom  |  WASD pan  |  SPACE centre  |  R reset  |  F4 flat 2D  |  Shift+F4 corner" % orbit
	_board_mirror.board = $Board
	_unit_mirror.units_root = game.units_root
	_overlay_mirror.game = game
	_overlay_mirror.overlays = _overlays
	_overlay_mirror.unit_mirror = _unit_mirror
	_overlay_mirror.board_mirror = _board_mirror
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
	_board_mirror.rebuild(game.grid, game.terrain_states.burning_cells())
	_refresh_tops()


# _tops and _board_rect are one fact in two shapes — never write one without the other.
func _refresh_tops() -> void:
	_tops = BoardPicker.column_tops_from($Board)
	_board_rect = BoardPicker.used_rect(_tops)


# The live terrain poll (#231). Confined to DEV_MODE on purpose: the sim never paints
# terrain — the only writers are the dev brush and its Resize — so gating here keeps an
# O(board) diff entirely out of the shipping game while still catching every writer,
# including any future one, with no trigger site to remember. (An engine signal was the
# first choice and is not available: TileMapLayer.changed does NOT fire on set_cell /
# erase_cell in 4.7 — measured, with a property write as the control.)
#
# Repainting can add or erase a COLUMN, which is what the picker and the camera bounds
# are derived from — so refresh them with it, or the newly painted cell is unclickable
# and panning stops at the old edge. Bounds only, never a re-frame: the 2D twin
# (CameraController.refresh_bounds) moves limits and never re-aims, and yanking the
# camera mid-stroke is not what painting a tile should do.
func _sync_terrain_while_authoring() -> void:
	if game.game_state != game.GameState.DEV_MODE:
		return
	_board_mirror.sync(game.grid)
	var before := _board_rect
	_refresh_tops()
	if _board_rect != before:
		_rig.rebound(_board_volume())


func _fit_camera() -> void:
	var board := _board_volume()
	_rig.frame(_opening_volume(board), board)


# The opening shot: the player's own units with opening_view_cells of board around them,
# passed as the SHOT while the board is passed as the bounds — so the game opens on the
# squad and zooming out still reaches the far corner. Falls back to the whole board when
# a scenario opens with no player units (the sandbox, demo_mode).
func _opening_volume(board: AABB) -> AABB:
	var lo := Vector2.INF
	var hi := -Vector2.INF
	var units_root: Node2D = game.units_root
	for child in units_root.get_children():
		var unit := child as Unit
		if unit == null or unit.get_faction() != Team.Faction.PLAYER:
			continue
		var at := Vector2(unit.movement.cell)
		lo = lo.min(at)
		hi = hi.max(at)
	if is_inf(lo.x):
		return board
	# Cells span [x, x+1], so an occupied footprint is one wider than its corner spread.
	var span := maxf(opening_view_cells, maxf(hi.x - lo.x, hi.y - lo.y) + 1.0)
	var center := (lo + hi + Vector2.ONE) * 0.5
	return AABB(
		Vector3(center.x - span * 0.5, board.position.y, center.y - span * 0.5),
		Vector3(span, board.size.y, span))


# The volume the camera must see, derived from the picker's column tops rather than the
# 2D grid rect: _tops is the footprint actually RENDERED, and it already carries per
# column heights for the day the sim grows elevation. Cells span [x, x+1].
func _board_volume() -> AABB:
	if _tops.is_empty():
		return AABB()
	# The bbox itself is BoardPicker's — it derives the same one to bound its walk, and
	# two copies of "how big is this board" is exactly the seam Law #4 forbids (#231).
	var rect := _board_rect
	return AABB(
		Vector3(rect.position.x, 0.0, rect.position.y),
		Vector3(rect.size.x, float(BoardPicker.max_top(_tops)), rect.size.y))


# --- Hosting the 2D game (stage 4c) ---------------------------------------------------

# All of this is RUNTIME, never authored into Main.tscn: the flat 2D game is a
# shipping target of its own and must open exactly as it always has (#176's
# presentation-effects ruling).
func _apply_hosting() -> void:
	_game_container.visible = true
	match view:
		View.CORNER:
			_setup_corner()
		View.FLAT_2D:
			_setup_flat_2d()
		_:
			_setup_fullscreen()
	_apply_input_ownership()


# WHO owns board input, derived from the view rather than tracked separately.
# In FLAT_2D the 2D game is the whole game again: it derives its own clicks, hovers
# off its own mouse, and owns WASD — so the delegation gate, the injected pointer
# source and the 3D rig all stand down together. Anywhere else the 3D picker drives.
func _apply_input_ownership() -> void:
	var flat: bool = view == View.FLAT_2D
	game.board_input_delegated = not flat
	if flat:
		game.hover_presenter.pointer_source = Callable()
		_pointer_cell = BoardSpace.NO_CELL
		_overlays.clear(BoardOverlays.Layer.HOVER)
	else:
		game.hover_presenter.pointer_source = func() -> Vector2i: return BoardSpace.flat(_pointer_cell)


# The real hosting: the 2D game covers the window at native scale over a
# transparent viewport, with its board visuals hidden — so what shows through is
# the 3D world with the 2D UI on top, and Controls take physical clicks directly.
func _setup_fullscreen() -> void:
	_game_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game_container.scale = Vector2.ONE
	_game_view.transparent_bg = true
	_set_board_visible(false)


# The escape hatch: the flat 2D game, full-screen and OPAQUE, board and all. The
# 3D world is still there, simply covered — nothing tears down, so F4 back is free.
func _setup_flat_2d() -> void:
	_game_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game_container.scale = Vector2.ONE
	_game_view.transparent_bg = false
	_set_board_visible(true)


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
	if view != View.CORNER:
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
	# FLAT_2D hands the camera back too: the rig is invisible behind an opaque 2D
	# viewport, and CameraController's WASD poll is global, so leaving it alive would
	# pan both cameras at once off one keypress.
	var live: bool = (demo_mode or game.can_process()) and view != View.FLAT_2D
	_rig.set_process(live)
	_rig.set_process_unhandled_input(live)
	_sync_terrain_while_authoring()
	# Separate from `live`, and deliberately so: while the AI acts or a menu is up the
	# rig must keep SMOOTHING (the mirror below drives it) while refusing the player.
	# Same predicate that refuses their clicks — one question, one answer.
	_rig.manual_input_enabled = demo_mode or not game._board_locked_for_player()
	_mirror_camera()


# The 3D view follows the action by MIRRORING the 2D camera, which is already the
# authority for where the action is (AIController pans it to each acting squad). No
# second follow seam, and because the 2D camera owns the tween the 3D inherits
# Pacing.AI_SQUAD_PAN exactly — one number, one reader.
#
# ai_locked is the gate, NOT _board_locked_for_player(): the latter also covers MENU,
# and Mission Select opts out of the modal lock, so mirroring there would yank the rig
# to a stale 2D position the moment a menu opened. ai_locked IS the fact "the AI owns
# the 2D camera" — set in the same block as AI_TURN, cleared the moment it returns.
# Re-read every frame, never latched: a turn handoff can re-enter set_ai_locked inside
# the previous turn's stack, so the flag can legitimately flicker for a frame.
func _mirror_camera() -> void:
	var cam: CameraController = game.camera_controller
	# Square-on for the enemy phase (dev call 2026-08-14), on the EDGE into the turn rather
	# than every frame: idempotent either way today, but the moment orbit is allowed to stay
	# live under an AI turn a per-frame snap would fight the player's own drag.
	if cam.ai_locked != _ai_owned_camera:
		_ai_owned_camera = cam.ai_locked
		if _ai_owned_camera:
			_rig.align_to_detent()
	if not cam.ai_locked:
		return
	_rig.position = BoardSpace.of_pixels(cam.global_position, _rig.position.y)


func _unhandled_input(event: InputEvent) -> void:
	if demo_mode:
		return
	# The view keys sit ABOVE the freeze gate on purpose — they are dev controls, and
	# dev controls are a layer above ModalLock (#154). This node lives outside the
	# frozen subtree, so its callbacks run regardless.
	var key := event as InputEventKey
	if DevTools.enabled() and key != null and key.pressed and key.keycode == KEY_F4:
		if key.shift_pressed:
			view = View.HD_2D if view == View.CORNER else View.CORNER
		else:
			view = View.HD_2D if view == View.FLAT_2D else View.FLAT_2D
		_apply_hosting()
		return
	# In FLAT_2D the flat game owns its own clicks — picking here would double-act,
	# the mirror image of the bug game.board_input_delegated exists to prevent.
	# The board lock joins it: while an AI turn, a menu or the end banner is up, the
	# click handlers below refuse anyway, so pointing would only paint a bracket over
	# a board nobody can touch. (Mission Select opts OUT of the modal lock, so
	# can_process() does not cover this — measured.)
	if view == View.FLAT_2D or not game.can_process() or game._board_locked_for_player():
		return
	# UI consumed the event before it reached here (the container forwards physical
	# clicks into the 2D game natively). What arrives is board pointing.
	var motion := event as InputEventMouseMotion
	if motion != null:
		if not _rig.is_orbiting():   # a drag is camera work, not pointing
			_update_pointer(motion.position)
		return
	if key != null and key.pressed and key.keycode == KEY_SPACE:
		_center_on_pointer()
		return
	var click := event as InputEventMouseButton
	if click == null:
		return
	if click.button_index == MOUSE_BUTTON_RIGHT:
		_handle_cancel_button(click)
		return
	if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_update_pointer(click.position)  # a click is also a point — robust when no motion preceded it
		_click_pointer_cell()


# Cancel fires on PRESS — the meaning right-click carries everywhere else in the game —
# UNLESS right-click is also the orbit button, in which case it has to wait for the
# release to know whether the gesture was a click or a drag. Branching here rather than
# hard-coding either means orbit_button is a real inspector knob: flip it and both
# behaviours follow.
func _handle_cancel_button(click: InputEventMouseButton) -> void:
	if _rig.orbit_button != MOUSE_BUTTON_RIGHT:
		if click.pressed:
			_cancel()
		return
	if not click.pressed and _rig.last_gesture_was_click():
		_cancel()


# SPACE recentres the diorama on whatever the pointer is over — the 3D answer to the 2D
# camera's centre-on-mouse, which the delegation gate makes unreachable in this host.
# Kept here so game.gd's one bool stays the arc's only edit to its input path.
func _center_on_pointer() -> void:
	if _pointer_cell == BoardSpace.NO_CELL:
		return
	var point := BoardSpace.standing_point(_pointer_cell)
	_rig.position = Vector3(point.x, _rig.position.y, point.z)


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
	return BoardPicker.pick_at(_camera, screen_pos, _tops, _paint_plane())


# Where a click still lands with no block under it (#231): the painted board plus the
# authoring apron, so an erased cell stays clickable and painting can still grow the
# board outward the way the 2D view allows.
func _paint_plane() -> Rect2i:
	return _board_rect.grow(paint_apron_cells)
