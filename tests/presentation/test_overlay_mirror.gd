# OverlayMirror (#222): 2D-to-3D overlay parity, driven through the REAL 2D
# triggers (the documented direct-call idiom — mode entries, hover branches, the
# production draw seams) and asserted on BoardOverlays/UnitMirror state. Every
# expectation is hand-derived from the 2D layers (the independent spelling, never
# the mirror's own helpers). Colors and textures are asserted as COPIES of the 2D
# values — the parallel-stacks doctrine — not pinned to numbers here.
#
# Fixture is the Battle3D scene with a hand-built board, the attack-visuals shape:
# clear the boot board, spawn known units, drive a trigger, settle two frames
# (process_frame resumes coroutines BEFORE node _process — one frame is stale).
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _scene: Node3D
var game: Node2D
var _overlays: BoardOverlays
var _unit_mirror: UnitMirror
var _mirror: OverlayMirror


var _ring_alpha_was: float
var _shove_colour_was: Color


func before_test() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	# Statics outlive a test; cache rather than restore-to-a-literal, per the tuning razor.
	_ring_alpha_was = OverlayManager.SQUAD_RING_ALPHA
	_shove_colour_was = OverlayManager.KNOCKBACK_MODULATE
	# DECLARES which board this suite asserts on: the one a player who has changed nothing sees.
	# The icon channel forks on ALWAYS_SHOW_SQUAD_RINGS, and the ON branch is a real player-facing
	# state, not a stray -- it is pinned next door in test_standing_squad_rings (#449).
	PlayerSettings.reset_for_test()
	var packed := load(SCENE_PATH) as PackedScene
	_scene = packed.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	game = _scene.game
	_overlays = _scene.get_node("BoardOverlays") as BoardOverlays
	_unit_mirror = _scene.get_node("UnitMirror") as UnitMirror
	_mirror = _scene.get_node("OverlayMirror") as OverlayMirror
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	OverlayManager.SQUAD_RING_ALPHA = _ring_alpha_was
	OverlayManager.KNOCKBACK_MODULATE = _shove_colour_was
	get_tree().root.remove_child(_scene)
	_scene.free()


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


func _om() -> OverlayManager:
	return game.overlay_manager


# The independent expectation: the 2D layer's cells, hand-lifted to the ROW each one's height puts
# it on, sorted. It said "flat-3D" and hardcoded row 0 until #427 slice 2, which was only ever right
# because a ground cell's top row WAS 0 while a slab was one row deep.
func _lifted(layer_2d: TileMapLayer) -> Array[Vector3i]:
	var heights: BoardHeights = game.board_heights
	var cells: Array[Vector3i] = []
	for cell: Vector2i in layer_2d.get_used_cells():
		cells.append(BoardSpace.of_cell(cell, BoardSpace.top_row_of(heights.elevation_at(cell))))
	cells.sort()
	return cells


# How many fill quads are lying on something other than level ground -- the VISIBLE consequence of a
# tilt, read off the live pool rather than off any helper the mirror also uses.
func _tilted_fills() -> int:
	var tilted := 0
	for child in _overlays.get_children():
		var quad := child as MeshInstance3D
		if quad != null and quad.visible and quad.mesh is PlaneMesh \
				and not quad.basis.y.normalized().is_equal_approx(Vector3.UP):
			tilted += 1
	return tilted


func _sorted_3d(layer: BoardOverlays.Layer) -> Array[Vector3i]:
	var cells := _overlays.cells_of(layer)
	cells.sort()
	return cells


func _spawn(faction: Team.Faction, cell: Vector2i, overrides: Dictionary = {}) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data(overrides, faction), cell)
	assert_object(unit).is_not_null()   # fixture setup, not the claim under test
	return unit


func _squad_pair() -> Array[Unit]:
	var leader := _spawn(PLAYER, Vector2i(2, 2))
	var member := _spawn(PLAYER, Vector2i(5, 2))
	game.squad_manager.join_squad(member, leader.squad)
	return [leader, member]


# --- Fills -------------------------------------------------------------------------

# The WIRE for #281: BoardOverlays can tilt a fill onto a slope, and OverlayMirror knows the board's
# heights, and neither of those facts puts a tilt on screen unless the mirror actually HANDS the
# heights over. Both ends were correct while nothing connected them is #103's shape exactly, and the
# unit-level cases cannot see it -- they call set_cells themselves.
#
# The ramp is painted into the fixture's own hand-built board, so nothing here reads authored
# content. It is painted BEFORE the mode is entered, which is the plain case; the rise-under-a-drawn
# -fill ordering is #308's, and its own case is below.
func test_a_fill_over_a_ramp_reaches_the_3d_tilted() -> void:
	var pair := _squad_pair()
	var mover: Unit = pair[1]

	# Discover the real range first, then ramp a cell inside it -- picking a cell blind would sit
	# outside the range on any future change to MOV or cohesion and quietly assert nothing.
	game.enter_move_mode(mover)
	await _settle()
	var painted: Array[Vector2i] = _om().move_overlay.get_used_cells()
	assert_bool(painted.size() > 0).override_failure_message(
			"nothing painted -- this case cannot see the wire").is_true()
	game.exit_current_mode()
	await _settle()

	# EAST, on the cell directly east of the mover, so the ONE step onto it runs west-to-east up the
	# slope and costs one movement whatever the range's shape is.
	#
	# It used to take painted[0] blind, which worked only by a looseness #427 slice 3 removed: a ramp
	# is now enterable strictly from its LOW side, because the rule compares the shared EDGE rather
	# than the two cells' low corners. This ramp's east edge sits a level up, and the old rule let a
	# unit step onto it from ground two units beneath. Any cell reached by some other route is
	# therefore no longer guaranteed to stay in range once it becomes a ramp.
	var ramp: Vector2i = mover.movement.cell + Vector2i.RIGHT
	assert_bool(painted.has(ramp)).override_failure_message(
			"the cell east of the mover is not even in range, so this case cannot see the wire"
			).is_true()
	game.board_heights.set_cell(ramp, 0, Terrain.RampRise.EAST)

	game.enter_move_mode(mover)
	await _settle()
	var still_painted: Array[Vector2i] = _om().move_overlay.get_used_cells()
	assert_bool(still_painted.has(ramp)).override_failure_message(
			"the ramped cell fell out of range -- nothing tilted would be drawn").is_true()

	assert_int(_tilted_fills()).override_failure_message(
			"every fill came through level -- the mirror is not handing its heights to set_cells") \
		.is_greater(0)


# #308: the same wire, driven in the order the dev's elevation brush actually produces. A rise
# painted onto a cell whose ELEVATION does not change leaves BoardSpace.of_cell's Vector3i identical,
# so _fill's cell-list diff short-circuits and the quad keeps the tilt it already had. Nothing about
# the cell list can see this -- only the heights store moving can -- which is why the gate reads
# BoardHeights.dirty.version rather than folding the rise into the compared value.
#
# The mode stays OPEN across the paint on purpose: that is what holds the 2D layer's cells fixed.
func test_a_rise_painted_under_a_drawn_fill_re_tilts_it() -> void:
	var pair := _squad_pair()
	var mover: Unit = pair[1]

	game.enter_move_mode(mover)
	await _settle()
	var painted: Array[Vector2i] = _om().move_overlay.get_used_cells()
	assert_bool(painted.size() > 0).override_failure_message(
			"nothing painted -- this case cannot see the gate").is_true()
	assert_int(_tilted_fills()).override_failure_message(
			"a fill was already tilted before the rise -- the case would pass vacuously").is_equal(0)

	# Elevation stays 0, so the cell list the mirror builds is byte-identical to the one it pushed.
	painted.sort()
	game.board_heights.set_cell(painted[0], 0, Terrain.RampRise.EAST)
	await _settle()

	assert_int(_tilted_fills()).override_failure_message(
			"the fill is still level -- a rise-only edit never reached set_cells").is_greater(0)


# --- Standing states -----------------------------------------------------------------

# #308's second surface. _standing_states diffs on the BURNING/COVER cell lists, and a flame does not
# lie on its cell -- it stands on it -- so raising the ground moves it while that list holds still.
# Asserted on the marker's own position against BoardSpace.surface_point, never a pinned number, and
# on the SAME node, since re-seating a survivor must not become free-and-rebuild.
func test_raising_the_ground_under_a_flame_re_seats_it() -> void:
	var ground: Array[Vector2i] = game.grid.get_used_cells()
	assert_bool(ground.size() > 0).override_failure_message(
			"the fixture board has no ground; fire cannot be deposited").is_true()
	ground.sort()
	var cell: Vector2i = ground[0]

	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.assign([Terrain.TileState.BLAZE])
	game.terrain_states.apply(effect)
	await _settle()

	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	var marker := mirror.fire_marker_at(cell)
	assert_object(marker).override_failure_message(
			"no flame was ever stood up -- this case cannot see the gate").is_not_null()
	var before := marker.position
	var id := marker.get_instance_id()

	game.board_heights.set_cell(cell, 4)
	await _settle()

	var after := mirror.fire_marker_at(cell)
	assert_int(after.get_instance_id()).override_failure_message(
			"the flame was rebuilt rather than re-seated").is_equal(id)
	assert_vector(after.position).override_failure_message(
			"the flame is still standing on the old surface").is_not_equal(before)
	assert_vector(after.position).is_equal(BoardSpace.surface_point(cell, game.board_heights))


