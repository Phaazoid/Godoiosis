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


func before_test() -> void:
	get_tree().root.size = Vector2i(1280, 720)
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
	get_tree().root.remove_child(_scene)
	_scene.free()


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


func _om() -> OverlayManager:
	return game.overlay_manager


# The independent expectation: the 2D layer's cells, hand-lifted to flat-3D, sorted.
func _lifted(layer_2d: TileMapLayer) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for cell: Vector2i in layer_2d.get_used_cells():
		cells.append(Vector3i(cell.x, 0, cell.y))
	cells.sort()
	return cells


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
# content. It is painted BEFORE the mode is entered because _fill diffs on the CELL LIST: a rise
# added under an already-drawn overlay does not change any cell, so it would not re-push.
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

	# EAST so the ramp is entered along its own axis from the west, keeping it reachable.
	painted.sort()
	var ramp: Vector2i = painted[0]
	game.board_heights.set_cell(ramp, 0, Terrain.RampRise.EAST)

	game.enter_move_mode(mover)
	await _settle()
	var still_painted: Array[Vector2i] = _om().move_overlay.get_used_cells()
	assert_bool(still_painted.has(ramp)).override_failure_message(
			"the ramped cell fell out of range -- nothing tilted would be drawn").is_true()

	var tilted := 0
	for child in _overlays.get_children():
		var quad := child as MeshInstance3D
		if quad != null and quad.visible and quad.mesh is PlaneMesh \
				and not quad.basis.y.normalized().is_equal_approx(Vector3.UP):
			tilted += 1
	assert_int(tilted).override_failure_message(
			"every fill came through level -- the mirror is not handing its heights to set_cells") \
		.is_greater(0)


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
	assert_object(picks[0]["texture"]).is_not_null()
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
	var shoves: Array = [{"target": foe, "from": Vector2i(3, 2), "to": Vector2i(5, 2)}]
	_om().show_knockback_preview(shoves)   # the one draw seam every shove preview crosses
	await _settle()
	var trails := _overlays.markers_of(BoardOverlays.Layer.KNOCKBACK)
	assert_bool(trails.size() > 0).is_true()
	# The landing ghost joins the unit-mirror pool; the real sprite hides behind it.
	assert_int(_unit_mirror.ghost_count()).is_equal(1)
	assert_bool(_unit_mirror.sprite_for(foe).visible).is_false()


# --- Squad + board channels --------------------------------------------------------

func test_squad_fills_and_icons_mirror() -> void:
	var pair := _squad_pair()
	game.draw_squad_leader_range(pair[0].squad, pair[0].movement.cell)
	_om().redraw_squad_unit_icons(pair[0].squad)
	await _settle()
	assert_bool(_om().squadrange_overlay.get_used_cells().size() > 0).is_true()
	assert_that(_sorted_3d(BoardOverlays.Layer.SQUAD_RANGE)).is_equal(_lifted(_om().squadrange_overlay))
	# One billboard per 2D icon (crown + squadmember), textures copied.
	var icon_count := 0
	var textures: Array = []
	for unit in _om().icons_by_unit:
		for type in _om().icons_by_unit[unit]:
			icon_count += 1
			textures.append((_om().icons_by_unit[unit][type] as OverlayIcon).sprite.texture)
	assert_bool(icon_count >= 2).is_true()
	var markers := _overlays.markers_of(BoardOverlays.Layer.ICONS)
	assert_int(markers.size()).is_equal(icon_count)
	for marker in markers:
		assert_bool(textures.has(marker["texture"])).is_true()


func test_zone_fills_mirror_and_captured_zones_drop() -> void:
	var zones := {
		"cap": {"kind": ZoneManager.Kind.CAPTURE, "cells": [Vector2i(1, 1), Vector2i(2, 1)]},
		"ext": {"kind": ZoneManager.Kind.EXTRACTION, "cells": [Vector2i(6, 6)]},
	}
	game.zone_manager.load_dict(zones)
	_om().redraw_zones(game.zone_manager)
	await _settle()
	assert_that(_sorted_3d(BoardOverlays.Layer.ZONE_CAPTURE)) \
		.is_equal([Vector3i(1, 0, 1), Vector3i(2, 0, 1)] as Array[Vector3i])
	assert_that(_sorted_3d(BoardOverlays.Layer.ZONE_EXTRACTION)) \
		.is_equal([Vector3i(6, 0, 6)] as Array[Vector3i])
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


func test_terrain_icons_mirror_with_the_fire_exception() -> void:
	game.terrain_states.load_state_dict({
		Vector2i(1, 1): [Terrain.TileState.FROZEN],
		Vector2i(2, 1): [Terrain.TileState.BURNING],
	})
	_om().redraw_terrain_live(game.terrain_states)
	await _settle()
	# FROZEN mirrors as an icon; fire does NOT — BoardMirror's flame + light IS
	# fire's 3D form (#174: one Fire texture covers BURNING and BLAZE).
	var fire: Texture2D = OverlayManager.TERRAIN_STATE_ICONS[Terrain.TileState.BURNING]
	var ice: Texture2D = OverlayManager.TERRAIN_STATE_ICONS[Terrain.TileState.FROZEN]
	var live := _overlays.markers_of(BoardOverlays.Layer.TERRAIN)
	assert_int(live.size()).is_equal(1)
	assert_that(live[0]["texture"]).is_equal(ice)
	# The PREVIEW keeps its fire: a pending ignite has no 3D flame preview, so the
	# ghosted icon is the only warning the player gets.
	_om().show_terrain_preview([{"cell": Vector2i(3, 1), "state": Terrain.TileState.BURNING}])
	await _settle()
	var preview := _overlays.markers_of(BoardOverlays.Layer.TERRAIN_PREVIEW)
	assert_int(preview.size()).is_equal(1)
	assert_that(preview[0]["texture"]).is_equal(fire)
	assert_that(preview[0]["modulate"]).is_equal(OverlayManager.TERRAIN_PREVIEW_MODULATE)


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
