extends Node
class_name HoverPresenter

# Turns "where is the mouse" into board feedback: cursor state/position, the hover info card,
# range + preview overlays, and the queue panel's row-hover highlight. Pulled out of game.gd
# 2026-07-26, where it lived as one 133-line per-state switch; holds a back-ref to the Game
# coordinator (same pattern as DevController/AIController/MainActionMenu).
#
# Detection lives here too: _process watches for a hovered-CELL change and fires the two
# signals. This node is its own first listener (see _ready), so external listeners -- wired
# from game._ready -- always run after it.
#
# Explicit types throughout this file: `game` is untyped (game.gd has no class_name), so every
# game.* call reads as Variant and `:=` cannot infer from it.
#
# One branch per GameState, mirroring game.gd's click handlers. The branches are read-only on
# game state; anything that needs to MUTATE it belongs on the coordinator. The one deliberate
# exception is CHOOSING_MOVE, which re-validates the squad plan as the mouse sweeps: that live
# preview IS the feature (CLAUDE.md's Actions bullet), not a leak.

signal hovered_cell_changed(cell: Vector2i)
signal hovered_unit_changed(previous_unit: Unit, new_unit: Unit)

var game   # the Game coordinator (Node2D); set by game._ready()

# Injectable pointer-cell source (#222, the board_source shape): a host whose pointer
# is NOT this viewport's mouse (the 3D picker) supplies the hovered cell directly.
# Unset = the mouse derivation below, i.e. the flat 2D game is untouched.
var pointer_source: Callable

var last_hovered_cell: Vector2i = GridUtils.NO_CELL

var _highlighted_queue_units: Array[Unit] = []

func _ready() -> void:
	# Self-wiring: this node is both the detector and the first listener of its own signals.
	hovered_unit_changed.connect(_on_hovered_unit_changed)
	hovered_cell_changed.connect(update_hover_visuals)

func _process(_delta: float) -> void:
	var hovered_cell: Vector2i
	if pointer_source.is_valid():
		hovered_cell = pointer_source.call()
	else:
		var mouse_world: Vector2 = game.get_global_mouse_position()
		hovered_cell = game.grid.local_to_map(game.grid.to_local(mouse_world))

	if hovered_cell == last_hovered_cell:   # everything below only runs on a CELL change
		return

	var previous: Unit = game.unit_at_pointer(last_hovered_cell)
	var current: Unit = game.unit_at_pointer(hovered_cell)
	hovered_unit_changed.emit(previous, current)
	hovered_cell_changed.emit(hovered_cell)
	last_hovered_cell = hovered_cell

# ==============================================================================
#  Board hover, per mode
# ==============================================================================

# Repaint for wherever the mouse already is, without waiting for a cell change -- for when the
# MODE changed under a stationary mouse (a menu closing, for one).
func refresh() -> void:
	update_hover_visuals(last_hovered_cell)


# The enemy under the pointer, or null -- the TRANSIENT half of what the range view draws (#710
# slice 3). Asked by game._redraw_enemy_ranges' callers, which can fire from a key or a pin rather
# than from a pointer move and so have no hovered unit in hand.
func hovered_enemy() -> Unit:
	var unit: Unit = game.unit_at_pointer(last_hovered_cell)
	if unit == null or not is_instance_valid(unit):
		return null
	return unit if Team.is_enemy(Team.Faction.PLAYER, unit.get_faction()) else null