func test_move_and_invalid_fills_mirror_the_2d_layers() -> void:
	var pair := _squad_pair()
	game.enter_move_mode(pair[1])   # the member: cohesion clips its range -> both layers paint
	await _settle()
	assert_bool(_om().move_overlay.get_used_cells().size() > 0).is_true()
	assert_bool(_om().invalidmove_overlay.get_used_cells().size() > 0).is_true()
	assert_that(_sorted_3d(BoardOverlays.Layer.MOVE)).is_equal(_lifted(_om().move_overlay))
	assert_that(_sorted_3d(BoardOverlays.Layer.INVALID_MOVE)).is_equal(_lifted(_om().invalidmove_overlay))


func test_group_move_paints_green_and_red_in_both_worlds() -> void:
	# A fast leader and a slow member: far leader destinations are unfollowable, so
	# the split genuinely paints both colors (an even pair paints no red at all).
	var leader := _spawn(PLAYER, Vector2i(2, 2), {Stats.Stat.DEX: 40})
	var member := _spawn(PLAYER, Vector2i(5, 2), {Stats.Stat.DEX: 1})
	game.squad_manager.join_squad(member, leader.squad)
	game.enter_group_move_mode(leader)
	await _settle()
	assert_bool(_om().move_overlay.get_used_cells().size() > 0).is_true()
	assert_bool(_om().invalidmove_overlay.get_used_cells().size() > 0).is_true()   # the unfollowable red
	assert_that(_sorted_3d(BoardOverlays.Layer.MOVE)).is_equal(_lifted(_om().move_overlay))
	assert_that(_sorted_3d(BoardOverlays.Layer.INVALID_MOVE)).is_equal(_lifted(_om().invalidmove_overlay))


func test_attack_reach_mirrors_cells_and_heal_color() -> void:
	var attacker := _spawn(PLAYER, Vector2i(2, 2))
	attacker.equipped_weapon = H.make_weapon(3)
	game.enter_attack_mode(attacker)
	await _settle()
	assert_bool(_om().attack_overlay.get_used_cells().size() > 0).is_true()
	assert_that(_sorted_3d(BoardOverlays.Layer.ATTACK)).is_equal(_lifted(_om().attack_overlay))
	assert_that(_overlays.layer_modulate(BoardOverlays.Layer.ATTACK)).is_equal(_om().attack_overlay.modulate)

	game.exit_current_mode()
	attacker.get_equipped_weapon().template.main_attack.heals = true
	game.enter_attack_mode(attacker)
	await _settle()
	# The heal-green arrives as the 2D layer's own modulate, copied — never re-derived.
	assert_that(_om().attack_overlay.modulate).is_equal(OverlayManager.HEAL_ATTACK_MODULATE)
	assert_that(_overlays.layer_modulate(BoardOverlays.Layer.ATTACK)).is_equal(OverlayManager.HEAL_ATTACK_MODULATE)


# A third atlas coord on the 2D layer -- #258's vertically-blocked reach -- must be routed
# EXPLICITLY: the old else branch mirrored any unknown coord as plain red reach, which is exactly
# how the blocked state would have silently vanished in 3D. Its colour is DERIVED (the live reach
# modulate dimmed by one factor), never a second authored colour.
func test_blocked_reach_cells_route_to_their_own_layer() -> void:
	var attacker := _spawn(PLAYER, Vector2i(2, 2))
	attacker.equipped_weapon = H.make_weapon(3)
	(attacker.get_equipped_weapon() as WeaponInstance).template.main_attack.up_tolerance = 1
	var ledge := Vector2i(3, 2)
	game.board_heights.set_cell(ledge, 4)
	game.enter_attack_mode(attacker)
	await _settle()

	# The ledge cell, on the row its own height puts it on.
	var on_the_ledge := BoardSpace.of_cell(ledge, BoardSpace.top_row_of(4))
	var expected: Array[Vector3i] = [on_the_ledge]
	assert_that(_sorted_3d(BoardOverlays.Layer.ATTACK_BLOCKED)).is_equal(expected)
	assert_bool(_sorted_3d(BoardOverlays.Layer.ATTACK).has(on_the_ledge)).is_false()
	assert_int(_sorted_3d(BoardOverlays.Layer.ATTACK).size()) \
		.is_equal(_om().attack_overlay.get_used_cells().size() - 1)
	var m: Color = _om().attack_overlay.modulate
	var dim: float = OverlayManager.BLOCKED_REACH_DIM
	assert_that(_overlays.layer_modulate(BoardOverlays.Layer.ATTACK_BLOCKED)) \
		.is_equal(Color(m.r * dim, m.g * dim, m.b * dim, m.a))


# The sight line (#258) reaches the diorama as a polyline at the trajectory's own heights, gated
# on the store's version (#308's rule), and clears when the trace clears. The world mapping is
# hand-derived here (the independent spelling): rule-height h sits at world surface_y(0) + h * CELL_SIZE.
func test_sight_trace_line_reaches_the_diorama_and_clears() -> void:
	var attacker := _spawn(PLAYER, Vector2i(2, 2))
	var foe := _spawn(ENEMY, Vector2i(3, 2))
	attacker.equipped_weapon = H.make_weapon(3)
	game.enter_attack_mode(attacker)
	game.selected_unit = attacker
	game.hover_presenter._hover_attack_targeting(foe.movement.cell)
	await _settle()

	var trace: Reach.SightTrace = _om().sight_trace
	assert_object(trace).is_not_null()
	var line := _overlays.line_of(BoardOverlays.Layer.SIGHT_TRACE)
	assert_int(line.size()).is_equal(trace.points.size())
	var first: Vector3 = trace.points[0]
	# The trace's y counts height UNITS (#427), and since slice 2 a ROW is that same unit — so the
	# world lift is one multiply off the height-0 surface rather than a divide down from a level.
	assert_that(line[0]).is_equal(Vector3(
		first.x * BoardSpace.CELL_SIZE,
		BoardSpace.surface_y(BoardSpace.top_row_of(0)) + first.y * BoardSpace.ROW_HEIGHT,
		first.z * BoardSpace.CELL_SIZE))

	game.exit_current_mode()
	await _settle()
	assert_int(_overlays.line_of(BoardOverlays.Layer.SIGHT_TRACE).size()).is_equal(0)


func test_target_pick_markers_split_from_the_reach_fill() -> void:
	var rescuer := _spawn(PLAYER, Vector2i(2, 2))
	var body := _spawn(PLAYER, Vector2i(3, 2))
	var candidates: Array[Unit] = [body]
	game.enter_target_pick_mode(candidates, func(_u: Unit) -> void: pass)
	await _settle()
	assert_object(rescuer).is_not_null()
	# The 2D draws picks on the ATTACK layer with a different atlas tile; the mirror
	# must split them — markers on TARGET_PICK, nothing on the reach fill.
	var picks := _overlays.markers_of(BoardOverlays.Layer.TARGET_PICK)
	assert_int(picks.size()).is_equal(1)
	assert_that(picks[0]["pos"]).is_equal(Vector3(3.5, 1.0, 2.5))
	# #316: a cut from a coord the atlas lacks used to return a non-null AtlasTexture with an
	# EMPTY region -- invisible, and `is_not_null` alone is exactly what passes against that.
	var pick_art := picks[0]["texture"] as AtlasTexture
	assert_object(pick_art).is_not_null()
	assert_bool(pick_art.region.has_area()).is_true()
	assert_int(_overlays.cells_of(BoardOverlays.Layer.ATTACK).size()).is_equal(0)


func test_aim_footprint_and_tile_pulse_ride_the_poll() -> void:
	var attacker := _spawn(PLAYER, Vector2i(2, 2))
	var foe := _spawn(ENEMY, Vector2i(3, 2))
	attacker.equipped_weapon = H.make_weapon(3)
	attacker.get_equipped_weapon().template.main_attack.targets = EquippableData.TargetMode.BOTH
	game.enter_attack_mode(attacker)
	game.selected_unit = attacker
	game.hover_presenter._hover_attack_targeting(foe.movement.cell)
	await _settle()
	assert_bool(_om().hover_overlay.get_used_cells().size() > 0).is_true()
	assert_that(_sorted_3d(BoardOverlays.Layer.AIM)).is_equal(_lifted(_om().hover_overlay))
	# The pulse is the 2D layer's live modulate, polled — no 3D tween. Drive one poll
	# synchronously so the copy and the read see the same tween frame.
	assert_object(_om()._tile_pulse).is_not_null()
	var live: Color = _om().hover_overlay.modulate
	_mirror._process(0.0)
	assert_that(_overlays.layer_modulate(BoardOverlays.Layer.AIM)).is_equal(live)


# --- Units -------------------------------------------------------------------------

func test_unit_pulse_reaches_the_mirrored_sprite() -> void:
	var attacker := _spawn(PLAYER, Vector2i(2, 2))
	var foe := _spawn(ENEMY, Vector2i(3, 2))
	attacker.equipped_weapon = H.make_weapon(3)
	game.enter_attack_mode(attacker)
	game.selected_unit = attacker
	game.hover_presenter._hover_attack_targeting(foe.movement.cell)
	await _settle()
	assert_object(foe.visuals.pulse_tween).is_not_null()   # the 2D pulse is live
	# The PRODUCT, sampled at this instant: 2D multiplies the Unit node's faction tint down
	# onto its sprite's pulse, so tint x pulse is what the screen shows (#232). Reading the
	# child alone is the bug that left this foe un-reddened in 3D.
	var live: Color = foe.modulate * foe.visuals.sprite.modulate
	_unit_mirror.reconcile()
	var sprite: UnitSprite3D = _unit_mirror.sprite_for(foe)
	assert_that(sprite.modulate).is_equal(live)
	# And the two COMPOSE rather than one replacing the other: a pulsing enemy still reads red.
	assert_bool(sprite.modulate.r > sprite.modulate.g).override_failure_message(
			"the pulse overwrote the faction tint instead of multiplying with it").is_true()


