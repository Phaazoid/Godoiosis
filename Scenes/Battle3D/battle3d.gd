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
# How opaque the plate behind the top-left readouts is (#498). A KNOB rather than a constant
# because "difficult to read" is a contrast complaint and the answer is taste -- but only the
# ALPHA is one: the colour is black because the text is light, and the padding is not a value
# anyone will argue about. Its setter re-applies immediately, or it is a slider that moves
# nothing until the help line happens to be rebuilt (#264's born-dead knob).
#
# PLAIN `@export`, never `@export_range`: KnobSource.DECLARATION_LINE matches `^@export<space>var`,
# so an annotated form has no declaration line to write back and Save would silently find nothing.
# The row's own min/max/step is what builds the panel's slider anyway.
@export var help_plate_alpha := 0.45: set = _set_help_plate_alpha
# Breathing room around the widest line, in pixels. Constant: see above.
const HELP_PLATE_PAD := Vector2(7.0, 5.0)

@onready var _main: Node = $Main
@onready var _board_mirror: BoardMirror = $BoardMirror
@onready var _unit_mirror: UnitMirror = $UnitMirror
@onready var _overlay_mirror: OverlayMirror = $OverlayMirror
@onready var _overlays: BoardOverlays = $BoardOverlays
@onready var _rig: CameraRig3D = $CameraRig
# The AUTHORED orbit binding, captured before anything rewrites it. The brush borrows MIDDLE
# while it is armed and gives this back when it disarms, so orbit_button stays a real
# inspector knob instead of a constant this file re-asserts every frame.
@onready var _orbit_button_default: MouseButton = _rig.orbit_button
# What the help label was last built for. The label is only worth rebuilding on a change.
var _help_brush_armed := false
var _help_dev_mode := false
var _help_wheel_is_level := false
# Which PAGE is up is a help-line input too since 2026-08-23 (SPACE spawn vs SPACE centre). It joins
# the key rather than being read only at render: a diff key blind to one of its own render's inputs
# is the #308 shape, and the line would sit stale until something else happened to move.
var _help_can_spawn := false
# Where the cursor was at the last poll. Seeded from the REAL position so the first frame
# cannot fire a move that never happened and yank the pointer off its starting cell.
@onready var _last_polled_mouse: Vector2 = get_viewport().get_mouse_position()
@onready var _camera: Camera3D = $CameraRig/Pitch/Camera
# The camera at the last poll. The pick depends on the CAMERA as much as on the mouse — pan the
# world under a still cursor and the cell beneath it genuinely changes — so a mouse-only early-out
# leaves the bracket on a cell the pointer has left. True of WASD and of SPACE since 4d; #471's
# return-to-the-acting-unit is what made it frequent enough to be worth fixing. The whole
# TRANSFORM rather than the rig's position, because yaw and zoom move the pick too and both lerp
# for frames after the input that started them.
@onready var _last_polled_camera: Transform3D = _camera.global_transform
@onready var _help: Label = $UI/Help
@onready var _checkout: Label = $UI/Checkout
@onready var _dev_badge: Label = $UI/DevMode
# ONE plate behind all three, not one each (#498). They are read together and sit in one corner,
# so three plates would give three ragged edges; and the CanvasLayer draws its children in tree
# order, which is the whole reason this is the FIRST child rather than a z_index.
@onready var _plate: Panel = $UI/Plate

var game: Node2D
var _game_container: SubViewportContainer
var _game_view: SubViewport
var _tops: Dictionary[Vector2i, int] = {}
# The shared column floor the mirror last drew against (#319). Held here rather than asked of the
# mirror because the question is "has it MOVED since the last pass", which only a caller that runs
# every frame can answer.
var _floor_row := 0
# The painted footprint, cached beside _tops and written wherever it is (#231): the
# picker needs it grown by the apron on every motion event, and deriving it per pick
# would walk every column of the board each time the mouse moves.
var _board_rect := Rect2i()
var _pointer_cell: Vector3i = BoardSpace.NO_CELL
# The staging this poll last drew (#521) -- its own last-drawn key, the _help_* fields' shape.
var _staged_version := 0
var _staged_drawn: Array[Vector2i] = []
# One GridMap per tile currently in the air (#521 slice B), and the white-out that covers the swap.
# Both are created on demand: a board that never stages pays nothing for either.
var _flight_drawn: Dictionary[Vector2i, GridMap] = {}
var _whiteout: ColorRect = null
# Which grid VERTEX the pointer is nearest (#427 slice 4). Stored beside the cell rather than derived
# from it: it changes as the cursor crosses the MIDDLE of a cell, so the cell early-out below would
# freeze it for the whole tile.
var _pointer_vertex := Vector2i.ZERO
# The 2D game's native resolution, read in _ready off the container's authored
# custom_minimum_size (Main.tscn) — the one source of that fact. The PiP pins the
# container SIZE to it (GameView keeps full resolution under stretch) and shrinks
# only the display via scale.
var _pip_native: Vector2 = Vector2(1280.0, 720.0)
# Last frame's playback_locked, so the square-on realign fires once per AI turn, not per frame.
var _playback_owned_camera := false
# ...and last frame's framed span (#520), for the same reason: the widen is an EDGE, so the player's
# wheel is theirs again the instant the shot is set up. Gated on the published span itself -- the
# store the answer is drawn from -- rather than on a copy of what it resolves to (#308).
var _framed_span: Array[Vector2i] = []

# The diorama's own surface height, solved ONCE per published stage (#602 round 3; the edge moved
# to cam.shot_cells in round 4). Latched rather than tracked because bodies get THROWN during a
# pass: a live re-solve would find them standing on whatever they landed on and walk the whole
# shot down after them mid-fight. `_stage_cells_solved` is the edge detector -- the published
# store itself, not a copy of what it resolves to (#308) -- and the claim edge clears it, so two
# passes staging the identical cells still each get their own solve against where the units stand
# NOW.
var _stage_height := 0.0
var _stage_cells_solved: Array[Vector2i] = []
# The last depth the fall channel published while its body still existed (#602 round 4). A void
# death frees the unit -- taking the fact with it -- so this is what the shot holds at while the
# burst's cubes fly. Zeroed at the claim edge and whenever the show is over; the board-swap door
# is drop_stashed_view's, which cuts the rig's own drop the same frame.
var _held_drop := 0.0
# ...and which unit the shot is trained on, BY ID, an edge detector for the zoom (#602 round 4).
# An id rather than a ref so a body freed mid-beat cannot wedge the edge, and 0 is "nobody".
var _trained_seen_id := 0


func _ready() -> void:
	game = _main.get_node("GameContainer/GameView/Game")
	_game_container = _main.get_node("GameContainer") as SubViewportContainer
	_game_view = _main.get_node("GameContainer/GameView") as SubViewport
	_pip_native = _game_container.custom_minimum_size
	# The SAME push, one layer down (#240): a bug report names the angle it was seen from.
	# Unconditional, because F3 files a report in demo_mode too.
	game.bug_reporter.view_source = _describe_view
	var dev_overlay: Node = _main.get_node_or_null("DevOverlay")
	if dev_overlay is Window:
		(dev_overlay as Window).visible = false
	# PUSH the 3D world at the dev window rather than letting it reach up for one (#212): the game
	# subtree keeps no path to this scene, and a flat Main.tscn launch simply never gets a host.
	if dev_overlay is DevOverlay:
		(dev_overlay as DevOverlay).attach_3d_host(self)
	_set_help_plate_alpha(help_plate_alpha)
	_show_checkout()
	game.dev_mode_changed.connect(_show_dev_badge)
	_show_dev_badge(game.dev_mode_enabled)
	if demo_mode:
		_game_container.visible = false
		_help.text = "Battle3D mirror (demo mode, read-only)  |  Q/E orbit  |  wheel zoom  |  WASD pan  |  R reset"
		_fit_help_plate()
	else:
		# _apply_hosting also assigns input ownership: the 3D pick becomes the pointer
		# source HoverPresenter reads (so hover reaches every cell, not just the ones
		# the hidden camera shows) and the 2D game stops deriving its own board clicks.
		_apply_hosting()
		get_viewport().size_changed.connect(_position_pip)
		_update_help()
	_board_mirror.board = $Board
	_board_mirror.staged_board = $StagedBoard
	_unit_mirror.units_root = game.units_root
	_unit_mirror.heights = game.board_heights
	_unit_mirror.hovered_unit_source = _hovered_unit
	_unit_mirror.plan_source = _previewed_plan
	_unit_mirror.effect_subjects_source = _effect_pass_subjects
	# The impact wire (#520 diff 2b): the mirror sees the blow land, and this decides what it is
	# worth. It bound straight to _rig.shake until 2c gave a killing blow a second consequence --
	# the freeze -- which is not the rig's to do, so the decision moved here where both are reachable.
	_unit_mirror.report_impact = _on_impact
	# ...and where the bottom of the shot is, so a void death's burst erupts from under the frame
	# the camera is actually holding (#602 round 4). Only this host knows the rig -- same reason
	# report_impact is a callable and not a lookup.
	_unit_mirror.frame_floor = _shot_floor
	_overlay_mirror.game = game
	_overlay_mirror.overlays = _overlays
	_overlay_mirror.unit_mirror = _unit_mirror
	_overlay_mirror.board_mirror = _board_mirror
	game.scenario_manager.board_loaded.connect(_on_board_loaded)
	# The visible camera answers "look at this cell" (#471). Wired unconditionally, beside the other
	# game-tells-us signals: demo_mode has no action ring to fire it, so there is nothing to branch on.
	game.view_focus_requested.connect(_center_rig_on)
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
	# The scene knows whether a student is present: demo_mode is watch-only, so the #182 lesson
	# and its dialog stay disarmed (#375).
	game.mission_controller.begin_mission(path, not demo_mode)  # board_loaded does the rest