func update_hover_visuals(hovered_cell: Vector2i) -> void:
	_clear_threat_markup()   # cleared on every cell change; the branch that wants it draws it back
	if game.grid.get_cell_tile_data(hovered_cell) == null:
		# Off the map -- every mode draws nothing out there. CLEARING is part of drawing nothing
		# (#582): a bare return left the last card standing, so the readout went on describing a
		# cell the pointer had left, and while chasing an unclickable tile it insisted the cell was
		# at height -1 when the board said -3. A card that cannot be trusted to be about NOW is
		# worse than no card.
		game.hover_info_panel.clear()
		return

	# Only IDLE produces squad icons. They're collected rather than drawn inline because that
	# branch clears icon types partway through; drawing once at the end survives the clear.
	var icons_to_draw := {}
	var state = game.game_state

	if state == game.GameState.DEV_MODE:
		_hover_dev_mode(hovered_cell)
	elif state == game.GameState.IDLE or state == game.GameState.PRE_MISSION:
		# The phase reads the board the way an idle board reads (#739): a cursor, a card on every
		# tile, and an enemy inspectable exactly as the mission will show them -- which is #731
		# ruling 6's whole point, that the preview is the board rather than a second rendering of
		# it. It shares IDLE's branch rather than getting one of its own because every readout in
		# there takes a wielder with a real cell, and a deployed unit has both. The squad icons come
		# along, and should: squads are being BUILT here.
		icons_to_draw = _hover_idle(hovered_cell)
	elif state == game.GameState.TILE_SELECTED:
		_hover_tile_selected()
	elif state == game.GameState.PICKING_TARGET:
		_hover_picking_target(hovered_cell)
	elif state == game.GameState.CHOOSING_GROUP_MOVE:
		_hover_choosing_group_move(hovered_cell)
	elif state == game.GameState.ATTACK_TARGETING:
		_hover_attack_targeting(hovered_cell)
	elif state == game.GameState.CHOOSING_MOVE:
		_hover_choosing_move(hovered_cell)

	for unit in icons_to_draw.keys():
		for icontype in icons_to_draw[unit]:
			game.overlay_manager.create_unit_icon(unit, icontype)

# CLEARS the card rather than filling it (#582). Dev mode never wrote it, so it held whatever the
# last IDLE hover had left -- a card from before the mode was even entered, which is how a readout
# for a cell at -3 came to say -1. Clearing rather than describing, because the dev-mode height
# readout is HeightDebugOverlay's and a second voice for it is a second thing to keep in step.
func _hover_dev_mode(cell: Vector2i) -> void:
	game.hover_info_panel.clear()
	var board: BoardContext = game._board()
	if not board.is_walkable(cell) or game.unit_at_pointer(cell) != null:
		game.cursor_controller.set_state(CursorController.CursorState.INVALID)
	else:
		game.cursor_controller.set_state(CursorController.CursorState.DEFAULT)
	game.cursor_controller.set_cursor_pos(cell)

# Returns the squad icons to draw (empty when there's nothing hovered worth marking).
func _hover_idle(cell: Vector2i) -> Dictionary:
	game.cursor_controller.set_cursor_pos(cell)
	game.overlay_manager.clear_selection_overlays()

	var hovered: Unit = game.unit_at_pointer(cell)
	if hovered == null:
		_show_hover_panel(null, cell)   # every real tile carries a card (dev, #135 round 2)
		game.overlay_manager.clear_selection_overlays()
		game.cursor_controller.set_state(CursorController.CursorState.DEFAULT)
		if game.squad_manager.active_squad == null:
			game.clear_selection_icons()
		return {}

	if game.squad_manager.active_squad == null:
		game.clear_selection_icons()

	# AN ENEMY IS READ IN THE ENEMY'S OWN VOCABULARY (#710 slice 3, dev ruling: unify). Hovering
	# one used to borrow THREE of your layers -- the yellow MOVE range, the orange SQUAD_RANGE
	# cohesion bubble and the red INVALID_MOVE -- all of them RAW, so the board answered "where
	# could this body physically walk" beside a threat fill answering "where will it". Worse, the
	# cohesion bubble is a third picture of enemy movement that ThreatField deliberately ignores.
	# The fork is the whole branch rather than one call, because every one of those three is the
	# wrong question to ask about somebody you do not command.
	if Team.is_enemy(Team.Faction.PLAYER, hovered.get_faction()):
		_show_hover_panel(hovered, cell)
		game._redraw_enemy_ranges(hovered)
		if hovered.has_squad() and game.squad_manager.active_squad == null:
			return game.get_squad_icons(hovered.squad)
		return {}

	var moverange: Dictionary = game.compute_move_range(hovered)
	if hovered.has_squad():
		game.draw_squad_cohesion(hovered.squad, hovered.squad.leader.get_projected_destination())

	# BLUE ALONE ON HOVER (#1069), where #1066 drew blue and red both. The dev, on 3D FE: "hovering a
	# unit doesn't show the attack range at all, actually. Selecting a unit, though... brings up the
	# unit's attack radius from the unit's tile." That repeals his own earlier ruling here -- the red
	# WAS on hover deliberately -- and the reason it moves is what the red now means: it grew from
	# everywhere the unit could walk, which is most of the board and worth little, and it now grows
	# from one cell, which is worth something only once you have said which cell. Hover is before
	# that; the ring and the move gesture are after it. Painted by game._click_idle and by
	# HoverPresenter's own move-hover branches respectively.
	var standable: Array[Vector2i] = game.get_move_range(moverange, hovered)
	var blocked: Array[Vector2i] = []
	blocked.assign(moverange.squad_unreachable.keys())
	# A LEADER'S RANGE IS SPLIT HERE TOO (#1070, dev: "These two floodfills disagreeing is
	# problematic"). Only Move used to ask whether the squad could follow, so hovering a leader drew
	# his whole range blue and opening Move then cut it -- and the ring, which shows whatever hover
	# last drew, sided with the hover. The same split through the same helper, so the three agree:
	# about 7 ms, once, when the pointer lands on a leader (docs/performance.md).
	if hovered.is_leader() and hovered.has_squad():
		var split: Dictionary = game.leader_range_split(hovered, standable)
		standable = split["green"]
		blocked = split["blocked"]
	game.overlay_manager.show_overlay(OverlayManager.OverlayType.MOVE, standable, OverlayManager.ATLAS_COORDS)
	_show_hover_panel(hovered, cell)
	game.overlay_manager.show_overlay(OverlayManager.OverlayType.INVALIDMOVE, blocked, OverlayManager.ATLAS_COORDS)

	# Idle only: an active squad's own markers are already up, and a second set for whoever the
	# mouse happens to be over competes with them. The "draw them muted instead" TODO that used to
	# sit here was dropped rather than built (dev, 2026-08-21, #44).
	if hovered.has_squad() and game.squad_manager.active_squad == null:
		return game.get_squad_icons(hovered.squad)
	return {}