func test_a_queued_move_mirrors_ghost_hide_and_arrows() -> void:
	var unit := _spawn(PLAYER, Vector2i(2, 2))
	game.enter_move_mode(unit)
	game.selected_unit = unit
	game._on_left_click(Vector2i(3, 2))   # the documented dispatcher idiom: queue the move
	await _settle()
	var move: MoveAction = _om().planned_move_by_unit.get(unit)
	assert_object(move).is_not_null()
	# Ghost at the destination, tinted exactly as 2D tints it; the real sprite hides.
	assert_int(_unit_mirror.ghost_count()).is_equal(1)
	assert_bool(_unit_mirror.sprite_for(unit).visible).is_false()
	# One arrow marker per retained preview sprite, same texture REF, same tint.
	var markers := _overlays.markers_of(BoardOverlays.Layer.PATH_ARROWS)
	assert_int(markers.size()).is_equal(move.preview.size())
	assert_bool(markers.size() > 0).is_true()
	assert_that(markers[0]["texture"]).is_equal(move.preview[0].texture)
	assert_that(markers[0]["modulate"]).is_equal(move.preview[0].modulate)


func test_a_ghost_sorts_where_its_priority_is_actually_read() -> void:
	# #317, found in play: arrows and freeze icons drew over planning ghosts even though every
	# UnitSprite3D carries UNIT_RENDER_PRIORITY. A ghost is TRANSLUCENT, and OPAQUE_PREPASS writes
	# depth only above the prepass threshold — so a ghost wrote none, and priority does not
	# arbitrate outside the alpha queue. Driven through the real ghost path, because the POOL is
	# what shipped wrong; the constructor was always carrying the number.
	var unit := _spawn(PLAYER, Vector2i(2, 2))
	game.enter_move_mode(unit)
	game.selected_unit = unit
	game._on_left_click(Vector2i(3, 2))
	await _settle()
	assert_int(_unit_mirror.ghost_count()).is_equal(1)
	var ghost: UnitSprite3D = _unit_mirror._ghosts[0]
	assert_bool(ghost.modulate.a < 1.0).override_failure_message(
			"the ghost tint is opaque, so this case no longer covers the translucent path").is_true()
	assert_int(ghost.alpha_cut).override_failure_message(
			"a translucent ghost on OPAQUE_PREPASS writes no depth and is not priority-sorted, so "
			+ "board markup draws over it (#317)").is_equal(SpriteBase3D.ALPHA_CUT_DISABLED)
	# ...and the priority now doing the work really does outrank what was drawing over it.
	for layer: BoardOverlays.Layer in [BoardOverlays.Layer.PATH_ARROWS, BoardOverlays.Layer.TERRAIN]:
		var sort: int = BoardOverlays.LAYERS[layer]["sort"]
		assert_int(ghost.render_priority).override_failure_message(
				"layer %d sorts at %d, at or above the ghost" % [layer, sort]).is_greater(sort)


func test_hover_path_preview_mirrors_while_sweeping() -> void:
	var unit := _spawn(PLAYER, Vector2i(2, 2))
	game.enter_move_mode(unit)
	game.selected_unit = unit
	game.hover_presenter._hover_choosing_move(Vector2i(4, 2))
	await _settle()
	var preview: MoveAction = _om().hover_move_preview
	assert_object(preview).is_not_null()
	var markers := _overlays.markers_of(BoardOverlays.Layer.PATH_ARROWS)
	assert_int(markers.size()).is_equal(preview.preview.size())
	assert_bool(markers.size() > 0).is_true()
	var first: Sprite2D = preview.preview[0]
	assert_that(markers[0]["pos"]).is_equal(Vector3(
			first.global_position.x / 16.0, 1.0, first.global_position.y / 16.0))


func test_knockback_preview_mirrors_trail_and_landing_ghost() -> void:
	var foe := _spawn(ENEMY, Vector2i(3, 2))
	var path: Array[Vector2i] = [Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2)]
	var shoves: Array = [{"target": foe, "path": path, "to": Vector2i(5, 2)}]
	_om().show_knockback_preview(shoves)   # the one draw seam every shove preview crosses
	await _settle()
	var trails := _overlays.markers_of(BoardOverlays.Layer.KNOCKBACK)
	assert_bool(trails.size() > 0).is_true()
	# The landing ghost joins the unit-mirror pool; the real sprite hides behind it.
	assert_int(_unit_mirror.ghost_count()).is_equal(1)
	assert_bool(_unit_mirror.sprite_for(foe).visible).is_false()


# The honest trail (#259 rework, dev: the arrow should paint "in the air until he would drop,
# then point straight down to his destination"). A shove off a terrace: the flown cell's arrow
# hangs at the LAUNCH cell's level rather than lying on the ground below it, and the drop folds
# the ribbon down -- a half-cell BRIDGE at flight height carrying it from the landing cell's entry
# edge to that cell's CENTRE, then the RAIL falling from there onto the destination surface.
func test_a_cliff_shove_draws_its_trail_in_the_air_with_a_drop_pointer() -> void:
	var origin := Vector2i(3, 2)
	game.board_heights.set_cell(origin, 4)   # the cliff edge; (4,2)/(5,2) stay ground level
	var foe := _spawn(ENEMY, origin)
	var path: Array[Vector2i] = [origin, Vector2i(4, 2), Vector2i(5, 2)]
	var shoves: Array = [{"target": foe, "path": path, "to": Vector2i(5, 2),
			"removed": false, "landing_index": 2}]
	_om().show_knockback_preview(shoves)
	await _settle()

	var flight_y := BoardSpace.surface_transform(origin, game.board_heights).origin.y
	var ground_y := BoardSpace.surface_transform(Vector2i(4, 2), game.board_heights).origin.y
	assert_bool(flight_y > ground_y).override_failure_message(
			"the terrace never rose; the case is vacuous").is_true()
	# The FLOWN cell (4,2): its marker must carry the launch height, not the ground under it.
	var flown_x := (4.0 * 16.0 + 8.0) / 16.0
	var found := false
	for marker: Dictionary in _overlays.markers_of(BoardOverlays.Layer.KNOCKBACK):
		var pos: Vector3 = marker["pos"]
		if absf(pos.x - flown_x) < 0.01 and _is_flat(marker):
			found = true
			assert_float(pos.y).override_failure_message(
					"the flown cell's arrow lies on the ground under the flight (y %f, flight %f)"
					% [pos.y, flight_y]).is_equal_approx(flight_y, 0.001)
	assert_bool(found).override_failure_message("no trail marker over the flown cell").is_true()
	# The drop: ONE vertical rail, starting down at the landing cell's ENTRY EDGE (x = 5.0,
	# z = the cell centre). It falls immediately rather than after crossing half the tile,
	# because the flat arrow it lands on begins at that same edge -- a fold further in leaves
	# that much flat shaft sticking out behind the foot (dev, #431 round 5). Its BAND runs across
	# the trail, the same direction the flat arrows' thickness runs, so the drop reads as the
	# trail continuing. One quad, never a cross: the rig's pitch is fixed, so a vertical quad
	# across the trail never goes edge-on.
	var rails := _rail_markers()
	assert_int(rails.size()).is_equal(1)
	var rail: Dictionary = rails[0]
	var pos: Vector3 = rail["pos"]
	assert_float(pos.x).is_equal_approx(5.0 + OverlayMirror.WALL_CLEARANCE, 0.001)
	assert_float(pos.z).is_equal_approx(2.5, 0.001)
	var basis: Basis = rail["basis"]
	# It spans the whole drop, plus the deliberate overshoot at each end -- a butt joint between
	# two quads meeting at a right angle can leave a sub-pixel sliver where neither covers the
	# corner, and a hair of overlap into art of the same colour cannot.
	assert_float(absf(basis.x.y)).is_equal_approx(
			flight_y - ground_y + OverlayMirror.JOIN_OVERLAP * 2.0, 0.001)
	assert_float(basis.x.x).is_equal_approx(0.0, 0.001)   # rail axis is PURELY vertical
	assert_float(basis.x.z).is_equal_approx(0.0, 0.001)
	assert_float(basis.y.x).is_equal_approx(1.0, 0.001)   # face normal along travel (RIGHT)
	assert_float(basis.y.y).is_equal_approx(0.0, 0.001)
	assert_float(basis.y.z).is_equal_approx(0.0, 0.001)
	assert_float(basis.z.x).is_equal_approx(0.0, 0.001)   # band runs ACROSS the trail
	assert_float(basis.z.y).is_equal_approx(0.0, 0.001)
	assert_float(basis.z.z).is_equal_approx(1.0, 0.001)
	assert_object(rail["texture"]).is_not_null()
	# ONE marker per break, and no companion piece: the fold is at the edge, so there is no half
	# cell left for a bridge to close. Every OTHER knockback marker is a flat trail arrow lying on
	# a cell centre.
	for marker: Dictionary in _overlays.markers_of(BoardOverlays.Layer.KNOCKBACK):
		if marker == rail:
			continue
		var other: Vector3 = marker["pos"]
		assert_float(absf(other.x - floorf(other.x) - 0.5)).override_failure_message(
				"a knockback marker sits off a cell centre at x %f -- a stray drop piece?"
				% other.x).is_less(0.001)
	# The layer's clearance is applied along the marker's own plane NORMAL by the sink, never to
	# the marker data -- so this reads the LIVE quad, and for a vertical rail that normal is the
	# travel direction, i.e. straight out of the cliff face it hangs on.
	var rail_quads: Array[MeshInstance3D] = []
	for child in _overlays.get_children():
		var quad := child as MeshInstance3D
		if quad != null and quad.visible and quad.mesh is PlaneMesh \
				and not quad.basis.y.normalized().is_equal_approx(Vector3.UP):
			rail_quads.append(quad)
	assert_int(rail_quads.size()).is_equal(1)
	assert_float(rail_quads[0].position.z).is_equal_approx(2.5, 0.001)
	# THE JOIN, at BOTH ends. The pointer has to reach the plane each flat arrow was drawn in --
	# never stop short of it, which is a visible break, and never overshoot by more than the
	# deliberate overlap. Only readable on the LIVE quads, because that plane is the layer's own
	# clearance and the sink is what applies it, which is why nothing here caught the lift
	# regression the first two times it shipped (#431).
	var rail_quad := rail_quads[0]
	var rail_top := rail_quad.position.y + absf(rail_quad.basis.x.y) * 0.5
	var rail_foot := rail_quad.position.y - absf(rail_quad.basis.x.y) * 0.5
	var air_quad := _flat_quad_at(flown_x)
	var land_quad := _flat_quad_at(5.5)
	assert_object(air_quad).override_failure_message(
			"no flat arrow over the flown cell to join").is_not_null()
	assert_object(land_quad).override_failure_message(
			"no flat arrowhead on the landing cell to join").is_not_null()
	assert_float(rail_top - air_quad.position.y).override_failure_message(
			"the pointer's top misses the arrow it falls from -- the ribbon breaks at the corner") \
			.is_between(0.0, OverlayMirror.JOIN_OVERLAP + 0.001)
	assert_float(land_quad.position.y - rail_foot).override_failure_message(
			"the pointer's foot misses the arrow it lands on -- the ribbon breaks at the bottom") \
			.is_between(0.0, OverlayMirror.JOIN_OVERLAP + 0.001)
	# ...and it still starts falling AT that corner. The wall clearance keeps it off the coplanar
	# cliff face, but it must stay invisibly small: at the layer lift's own size it would step the
	# top visibly past the edge, which is the same break seen from the side.
	assert_float(rail_quad.position.x - 5.0).override_failure_message(
			"the pointer is not standing at the edge with a hair of wall clearance") \
			.is_between(0.0, 0.01)
	# On the LIVE material (the sink applies these, never the dict): double-sided, because the
	# pointer stands in the world and orbit reaches both its faces -- but it DEPTH-TESTS like
	# every other marker. Skipping the test made it an x-ray, drawn through the platform the
	# camera had panned behind (#431); standing clear of the cliff face is what fixed the
	# z-fight it was papering over.
	var mat := rail_quads[0].material_override as StandardMaterial3D
	assert_bool(mat.no_depth_test).override_failure_message(
			"the drop pointer skips the depth test -- it will draw through platforms").is_false()
	assert_int(mat.cull_mode).is_equal(BaseMaterial3D.CULL_DISABLED)