# Every board swap lands here via ScenarioManager.board_loaded (#222): mission load,
# Load Game (any mission), F2/Restart, Mission Select, sandbox. Rebuild the mirror
# world and drop pointer state aimed at the dead board — _update_pointer's dedup
# would otherwise eat the first repaint on a same-coordinate cell.
#
# HOVER and nothing else: BoardOverlays is partitioned by writer — this file owns the pointer
# bracket, OverlayMirror owns every other layer AND caches what it has pushed there. The
# clear_all() that used to sit here emptied the mirror's layers behind its back, so reloading an
# UNCHANGED board diffed equal and never repainted (#318). Zones were the visible casualty for
# being the only markup static across a whole board.
func _on_board_loaded() -> void:
	rebuild()
	_apply_board_look()   # before fit_camera: the preset carries pitch/FOV, which framing reads
	fit_camera()
	_pointer_cell = BoardSpace.NO_CELL
	_overlays.clear(BoardOverlays.Layer.HOVER)


# A board wears the look it names (#253 part 2). Deliberately "apply this preset" rather than
# "apply the mission's look": weather (#277) and battle-effect flashes (#278) are meant to drive
# the same seam later, and naming it after its first caller would fork a second applier.
func _apply_board_look() -> void:
	var preset := LookKnobs.resolve(game.scenario_manager.current_look_preset)
	if preset == null:
		return   # resolve already said so loudly; render whatever is loaded rather than crash
	LookKnobs.apply(self, preset)


# Re-stand every prop against its tile's CURRENT fields (#272 slice 2) — the Objects tab's door
# after editing a per-type value. It lives here rather than on the mirror because the grid and the
# heights are this node's to hand over; the mirror is passed them per call and stores neither.
func rebuild_props() -> void:
	_board_mirror.drop_props()
	rebuild()


# The 3D sprite standing in for a unit. A named door rather than letting a caller walk to the
# mirror by node path, since #629's dev key has to reach one from outside this scene entirely.
func sprite_for(unit: Unit) -> UnitSprite3D:
	return _unit_mirror.sprite_for(unit)


func rebuild() -> void:
	var states: TerrainStateManager = game.terrain_states
	var heights: BoardHeights = game.board_heights
	_board_mirror.rebuild(game.grid, heights, states.burning_cells(),
			states.cells_with(Terrain.TileState.COVER))
	_refresh_tops()
	# A rebuild IS the full sync every pending announcement was asking for, so it consumes them
	# rather than leaving the next poll to redo the whole board (#319). The floor is adopted here
	# for the same reason: a board swap moves it, and nothing has drawn against the old one since.
	_floor_row = _board_mirror.floor_row_of(heights)
	game.grid.dirty.clear()
	heights.dirty.clear()


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
# The tear-out's reconcile (#521): when the staged set changes, the cells that CROSSED between the
# board and the diorama have to be re-routed, and the staged lattice moved to its offset.
#
# The UNION of what was staged and what is staged now, because a cell coming HOME is as much a
# change as one going up and neither set alone names it. Gated on a monotonic version rather than a
# diff, DirtyCells.version's shape -- and the previously-staged set is remembered here rather than
# on BoardSpace, because it is this poll's own last-drawn key, not a fact about the board.
# The tear-out transition, driven (#521 slice B). The executor publishes a schedule and awaits its
# total; this advances it and draws the result. Neither side computes a timing the other cannot see.
#
# The whole function is dead unless a flight is running, which is what keeps every other frame -- and
# every headless run, where a flight can never start because the await returns instantly -- exactly
# as it was.
func _drive_transition(delta: float) -> void:
	if not BoardSpace.flight_active():
		if not _flight_drawn.is_empty():
			_clear_flight_maps()
		if _whiteout != null and _whiteout.visible:
			_apply_whiteout(0.0)
		return
	var landed := BoardSpace.advance_flight(delta)
	_sync_flight_maps()
	_drive_transition_camera()
	_drive_whiteout()
	if landed:
		return   # advance_flight bumped the version; _sync_staging re-seats the landed columns


# WHERE THE CAMERA WATCHES FROM, and the only thing the Experiments flag decides. The travel itself
# is identical either way -- a tile always runs between its socket and the diorama -- so this is a
# fork about the SHOT, not about the geometry, which is why knobs can tune within either arm.
#
# The cut is sanctioned: #520's "the camera should always pan, never teleport" is a rule about the
# map, and the dev carved this transition out of it by name (2026-08-27) -- "we can make an exception
# for the transition from the map view to the battle view".
func _drive_transition_camera() -> void:
	if Experiments.is_on(Experiments.Flag.DIORAMA_CAMERA_CUTS_AHEAD):
		# Already up there, over empty sky, before a single tile arrives.
		BoardSpace.drive_camera_lift(BoardSpace.stage_offset())
		return
	# Travelling with the tear-out: hold with the board long enough to see the tiles leave, then
	# rise. The hold is a knob whose 0 is exactly the cut's starting position, so the two treatments
	# meet in the middle rather than being separate code.
	var hold := maxf(Pacing.TEAR_OUT_CAMERA_HOLD, 0.0)
	var elapsed := BoardSpace.flight_elapsed()
	var lift := BoardSpace.stage_offset()
	if not BoardSpace.flight_entering():
		BoardSpace.drive_camera_lift(lift)
		return
	if elapsed <= hold:
		BoardSpace.drive_camera_lift(Vector3.ZERO)
		return
	BoardSpace.release_camera_lift()   # hand the height back; the rig eases the rest of the way


# One GridMap per tile in the air. Created on demand and freed the moment it lands, because a cell is
# a COLUMN and only a node transform carries a whole stack -- and because one map is one offset, so
# tiles arriving at different moments cannot share the landed lattice.
func _sync_flight_maps() -> void:
	var flying := BoardSpace.flying_cells()
	var wanted: Dictionary[Vector2i, bool] = {}
	for cell in flying:
		wanted[cell] = true
		if not _flight_drawn.has(cell):
			var map := GridMap.new()
			map.mesh_library = $StagedBoard.mesh_library
			map.cell_size = $StagedBoard.cell_size
			map.collision_layer = 0
			map.collision_mask = 0
			add_child(map)
			_flight_drawn[cell] = map
			_board_mirror.flight_maps[cell] = map
	for cell: Vector2i in _flight_drawn.keys():
		if not wanted.has(cell):
			_drop_flight_map(cell)
	# The transform is the whole point: the column sits at the diorama's cell coordinates and this
	# is what holds it short of them.
	for cell: Vector2i in _flight_drawn:
		var map: GridMap = _flight_drawn[cell]
		map.position = BoardSpace.stage_offset() + BoardSpace.flight_offset(cell)


