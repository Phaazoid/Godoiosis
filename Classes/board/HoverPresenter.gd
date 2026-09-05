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

func update_hover_visuals(hovered_cell: Vector2i) -> void:
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
	elif state == game.GameState.IDLE:
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

	var moverange: Dictionary = game.compute_move_range(hovered)
	if game.squad_manager.active_squad == null:
		game.clear_selection_icons()

	if hovered.has_squad():
		game.draw_squad_leader_range(hovered.squad, hovered.squad.leader.get_projected_destination())

	game.overlay_manager.show_overlay(OverlayManager.OverlayType.MOVE, game.get_move_range(moverange, hovered), OverlayManager.ATLAS_COORDS)
	_show_hover_panel(hovered, cell)
	game.overlay_manager.show_overlay(OverlayManager.OverlayType.INVALIDMOVE, moverange.squad_unreachable.keys(), OverlayManager.ATLAS_COORDS)

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
	var followable: bool = game.compute_move_range(leader).reachable.keys().has(cell) \
		and game.group_move_followable.has(cell)
	if followable:
		game.overlay_manager.show_hover_move_paths(GroupMoveSolver.plan(leader.squad, cell, game._board()))
	_set_cursor_for_preview(cell, followable)

func _hover_attack_targeting(cell: Vector2i) -> void:
	var attacker: Unit = game.selected_unit

	var preview_cells: Array[Vector2i] = []
	var victims: Array[Unit] = []
	var pulse_tiles := false
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
			preview_cells = Reach.get_affected_cells_from(attacker, origin, cell, aiming, board)
			# A null pick is bare fists -- unit-only by definition, so it has no hits_map/hits_units
			# to ask and answers as UNIT.
			pulse_tiles = aiming != null and aiming.hits_map()
			if aiming == null or aiming.hits_units():
				victims = RulesService.gather_attack_victims(attacker, preview_cells, board, aiming)

	if not trace_shown:
		game.overlay_manager.clear_sight_trace()
	game.overlay_manager.show_overlay(OverlayManager.OverlayType.HOVER, preview_cells, OverlayManager.ATLAS_COORDS)
	game.overlay_manager.set_target_pulse(victims, pulse_tiles)
	_set_cursor_for_preview(cell, not preview_cells.is_empty())

func _hover_choosing_move(cell: Vector2i) -> void:
	var unit: Unit = game.selected_unit
	game.overlay_manager.clear_hover_move_path()
	var moverange: Dictionary = game.compute_move_range(unit)

	if unit.is_leader():
		game.overlay_manager.clear_squad_range()
	if unit.is_leader() and unit.has_squad() and moverange.reachable.keys().has(cell):
		game.draw_squad_leader_range(unit.squad, cell)
		game.overlay_manager.redraw_planned_paths()
		game.overlay_manager.redraw_projected_units()

	if not moverange.reachable.keys().has(cell) and not moverange.squad_unreachable.keys().has(cell):
		_set_cursor_for_preview(cell, false)
		return

	# Live preview: build the move this click WOULD queue and validate the plan against it, so
	# the arrow and the queue panel show the real consequence before anything is committed.
	var path := RulesService.reconstruct_path(moverange.came_from, unit.movement.cell, cell)
	var move := MoveAction.new()
	move.init(unit, path, GridUtils.get_terrain_icon_at_cell(game.grid, path.back()))

	var squad = unit.squad
	game.squad_manager.validate_squad_plan_preview(squad, move)
	game.overlay_manager.show_hover_move_path(move)

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
	# icon + name header, then the tile's states, rules and possible interactions.
	var board: BoardContext = game._board()
	var kind: Terrain.Kind = board.terrain_kind_at(cell)
	# The tile's OWN data names and pictures the card (2026-08-12): authored terrain_name first,
	# kind name as the fallback, the tile's sprite as the picture -- the same policy the brush
	# palette rows read (GridUtils.authored_tile_display_name / tile_sprite), so hover and palette
	# cannot disagree. A bare unnamed NONE-kind tile stays headerless on purpose, and
	# TERRAIN_ICONS stays the queue rows' pathing glyph, not a display read.
	var data: TileData = game.grid.get_cell_tile_data(cell)
	var authored: String = GridUtils.authored_tile_display_name(data)
	var header: String = authored if authored != "" \
		else (Terrain.kind_display_name(kind) if kind != Terrain.Kind.NONE else "")
	var source: TileSetAtlasSource = game.grid.tile_set.get_source(game.grid.get_cell_source_id(cell)) as TileSetAtlasSource
	var icon: Texture2D = GridUtils.tile_sprite(source, game.grid.get_cell_atlas_coords(cell))
	var tile_lines: Array[String] = _tile_readout_lines(cell)
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