# The rail's band direction must NOT flip with the travel sign (#431): the flat arrows draw their
# thickness with a fixed orientation, so a band that mirrored for a LEFT shove shifted the rail's
# off-centre sprite a full pixel -- "matches in one direction, off by one in the other" (dev).
# LEFT keeps the same +Z band as RIGHT; only the face normal flips to the travel.
func test_a_left_shove_keeps_the_rail_band_consistent() -> void:
	var origin := Vector2i(5, 2)
	game.board_heights.set_cell(origin, 4)
	var foe := _spawn(ENEMY, origin)
	var path: Array[Vector2i] = [origin, Vector2i(4, 2), Vector2i(3, 2)]
	var shoves: Array = [{"target": foe, "path": path, "to": Vector2i(3, 2),
			"removed": false, "landing_index": 2}]
	_om().show_knockback_preview(shoves)
	await _settle()

	var rails := _rail_markers()
	assert_int(rails.size()).is_equal(1)
	var basis: Basis = rails[0]["basis"]
	assert_float(basis.y.x).is_equal_approx(-1.0, 0.001)   # face normal along travel (LEFT)
	assert_float(basis.y.z).is_equal_approx(0.0, 0.001)
	assert_float(basis.z.z).is_equal_approx(1.0, 0.001)   # band stays +Z, NOT mirrored
	assert_float(basis.z.x).is_equal_approx(0.0, 0.001)
	# LEFT enters the landing cell from the right, so the edge it starts falling at is x = 4.0 --
	# and its wall clearance leans the other way with it, always INTO the cell being fallen to.
	var pos: Vector3 = rails[0]["pos"]
	assert_float(pos.x).is_equal_approx(4.0 - OverlayMirror.WALL_CLEARANCE, 0.001)


# A shove off a cliff that LANDS on a ramp draws the rail (dev, #431): the unit FELL onto the
# slope, so the vertical story is real -- only a slide with no break skips it. Entered from the
# ramp's HIGH shoulder, a whole level below the flight.
func test_a_drop_onto_a_ramp_draws_a_drop_rail() -> void:
	var origin := Vector2i(3, 2)
	game.board_heights.set_cell(origin, 4)
	game.board_heights.set_cell(Vector2i(4, 2), 0, Terrain.RampRise.WEST)
	var foe := _spawn(ENEMY, origin)
	var path: Array[Vector2i] = [origin, Vector2i(4, 2)]
	var shoves: Array = [{"target": foe, "path": path, "to": Vector2i(4, 2),
			"removed": false, "landing_index": 1}]
	_om().show_knockback_preview(shoves)
	await _settle()
	var rails := _rail_markers()
	assert_int(rails.size()).override_failure_message(
			"a drop onto a ramp drew no rail -- the fall is the vertical story").is_equal(1)
	# And its FOOT lands in the plane the slope's own arrow is DRAWN in, at the edge the fall
	# arrives on. Three candidate answers, and only one is right: not the ramp's CENTRE (half a
	# level lower -- the tail of #431 round 5), and not the raw SURFACE at the edge either, because
	# the sink lifts every marker clear of the ground it lies on. Since #432 that lift is a CONSTANT
	# straight up, so the drawn plane is the surface plus it on a slope exactly as on the flat -- a
	# lift that leaned with the normal again would miss this band by most of its own length. Every
	# term derived from the board and the sink.
	var ramp := Vector2i(4, 2)
	var basis: Basis = rails[0]["basis"]
	var foot: float = (rails[0]["pos"] as Vector3).y - absf(basis.x.y) * 0.5
	var surface := BoardSpace.surface_transform(ramp, game.board_heights)
	var lift := _overlays.marker_lift(BoardOverlays.Layer.KNOCKBACK)
	var edge_y := BoardSpace.surface_height_at(ramp, 4.0, 2.5, game.board_heights)
	var drawn_at_edge := edge_y + lift
	assert_bool(edge_y > surface.origin.y).override_failure_message(
			"the ramp's edge and centre are level; the case cannot tell them apart").is_true()
	assert_bool(absf(surface.basis.y.y - 1.0) > 0.01).override_failure_message(
			"the ramp is not sloped; a tilt-dependent lift could not show itself here").is_true()
	assert_float(foot).override_failure_message(
			"the pointer's foot misses the plane the slope's arrow is drawn in") \
			.is_between(drawn_at_edge - OverlayMirror.JOIN_OVERLAP - 0.001, drawn_at_edge + 0.001)


# A pure SLIDE onto a ramp draws no rail -- the flat arrow on the slope is the whole story. The
# unit steps onto the ramp's HIGH shoulder level with its own footing and only then descends, so
# the two surfaces MEET at the shared edge and nothing has broken. No flag says so: the geometry
# does, which is why both sides must be measured AT THE EDGE. Measured at the cell's centre this
# board reads as half a level of fall, because a ramp's centre is half a level under its shoulder
# -- and that is the mutant this case exists to catch.
func test_a_slide_onto_a_ramp_draws_no_drop_rail() -> void:
	var origin := Vector2i(3, 2)
	var ramp := Vector2i(4, 2)
	game.board_heights.set_cell(origin, 2)
	game.board_heights.set_cell(ramp, 0, Terrain.RampRise.WEST)   # high shoulder faces the shove
	var foe := _spawn(ENEMY, origin)
	var flight_y := BoardSpace.surface_transform(origin, game.board_heights).origin.y
	var ramp_centre_y := BoardSpace.surface_transform(ramp, game.board_heights).origin.y
	assert_bool(ramp_centre_y < flight_y).override_failure_message(
			"the ramp's centre is not under the flight; the case cannot catch the mutant").is_true()
	var path: Array[Vector2i] = [origin, ramp]
	var shoves: Array = [{"target": foe, "path": path, "to": ramp,
			"removed": false, "landing_index": 1}]
	_om().show_knockback_preview(shoves)
	await _settle()
	assert_int(_rail_markers().size()).override_failure_message(
			"a slide onto a ramp hung a drop rail -- the slope's flat arrow is the whole story").is_equal(0)