# The flash that covers the swap. Ramp up, hold, ramp down -- and it STARTS where the treatment
# needs it to: at zero for the cut (it has to hide a camera teleport) and after the camera's hold for
# the travel arm (there is nothing to hide until you have watched the tiles leave).
func _drive_whiteout() -> void:
	var cuts: bool = Experiments.is_on(Experiments.Flag.DIORAMA_CAMERA_CUTS_AHEAD)
	var since := BoardSpace.flight_elapsed() - (0.0 if cuts else maxf(Pacing.TEAR_OUT_CAMERA_HOLD, 0.0))
	var ramp := maxf(Pacing.TEAR_OUT_WHITEOUT, 0.001)
	var hold := maxf(Pacing.TEAR_OUT_HOLD, 0.0)
	var level := 0.0
	if since >= 0.0:
		if since < ramp:
			level = since / ramp
		elif since < ramp + hold:
			level = 1.0
		elif since < ramp + hold + ramp:
			level = 1.0 - (since - ramp - hold) / ramp
	_apply_whiteout(level)


# #217's photosensitivity switch, which every white-out in this arc owes a reading of. The TIMING is
# identical either way, deliberately -- the transition's schedule is shared with the executor, so a
# shorter flash would desync the two -- and what changes is the CURVE and the PEAK: eased instead of
# linear, muted instead of white, and capped well below full.
#
# The cap is a const rather than a knob on purpose. Every other feel value in this slice is tunable,
# but a dev slider that could return this to 1.0 would quietly repeal the accessibility promise it
# exists to keep.
const WHITEOUT_SAFE_PEAK := 0.35
const WHITEOUT_SAFE_TINT := Color(0.72, 0.74, 0.80)


func _apply_whiteout(level: float) -> void:
	if level <= 0.0 and _whiteout == null:
		return
	if _whiteout == null:
		# Built in code rather than authored into the scene: it is a playback EFFECT owned by the
		# transition, not a UI control, and nothing else may address it.
		_whiteout = ColorRect.new()
		_whiteout.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_whiteout.set_anchors_preset(Control.PRESET_FULL_RECT)
		$UI.add_child(_whiteout)
	var safe: bool = PlayerSettings.is_on(PlayerSettings.Setting.PHOTOSENSITIVITY)
	var shown := smoothstep(0.0, 1.0, level) * WHITEOUT_SAFE_PEAK if safe else level
	var tint := WHITEOUT_SAFE_TINT if safe else Color.WHITE
	_whiteout.color = Color(tint.r, tint.g, tint.b, clampf(shown, 0.0, 1.0))
	_whiteout.visible = shown > 0.001


func _drop_flight_map(cell: Vector2i) -> void:
	var map: GridMap = _flight_drawn.get(cell)
	_flight_drawn.erase(cell)
	_board_mirror.flight_maps.erase(cell)
	if map != null:
		map.queue_free()


func _clear_flight_maps() -> void:
	for cell: Vector2i in _flight_drawn.keys():
		_drop_flight_map(cell)


func _sync_staging() -> void:
	if BoardSpace.staging_version == _staged_version:
		return
	_staged_version = BoardSpace.staging_version
	var now := BoardSpace.staged_cells()
	var touched: Dictionary[Vector2i, bool] = {}
	for cell in _staged_drawn:
		touched[cell] = true
	for cell in now:
		touched[cell] = true
	_staged_drawn = now
	$StagedBoard.position = BoardSpace.stage_offset()
	if touched.is_empty():
		return
	var cells: Array[Vector2i] = []
	cells.assign(touched.keys())
	# The props go FIRST: _reconcile_prop leaves a standing one alone when its tile and corners are
	# unchanged, which a tear-out does not touch -- so without this a crate stays on the board its
	# ground just left. The flames re-seat through OverlayMirror's own staging poll.
	for cell in cells:
		_board_mirror.drop_prop_at(cell)
	_board_mirror.sync_cells(game.grid, cells, game.board_heights,
			_board_mirror.floor_row_of(game.board_heights))


func _sync_terrain_while_authoring() -> void:
	if game.game_state != game.GameState.DEV_MODE:
		return
	var grid_dirty: DirtyCells = game.grid.dirty
	var height_dirty: DirtyCells = game.board_heights.dirty
	if not grid_dirty.pending() and not height_dirty.pending():
		return
	var heights: BoardHeights = game.board_heights
	var floor_row: int = _board_mirror.floor_row_of(heights)
	# A LOWERED (or raised) floor moves the bottom of every column on the board, so it is the one
	# edit no cell list can describe -- full sync, same as a bulk write that never had one.
	var whole_board: bool = grid_dirty.all or height_dirty.all or floor_row != _floor_row
	var cells: Array[Vector2i] = grid_dirty.cells()
	cells.append_array(height_dirty.cells())
	grid_dirty.clear()
	height_dirty.clear()
	_floor_row = floor_row

	var before := _board_rect
	if whole_board:
		_board_mirror.sync(game.grid, heights)
		_refresh_tops()
	else:
		_board_mirror.sync_cells(game.grid, cells, heights, floor_row)
		_update_tops(cells, floor_row)
	if _board_rect != before:
		_rig.rebound(_board_volume())


# The incremental twin of _refresh_tops, and it must keep the SAME invariant that one states:
# _tops and _board_rect are one fact in two shapes, never written apart.
#
# Growing the rect is O(1) (a merge), shrinking is not — a column removed from the middle changes
# nothing, one removed from an edge changes everything — so a removal pays for the full re-derive
# and a paint never does. Getting that backwards leaves panning and picking reaching a stale edge.
func _update_tops(columns: Array[Vector2i], floor_row: int) -> void:
	var shrank := false
	for column in columns:
		var top := BoardPicker.top_of($Board, column, floor_row)
		# NO_COLUMN, never `> 0` (#294): a dipped column's top IS 0, so the old gate sent it down
		# the erase branch — the poll did not merely miss a dip, it removed one already in _tops.
		if top != BoardPicker.NO_COLUMN:
			var known := _tops.has(column)
			_tops[column] = top
			if not known:
				var one := Rect2i(column, Vector2i.ONE)
				# An empty rect is Rect2i(), whose position is the ORIGIN rather than "nowhere", so
				# merging into it would drag every board's bounds back to (0,0).
				_board_rect = one if not _board_rect.has_area() else _board_rect.merge(one)
		elif _tops.erase(column):
			shrank = true
	if shrank:
		_board_rect = BoardPicker.used_rect(_tops)


# Public because the Look tab's Re-fit button calls it (#212): pitch and FOV feed the framing
# maths, which otherwise only runs on a board load, so tuning either leaves the shot stale.
#
# TWO answers to "where does the camera open", declared per Law #4 (#234): an AUTHORED pose on the
# board is AUTHORITATIVE, and _opening_volume below is the fallback for a board that authors none.
# Same shape as the objectives-vs-painted-zones guard in missions.md. Note the board already
# authors how WIDE it opens -- opening_view_cells rides the LookPreset it names -- so an authored
# start is a second influence over a different axis (where/which way/how far), not a duplicate;
# it simply retires the width knob for that board.
func fit_camera() -> void:
	var board := _board_volume()
	var start: CameraPose = game.scenario_manager.current_camera_start
	if start != null:
		_rig.pose(start.aim, start.yaw_degrees, start.distance, board)
		return
	_rig.frame(_opening_volume(board), board)


# What the Scenario tab's Capture button stores (#234). Here rather than in the dev tab for the
# same reason _describe_view is: only this scene knows what its own rig fields MEAN.
#
# The LIVE pose, never the _target_* twins -- you are capturing the shot you are looking at, not
# the one the smoothing is heading toward.
func capture_camera_start() -> CameraPose:
	var start := CameraPose.new()
	start.aim = _rig.position
	start.yaw_degrees = _rig.rotation_degrees.y
	start.distance = _camera.position.z
	return start


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