func _hover_tile_selected() -> void:
	game.cursor_controller.set_state(CursorController.CursorState.TARGET)
	game.cursor_controller.set_cursor_pos(game.last_clicked_cell)

func _hover_picking_target(cell: Vector2i) -> void:
	var preview_cells: Array[Vector2i] = []
	if game.target_pick_cells.has(cell):
		preview_cells.append(cell)
	game.overlay_manager.show_overlay(OverlayManager.OverlayType.HOVER, preview_cells, OverlayManager.ATLAS_COORDS)
	_set_cursor_for_preview(cell, not preview_cells.is_empty())

func _hover_choosing_group_move(cell: Vector2i) -> void:
	var leader: Unit = game.selected_unit
	game.overlay_manager.clear_hover_move_path()
	if leader == null:
		_set_cursor_for_preview(cell, false)
		return

	# Reads what enter_group_move_mode computed: per hovered cell it cost 6.8 ms of a 16.7 ms frame
	# (docs/performance.md). Same two questions, same order, as game._click_choosing_group_move.
	var moverange: Dictionary = game.compute_move_range(leader)
	var followable: bool = moverange.reachable.keys().has(cell) and game.leader_followable.has(cell)
	if followable:
		var formation := GroupMoveSolver.plan(leader.squad, cell, game._board())
		game.overlay_manager.show_hover_move_paths(formation)
		# ...and a stand-in for every member the formation places, not just the leader: what the
		# player is choosing here is where the whole squad lands.
		game.overlay_manager.show_hover_ghosts(formation)
		# ...and what the LEADER would threaten there, and who reaches it (#1069). Only on a
		# followable cell, unlike the single-unit branch above: an unfollowable one is not a
		# destination this squad has, so there is no "if you stop here" to answer.
		game.show_player_reach(leader, cell)
		game.show_reach_lines_at(cell)
		# ...and the squad's lines follow the formation (#1070): the range round the leader's ghost,
		# each tether from the stand-in the formation put its member on.
		var placed := {}
		for move: MoveAction in formation:
			placed[move.actor] = move.destination
		game.draw_squad_cohesion(leader.squad, cell, placed)
	elif game.leader_stranding.has(cell):
		_draw_stranding(leader, cell, moverange)
	else:
		# Outside the range: the red goes back to the leader's own tile, what enter_group_move_mode
		# painted, rather than standing where the last legal tile left it.
		game.show_player_reach(leader, leader.movement.cell)
		if leader.has_squad():
			game.draw_squad_cohesion(leader.squad, leader.get_projected_destination())
	_set_cursor_for_preview(cell, followable)