# Cliff -> slide -> drop (the dev's report, #431): a shove that falls onto a ramp, tumbles down it
# and then plummets off its lip breaks TWICE, and both breaks draw. The old gate stamped one flag
# on the ONE cell the flight ended on, so the second drop could not be expressed at all.
func test_a_tumble_that_plummets_draws_a_pointer_at_both_breaks() -> void:
	var origin := Vector2i(2, 2)
	var ramp := Vector2i(3, 2)
	var floor_cell := Vector2i(4, 2)
	game.board_heights.set_cell(origin, 8)
	game.board_heights.set_cell(ramp, 4, Terrain.RampRise.WEST)   # entered at its high shoulder
	game.board_heights.set_cell(floor_cell, 0)                    # the lip: a sheer 2-drop
	var foe := _spawn(ENEMY, origin)
	# Both breaks stated from the board, not from constants: the flight clears the ramp's shoulder,
	# and the ramp's lip hangs over the floor. Either being false makes the case vacuous.
	var flight_y := BoardSpace.surface_transform(origin, game.board_heights).origin.y
	var shoulder_y := BoardSpace.surface_height_at(ramp, 3.0, 2.5, game.board_heights)
	var lip_y := BoardSpace.surface_height_at(ramp, 4.0, 2.5, game.board_heights)
	var floor_y := BoardSpace.surface_transform(floor_cell, game.board_heights).origin.y
	assert_bool(flight_y > shoulder_y).override_failure_message("the flight does not clear the ramp").is_true()
	assert_bool(lip_y > floor_y).override_failure_message("the ramp does not overhang the floor").is_true()

	var path: Array[Vector2i] = [origin, ramp, floor_cell]
	var shoves: Array = [{"target": foe, "path": path, "to": floor_cell,
			"removed": false, "landing_index": 1}]   # the FLIGHT ends on the ramp; the rest tumbles
	_om().show_knockback_preview(shoves)
	await _settle()

	var rails := _rail_markers()
	assert_int(rails.size()).override_failure_message(
			"the tumble's own plummet drew no pointer -- only the flight's landing did").is_equal(2)
	var xs: Array[float] = []
	for marker: Dictionary in rails:
		xs.append((marker["pos"] as Vector3).x)
	xs.sort()
	# Each pointer stands AT the edge it falls over, offset only by the hair of WALL_CLEARANCE that
	# keeps it off the cliff face. This band used to be a whole marker_lift wider, because an end
	# landing on a slope leaned downhill by the ramp normal's horizontal part; #432 took that lean
	# out, so the tight band is the claim now -- it reds if the lift ever leans again. The second
	# term is float slop, not clearance.
	var slack := OverlayMirror.WALL_CLEARANCE + 0.0005
	assert_float(xs[0]).is_between(3.0, 3.0 + slack)   # the fall onto the ramp, at its top edge
	assert_float(xs[1]).is_between(4.0, 4.0 + slack)   # the plummet, at the lip it goes over


# A void removal draws the rail (the arrow curves down into the hole) but no FLAT arrowhead on the
# hole cell itself -- the landing sprite's texture is nulled, and the rail alone says where it went.
# NB the drop's own bridge is flat too, but it sits at the QUARTER point (the entry edge to the
# fold), so the cell-centre test below still means "no arrowhead" and not "no markers at all".
func test_a_void_removal_draws_no_arrowhead_but_a_rail() -> void:
	var origin := Vector2i(3, 2)
	game.board_heights.set_cell(origin, 4)
	var foe := _spawn(ENEMY, origin)
	var path: Array[Vector2i] = [origin, Vector2i(4, 2)]
	var shoves: Array = [{"target": foe, "path": path, "to": Vector2i(4, 2),
			"removed": true, "landing_index": 1}]
	_om().show_knockback_preview(shoves)
	await _settle()

	var rails := _rail_markers()
	assert_int(rails.size()).override_failure_message(
			"a void removal drew no drop rail").is_equal(1)
	# It falls the WHOLE plummet, not one tile into the hole (dev: "for spectacle, it should go
	# down a bunch, offscreen") -- the same distance the sprite itself falls in execution, so the
	# preview cannot promise a shorter drop than playback shows. Asserted against the knob rather
	# than a number: tuning a feel value must never redden the suite.
	var flight_y := BoardSpace.surface_transform(origin, game.board_heights).origin.y
	var lip_y := BoardSpace.surface_height_at(Vector2i(4, 2), 4.0, 2.5, game.board_heights)
	var span := -(rails[0]["basis"] as Basis).x.y
	assert_float(span).override_failure_message(
			"the void pointer stops short of the plummet the unit actually falls") \
			.is_equal_approx(flight_y - lip_y + MovementComponent.VOID_PLUMMET_CELLS
					+ OverlayMirror.JOIN_OVERLAP * 2.0, 0.001)
	var landing_x := (4.0 * 16.0 + 8.0) / 16.0
	var flat_at_hole := 0
	for marker: Dictionary in _overlays.markers_of(BoardOverlays.Layer.KNOCKBACK):
		if _is_flat(marker) and absf((marker["pos"] as Vector3).x - landing_x) < 0.01:
			flat_at_hole += 1
	assert_int(flat_at_hole).override_failure_message(
			"the hole cell drew a flat arrowhead").is_equal(0)


# A drop pointer's own axis (basis.x) runs overwhelmingly DOWN; a ground marker's -- flat, or lying
# on a ramp, where the 45-degree tilt makes its horizontal and vertical parts exactly equal -- never
# does. A RATIO rather than "purely vertical", because a pointer whose foot lands on a slope leans
# a fraction off vertical to reach the arrow drawn there, and the two classes are still an order of
# magnitude apart.
func _is_flat(marker: Dictionary) -> bool:
	var x: Vector3 = ((marker.get("basis", Basis.IDENTITY)) as Basis).x
	return absf(x.y) <= Vector2(x.x, x.z).length() * 2.0


# The LIVE flat-lying quad whose centre sits at this x, or null. Flat markers are the ones whose
# plane normal is up; the drop pointer's is not, which is what tells the two apart in the pool.
func _flat_quad_at(x: float) -> MeshInstance3D:
	for child in _overlays.get_children():
		var quad := child as MeshInstance3D
		if quad != null and quad.visible and quad.mesh is PlaneMesh \
				and quad.basis.y.normalized().is_equal_approx(Vector3.UP) \
				and absf(quad.position.x - x) < 0.01:
			return quad
	return null


func _rail_markers() -> Array[Dictionary]:
	var rails: Array[Dictionary] = []
	for marker: Dictionary in _overlays.markers_of(BoardOverlays.Layer.KNOCKBACK):
		if not _is_flat(marker):
			rails.append(marker)
	return rails


# --- Squad + board channels --------------------------------------------------------

func test_squad_fills_and_icons_mirror() -> void:
	var pair := _squad_pair()
	game.draw_squad_leader_range(pair[0].squad, pair[0].movement.cell)
	_om().redraw_squad_unit_icons(pair[0].squad)
	await _settle()
	assert_bool(_om().squadrange_overlay.get_used_cells().size() > 0).is_true()
	assert_that(_sorted_3d(BoardOverlays.Layer.SQUAD_RANGE)).is_equal(_lifted(_om().squadrange_overlay))
	# Ring style is the default (#325): one GROUND decal per 2D MEMBER icon, texture AND tint
	# copied off the 2D sprite -- the squad hue is authored 2D-side, and the mirror must never
	# re-derive it. CROWN entries stay off the ground (the bar badge is the leader's mark).
	var member_count := 0
	var textures: Array = []
	var tints: Array = []
	for unit in _om().icons_by_unit:
		for type in _om().icons_by_unit[unit]:
			if type != OverlayIcon.IconType.SQUADMEMBER:
				continue
			member_count += 1
			var sprite: Sprite2D = (_om().icons_by_unit[unit][type] as OverlayIcon).sprite
			textures.append(sprite.texture)
			tints.append(sprite.modulate)
	assert_bool(member_count >= 2).is_true()
	var markers := _overlays.markers_of(BoardOverlays.Layer.GROUND_ICONS)
	assert_int(markers.size()).is_equal(member_count)
	for marker in markers:
		assert_bool(textures.has(marker["texture"])).is_true()
		assert_bool(tints.has(marker["modulate"])).override_failure_message(
				"a ground decal's tint is not the 2D sprite's -- the hue stopped arriving by copy").is_true()
	# The two channels split by TYPE, not by mode (#325 verdict): rings on the ground, the leader's
	# crown over the head. One squad, one leader, so exactly one head marker.
	assert_int(_overlays.markers_of(BoardOverlays.Layer.ICONS).size()).is_equal(1)


func test_the_leader_wears_the_crown_over_the_head_and_a_ring_underfoot() -> void:
	var pair := _squad_pair()
	_om().redraw_squad_unit_icons(pair[0].squad)
	await _settle()
	# #325's verdict, and the half that was DEAD between 2026-08-18 and the verdict: the crown is
	# produced in 2D (it always was) and the 3D mirror has to carry it to the head channel. Ring
	# mode used to drop it on the floor of _icons and badge the health bar instead.
	assert_bool(_om().icons_by_unit[pair[0]].has(OverlayIcon.IconType.CROWN)).is_true()
	var crown: Texture2D = OverlayManager.ICON_TEXTURES[OverlayIcon.IconType.CROWN]
	var heads := _overlays.markers_of(BoardOverlays.Layer.ICONS)
	assert_int(heads.size()).override_failure_message(
			"the crown never reached the head channel -- the 3D mirror dropped it").is_equal(1)
	assert_bool(heads[0]["texture"] == crown).is_true()

	# ...and it is NOT also on the ground. The leader still gets a ring there, because they are a
	# member too, so the ground channel holds rings only -- never the crown.
	for marker in _overlays.markers_of(BoardOverlays.Layer.GROUND_ICONS):
		assert_bool(marker["texture"] == crown).override_failure_message(
				"the crown landed on the ground channel as well as the head").is_false()
	assert_int(_overlays.markers_of(BoardOverlays.Layer.GROUND_ICONS).size()).override_failure_message(
			"the leader lost its own membership ring").is_equal(2)