# What a bug report needs to know about the angle it was seen from (#240), pushed at
# BugReporter in _ready. Composed here rather than shipped out as a bag of numbers: only this
# scene knows what its own rig fields MEAN, and BugReporter.build_report_text stays pure.
#
# The LIVE yaw and distance, never their _target twins: a screenshot caught where the smoothing
# had reached, not where it was heading.
func _describe_view() -> String:
	return "%s -- yaw %.0f deg, zoom %.1f, centred on %s" % [
		View.keys()[view],
		_rig.rotation_degrees.y,
		_camera.position.z,
		BoardSpace.flat(BoardSpace.cell_of(_rig.position)),
	]


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
# sources and the 3D rig all stand down together. Anywhere else the 3D picker drives.
# Hover and the dev brush are two CONSUMERS of one question ("what cell is the 3D
# pointer over"), so they share a single source rather than each deriving their own.
func _apply_input_ownership() -> void:
	var flat: bool = view == View.FLAT_2D
	game.board_input_delegated = not flat
	if flat:
		game.hover_presenter.pointer_source = Callable()
		game.dev_controller.cell_source = Callable()
		game.dev_controller.vertex_source = Callable()
		_pointer_cell = BoardSpace.NO_CELL
		_overlays.clear(BoardOverlays.Layer.HOVER)
	else:
		var pointer_cell: Callable = func() -> Vector2i: return BoardSpace.flat(_pointer_cell)
		game.hover_presenter.pointer_source = pointer_cell
		game.dev_controller.cell_source = pointer_cell
		# The corner tool's own question (#427 slice 4), a THIRD consumer of the same pick. It gets
		# its own source rather than deriving off the cell one, because the answer changes within a
		# cell and a cell has already thrown that away.
		game.dev_controller.vertex_source = func() -> Vector2i: return _pointer_vertex


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
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_game_container.position = viewport_size - _pip_native * pip_scale - pip_margin


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
	# The two authoring-zone layers are skipped above because OverlayManager computes their
	# visibility from BOTH inputs — a blanket true here would reveal PATROL zones in play, and
	# a blanket false would be re-overridden the next time the Tile Brush tab changed. Telling
	# it whether the 2D draws at all is this host's half; it owns the product (#231).
	overlays.set_board_rendering(shown)


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
	_drive_transition(_delta)
	_sync_staging()
	# Separate from `live`, and deliberately so: while the AI acts or a menu is up the
	# rig must keep SMOOTHING (the mirror below drives it) while refusing the player.
	# Same predicate that refuses their clicks — one question, one answer.
	_rig.manual_input_enabled = demo_mode or not game._board_locked_for_player()
	# The ZOOM half rejoined the same gate in #602 round 4 (dev, 2026-08-29: "we control the camera,
	# fully. Their zoom gets overridden, period" -- restoring #520's own Done-when after the
	# 2026-08-26 carve-out left the wheel live under playback). One predicate, both halves: whoever
	# owns where the camera looks owns how far out it sits. The player's only way out of a pass is
	# the skip, which is #545's build.
	_rig.zoom_input_enabled = _rig.manual_input_enabled
	_poll_pointer()
	_sync_brush_bindings()
	_sync_brush_ghost()
	_sync_bracket_tint()
	_mirror_camera()


# The 3D view follows the action by MIRRORING the 2D camera, which is already the
# authority for where the action is (AIController pans it to each acting squad). No
# second follow seam, and because the 2D camera owns the tween the 3D inherits
# Pacing.AI_SQUAD_PAN exactly — one number, one reader.
#
# playback_locked is the gate, NARROWER than _board_locked_for_player(): the latter also covers
# MENU, and Mission Select opts out of the modal lock, so mirroring there would yank the rig
# to a stale 2D position the moment a menu opened. playback_locked IS the fact "the AI owns
# the 2D camera" — set in the same block as AI_TURN, cleared the moment it returns.
# Re-read every frame, never latched: a turn handoff can re-enter set_playback_locked inside
# the previous turn's stack, so the flag can legitimately flicker for a frame.
#
# Narrower, and since #484 strictly so: the board lock READS this flag, so whenever this gate
# is open _update_pointer's is shut. That is what keeps the two apart, and it has to be
# structural — they write to each other (this READS the 2D camera, _update_pointer WRITES it),
# so a frame running both marches the view to the pan limit on every mouse move. It used to
# rest on game_state carrying AI_TURN for the whole turn, which set_dev_mode falsified.
func _mirror_camera() -> void:
	var cam: CameraController = game.camera_controller
	# Square-on for the enemy phase (dev call 2026-08-14), on the EDGE into the turn rather
	# than every frame: idempotent either way today, but the moment orbit is allowed to stay
	# live under an AI turn a per-frame snap would fight the player's own drag.
	if cam.playback_locked != _playback_owned_camera:
		_playback_owned_camera = cam.playback_locked
		if _playback_owned_camera:
			# BEFORE the two resets below, or it stashes the reset rather than the player's own
			# framing. One edge serves every case the dev named (dev, 2026-08-26): a pass claims and
			# releases inside execute_orders, an AI turn holds it across the whole turn, and the
			# post-turn pass (#534) claims it again after that.
			_rig.stash_view()
			_rig.align_to_detent()
			# ...and frame from a known distance (#520). Still an EDGE, though the reason moved in
			# #602 round 4: the wheel is dead under playback now, so this is the director's own
			# opening base rather than a one-time reset the player zooms away from. The states
			# below re-aim it -- a stage widens it to fit, a followed unit pulls it to the trained
			# distance -- each on its own edge.
			_rig.set_zoom(_rig.playback_distance)
			# A fresh pass solves its own stage and holds no leftover fall: the same cells staged
			# twice in a row still describe different standing units, and a held depth belongs to
			# the show that latched it.
			_stage_cells_solved = []
			_held_drop = 0.0
			_trained_seen_id = 0
		else:
			_rig.restore_view()
	# ABOVE the early return, deliberately: how far the ground has been torn out is a fact about the
	# BOARD, not about who owns the camera (#521). The tiles thud back into their sockets INSIDE
	# execute_orders and the lock is put back in the same synchronous stretch, so a poll below the
	# return would never see a frame with the staging cleared and the rig would stay in the sky for
	# ever. The whole stage, never the cell under the camera: the diorama is one thing at one height,
	# and asking per cell would dip the camera every time a pan crossed unstaged ground.
	# ...and it asks where the CAMERA should be, which is the diorama's height at rest and something
	# the transition drives while one is running (#521 slice B). Equal whenever nothing is driving
	# it, so with the battle zoom off, or the flag off, this is bit-for-bit the old poll.
	_rig.lift_to(BoardSpace.camera_lift())
	# ...and how far below the board the rig has GOT, published back to playback (#602). ABOVE the
	# gate for the same reason the lift is, and it is the whole point: the climb home finishes after
	# playback lets go, so a poll below the return would freeze on the last value it saw and the
	# exit transition would wait for ever. The one fact that travels rig -> playback down this
	# channel; see CameraController.fall_depth for why it has to.
	cam.fall_depth = _rig.drop_depth()
	# ABOVE the early return for the same reason, and it is the whole point of the field: the readout
	# has to learn when a pass ENDS, and everything below here stops being polled the moment the lock
	# releases. Mirrored under the return -- where beat_profile sits -- it would hold the last pass's
	# answer and leave every bar on the board up for ever.
	_unit_mirror.cinematic_playback = cam.playback_cinematic
	if not cam.playback_locked:
		return
	# The 2D camera answers WHERE on the board; the board answers HOW HIGH. It used to keep
	# _rig.position.y, i.e. whatever the opening shot had left there — see _aim_over. Continuous
	# rather than per cell because this is a GLIDING pan: stepping the height at cell boundaries
	# would jolt the whole diorama mid-beat.
	#
	# HELD rather than glided (#520): the 2D camera this mirrors already tweens its own travel, so
	# easing on top of that ease is lag between the action and the frame it is in.
	# THE STAGE'S EDGE (#602 round 4): one height solve and one framing per published stage. On the
	# publish -- which the executor makes BEFORE its pan, so the whole approach aims at the stage
	# rather than hugging the ground under the moving centre -- solve where the fighters stand and
	# widen the shot until the staged volume fits; on the clear, back to the playback base. Edges,
	# never per-frame asserts: the walk phase's span widen and the dolly both live on this rig, and
	# a per-frame set_zoom would stomp them.
	if cam.shot_cells != _stage_cells_solved:
		_stage_cells_solved = cam.shot_cells.duplicate()
		_rig.set_zoom(_rig.playback_distance)
		if not _stage_cells_solved.is_empty():
			_stage_height = _solve_stage_height(_stage_cells_solved)
			_rig.widen_to_fit(_shot_volume(_stage_cells_solved))
	# ...and the TRAINED edge, its sibling: while the 2D camera is following one unit -- a beat's
	# subject, a body mid-tumble -- the shot sits at the trained distance, the close-up the dev
	# asked for. By id, so a body freed mid-beat reads as "nobody" and hands the distance back.
	var trained: Unit = cam.follow_unit if is_instance_valid(cam.follow_unit) else null
	var trained_id := trained.get_instance_id() if trained != null else 0
	if trained_id != _trained_seen_id:
		_trained_seen_id = trained_id
		_rig.set_zoom(Pacing.TRAINED_DISTANCE if trained != null else _rig.playback_distance)
	var flat := BoardSpace.of_pixels(cam.global_position, 0.0)
	var aim := _aim_over(flat.x, flat.z)
	_rig.hold_at(aim)
	# ...and how far the body it is watching sits ABOVE OR BELOW that aim (#602, re-based in round
	# 4). The aim answers where the STAGE is; this channel is what trains the shot's height on the
	# followed body itself -- riding a landing fall all the way down, riding a plummet as far as
	# the follow cap, aiming UP at a subject standing higher than the stage's mean. Handing it the
	# aim's own height is what makes the two channels one shot: camera height = aim - drop = the
	# body's stand height plus the framing lift, whatever either base does.
	_rig.drop_to(_fall_below(cam, aim.y))
	# ...and WHICH PROFILE the beat runs under (#647), mirrored FIRST because all three channels below
	# scale through it. It is what carries COMBAT_ONLY to a rig that has no beat in hand: a plain walk
	# publishes BOARD and the sway, the push-in and the yaw all land at zero strength.
	_rig.beat_profile = cam.beat_profile
	# ...and the 2D camera answers WHERE, while the beat answers FROM WHICH SIDE (#520). Polled
	# beside the position for the same reason it is: this is the one block that already runs every
	# frame under playback. Below the early return deliberately -- the release edge above restores
	# the player's own yaw, and re-aiming after it would undo the return in the same frame.
	_rig.aim_along(cam.directed_line)
	# ...and HOW BIG the beat is, the fourth of the same questions (#520 diff 2c). Polled beside the
	# angle rather than edged like the widen below, because it must relax as well as push: a quiet
	# beat publishes 0 and the camera eases back out on its own, with nothing to remember to undo.
	_rig.dolly_to(cam.beat_emphasis)
	# ...and HOW WIDE, the third of the same three questions (#520). An EDGE, never a per-frame
	# apply: the same rule the playback-distance reset above follows, so the shot is set up once and
	# the wheel is the player's again for the rest of it.
	if cam.framed_span != _framed_span:
		_framed_span = cam.framed_span.duplicate()
		if _framed_span.size() == 2:
			_rig.widen_to_fit(_span_volume(_framed_span))


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
	var click := event as InputEventMouseButton
	# The pointer moves BEFORE anything else consumes the event. DevController.cell_source
	# reads _pointer_cell, so a brush routed ahead of this would paint the cell the cursor
	# just LEFT — one cell of lag, smeared down the whole stroke.
	if motion != null:
		if _rig.is_orbiting():   # a drag is camera work, not pointing
			return
		_update_pointer(motion.position)
	elif click != null and click.pressed:
		_update_pointer(click.position)  # a click is also a point — robust when no motion preceded it
	# Armed, the brush owns the mouse outright — the same precedence game.gd gives it above
	# its own board handlers, so RMB erases here instead of cancelling. BOTH button edges go
	# through: paint and erase are hold-to-drag, and forwarding presses only would strand the
	# drag flag TRUE and paint for ever.
	if (motion != null or click != null) and game.dev_controller.brush_armed():
		if _handle_brush_zoom(click):
			return
		game.dev_controller.handle_tile_brush(event)
		return
	if motion != null:
		return
	if key != null and key.pressed and key.keycode == KEY_SPACE:
		_handle_space()
		return
	if click == null:
		return
	if click.button_index == MOUSE_BUTTON_RIGHT:
		_handle_cancel_button(click)
		return
	if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_click_pointer_cell()