# The leader hovered onto a tile he could walk to and the squad could not follow him onto (#1070): his
# ghost standing there, and the squad's lines drawn as though he had gone, with the tethers of whoever
# would be stranded in red -- which is the reason the tile is grey, said where the player is looking.
# A ghost authors nothing; the path preview and the plan re-validation stay withheld, as they were.
# And NOTHING ELSE (dev, 2026-09-22): no red reach and no reach lines, because a tile wearing "what you
# would threaten here" reads as one you may take. The red the last legal tile drew is cleared.
func _draw_stranding(leader: Unit, cell: Vector2i, moverange: Dictionary) -> void:
	game.overlay_manager.clear_reach()
	_show_stand_in(leader, cell, moverange)
	var strained: Array[Unit] = []
	strained.assign(game.leader_stranding.get(cell, []))
	game.draw_squad_cohesion(leader.squad, cell, {}, strained)


# A ghost of `unit` standing on `cell` and nothing else -- no arrow, no re-validation -- for a tile the
# player may look at but not take. The typed local is required through the untyped `game` ref.
func _show_stand_in(unit: Unit, cell: Vector2i, moverange: Dictionary) -> void:
	var path := RulesService.reconstruct_path(moverange.came_from, unit.movement.cell, cell)
	var ghost := MoveAction.new()
	ghost.init(unit, path, GridUtils.get_terrain_icon_at_cell(game.grid, path.back()))
	var one: Array[MoveAction] = [ghost]
	game.overlay_manager.show_hover_ghosts(one)


# A single unit's move being chosen (#1070): the squad's lines with this unit moved onto the hovered
# tile. A member's tether leaves its ghost, red where the tile is past the leader's range; a leader
# carries the range with him, and every member he would strand goes red.
func _draw_move_lines(unit: Unit, cell: Vector2i, moverange: Dictionary) -> void:
	var squad: Squad = unit.squad
	if unit.is_leader():
		if not moverange.reachable.keys().has(cell):
			game.draw_squad_cohesion(squad, unit.get_projected_destination())
			return
		var stranded: Array[Unit] = []
		stranded.assign(game.leader_stranding.get(cell, []))
		game.draw_squad_cohesion(squad, cell, {}, stranded)
		return
	var leader_cell := squad.leader.get_projected_destination()
	var none: Array[Unit] = []
	if moverange.reachable.keys().has(cell):
		game.draw_squad_cohesion(squad, leader_cell, {unit: cell}, none)
	elif moverange.squad_unreachable.keys().has(cell):
		var strained: Array[Unit] = [unit]
		game.draw_squad_cohesion(squad, leader_cell, {unit: cell}, strained)
	else:
		game.draw_squad_cohesion(squad, leader_cell)

func _hover_attack_targeting(cell: Vector2i) -> void:
	var attacker: Unit = game.selected_unit

	var preview_cells: Array[Vector2i] = []
	var travel: Dictionary[Vector2i, Array] = {}
	var victims: Array[Unit] = []
	var trace_shown := false
	if attacker != null:
		var board: BoardContext = game._board()
		var origin := attacker.get_projected_destination()
		var aiming := attacker.get_fired_attack()   # aiming: the live pick IS the question (#102)
		# The sight line (#258): for a RANGED point aim at any cell in horizontal reach, show the
		# trace -- valid or blocked, the player sees the line the gate judged. Melee draws none
		# (visually obvious anytime -- dev); a directional aim has no single line.
		if Reach.draws_sight_trace(aiming) \
				and Reach.get_attack_cells_from(attacker, origin, cell, aiming).has(cell):
			game.overlay_manager.show_sight_trace(Reach.sight_trace(aiming, origin, cell, board))
			trace_shown = true
		# Directional: a facing whose spread the terrain leaves standing (#756 -- it was any non-zero
		# facing before truncation). Point: the hovered cell itself must be in range AND within
		# vertical tolerance (#258). One predicate, the same one the click commits through.
		if Reach.can_aim_at(attacker, origin, cell, aiming, board):
			# The wash shows the CURRENT as well as the blast (Law #2 -- a shock that will arc has to
			# say so before the click). Read against LIVE wetness, since that is what is true at the
			# moment the player is aiming; a queued-but-unexecuted WATER order is threaded into the
			# pass instead, and the queue row it produces is where that reading is honest.
			var reach := Conduction.sweep(attacker, origin, cell, aiming, board)
			preview_cells = reach.cells
			# Every footprint flashes in the order the attack travels (#1057 part 2), whatever it
			# targets -- the tiles say HOW it lands, the victims' own pulse says WHO.
			travel = reach.steps
			# A null pick is bare fists -- unit-only by definition, so it has no hits_units to ask and
			# answers as UNIT.
			if aiming == null or aiming.hits_units():
				victims = reach.victims

	if not trace_shown:
		game.overlay_manager.clear_sight_trace()
	game.overlay_manager.show_overlay(OverlayManager.OverlayType.HOVER, preview_cells, OverlayManager.ATLAS_COORDS)
	game.overlay_manager.set_aim_flash(travel)
	game.overlay_manager.set_target_pulse(victims)
	_set_cursor_for_preview(cell, not preview_cells.is_empty())