# The tile card's body (#135): each dynamic state (with its live clock), the ground rules worth
# knowing (water's traversal gate, a move cost above the norm), then which elements can touch
# this tile — filtered through the SAME predicate the resolver's deposit filter runs
# (TerrainReaction.applies_to_tile, via Glossary.terrain_reactions_for). Meanings come from
# Glossary short texts, numbers from the reads the rules make — the card can't disagree with
# either. The kind itself is the card's header, composed in _show_hover_panel.
func _tile_readout_lines(cell: Vector2i) -> Array[String]:
	var lines: Array[String] = []
	var board: BoardContext = game._board()
	var held: Array[Terrain.TileState] = []
	if board.terrain_states != null:
		held = board.terrain_states.states_at(cell)
	for state: Terrain.TileState in held:
		var line: String = "%s — %s" % [Terrain.tile_state_display_name(state),
			Glossary.short(Glossary.term_for_tile_state(state))]
		var turns: int = board.terrain_states.turns_remaining(cell, state)
		if turns > 0:
			line += " %d left." % turns
		lines.append(line)
	var kind: Terrain.Kind = board.terrain_kind_at(cell)
	if kind == Terrain.Kind.WATER:
		# One Kind, two tiles (#116) — so the card asks the same question the rules ask: water you
		# cannot stand on is the DEEP kind. Reading walkability rather than a second enum member is
		# what makes a FROZEN cell read as the shallow line for free, since is_walkable knows state.
		lines.append(Glossary.short(Glossary.Term.WATER_TILE if not board.is_walkable(cell)
			else Glossary.Term.SHALLOW_WATER))
	var data: TileData = game.grid.get_cell_tile_data(cell)
	if data != null and data.has_custom_data("move_cost"):
		var cost: int = data.get_custom_data("move_cost")
		if cost > 1:
			lines.append("Slow going — costs %d movement to enter." % cost)
	# Elevation (#257). Only spoken when it is non-default, so a flat board's card reads exactly as
	# it did before verticality existed — the same rule the move_cost line above follows.
	var elevation: int = board.elevation_at(cell)
	var corners: Vector4i = board.corners_at(cell)
	var rise: Terrain.RampRise = Terrain.rise_of_corners(corners)
	var climb: int = Terrain.climb_of_corners(corners)
	if rise != Terrain.RampRise.NONE:
		# BOTH ends, because a ramp's steepness is authored since #427 slice 2 — "rises east from 4"
		# no longer says where it arrives, and which heights it joins is the whole rule.
		#
		# The sideways clause went with #427 slice 3: a step is refused when the shared edge does not
		# meet, which still refuses this ramp's sides but no longer refuses a slope continuing
		# alongside it. Saying "only along that slope" would now be a card describing a rule the
		# board does not follow.
		lines.append("Ramp — rises %s from height %d to height %d."
			% [Terrain.ramp_rise_display_name(rise).to_lower(), elevation, elevation + climb])
	elif climb > 0:
		# A corner form: RampRise cannot name it, so the card says what it IS rather than reaching
		# for a direction that does not exist (#427 slice 3).
		lines.append("Corner slope — height %d rising to %d across part of the cell."
			% [elevation, elevation + climb])
	elif elevation != 0:
		lines.append("Height %d — reached only by a ramp that climbs to it." % elevation)
	lines.append_array(Glossary.terrain_reactions_for(kind, held))
	return lines