# Ctrl+wheel zooms while the elevation brush owns the plain wheel (#285). The rig cannot answer
# this one itself: _sync_brush_bindings has stood its wheel down for the duration, because it is a
# CHILD of this node and sees _unhandled_input FIRST — consuming the event up here lands after the
# zoom has already happened (measured, and it is why the obvious fix is not the one that shipped).
# Returns true when the notch was spent here.
func _handle_brush_zoom(click: InputEventMouseButton) -> bool:
	if click == null or not click.pressed or not click.ctrl_pressed:
		return false
	if not game.dev_controller.elevation_brush_live():
		return false
	if click.button_index == MOUSE_BUTTON_WHEEL_UP:
		_rig.zoom_by(-1)
	elif click.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_rig.zoom_by(1)
	else:
		return false
	return true


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


# The pointer POLLS the mouse as well as riding motion events — the 2D ghost's lesson, found
# in play again here (#231). While the Dev Tools OS window holds focus the game window receives
# no motion events at all, so an event-only pointer sits STALE until a click refocuses: no tile
# highlight, no brush ghost, until you click the window twice. DevController's ghost already
# polls for exactly this and its comment says so; the 3D pointer had re-derived the event-only
# version and brought the bug back with it.
#
# The event path in _unhandled_input STAYS — it has to run before the brush routing inside the
# same frame, or a drag paints the cell the cursor just left. So this is a FALLBACK, not a
# second authority, and the cursor-moved check is what keeps it one: an unconditional poll
# re-answers the pointer every frame from a source the event path may legitimately disagree
# with, which reds test_pointing_snaps_the_hidden_camera_to_the_hovered_cell and
# test_the_3d_camera_follows_the_ai_camera the moment it is written that way (measured).
# 2D has no such tension because DevController._mouse_cell() reads the mouse LIVE and caches
# nothing; the 3D pointer is a cache, so it needs the guard.
func _poll_pointer() -> void:
	if demo_mode or view == View.FLAT_2D:
		return
	if not game.can_process() or game._board_locked_for_player():
		return
	if _rig.is_orbiting():   # a drag is camera work, not pointing — same rule the events use
		return
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var camera_now := _camera.global_transform
	if mouse == _last_polled_mouse and camera_now == _last_polled_camera:
		return
	_last_polled_mouse = mouse
	_last_polled_camera = camera_now
	_update_pointer(mouse)


# The hover bracket goes RED over anything the 2D calls invalid (#245, asked for in play after the
# groundless-state forbid started refusing paints SILENTLY). It MIRRORS CursorController's state
# rather than deciding for itself: the 2D already answers "is the thing under the pointer valid"
# — in dev mode, unwalkable or occupied — and a groundless cell is unwalkable, which is exactly the
# refusal that prompted this. Re-deriving it here would be a second answer free to disagree with
# the cursor sitting right next to it, which is the #232 shape.
func _sync_bracket_tint() -> void:
	if demo_mode:
		return
	var invalid: bool = game.cursor_controller.state == CursorController.CursorState.INVALID
	var restore: Color = _overlays.authored_color(BoardOverlays.Layer.HOVER)
	var color: Color = _overlays.invalid_bracket_color if invalid else restore
	_overlays.set_layer_modulate(BoardOverlays.Layer.HOVER, color)   # skip-if-equal inside


# The 3D half of the brush preview. POLLED off the brush's own intent, never hooked at the
# paint site — the mirror stack's zero-hooks doctrine, and the same call PR 1 made for terrain.
# The 2D ghost keeps running underneath as the tile source; it simply draws under a hidden board
# here, which is why this asks brush_ghost() and not that layer's `.visible`. Since #285 that
# answer is per MODE, so an ELEVATION preview — a block at the level the wheel is set to — comes
# through the same call rather than needing a second one.
func _sync_brush_ghost() -> void:
	if demo_mode or view == View.FLAT_2D:
		_board_mirror.hide_brush_ghost()   # the flat view has the 2D ghost for this
		return
	var ghost: BrushGhost = game.dev_controller.brush_ghost()
	if ghost == null:
		_board_mirror.hide_brush_ghost()
		return
	_board_mirror.show_brush_ghost(ghost)