func test_a_ring_on_a_ramp_lies_tilted_with_the_slope() -> void:
	# The #281 wire, extended to the ground-icon channel: a decal on a ramped cell must arrive
	# with a tilted basis, or it hangs level through the slope.
	var pair := _squad_pair()
	game.board_heights.set_cell(pair[0].movement.cell, 0, Terrain.RampRise.EAST)
	_om().redraw_squad_unit_icons(pair[0].squad)
	await _settle()
	var tilted := 0
	for marker in _overlays.markers_of(BoardOverlays.Layer.GROUND_ICONS):
		var lie: Basis = marker["basis"]
		if not lie.y.normalized().is_equal_approx(Vector3.UP):
			tilted += 1
	assert_int(tilted).override_failure_message(
			"every ground decal came through level -- the mirror is not keeping the surface basis").is_greater(0)


func test_a_ring_on_a_corner_cell_carries_the_shape_it_lies_on() -> void:
	# The case above's twin, and it exists because a mutant proved it had to: a corner cell's surface
	# is not a plane, so the basis is IDENTITY there and the FOLD travels as the cell's corners for
	# the renderer's mesh to carry (#427 slice 4 follow-up). Delete that key from OverlayMirror and
	# every case in this file still passes -- the renderer end is pinned in test_board_overlays and
	# the mirror end was not, which is #103's shape exactly.
	var pair := _squad_pair()
	var cell: Vector2i = pair[0].movement.cell
	var corners := Terrain.corners_of_form(0, Terrain.CORNER_NE, Terrain.UNITS_PER_LEVEL)
	game.board_heights.set_corners(cell, corners)
	_om().redraw_squad_unit_icons(pair[0].squad)
	await _settle()
	var folded := 0
	for marker in _overlays.markers_of(BoardOverlays.Layer.GROUND_ICONS):
		if marker.get("corners", Vector4i.ZERO) == corners:
			folded += 1
	assert_int(folded).override_failure_message(
			"no ground decal carried the corner cell's shape -- the mirror is dropping it, so every "
			+ "marker on a corner cell draws flat and cuts through the ground").is_greater(0)


func test_zone_fills_mirror_and_captured_zones_drop() -> void:
	var zones := {
		"cap": {"kind": ZoneManager.Kind.CAPTURE, "cells": [Vector2i(1, 1), Vector2i(2, 1)]},
		"ext": {"kind": ZoneManager.Kind.EXTRACTION, "cells": [Vector2i(6, 6)]},
	}
	game.zone_manager.load_dict(zones)
	_om().redraw_zones(game.zone_manager)
	await _settle()
	assert_that(_sorted_3d(BoardOverlays.Layer.ZONE_CAPTURE)) \
		.is_equal([BoardSpace.of_cell(Vector2i(1, 1), BoardSpace.top_row_of(0)), BoardSpace.of_cell(Vector2i(2, 1), BoardSpace.top_row_of(0))] as Array[Vector3i])
	assert_that(_sorted_3d(BoardOverlays.Layer.ZONE_EXTRACTION)) \
		.is_equal([BoardSpace.of_cell(Vector2i(6, 6), BoardSpace.top_row_of(0))] as Array[Vector3i])
	# A captured zone stops glowing in 2D (redraw_zones' hidden list) — and therefore in 3D.
	_om().redraw_zones(game.zone_manager, ["cap"])
	await _settle()
	assert_int(_overlays.cells_of(BoardOverlays.Layer.ZONE_CAPTURE).size()).is_equal(0)
	assert_int(_overlays.cells_of(BoardOverlays.Layer.ZONE_EXTRACTION).size()).is_equal(1)


func test_the_patrol_zone_and_picked_highlight_mirror_only_while_visible() -> void:
	# #231's whole point. PATROL is the tile brush's DEFAULT kind and had no 3D twin, so
	# zone painting in the 3D view drew nothing. Mirroring its cells alone is the opposite
	# error: the 2D shows that layer only while the Tile Brush tab is up, so an ungated
	# mirror leaks authoring scaffolding into the play view.
	game.zone_manager.load_dict({
		"patrol": {"kind": ZoneManager.Kind.PATROL, "cells": [Vector2i(3, 4), Vector2i(3, 5)]},
	})
	_om().redraw_zones(game.zone_manager)
	_om().redraw_zone_highlight([Vector2i(3, 4)])
	var patrol := _om().zone_overlay as TileMapLayer
	var highlight := _om().zone_highlight_overlay

	_om().set_zone_visibility(true)
	await _settle()
	assert_that(_sorted_3d(BoardOverlays.Layer.ZONE_PATROL)).override_failure_message(
			"a painted patrol zone is invisible in 3D").is_equal(_lifted(patrol))
	assert_bool(_overlays.cells_of(BoardOverlays.Layer.ZONE_PATROL).size() > 0).override_failure_message(
			"the case proves nothing — nothing was painted").is_true()
	assert_that(_sorted_3d(BoardOverlays.Layer.ZONE_HIGHLIGHT)).is_equal(_lifted(highlight))

	_om().set_zone_visibility(false)
	await _settle()
	assert_int(_overlays.cells_of(BoardOverlays.Layer.ZONE_PATROL).size()).override_failure_message(
			"patrol zones leaked into the play view").is_equal(0)
	assert_int(_overlays.cells_of(BoardOverlays.Layer.ZONE_HIGHLIGHT).size()).is_equal(0)
	# The 2D still HOLDS the cells — it is visibility that changed, not the data. Without
	# this the case would pass against a mirror that merely lost the zone.
	assert_bool(patrol.get_used_cells().size() > 0).override_failure_message(
			"the 2D dropped the cells, so the gate was never tested").is_true()


func test_the_2d_zone_layers_stay_dark_in_3d_while_the_mirror_draws_them() -> void:
	# Found in play: authoring zones drew TWICE in the 3D view — flat 2D tiles overlaid on
	# screen plus the 3D fills — because _set_board_visible deliberately skipped those two
	# layers (before the mirror existed they were the only way to see zones at all).
	#
	# The fix has to keep both halves true at once, which is why `.visible` cannot be the
	# gate: it is false in this host by design. The mirror reads the authoring INTENT.
	game.zone_manager.load_dict({
		"patrol": {"kind": ZoneManager.Kind.PATROL, "cells": [Vector2i(2, 2)]},
	})
	_om().redraw_zones(game.zone_manager)
	_om().set_zone_visibility(true)
	await _settle()

	var patrol := _om().zone_overlay as TileMapLayer
	assert_bool(patrol.visible).override_failure_message(
			"the flat 2D zone layer is drawing over the diorama").is_false()
	assert_int(_overlays.cells_of(BoardOverlays.Layer.ZONE_PATROL).size()).override_failure_message(
			"hiding the 2D layer took the 3D mirror down with it").is_equal(1)

	# FLAT_2D hands the board back, and the 2D layer must return — the intent never changed.
	_scene.view = _scene.View.FLAT_2D
	_scene._apply_hosting()
	await _settle()
	assert_bool(patrol.visible).override_failure_message(
			"the 2D zone layer never came back in the flat view").is_true()


func test_terrain_icons_mirror_with_the_standing_state_exception() -> void:
	game.terrain_states.load_state_dict({
		Vector2i(1, 1): [Terrain.TileState.FROZEN],
		Vector2i(2, 1): [Terrain.TileState.BURNING],
		Vector2i(4, 1): [Terrain.TileState.COVER],
	})
	_om().redraw_terrain_live(game.terrain_states)
	await _settle()
	# FROZEN mirrors as a flat icon; a state whose art draws OBJECTS does NOT — BoardMirror
	# stands its 3D form on the cell instead (the flame + light IS fire, #174: one Fire texture
	# covers BURNING and BLAZE; the mud bumps ARE cover, #326).
	var fire: Texture2D = OverlayManager.TERRAIN_STATE_ICONS[Terrain.TileState.BURNING]
	var ice: Texture2D = OverlayManager.TERRAIN_STATE_ICONS[Terrain.TileState.FROZEN]
	var live := _overlays.markers_of(BoardOverlays.Layer.TERRAIN)
	assert_int(live.size()).override_failure_message(
			"a state with a standing 3D form is also lying flat on the tile").is_equal(1)
	assert_that(live[0]["texture"]).is_equal(ice)
	# The PREVIEW keeps both: a pending ignite or Burrow has no 3D preview, so the ghosted
	# icon is the only warning the player gets.
	_om().show_terrain_preview([
		{"cell": Vector2i(3, 1), "state": Terrain.TileState.BURNING},
		{"cell": Vector2i(5, 1), "state": Terrain.TileState.COVER},
	])
	await _settle()
	var preview := _overlays.markers_of(BoardOverlays.Layer.TERRAIN_PREVIEW)
	assert_int(preview.size()).is_equal(2)
	assert_that(preview[0]["texture"]).is_equal(fire)
	assert_that(preview[0]["modulate"]).is_equal(OverlayManager.TERRAIN_PREVIEW_MODULATE)
	assert_that(preview[1]["texture"]).is_equal(
			OverlayManager.TERRAIN_STATE_ICONS[Terrain.TileState.COVER])


func test_exit_current_mode_clears_the_mirrored_layers() -> void:
	var pair := _squad_pair()
	game.enter_move_mode(pair[1])
	await _settle()
	assert_bool(_overlays.cells_of(BoardOverlays.Layer.MOVE).size() > 0).is_true()
	game.exit_current_mode()
	await _settle()
	assert_int(_overlays.cells_of(BoardOverlays.Layer.MOVE).size()).is_equal(0)
	assert_int(_overlays.cells_of(BoardOverlays.Layer.INVALID_MOVE).size()).is_equal(0)
	assert_int(_overlays.cells_of(BoardOverlays.Layer.AIM).size()).is_equal(0)
	assert_int(_overlays.markers_of(BoardOverlays.Layer.TARGET_PICK).size()).is_equal(0)