func _hover_choosing_move(cell: Vector2i) -> void:
	var unit: Unit = game.selected_unit
	game.overlay_manager.clear_hover_move_path()
	var moverange: Dictionary = game.compute_move_range(unit)

	if unit.has_squad():
		_draw_move_lines(unit, cell, moverange)
		if unit.is_leader() and moverange.reachable.keys().has(cell):
			game.overlay_manager.redraw_planned_paths()
			game.overlay_manager.redraw_projected_units()

	if not moverange.reachable.keys().has(cell) and not moverange.squad_unreachable.keys().has(cell):
		# Outside the range: the red goes back to the unit's own tile, what enter_move_mode painted,
		# rather than standing where the last legal tile left it.
		game.show_player_reach(unit, unit.movement.cell)
		_set_cursor_for_preview(cell, false)
		return

	# A tile this unit could WALK to and may not TAKE (#1070): a member past its leader's range, or
	# a leader's destination the squad cannot follow to (#1069 -- asked here as well as at the click,
	# off the same cache, so the cursor and the click cannot disagree). It draws the unit's ghost and
	# the red tether _draw_move_lines just drew, and nothing else (dev, 2026-09-22): no red reach, no
	# reach lines, no path arrow, no re-validation. A tile wearing "what you would threaten here"
	# reads as one you may take, which is the thing this tile is saying you may not.
	var strands: bool = unit.is_leader() and unit.has_squad() and not game.leader_followable.has(cell)
	if strands or moverange.squad_unreachable.keys().has(cell):
		game.overlay_manager.clear_reach()
		if not strands or game.leader_stranding.has(cell):
			_show_stand_in(unit, cell, moverange)
		_set_cursor_for_preview(cell, false)
		return

	# WHAT YOU WOULD THREATEN FROM THERE, and WHO REACHES YOU THERE (#1069) -- the two halves of
	# "what happens if I stop here", both re-aimed at the cell under the pointer rather than at the
	# body. The red is the same layer enter_move_mode painted from the unit's own cell; it simply
	# follows the candidate now.
	game.show_player_reach(unit, cell)
	game.show_reach_lines_at(cell)

	# Live preview: build the move this click WOULD queue and validate the plan against it, so
	# the arrow and the queue panel show the real consequence before anything is committed.
	var path := RulesService.reconstruct_path(moverange.came_from, unit.movement.cell, cell)
	var move := MoveAction.new()
	move.init(unit, path, GridUtils.get_terrain_icon_at_cell(game.grid, path.back()))

	var squad = unit.squad
	game.squad_manager.validate_squad_plan_preview(squad, move)
	game.overlay_manager.show_hover_move_path(move)
	# ...and the body that would stand there (#1069). After show_hover_move_path, which clears the
	# whole hover store: drawn before it, the ghost would be swept away by the arrows. The typed
	# local is required -- a bare literal passed through the untyped `game` ref is not coerced and
	# fails at RUNTIME (see CLAUDE.md's note on clear_selection_icons).
	var one: Array[MoveAction] = [move]
	game.overlay_manager.show_hover_ghosts(one)

	if unit.has_squad():
		game.overlay_manager.redraw_squad_unit_icons(squad)

	game.overlay_manager.redraw_planned_paths()
	game.overlay_manager.redraw_projected_units()
	game.refresh_action_queue(squad)
	_set_cursor_for_preview(cell, true)