# The brush erases on RIGHT, so orbit steps aside to MIDDLE while it is armed — 2D and 3D keep
# identical bindings (dev ruling), and 2D's brush already owns RMB. The BINDING is declarative
# every frame: the rig's setter early-outs on an unchanged write and releases a live drag on a
# real one, which is exactly why that setter exists. The LABEL is rebuilt only on the edge,
# because it allocates a string and nothing else on this path does per frame.
func _sync_brush_bindings() -> void:
	if demo_mode:
		return   # no 2D game to ask, and the demo label is not this function's to overwrite
	var armed: bool = game.dev_controller.brush_armed()
	var dev: bool = game.game_state == game.GameState.DEV_MODE
	# The elevation brush paints at the WHEEL's level (#260), so the camera gives the wheel up for
	# as long as that mode is live — scoped to it, because the other three paint modes never read
	# the wheel and would be losing zoom for nothing. Ctrl+wheel is where zoom goes meanwhile.
	var wheel_is_level: bool = game.dev_controller.elevation_brush_live()
	_rig.orbit_button = MOUSE_BUTTON_MIDDLE if armed else _orbit_button_default
	_rig.wheel_zoom_enabled = not wheel_is_level
	# The help line names the wheel and SPACE, so every MODE they depend on joins the edge — a
	# one-shot label goes stale the moment its input starts varying, which is the trap this label
	# already fell into once over the orbit button.
	var can_spawn: bool = game.dev_controller.spawn_armed()
	if armed == _help_brush_armed and dev == _help_dev_mode \
			and wheel_is_level == _help_wheel_is_level and can_spawn == _help_can_spawn:
		return
	_help_brush_armed = armed
	_help_dev_mode = dev
	_help_wheel_is_level = wheel_is_level
	_help_can_spawn = can_spawn
	_update_help()


# Every binding this label names can now CHANGE at runtime, so it is rebuilt from the live
# state instead of snapshotted at _ready. The orbit button was already a knob the label had
# to read — it once still said MMB after the binding was flipped — and #231 gives right-click
# and SPACE second meanings while the brush is armed and while dev mode is up. A one-shot
# string would tell exactly that lie again, one release later.
func _update_help() -> void:
	var orbit := "RMB" if _rig.orbit_button == MOUSE_BUTTON_RIGHT else "MMB"
	# Right-click carries two verbs since #228 and the label names both in the order they fire:
	# it leaves an open aim first, and only from a board at rest does it undo the last order.
	var right := "RMB erase" if game.dev_controller.brush_armed() else "RMB cancel/undo"
	# The SAME predicate the gate reads (_handle_space), never a second answer -- this line said
	# "spawn" for every dev page while only the Spawn one could, which is the bug it was describing.
	var space := "SPACE spawn" if game.dev_controller.spawn_armed() else "SPACE centre"
	var wheel := "wheel level  |  Ctrl+wheel zoom" if game.dev_controller.elevation_brush_live() else "wheel zoom"
	# The drag turns AND tilts since #586, so the line says both -- a readout that names a gesture has
	# to name what the gesture actually does, or it goes stale against the control it describes.
	_help.text = "Battle3D  |  LMB act  |  %s  |  %s-drag orbit/tilt  |  Q/E realign  |  %s  |  WASD pan  |  %s  |  R reset  |  F4 flat 2D  |  Shift+F4 corner" % [right, orbit, wheel, space]
	_fit_help_plate()


# WHICH CHECKOUT is on screen (#295) — several agents move the dev's working tree, so the build he
# is playing is a fact worth reading rather than remembering. A LABEL OF ITS OWN, not a field of
# the help line: that line is rebuilt from live bindings and rewritten wholesale in demo_mode,
# while this is fixed for the process, and a suffix on a 140-character string is exactly the kind
# of absence nobody notices. Set once — describe() names the checkout this build was LOADED from,
# and re-reading per frame would answer about the tree instead, which is a different question.
#
# This UI CanvasLayer sits above the 2D game's container in all three hosting views, so the
# readout survives F4 into FLAT_2D (#292 parity). Hidden, not blanked, outside a dev build.
func _show_checkout() -> void:
	var stamp := Checkout.describe()
	_checkout.visible = stamp != ""
	_checkout.text = stamp
	_fit_help_plate()


# IS DEV MODE ON — the badge is PRESENT or it is not, so there is no off-state to misread. Reads
# the INTENT off game.dev_mode_changed, never game_state == DEV_MODE: that one is derived and
# drops out the moment any other mode is entered, so a badge on it would blink off mid-click.
#
# A third label in the same stack for _show_checkout's reason: this CanvasLayer draws above the 2D
# game's container in every hosting view, so one node covers HD_2D and FLAT_2D alike (#292) --
# and a word appended to the help line is invisible in a 140-character string, which is the
# problem this is fixing rather than a shape to copy.
func _show_dev_badge(active: bool) -> void:
	_dev_badge.visible = active
	_fit_help_plate()


# The plate is fitted to the TEXT, not to the labels (#498). Each label is authored 900px wide so a
# rebuilt help line never reflows, which means their rects say nothing about where the words end --
# a plate sized to them would be a bar across most of the screen. So the width comes from the font
# measuring each live string, and the height from the authored rows, which is what keeps their
# spacing. Hidden when nothing is showing, since an empty plate is a smudge in the corner.
#
# Called from all three writers rather than polled: every one of them can change what is on screen
# (the help line rebuilds as the brush arms, the checkout hides outside a dev build, the badge
# toggles with dev mode), and a plate sized on a stale set is the artifact this is fixing.
func _fit_help_plate() -> void:
	var bounds := Rect2()
	var found := false
	for label: Label in [_help, _checkout, _dev_badge]:
		if not label.visible or label.text.is_empty():
			continue
		var font := label.get_theme_font(&"font")
		var width: float = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				label.get_theme_font_size(&"font_size")).x
		var line := Rect2(label.position, Vector2(width, label.size.y))
		bounds = line if not found else bounds.merge(line)
		found = true
	_plate.visible = found
	if not found:
		return
	_plate.position = bounds.position - HELP_PLATE_PAD
	_plate.size = bounds.size + HELP_PLATE_PAD * 2.0


# Writes THROUGH to the stylebox rather than storing and hoping: a knob whose value is only read
# where the plate is built moves nothing until the next rebuild. Guarded because an @export setter
# runs at instantiation, before @onready assigns the node -- _ready re-applies it for that case.
func _set_help_plate_alpha(value: float) -> void:
	help_plate_alpha = value
	if _plate == null:
		return
	var box := _plate.get_theme_stylebox(&"panel") as StyleBoxFlat
	if box != null:
		box.bg_color.a = value


# SPACE means two things, and dev mode wins — exactly how game.gd's own SPACE arm resolves
# it (#231). The 3D view is not a reason for a key to mean something different than it does
# in the flat one; the only difference is where the cell comes from.
# SPACE spawns only while the SPAWN PAGE is showing (dev, 2026-08-23) — it was gated on DEV_MODE
# alone, so pressing space while brushing spawned a unit. This is the 3D half of a question asked in
# TWO places: game.gd's own handler is the 2D one, and both now read DevOverlay.showing rather than
# each deciding what "the spawn tool is up" means.
func _handle_space() -> void:
	if game.dev_controller.spawn_armed():
		if _pointer_cell != BoardSpace.NO_CELL:
			game.dev_overlay.spawn.try_spawn_at(BoardSpace.flat(_pointer_cell))
		return
	_center_on_pointer()


# SPACE recentres the diorama on whatever the pointer is over — the 3D answer to the 2D
# camera's centre-on-mouse, which the delegation gate makes unreachable in this host.
# Kept here so game.gd's one bool stays the arc's only edit to its input path.
func _center_on_pointer() -> void:
	if _pointer_cell == BoardSpace.NO_CELL:
		return
	_center_rig_on(BoardSpace.flat(_pointer_cell))