# --- Board reload (#318) ------------------------------------------------------------

# battle3d._on_board_loaded used to empty EVERY 3D layer while the mirror's push cache went on
# saying it had already drawn them. apply_scenario is synchronous end to end, so the mirror never
# observes the intermediate empty — it sees the same cells before and after, diffs equal, and the
# wiped layer stays wiped for the life of the board. Zones are the visible casualty for being the
# only markup static across a whole board; a gameplay layer self-heals within a click or two.
#
# Asserting the settled end state of a FIRST load passes against that bug (the cache starts empty),
# so this reloads an UNCHANGED board through the real funnel: capture_scenario -> apply_scenario ->
# board_loaded -> battle3d. The zones are hand-built rather than read off a mission, so nothing here
# pins authored content — they round-trip through ScenarioData.zones like any other board content.
func test_a_reload_of_an_unchanged_board_leaves_the_zone_fills_drawn() -> void:
	game.zone_manager.load_dict({
		"cap": {"kind": ZoneManager.Kind.CAPTURE, "cells": [Vector2i(1, 1), Vector2i(2, 1)]},
	})
	_om().redraw_zones(game.zone_manager)
	await _settle()
	var drawn := _sorted_3d(BoardOverlays.Layer.ZONE_CAPTURE)
	assert_array(drawn).override_failure_message(
			"nothing was drawn before the reload, so the reload could not lose it").is_not_empty()

	var manager: ScenarioManager = game.scenario_manager
	manager.apply_scenario(manager.capture_scenario("reload-test"))
	await _settle()
	# The 2D kept them, or the 3D would be right to be empty — assert the authority first.
	assert_that(_lifted(_om().capture_overlay)).override_failure_message(
			"the 2D lost the zones on reload, which is a different bug").is_equal(drawn)
	assert_that(_sorted_3d(BoardOverlays.Layer.ZONE_CAPTURE)).override_failure_message(
			"the board reloaded and its zones never came back in 3D").is_equal(drawn)


# Move the pointer the way the picker does, so everything past this line is the real hover wire:
# battle3d hands the cell to HoverPresenter, which resolves the unit and creates the icons.
func _point_at(cell: Vector2i) -> void:
	var heights: BoardHeights = game.board_heights
	_scene._pointer_cell = BoardSpace.of_cell(cell, BoardSpace.top_row_of(heights.elevation_at(cell)))


func test_with_rings_off_hovering_any_squadmate_crowns_the_leader_and_clears_on_the_way_out() -> void:
	# The TIMING half of #325's verdict, in the dev's own words: the crown "stays over the squad
	# leader whenever you are hovering over any squad member, like it did before". Nothing asserted
	# that end to end before -- get_squad_icons was never the thing that broke, the 3D mirror was,
	# and a case that draws the icons by hand cannot tell the two apart.
	#
	# The clearing half is TRUE ONLY WITH STANDING RINGS OFF, which before_test declares (#449):
	# with them on the crown stands with them, and that branch is pinned in test_standing_squad_rings.
	var pair := _squad_pair()
	_point_at(pair[1].movement.cell)   # the MEMBER, not the leader
	await _settle()

	var crown: Texture2D = OverlayManager.ICON_TEXTURES[OverlayIcon.IconType.CROWN]
	var heads := _overlays.markers_of(BoardOverlays.Layer.ICONS)
	assert_int(heads.size()).override_failure_message(
			"hovering a squadmate did not put a crown over the leader").is_equal(1)
	assert_bool(heads[0]["texture"] == crown).is_true()

	# It is over the LEADER, not the unit under the cursor.
	var leader_anchor := BoardSpace.surface_point(pair[0].movement.cell, game.board_heights)
	assert_float(heads[0]["pos"].x).is_equal_approx(leader_anchor.x, 0.01)
	assert_float(heads[0]["pos"].z).override_failure_message(
			"the crown is over the hovered member, not the leader").is_equal_approx(leader_anchor.z, 0.01)

	# Somewhere on the board with nobody on it. DERIVED, never a literal: hover draws nothing OFF
	# the painted board (update_hover_visuals returns early on a tileless cell), so "look away" has
	# to land on a real tile -- and which tiles exist is authored content this suite must not pin.
	var empty := GridUtils.NO_CELL
	for cell: Vector2i in game.grid.get_used_cells():
		if game.unit_at_pointer(cell) == null:
			empty = cell
			break
	assert_bool(empty != GridUtils.NO_CELL).override_failure_message(
			"the fixture board has no empty tile to look away at").is_true()
	_point_at(empty)
	await _settle()
	assert_int(_overlays.markers_of(BoardOverlays.Layer.ICONS).size()).override_failure_message(
			"the crown outlived the hover that raised it").is_equal(0)


# --- Guard ward marker (#414) -------------------------------------------------------

# The channel wire: an armed Guard's ground mark has to REACH the 3D view, because that is what the
# game boots into — a mark that only exists in the hidden 2D board is a mark nobody sees. The
# 2D-side store is pinned in tests/flow/test_guard_lifecycle_wires.gd; this is the other half, and
# it is exactly the split that made the marker look "not showing up" in play.
func test_an_armed_guards_ground_mark_reaches_the_3d_ward_channel() -> void:
	var pair := _squad_pair()
	pair[0].arm_guard(pair[1], pair[0].get_guard_range())
	game.refresh_guard_markers()
	await _settle()

	var ward_art: Texture2D = OverlayManager.ICON_TEXTURES[OverlayIcon.IconType.GUARD_WARD]
	var found := 0
	for marker in _overlays.markers_of(BoardOverlays.Layer.GUARD_ICONS):
		if marker["texture"] == ward_art:
			found += 1
	assert_int(found).override_failure_message(
			"the Guard's ward mark never reached its 3D channel — 3D is the view the game boots into"
			).is_equal(1)   # the WARD alone since #450; the blocker's end is the link below


# The link's half of the same wire (#450). Its own case rather than an assertion inside the one
# above, because the two halves reach 3D through DIFFERENT mirror branches — the shield rides
# _icons off icons_by_unit, the arrows ride _guard_links off guard_link_sprites — so a missing
# branch takes exactly one of them out and the other keeps passing.
func test_an_armed_guards_link_reaches_the_3d_view() -> void:
	var pair := _squad_pair()
	pair[0].arm_guard(pair[1], pair[0].get_guard_range())
	game.refresh_guard_markers()
	await _settle()

	# Two sprites for a one-step trail: the start tile under the blocker, the arrowhead on the ward.
	assert_int(game.overlay_manager.guard_link_sprites.size()).override_failure_message(
			"the 2D never drew the link, so this case cannot speak for the mirror").is_equal(2)
	assert_int(_overlays.markers_of(BoardOverlays.Layer.GUARD_LINK).size()).override_failure_message(
			"the blocker→ward link never reached 3D — the board there still cannot say which unit "
			+ "is covering which").is_equal(2)


# The Z-FIGHT, as a rule rather than a bug report. A layer IS a plane (_lift_of is
# fill_lift + sort * lift_step), so two markers that share a cell AND a sort are coplanar by
# construction and flicker. The ward mark and the squad ring share cells constantly — a blocker
# wears both — so they must never share a sort. Found in play, 2026-08-21.
func test_the_ward_mark_and_the_squad_ring_are_on_different_planes() -> void:
	var ring_sort: int = BoardOverlays.LAYERS[BoardOverlays.Layer.GROUND_ICONS]["sort"]
	var ward_sort: int = BoardOverlays.LAYERS[BoardOverlays.Layer.GUARD_ICONS]["sort"]
	assert_int(ward_sort).override_failure_message(
			"the ward mark shares a sort with the squad ring, so the two lift to the same plane "
			+ "and z-fight on any cell that carries both").is_not_equal(ring_sort)
	assert_float(_overlays.marker_lift(BoardOverlays.Layer.GUARD_ICONS)).override_failure_message(
			"same lift, so same plane — the sorts differ but the planes did not"
			).is_not_equal(_overlays.marker_lift(BoardOverlays.Layer.GROUND_ICONS))


# A ward mark can also share a cell with an aim fill, a target-pick marker, an arrow or a sight
# trace, so its sort has to be free of EVERY other layer's, not just the ring's. This is the rule
# that says why 8 and not 4 -- and it goes red the day someone else takes the slot.
#
# Widened to the LINK by #450 rather than copied for it: the arrow lands on the very cells the
# shield does, so both channels ask the identical question and one loop is the one answer. Checking
# each against every other layer covers the pair against each other too.
func test_both_guard_channels_sorts_are_unshared() -> void:
	var guard_layers: Array[BoardOverlays.Layer] = [
		BoardOverlays.Layer.GUARD_ICONS, BoardOverlays.Layer.GUARD_LINK]
	for guard_layer in guard_layers:
		for layer in BoardOverlays.LAYERS:
			if layer == guard_layer:
				continue
			assert_int(BoardOverlays.LAYERS[layer]["sort"]).override_failure_message(
					"%s now shares %s's sort — they will lift to one plane and z-fight"
					% [BoardOverlays.Layer.keys()[layer], BoardOverlays.Layer.keys()[guard_layer]]
				).is_not_equal(BoardOverlays.LAYERS[guard_layer]["sort"])