# ==============================================================================
#  Queue-panel row hover
# ==============================================================================

func on_queue_row_hover_changed(action: BaseAction, hovering: bool) -> void:
	for u in _highlighted_queue_units:
		_highlight_unit(u, false)
	_highlighted_queue_units.clear()

	if not hovering or action == null:
		return

	if is_instance_valid(action.actor):
		_highlight_unit(action.actor, true)
		_highlighted_queue_units.append(action.actor)

	if action is AttackAction:
		var target := (action as AttackAction).target
		if target != null and is_instance_valid(target):
			_highlight_unit(target, true)
			_highlighted_queue_units.append(target)

func _highlight_unit(unit: Unit, on: bool) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	# A unit with a valid queued move is drawn as a projected "ghost" (its real sprite is
	# hidden). Highlight whichever sprite is actually on screen.
	if game.overlay_manager.has_projected_unit(unit):
		game.overlay_manager.set_projected_unit_highlighted(unit, on)
	else:
		unit.visuals.set_highlighted(on)

func _on_hovered_unit_changed(previous_unit: Unit, new_unit: Unit) -> void:
	if previous_unit != null and is_instance_valid(previous_unit):
		previous_unit.visuals.set_hovered(false)

	if new_unit != null and is_instance_valid(new_unit):
		new_unit.visuals.set_hovered(true)

# ==============================================================================
#  Enemy threat (#710 hover tier)
# ==============================================================================

# Cleared on every cell change; the branch that wants it draws it back. The RANGE fills are not
# cleared here and must not be -- game._redraw_enemy_ranges owns them, and a pinned enemy has to
# survive the pointer moving off it. Every arm of update_hover_visuals that does not draw them
# calls that door with no hovered enemy, which is what puts the transient half down.
#
# The REACH LINES are cleared here outright, which is the opposite treatment and the right one
# (#1069): they answer about the cell under the pointer, so there is no version of them that
# survives the pointer moving. Clearing unconditionally and letting the two move-hover branches
# draw them back is what makes "these exist only while you are choosing a move" true by
# construction rather than by every other branch remembering to say so. At rest both calls are
# free -- an empty clear over an empty store early-outs without touching the version.
func _clear_threat_markup() -> void:
	game._redraw_enemy_ranges(null)
	game.overlay_manager.clear_reach_lines()

# ==============================================================================
#  Shared helpers
# ==============================================================================

# Every pick mode reads the same way: nothing previewed means the aim is illegal.
# Currently disabled while working out how targeting is presented
func _set_cursor_for_preview(cell: Vector2i, valid: bool) -> void:
	if valid:
		game.cursor_controller.set_state(CursorController.CursorState.DEFAULT)
	else:
		game.cursor_controller.set_state(CursorController.CursorState.DEFAULT)
	game.cursor_controller.set_cursor_pos(cell)

func _show_hover_panel(hovered: Unit, cell: Vector2i) -> void:
	# Inspect + hover must never overlap. The inspect panel is a docked left column (#68):
	#   - hovering the inspected unit adds nothing -> suppress the hover card (tile card too)
	#   - anything else -> the card keeps its own top/bottom logic, shifted right of the column
	# The card is a stack since #135, and the tile half shows for EVERY real tile (dev, round 2):
	# icon + name header, then the tile's ground lines. Name, picture and lines all come off
	# TileReadout, the one builder the Inspect dock's tile mode reads too (#1105), so the two cannot
	# disagree. TERRAIN_ICONS stays the queue rows' pathing glyph, not a display read.
	var header: String = TileReadout.title_of(game, cell)
	var icon: Texture2D = TileReadout.icon_of(game, cell)
	var tile_lines: Array[String] = TileReadout.ground_lines(game, cell)
	var world_pos: Vector2 = hovered.global_position if hovered != null \
		else GridUtils.cell_world(game.grid, cell)
	if game.unit_info_panel.is_showing():
		if hovered != null and game.unit_info_panel.is_showing_unit(hovered):
			game.hover_info_panel.clear()
			return
		game.hover_info_panel.show_hover(hovered, icon, header, tile_lines, world_pos,
			int(game.unit_info_panel.panel_width()) + 8)
	else:
		game.hover_info_panel.show_hover(hovered, icon, header, tile_lines, world_pos)