# THE recentre, and the one answer to "put the rig over this cell": SPACE above, and #471's return
# to the acting unit, which arrives as game.view_focus_requested. A GLIDE since #520 -- both are
# board play, which is exactly the scope the dev put the never-teleport rule at (2026-08-27: "that
# only applies while we're on the map"). It snapped until then because the rig smoothed yaw and
# distance but not position; now it smooths all three.
#
# The HEIGHT comes from the cell, and that is the whole of the fix the dev's Level_1 report forced
# (2026-08-23). surface_point is the cell-shaped door onto the same surface plane _aim_over
# evaluates continuously — one authority, two entry points BoardSpace already ships (#273 / #259),
# and it is the seam UnitMirror places the sprite with, so the camera looks where the unit IS.
#
# surface_point carries the STAGED offset while _aim_over does not, so a call here while the board
# is torn out would lift the rig twice -- once through the point and once through the rig's own lift
# channel. Structurally unreachable rather than guarded: both callers are refused while playback
# owns the board (SPACE by _unhandled_input's lock check, an order commit by there being no pass
# running to commit during), and playback is the only thing that stages anything.
func _center_rig_on(cell: Vector2i) -> void:
	_rig.glide_to(BoardSpace.surface_point(cell, game.board_heights))


# THE aim point for a continuous world x/z — the AI pan's twin of _center_rig_on, which has a cell.
#
# Read this against CameraRig3D._aim_at, which lifts the OPENING shot to the top of the whole board
# volume so the pitch looks down at the surface rather than through it. That is right for FRAMING a
# board and wrong for LOOKING AT something standing on one, and until 2026-08-23 nothing ever
# re-derived it: every recentre kept _rig.position.y, so on Level_1 (columns to level 4, and an
# authored start that froze aim.y = 5) the camera aimed four cells into the air above whatever it
# had been pointed at. Invisible on a flat board, which is why Prolog never showed it.
func _aim_over(x: float, z: float) -> Vector3:
	# WHILE A FIGHT IS ON STAGE THE HEIGHT IS THE STAGE'S, NOT THE GROUND'S (2026-08-29, found in
	# play). The lift channel has always said this -- "the whole stage, never the cell under the
	# camera" -- and round 3 applied it to the aim. Round 4 moved the read to the PUBLISHED stage,
	# cam.shot_cells, which the executor sets before its pan: gated on BoardSpace._staged (filled
	# only at stage()) the approach still hugged the terrain under the moving centre, scaling a
	# cliff face on the way in and whiting out against it. The lift the fighters are framed with is
	# added HERE, over a raw solved mean, so the fall channel can reason about the same base.
	var cam: CameraController = game.camera_controller
	if not cam.shot_cells.is_empty():
		return Vector3(x, _stage_height + Pacing.STAGE_AIM_LIFT * BoardSpace.CELL_SIZE, z)
	var cell := Vector2i(floori(x), floori(z))
	return Vector3(x, BoardSpace.surface_height_at(cell, x, z, game.board_heights), z)


# The one height the diorama sits at: the RAW mean of the ground under the UNITS ON STAGE -- the
# framing lift goes on in _aim_over (dev, 2026-08-29: *"the units need to be at the center"*).
#
# It was the mean of every STAGED CELL for one round and that is wrong in a specific way.
# BeatSheet._gather_cells puts the whole KNOCKBACK PATH on stage -- correct for the ground, since a
# shoved body has to land on something -- so a shove off a pillar tears out the pillar top AND every
# plain cell the body flew across, and averaging that ground drags the shot down between them. The
# camera ended up staring at the pillar's wall with the fight above the frame, and the further a body
# was thrown the worse it got. What the shot is about is where the PEOPLE are.
#
# SOLVED ONCE PER PUBLISH, at the _mirror_camera edge (dev's pick: *stage height held, dip for a
# fall* -- the latch law cost two surviving mutants in round 3, and the round-4 trained shot is
# what made the dip half real). What the latch buys: bodies get THROWN during a pass, and a live
# re-solve would find them standing on whatever ground they landed on and walk the whole diorama's
# shot down after them, mid-fight. The trained shot follows its OWN subject through exactly that --
# the latch keeps everyone else's throw from dragging the establishing base along.
#
# Reads the GROUND under each unit rather than their stand height because the stage's height is a
# property of the ground, not of who happens to be standing on it -- and at the publish edge nothing
# is falling yet, so no case can tell the two apart. Kept for what it MEANS.
#
# The FALLBACK is the staged ground itself, for a pass whose stage nobody is standing on -- a
# cell-effect deposit, or a body freed between the resolve and this frame. Non-empty cells are the
# caller's contract (the edge only solves a published stage).
func _solve_stage_height(cells: Array[Vector2i]) -> float:
	var on_stage: Dictionary[Vector2i, bool] = {}
	for cell in cells:
		on_stage[cell] = true
	var heights: BoardHeights = game.board_heights
	var total := 0.0
	var counted := 0
	for child in game.units_root.get_children():
		var unit := child as Unit
		if unit == null:
			continue
		var cell := UnitMirror.cell_under(unit)
		if not on_stage.has(cell):
			continue
		total += BoardSpace.surface_point(cell, heights).y
		counted += 1
	if counted == 0:
		for cell in cells:
			total += BoardSpace.surface_point(cell, heights).y
		counted = cells.size()
	return total / float(counted)


# ...and the vertical half the aim above cannot answer (#602, re-based in round 4): how far above
# or below the aim to take the shot so it is TRAINED on the body the camera is following -- riding
# a landing fall all the way to the ground, riding a void plummet as far as the follow cap and no
# further, aiming up at a subject standing higher than the stage's mean. In world units, signed.
#
# The fall is UnitMirror.fall_depth's own, never re-derived -- that node places the sprite from
# the same arithmetic, so the shot and the body cannot end up at different heights, and a second
# spelling of exactly this fall is what #472 was filed for. Negative depth (a body in the air over
# a hole, holding its lip's height) rides the shot UP the same way, uncapped: only the descent has
# a follow limit, because only a death fall has no end to ride to.
#
# HANDED THE AIM'S OWN HEIGHT, this frame's, because the depth is a difference of the two bases the
# shot is actually built from: camera height = aim - drop, so drop = aim - (body + lift) makes the
# camera sit at the body plus the framing lift EXACTLY, whatever either base does. The round-2
# spelling measured the fall from the surface under the unit instead -- its own base -- which
# agreed with the aim's base only on flat ground; on a fight staged above the pit the two differed
# by the whole cliff, and the burst it anchored was never on screen (the pillar board, found in
# play). A base-step under the unstaged aim eases through this channel as a transient rather than
# cancelling exactly; the staged aim -- every showpiece -- is flat, so the ride there is exact.
#
# The follow cap is the body's own surface minus the knob: only a plummet descends below its
# surface, so a landing fall never meets it and rides free, which is the round-4 ruling ("a close
# up of that unit's tumble, all the way through").
#
# The guard is is_instance_valid BEFORE the typed read (#149): a void plummet ends in die(), and a
# freed Unit assigned into a typed slot dies on the type-check before any null test can run. A
# freed body hands the answer to the death show's hold.
func _fall_below(cam: CameraController, aim_y: float) -> float:
	if not is_instance_valid(cam.follow_unit):
		return _death_show_depth()
	var watched: Unit = cam.follow_unit
	var heights: BoardHeights = game.board_heights
	var surface := BoardSpace.surface_point(UnitMirror.cell_under(watched), heights).y
	var fall := minf(UnitMirror.fall_depth(watched, heights),
			Pacing.CLIFF_FOLLOW_MAX * BoardSpace.CELL_SIZE)
	var lift := Pacing.STAGE_AIM_LIFT * BoardSpace.CELL_SIZE \
			if not cam.shot_cells.is_empty() else 0.0
	var depth := aim_y - (surface - fall + lift)
	_held_drop = depth
	return depth


# What the fall channel answers once its body is gone (#602 round 4): a void death frees the unit
# mid-shot, and the camera used to start climbing the same frame the burst fired -- racing, and at
# any recover rate beating, the very show the hold at the bottom exists for. So the shot HOLDS the
# last depth the body published for as long as the burst's cubes are in the air, and only then
# hands the channel its zero. The claim edge and drop_stashed_view (the board-swap door) both
# zero the held value, so neither a new pass nor a new board inherits a dead show's pit.
func _death_show_depth() -> float:
	if _unit_mirror.death_show_live():
		return _held_drop
	_held_drop = 0.0
	return 0.0