# The link draws OVER the shield, in both views (#450). 2D settles it by tree order -- the arrows'
# overlay is a later sibling than the icons' at the same z_index -- so 3D has to be told, and the
# two views disagreeing is the #292 drift this pins. Reverse both together or neither.
func test_the_guard_link_sorts_above_the_shield_it_points_at() -> void:
	assert_int(BoardOverlays.LAYERS[BoardOverlays.Layer.GUARD_LINK]["sort"]).override_failure_message(
			"the 3D draws the link under the shield while the 2D draws it over — one arrowhead, "
			+ "two answers").is_greater(BoardOverlays.LAYERS[BoardOverlays.Layer.GUARD_ICONS]["sort"])


# The SIZE law, and the reason this channel needs one at all: BoardOverlays sizes a ground quad as
# texture pixels / ART_PIXELS_PER_CELL, so 16px of art is exactly ONE cell. A 32px marker is a
# FOUR-cell decal sprawling over its neighbours — which is what shipping the Utumno tile at its
# native size did. Every board icon must be authored at the cell size, not the sheet's.
func test_every_board_icon_is_authored_at_one_cell() -> void:
	for type in OverlayManager.ICON_TEXTURES:
		var art: Texture2D = OverlayManager.ICON_TEXTURES[type]
		var cells: Vector2 = art.get_size() / BoardOverlays.ART_PIXELS_PER_CELL
		assert_that(cells).override_failure_message(
				"%s is %s px, i.e. %s cells wide in 3D — board icons are authored at %d px"
				% [OverlayIcon.IconType.keys()[type], str(art.get_size()), str(cells),
					int(BoardOverlays.ART_PIXELS_PER_CELL)]
			).is_equal(Vector2.ONE)


# The CENTRING law, the other half of the size one. A ground marker is drawn centred on its cell,
# so art that does not sit centred on its own canvas lands off-centre on the board -- which is what
# the first cut of the ward shield did (its art centred on (8.5, 6.5) against the ring's (7.5, 7.5),
# i.e. a pixel right and a pixel up, spotted by eye in play).
#
# CROWN is exempt and that is the point of the split: it is a head billboard, so where it sits
# vertically is its own business, not the cell's centre.
func test_every_ground_marker_is_centred_on_its_canvas() -> void:
	for type in [OverlayIcon.IconType.SQUADMEMBER, OverlayIcon.IconType.GUARD_WARD]:
		var art: Image = (OverlayManager.ICON_TEXTURES[type] as Texture2D).get_image()
		var centre := _solid_centre(art)
		var canvas := (Vector2(art.get_width(), art.get_height()) - Vector2.ONE) / 2.0
		assert_that(centre).override_failure_message(
				"%s's art centres on %s, but its canvas centres on %s -- it will draw off-centre "
				% [OverlayIcon.IconType.keys()[type], str(centre), str(canvas)]
				+ "on every cell it marks").is_equal(canvas)


# The bounding box of what is actually SOLID, centred. Alpha above 0.5 rather than above 0, because
# a smooth downscale leaves a faint halo on the border that would drag the box out to the canvas
# edge and make every icon look perfectly centred (measured: 29 of 256 px on the ward shield).
func _solid_centre(art: Image) -> Vector2:
	var min_p := Vector2i(9999, 9999)
	var max_p := Vector2i(-1, -1)
	for y in art.get_height():
		for x in art.get_width():
			if art.get_pixel(x, y).a > 0.5:
				min_p = Vector2i(mini(min_p.x, x), mini(min_p.y, y))
				max_p = Vector2i(maxi(max_p.x, x), maxi(max_p.y, y))
	return (Vector2(min_p) + Vector2(max_p)) / 2.0


# --- The shove trail's own colour (2026-08-21) ----------------------------------------------

# A predicted shove and an authored move used to draw IDENTICALLY -- show_knockback_preview passed
# Color.WHITE and _arrow_modulate returns Color.WHITE for a valid planned move -- so the board said
# the same thing about a unit's own order and about what was about to be done to it.
#
# The assertion is a RELATIONSHIP, never the hue: KNOCKBACK_MODULATE is a tuning value on the Game
# tab and pinning its components here would red the moment the dev drags the slider.
func test_a_shove_trail_does_not_wear_a_planned_moves_colour() -> void:
	var foe := _spawn(ENEMY, Vector2i(3, 2))
	var path: Array[Vector2i] = [Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2)]
	_om().show_knockback_preview([{"target": foe, "path": path, "to": Vector2i(5, 2)}])
	await _settle()

	var move := MoveAction.new()
	move.is_valid = true
	move.is_trailing = false
	var authored: Color = _om()._arrow_modulate(move)   # the planned-move tint, derived not typed
	assert_that(OverlayManager.KNOCKBACK_MODULATE).override_failure_message(
			"a shove draws in the same colour as an order the player authored"
			).is_not_equal(authored)

	var trails := _overlays.markers_of(BoardOverlays.Layer.KNOCKBACK)
	assert_bool(trails.size() > 0).override_failure_message(
			"no knockback markers reached 3D; the case is vacuous").is_true()
	for marker: Dictionary in trails:
		assert_that(marker["modulate"]).override_failure_message(
				"a knockback marker reached 3D wearing the planned-move colour").is_not_equal(authored)


# The drop pointer (#431) hardcoded its own Color.WHITE, so tuning the trail would have left the
# pointer behind -- one shove drawn in two colours, which reads as a bug rather than as a knob. It
# copies the sprite it hangs from now, the way every other flat marker already does.
func test_the_drop_pointer_wears_the_trail_it_hangs_from() -> void:
	var origin := Vector2i(3, 2)
	game.board_heights.set_cell(origin, 4)   # a cliff, so there is a break to point at
	var foe := _spawn(ENEMY, origin)
	var path: Array[Vector2i] = [origin, Vector2i(4, 2), Vector2i(5, 2)]
	_om().show_knockback_preview([{"target": foe, "path": path, "to": Vector2i(5, 2),
			"removed": false, "landing_index": 2}])
	await _settle()

	var pointers := 0
	for marker: Dictionary in _overlays.markers_of(BoardOverlays.Layer.KNOCKBACK):
		if _is_flat(marker):
			continue   # the pointer is the one whose plane is NOT lying on the ground
		pointers += 1
		assert_that(marker["modulate"]).override_failure_message(
				"the drop pointer kept a colour of its own while the trail moved"
				).is_equal(OverlayManager.KNOCKBACK_MODULATE)
	assert_bool(pointers > 0).override_failure_message(
			"the cliff drew no drop pointer; the case is vacuous").is_true()


# #476: a null default on get_meta is a NO-OP -- Godot treats it exactly like no default and
# raises when the key is absent, so the guard that exists to handle the meta-less first trail
# cell is what error-spammed the log, once per such cell per frame. The guard must ask has_meta
# first. This case pins the ERROR CHANNEL rather than the early return -- the return happens
# either way, so the log is the only observable difference. gdUnit4's assert_error registers an
# OS logger with both report flags forced true, so the engine's ERR_FAIL_V_MSG lands in its
# entries and is_success() fails on it.
func test_the_drop_pointer_guard_stays_silent_on_the_meta_less_first_cell() -> void:
	var sprite := Sprite2D.new()
	await assert_error(func (): _mirror._append_drop([], sprite)).is_success()
	sprite.free()


# The knob has to move a preview that is ALREADY up, or it is a slider that appears to do nothing
# until the next shove (#324's lesson, and the reason restyle_squad_markers exists next door).
func test_tuning_the_shove_colour_moves_a_preview_already_on_the_board() -> void:
	var foe := _spawn(ENEMY, Vector2i(3, 2))
	var path: Array[Vector2i] = [Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2)]
	_om().show_knockback_preview([{"target": foe, "path": path, "to": Vector2i(5, 2)}])
	await _settle()

	var before: Color = OverlayManager.KNOCKBACK_MODULATE
	OverlayManager.KNOCKBACK_MODULATE = Color(before.r, before.g, before.b, before.a * 0.5)
	_om().restyle_knockback_trail()
	await _settle()

	for marker: Dictionary in _overlays.markers_of(BoardOverlays.Layer.KNOCKBACK):
		assert_that(marker["modulate"]).override_failure_message(
				"a standing shove preview kept the old colour after the knob moved"
				).is_equal(OverlayManager.KNOCKBACK_MODULATE)


# The ghost that stands in for a SHOVED unit was invisible to the queue-row highlight: the real
# sprite is hidden (set_projected), but has_projected_unit only knew about the MOVE ghost store, so
# HoverPresenter._highlight_unit fell through to UnitVisuals.set_highlighted and wrote its modulate
# to a node nothing draws -- in the flat view and the diorama alike.
func test_a_shoved_units_ghost_can_be_highlighted() -> void:
	var foe := _spawn(ENEMY, Vector2i(3, 2))
	var path: Array[Vector2i] = [Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2)]
	_om().show_knockback_preview([{"target": foe, "path": path, "to": Vector2i(5, 2)}])
	await _settle()

	assert_bool(foe.visuals.projected).override_failure_message(
			"the shove never hid the real sprite; the case is vacuous").is_true()
	assert_bool(_om().has_projected_unit(foe)).override_failure_message(
			"the board is standing a ghost in for this unit but will not admit it"
			).is_true()

	_om().set_projected_unit_highlighted(foe, true)
	var ghost: Sprite2D = _om().knockback_ghost_by_unit[foe]
	assert_that(ghost.modulate).override_failure_message(
			"highlighting a shoved unit moved nothing the player can see"
			).is_equal(OverlayManager.PROJECTED_HIGHLIGHT)

	_om().set_projected_unit_highlighted(foe, false)
	assert_that(ghost.modulate).is_equal(OverlayManager.PROJECTED_MODULATE)