# Where the bottom of the shot is, in world y -- the anchor a void death's burst erupts from,
# handed to UnitMirror as a callable (#602 round 4). The rig's node position IS the aim point (the
# camera sits back from it on a child), already carrying the stage lift and the fall, so this is
# the frame the player is actually watching -- not a re-derivation of where it ought to be.
#
# The offset is a CONST, not a knob, on WHITEOUT_SAFE_PEAK's reasoning: every other feel value in
# this arc is tunable, but a slider that could push the death show out of shot would quietly repeal
# the invariant this round exists to keep (dev, 2026-08-29: "I'll *always* want the death cubes in
# shot").
const PLUMMET_BURST_UNDER := 1.5

func _shot_floor() -> float:
	return _rig.position.y - PLUMMET_BURST_UNDER * BoardSpace.CELL_SIZE


# The box a framed span (#520) must fit inside: the two cells' own surface points, through the same
# seam UnitMirror stands a sprite with, so a walk that climbs is framed on the height it really
# ends at. The rig grows it by its own fit margin -- only this scene knows the cells, only the rig
# knows fov, aspect and pitch (Law #4: pass, don't look up).
func _span_volume(span: Array[Vector2i]) -> AABB:
	var heights: BoardHeights = game.board_heights
	return AABB(BoardSpace.surface_point(span[0], heights), Vector3.ZERO) \
			.expand(BoardSpace.surface_point(span[1], heights))


# ...and the whole STAGE's box (#602 round 4), for the WIDE shot: every staged cell's surface
# point, not two corners -- a stage is not a span, and the tallest ground in the middle of one is
# exactly what a corner pair misses. Small by nature (a fight's cells), so the loop is nothing.
func _shot_volume(cells: Array[Vector2i]) -> AABB:
	var heights: BoardHeights = game.board_heights
	var box := AABB(BoardSpace.surface_point(cells[0], heights), Vector3.ZERO)
	for cell in cells:
		box = box.expand(BoardSpace.surface_point(cell, heights))
	return box


func _update_pointer(screen_pos: Vector2) -> void:
	var cell := _pick(screen_pos)
	# The VERTEX is answered ABOVE the early-out, and that placement is the whole of #471's law
	# applied here: an early-out is a copy of the render key on the INPUT side, so a poll has to
	# compare every input its answer depends on. The corner tool's answer changes halfway ACROSS a
	# cell, so the cell compare below would pin the marker to whichever corner it first landed on.
	# Everything under it is genuinely cell-keyed and stays there.
	_pointer_vertex = _vertex_under(screen_pos, cell)
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


# Which unit the pointer resolves to, for UnitMirror's health readout (#229). Deliberately the
# SAME expression HoverPresenter._process runs — the 2D stays the one authority on what the
# pointer is over, and any other way of asking (nearest sprite, a 3D ray against units) would be
# a second answer free to disagree with the one a CLICK uses. Note it reads through
# unit_at_pointer, so it answers at the PROJECTED cell, which is what the readout anchors to.
#
# Wired in _ready rather than in _apply_hosting: it holds in FLAT_2D too, where last_hovered_cell
# comes off the 2D mouse instead of the 3D pick. Nothing renders the diorama there, so the bar is
# simply unseen rather than needing a branch.
func _hovered_unit() -> Unit:
	var presenter: HoverPresenter = game.hover_presenter
	var hovered: Unit = game.unit_at_pointer(presenter.last_hovered_cell)
	return hovered


# The plan being previewed, for UnitMirror's predicted readout (#313). resolved_plan_for guards on
# squad identity, so this is null whenever nothing is being commanded — no active squad, and an AI
# squad's own resolve (which never matches the player's active squad) — and the ghosts are simply
# absent rather than showing somebody else's intentions.
#
# While a pass is RUNNING that question has a better answer than the last resolve (#354): the plan
# being executed. #361 closed the divergence at its source — refresh_action_queue now refuses to
# re-derive mid-pass, so the last resolve IS the executing plan — but the preference stays: it costs
# nothing and it does not lean on that gate holding. One function still answers "which plan"; it
# just knows a live pass outranks a stale resolve.
func _previewed_plan() -> ResolvedPlan:
	var executing: ResolvedPlan = game.order_executor.executing_plan
	if executing != null:
		return executing
	var squads: SquadManager = game.squad_manager
	return squads.resolved_plan_for(squads.active_squad)


# ...and who its end-of-turn effect pass is about (#534). A separate question from the plan because
# that phase has none -- see OrderExecutor.effect_pass_subjects.
func _effect_pass_subjects() -> Dictionary[int, bool]:
	var subjects: Dictionary[int, bool] = game.order_executor.effect_pass_subjects
	return subjects


func _cancel() -> void:
	if game._board_locked_for_player():
		return
	# Mirrors game.gd's own RMB arm: cancel is position-blind, and DEV_MODE keeps
	# right-click for the tile brush.
	if game.game_state != game.GameState.DEV_MODE:
		game._on_right_click()


# ONE pick, whichever question is live (#582). The brush's aim-at-height mode replaces the geometry
# walk here rather than beside it, so cell_source, pointer_source and _vertex_under keep reading the
# single _pointer_cell below -- hover, the ghost, paint, erase and the corner tool cannot come to
# different conclusions about where the mouse is, which is the whole reason this funnel exists.
func _pick(screen_pos: Vector2) -> Vector3i:
	var row: int = game.dev_controller.brush_pick_row()
	if row != BoardPicker.NO_COLUMN:
		return BoardPicker.pick_at_height(_camera, screen_pos, row, _paint_plane())
	return BoardPicker.pick_at(_camera, screen_pos, _tops, _paint_plane())


# Which grid vertex a pick is nearest (#427 slice 4). The picker answers a CELL, so the sub-cell half
# is recovered by dropping the same ray onto that cell's top plane and reading where it lands.
#
# APPROXIMATE on sloped ground and deliberately so: the plane is the cell's top face, which for a
# ramp is its high edge rather than its actual surface, so a grazing view can pull the reading toward
# the uphill corner by a fraction of a cell. It is exact on flat ground — which is what a hill is
# built out of — the marker shows the answer before any click commits it, and the alternative is a
# per-form ray/triangle intersection in the hot pointer path for a dev tool.
func _vertex_under(screen_pos: Vector2, cell: Vector3i) -> Vector2i:
	if cell == BoardSpace.NO_CELL:
		return _pointer_vertex
	var column := BoardSpace.flat(cell)
	var origin := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	if is_zero_approx(dir.y):
		return _pointer_vertex   # looking along the surface: no crossing to read
	var hit := origin + dir * ((BoardSpace.surface_y(cell.y) - origin.y) / dir.y)
	return Terrain.vertex_near(column,
			hit.x / BoardSpace.CELL_SIZE - float(column.x),
			hit.z / BoardSpace.CELL_SIZE - float(column.y))


# Where a click still lands with no block under it (#231): the painted board plus the
# authoring apron, so an erased cell stays clickable and painting can still grow the
# board outward the way the 2D view allows.
func _paint_plane() -> Rect2i:
	return _board_rect.grow(paint_apron_cells)


# What a landed blow is worth (#520 diff 2b jolt, 2c freeze). The mirror observes the instant and
# names its KIND; the amplitudes and the freeze length are Pacing's, and choosing between them is
# this node's, because the rig owns one of the two consequences and the world owns the other.
#
# GATED ON PLAYBACK OWNING THE CAMERA, and the freeze is why. A jolt is already safe on its own --
# the rig's flourish channel is dead unless the view is borrowed -- but a time freeze is global, so
# ungated a die() from any source (a dev-tool kill, a board teardown) would stop the game dead. Same
# question the flourish gate asks, asked one layer up because the answer has to reach further.
func _on_impact(kind: int) -> void:
	if not game.camera_controller.playback_locked:
		return
	if kind == UnitMirror.Impact.DOWN:
		_rig.shake(Pacing.SHAKE_DOWN)
		# Fire-and-forget: the freeze runs on real time and ends itself, and awaiting it here would
		# stall the mirror's own reconcile inside a frozen frame.
		# The beat's OWN profile (#647), read off the published channel rather than a global -- an
		# impact is by definition a combat beat, so COMBAT_ONLY freezes here exactly as ALWAYS does,
		# but saying so through the publish keeps one answer instead of a second rule that agrees.
		Pacing.hitstop(self, Pacing.HITSTOP_DOWN * Pacing.hitstop_of(game.camera_controller.beat_profile))
		return
	_rig.shake(Pacing.SHAKE_HIT)
