# What a QUEUED attack leaves on the board (#1247): the queue row's own icon on a badge between
# attacker and target, counters in the same style, each mark in its own lane, the hovered unit's marks
# over everything, and the footprint only past one tile. Driven through the REAL queue door on the
# Battle3D scene, and asserted on the store AND on what the diorama was handed -- the wire is the claim.
#
# Fixture is test_overlay_mirror's: one shared Battle3D, a cleared board, units spawned per case. The
# hover pointer is borrowed per case through pointer_source (the 3D picker's own seam) and handed back,
# because a borrowed pointer outlives the case on a shared board.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _board := SharedBoard.new(SCENE_PATH)
var _scene: Node3D
var game: Node2D
var _overlays: BoardOverlays
var _pointer: Callable
var _pointed := GridUtils.NO_CELL


func before() -> void:
	await _board.open(self, _clear_the_board)


func _clear_the_board() -> void:
	_board.game.scenario_manager.clear_board()
	_board.game.game_state = _board.game.GameState.IDLE


func before_test() -> void:
	await _board.reset(self)
	_scene = _board.scene
	game = _board.game
	_overlays = _scene.get_node("BoardOverlays") as BoardOverlays
	_pointer = game.hover_presenter.pointer_source


func after_test() -> void:
	game.hover_presenter.pointer_source = _pointer
	await _board.check(self)


func after() -> void:
	_board.close()


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


func _om() -> OverlayManager:
	return game.overlay_manager


func _spawn(faction: Team.Faction, cell: Vector2i, armed := false) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).is_not_null()   # fixture setup, not the claim under test
	if armed:
		unit.add_item(H.make_weapon())
	return unit


# A weapon whose main lands on the aimed cell AND the one east of it -- a two-tile placed blast.
func _arm_with_blast(unit: Unit) -> void:
	var stamp: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0)]
	var shape := AttackShape.new()
	shape.stamp = stamp
	var weapon := H.make_weapon()
	weapon.template.main_attack.attack_shape = shape
	unit.add_item(weapon)


func _queue_attack(hero: Unit, aim: Vector2i) -> AttackAction:
	var action := AttackAction.declare(hero, hero.movement.cell, aim)
	assert_bool(game.squad_manager.queue_action(hero.squad, action)).override_failure_message(
			"fixture: the attack never queued (%s)" % ", ".join(action.validation_errors)).is_true()
	return action


func _entries_by(attacker: Unit) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry: Dictionary in _om().queued_strikes:
		if entry["attacker"] == attacker:
			found.append(entry)
	return found


func _badge_sprites() -> Array[Sprite3D]:
	var sprites: Array[Sprite3D] = []
	for node in _overlays._pool_for(BoardOverlays.Layer.QUEUED_BADGES):
		var sprite := node as Sprite3D
		if sprite != null and sprite.visible:
			sprites.append(sprite)
	return sprites


func _rows() -> Array[ActionQueueRow]:
	var rows: Array[ActionQueueRow] = []
	var pending: Array[Node] = [game.squad_action_queue_control]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is ActionQueueRow:
			rows.append(node as ActionQueueRow)
		pending.append_array(node.get_children())
	return rows


func _row_for(action: BaseAction) -> ActionQueueRow:
	for row in _rows():
		if row.action == action:
			return row
	return null


func _point_at(cell: Vector2i) -> void:
	_pointed = cell
	game.hover_presenter.pointer_source = func() -> Vector2i: return _pointed
	await _settle()


# --- One mark per row ------------------------------------------------------------------------------

func test_a_queued_attack_draws_one_badge_between_attacker_and_target() -> void:
	var hero := _spawn(PLAYER, Vector2i(2, 2), true)
	var foe := _spawn(ENEMY, Vector2i(3, 2))
	_queue_attack(hero, foe.movement.cell)
	await _settle()

	var mine := _entries_by(hero)
	assert_int(mine.size()).override_failure_message(
			"a queued attack left %d marks on the board, not one" % mine.size()).is_equal(1)
	assert_that(mine[0]["from"]).is_equal(hero.get_projected_destination())
	assert_that(mine[0]["to"]).is_equal(foe.movement.cell)
	# The diorama was handed it: a badge per mark, camera-facing.
	var badges := _overlays.markers_of(BoardOverlays.Layer.QUEUED_BADGES)
	assert_int(badges.size()).is_equal(_om().queued_strikes.size())
	var sprites := _badge_sprites()
	assert_bool(sprites.is_empty()).override_failure_message("no badge sprite was drawn").is_false()
	assert_int(sprites[0].billboard).is_equal(BaseMaterial3D.BILLBOARD_ENABLED)
	# ...and so was the flat view.
	var flat := _om().get_node("StrikeMarks2D") as StrikeMarks2D
	assert_int(flat.entries.size()).is_equal(_om().queued_strikes.size())


# The badge wears exactly what the row shows: a lethal hit's rung, where the plain swords would hide it.
func test_a_lethal_hit_wears_the_rung_its_queue_row_shows() -> void:
	var hero := _spawn(PLAYER, Vector2i(2, 2), true)
	var foe := _spawn(ENEMY, Vector2i(3, 2))
	foe.set_current_hp(1)
	_queue_attack(hero, foe.movement.cell)
	await _settle()

	var entry: Dictionary = _entries_by(hero)[0]
	var lead: AttackAction = (entry["members"] as Array)[0]
	var row := _row_for(lead)
	assert_object(row).override_failure_message("the queue drew no row for the hit").is_not_null()
	assert_object(row.action_icon.texture).override_failure_message(
			"fixture: the hit is not lethal, so its row shows the plain swords").is_not_equal(AttackAction.ATTACK_ICON)
	assert_object(entry["icon"]).override_failure_message(
			"the badge's icon is not the one its queue row shows").is_same(row.action_icon.texture)


func test_a_volley_is_one_badge_with_the_swords_its_folded_row_shows() -> void:
	var hero := _spawn(PLAYER, Vector2i(2, 2))
	_arm_with_blast(hero)
	var near := _spawn(ENEMY, Vector2i(3, 2))
	_spawn(ENEMY, Vector2i(4, 2))
	_queue_attack(hero, near.movement.cell)
	await _settle()

	var mine := _entries_by(hero)
	assert_int(mine.size()).override_failure_message(
			"a volley drew %d marks, not one" % mine.size()).is_equal(1)
	assert_int((mine[0]["members"] as Array).size()).override_failure_message(
			"fixture: the blast did not catch both foes").is_equal(2)
	var row := _row_for((mine[0]["members"] as Array)[0])
	assert_object(row).override_failure_message("the queue drew no row for the volley").is_not_null()
	assert_object(mine[0]["icon"]).is_same(row.action_icon.texture)


func test_a_counter_draws_its_own_mark_in_the_hostile_colour() -> void:
	var hero := _spawn(PLAYER, Vector2i(2, 2), true)
	var foe := _spawn(ENEMY, Vector2i(3, 2), true)
	_queue_attack(hero, foe.movement.cell)
	await _settle()

	var theirs := _entries_by(foe)
	assert_int(theirs.size()).override_failure_message(
			"the counter drew %d marks, not one" % theirs.size()).is_equal(1)
	var hostile: Color = theirs[0]["colour"]
	var mine: Color = _entries_by(hero)[0]["colour"]
	var pink := ThreatLines2D.MARK_LINE_COLOR
	assert_bool(hostile.is_equal_approx(Color(pink.r, pink.g, pink.b, 1.0))).override_failure_message(
			"the enemy's counter is not in the reach marks' pink").is_true()
	var reach := OverlayManager.attack_reach_color((_entries_by(hero)[0]["members"] as Array)[0].fired_attack)
	assert_bool(mine.is_equal_approx(Color(reach.r, reach.g, reach.b, 1.0))).override_failure_message(
			"your attack is not in the aim's own reach colour").is_true()
	# The diorama's badges are baked from those colours, not from a second answer.
	var textures: Array = []
	for marker: Dictionary in _overlays.markers_of(BoardOverlays.Layer.QUEUED_BADGES):
		textures.append(marker["texture"])
	assert_bool(textures.has(StrikeMarks2D.badge_texture(theirs[0]["icon"], hostile))).is_true()


# A blow and the counter answering it run along one pair of cells in opposite directions; their lanes
# keep the badges apart.
func test_an_attack_and_its_counter_keep_to_their_own_lanes() -> void:
	var hero := _spawn(PLAYER, Vector2i(2, 2), true)
	var foe := _spawn(ENEMY, Vector2i(3, 2), true)
	_queue_attack(hero, foe.movement.cell)
	await _settle()

	var points: Array[Vector3] = []
	for marker: Dictionary in _overlays.markers_of(BoardOverlays.Layer.QUEUED_BADGES):
		points.append(marker["pos"])
	assert_int(points.size()).override_failure_message("fixture: no counter was drawn").is_equal(2)
	assert_float(points[0].distance_to(points[1])).override_failure_message(
			"an attack and its counter put their badges on top of each other").is_greater(StrikeMarks2D.STRIKE_LANE)


func test_only_an_attack_past_one_tile_draws_its_footprint() -> void:
	var striker := _spawn(PLAYER, Vector2i(2, 2), true)
	var foe := _spawn(ENEMY, Vector2i(3, 2))
	_queue_attack(striker, foe.movement.cell)
	await _settle()
	assert_bool(_om().queued_footprint_overlay.get_used_cells().is_empty()).override_failure_message(
			"a one-tile hit drew a footprint the badge already points at").is_true()
	assert_bool(_overlays.cells_of(BoardOverlays.Layer.QUEUED_FOOTPRINT).is_empty()).is_true()

	var blaster := _spawn(PLAYER, Vector2i(2, 5))
	_arm_with_blast(blaster)
	var near := _spawn(ENEMY, Vector2i(3, 5))
	_spawn(ENEMY, Vector2i(4, 5))
	_queue_attack(blaster, near.movement.cell)
	await _settle()
	var drawn: Array[Vector2i] = _om().queued_footprint_overlay.get_used_cells()
	drawn.sort()
	assert_array(drawn).override_failure_message("the blast's two tiles were not drawn").contains_exactly(
			[Vector2i(3, 5), Vector2i(4, 5)])
	assert_int(_overlays.cells_of(BoardOverlays.Layer.QUEUED_FOOTPRINT).size()).is_equal(2)


func test_cancelling_the_attack_takes_its_mark_down() -> void:
	var hero := _spawn(PLAYER, Vector2i(2, 2), true)
	var foe := _spawn(ENEMY, Vector2i(3, 2))
	var action := _queue_attack(hero, foe.movement.cell)
	await _settle()
	assert_bool(_om().queued_strikes.is_empty()).override_failure_message("fixture: nothing drawn").is_false()

	game.squad_manager.remove_action(hero.squad, action)
	await _settle()
	assert_int(_entries_by(hero).size()).override_failure_message(
			"a cancelled attack left its mark on the board").is_equal(0)
	assert_int(_badge_sprites().size()).is_equal(_om().queued_strikes.size())


# --- The hover rule ---------------------------------------------------------------------------------

# Hovering EITHER end lifts the mark over everything, units and readouts included; hovering elsewhere
# puts it back down. Through the real hover poll, so the wire into the store is what is tested.
func test_hovering_either_end_lifts_the_mark_over_everything() -> void:
	var hero := _spawn(PLAYER, Vector2i(2, 2), true)
	var foe := _spawn(ENEMY, Vector2i(3, 2))
	_spawn(PLAYER, Vector2i(6, 6))   # somebody else to hover
	_queue_attack(hero, foe.movement.cell)
	await _settle()
	var sprites := _badge_sprites()
	assert_int(sprites.size()).override_failure_message("fixture: one badge expected").is_equal(1)

	await _point_at(Vector2i(6, 6))
	assert_bool(sprites[0].no_depth_test).override_failure_message(
			"a mark lifted although nobody it involves is hovered").is_false()

	for end: Unit in [hero, foe]:
		await _point_at(end.movement.cell)
		assert_bool(sprites[0].no_depth_test).override_failure_message(
				"hovering %s did not lift the mark it is part of" % ("the attacker" if end == hero else "the target")) \
				.is_true()
		assert_int(sprites[0].render_priority).is_greater(BoardOverlays.UNIT_HUD_RENDER_PRIORITY)

	await _point_at(Vector2i(6, 6))
	assert_bool(sprites[0].no_depth_test).override_failure_message(
			"the mark stayed lifted after the hover moved off").is_false()
	assert_int(sprites[0].render_priority).is_less(BoardOverlays.UNIT_RENDER_PRIORITY)


# Inside the lifted band, the hovered unit's OWN attack sits over the one aimed at it (#1251, the
# dev's report: hovering the enemy left his counter behind the attack on him). Both ends, since each
# unit is the attacker of one mark and the target of the other.
func test_the_hovered_units_own_mark_sits_over_the_one_aimed_at_it() -> void:
	var hero := _spawn(PLAYER, Vector2i(2, 2), true)
	var foe := _spawn(ENEMY, Vector2i(3, 2), true)
	_queue_attack(hero, foe.movement.cell)
	await _settle()
	assert_int(_badge_sprites().size()).override_failure_message("fixture: no counter was drawn").is_equal(2)
	var flat := _om().get_node("StrikeMarks2D") as StrikeMarks2D

	for hovered: Unit in [foe, hero]:
		await _point_at(hovered.movement.cell)
		var own: Dictionary = _entries_by(hovered)[0]
		var aimed: Dictionary = _entries_by(foe if hovered == hero else hero)[0]
		var own_badge := _badge_of(own)
		var aimed_badge := _badge_of(aimed)
		assert_object(own_badge).override_failure_message("fixture: the hovered unit's badge was not found").is_not_null()
		assert_bool(own_badge.no_depth_test and aimed_badge.no_depth_test).override_failure_message(
				"fixture: both marks should be lifted, the hovered unit is at both").is_true()
		assert_int(own_badge.render_priority).override_failure_message(
				"hovering %s left its own attack under the one aimed at it" % hovered.get_unit_name()) \
				.is_greater(aimed_badge.render_priority)
		# ...and the flat view draws it last.
		var ranks: Array[int] = []
		for entry in [own, aimed]:
			ranks.append(flat.focus_ranks[_om().queued_strikes.find(entry)])
		assert_array(ranks).is_equal([2, 1])


func _badge_of(entry: Dictionary) -> Sprite3D:
	var texture := StrikeMarks2D.badge_texture(entry["icon"], entry["colour"])
	for sprite in _badge_sprites():
		if sprite.texture == texture:
			return sprite
	return null


# --- The pointer rides its badge (#1253) ------------------------------------------------------------

# The dev's report: at rest every arrow drew at the strike layer's priority under every badge, so a far
# badge hid a near arrow, and hovering "fixed" it by lifting both into one band. A pointer is hung on
# its badge now and must sort AS ONE with it -- its priority, its depth test, its sort point, a nudge
# under it -- at rest and at both lifted tiers, through the real hover poll. An attack and its counter
# make two marks in one tier, which is the split a layer's single cone mesh allowed.
func test_each_pointer_sorts_with_its_own_badge_at_rest_and_lifted() -> void:
	var hero := _spawn(PLAYER, Vector2i(2, 2), true)
	var foe := _spawn(ENEMY, Vector2i(3, 2), true)
	_spawn(PLAYER, Vector2i(6, 6))
	_queue_attack(hero, foe.movement.cell)
	await _settle()

	for cell: Vector2i in [Vector2i(6, 6), hero.movement.cell, foe.movement.cell]:
		await _point_at(cell)
		var sprites := _badge_sprites()
		assert_int(sprites.size()).override_failure_message("fixture: an attack and its counter expected") 				.is_equal(2)
		for badge in sprites:
			_assert_one_with(badge)
	# ...and the arrow is drawn once: the line layers carry the shafts alone.
	for layer: BoardOverlays.Layer in [BoardOverlays.Layer.QUEUED_STRIKES, BoardOverlays.Layer.QUEUED_STRIKES_FOCUS]:
		assert_bool(_overlays.cone_vertices_of(layer).is_empty()).override_failure_message(
				"a strike line layer still draws a cone beside the badge's own").is_true()


func _assert_one_with(badge: Sprite3D) -> void:
	var pointer := BoardOverlays.pointer_of(badge)
	assert_object(pointer).override_failure_message("a badge drew no pointer").is_not_null()
	assert_bool(pointer.visible).override_failure_message("a badge's pointer is hidden").is_true()
	var material := pointer.material_override as ShaderMaterial
	assert_int(material.render_priority).override_failure_message(
			"a pointer sorts at %d and its badge at %d" % [material.render_priority, badge.render_priority]) 			.is_equal(badge.render_priority)
	var on_top := material.shader.resource_path == BoardOverlays.REACH_CONE_ON_TOP_SHADER_PATH
	assert_bool(on_top).override_failure_message("a pointer's depth test is not its badge's") 			.is_equal(badge.no_depth_test)
	assert_bool(pointer.sorting_use_aabb_center).override_failure_message(
			"a pointer sorts at its own bounds rather than at its badge").is_false()
	assert_that(pointer.global_position).is_equal(badge.global_position)
	assert_float(pointer.sorting_offset).override_failure_message(
			"a pointer does not sit under its own badge, as the flat view draws it").is_less(0.0)


# Cone shading and facets are baked into the mesh and the intensity is a uniform; all three are Game-tab
# knobs, so each has to reach a pointer already standing on the board.
func test_the_cone_knobs_reach_a_standing_pointer() -> void:
	var hero := _spawn(PLAYER, Vector2i(2, 2), true)
	var foe := _spawn(ENEMY, Vector2i(3, 2))
	_queue_attack(hero, foe.movement.cell)
	await _settle()
	var pointer := BoardOverlays.pointer_of(_badge_sprites()[0])
	assert_object(pointer).override_failure_message("fixture: the badge drew no pointer").is_not_null()

	var facets := _overlays.cone_facets
	var before_count := _vertex_count(pointer)
	_overlays.cone_facets = facets + 4
	var after_count := _vertex_count(pointer)
	_overlays.cone_facets = facets
	assert_int(after_count).override_failure_message(
			"turning the cone facets left a standing pointer's mesh as it was").is_greater(before_count)

	var intensity := _overlays.cone_intensity
	_overlays.cone_intensity = intensity + 0.5
	var read: float = (pointer.material_override as ShaderMaterial).get_shader_parameter("cone_intensity")
	_overlays.cone_intensity = intensity
	assert_float(read).override_failure_message("the cone intensity never reached a standing pointer") 			.is_equal_approx(intensity + 0.5, 0.0001)


func _vertex_count(pointer: MeshInstance3D) -> int:
	var mesh := pointer.mesh as ImmediateMesh
	var count := 0
	for s in mesh.get_surface_count():
		var points: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		count += points.size()
	return count


# --- Lifetime ---------------------------------------------------------------------------------------

# Each mark goes at its OWN blow, not when the pass starts. Headless a pass runs synchronously, so the
# observation point is the blow itself: volley_struck, after the game's own listener has run.
func test_each_mark_goes_when_its_own_blow_lands() -> void:
	var first := _spawn(PLAYER, Vector2i(2, 2), true)
	var second := _spawn(PLAYER, Vector2i(2, 4), true)
	game.squad_manager.join_squad(second, first.squad)
	var foe_a := _spawn(ENEMY, Vector2i(3, 2))
	var foe_b := _spawn(ENEMY, Vector2i(3, 4))
	_queue_attack(first, foe_a.movement.cell)
	_queue_attack(second, foe_b.movement.cell)
	await _settle()
	assert_int(_om().queued_strikes.size()).override_failure_message("fixture: two marks expected").is_equal(2)

	var standing_at_blow: Array[int] = []
	var listener := func(_attack: AttackAction) -> void: standing_at_blow.append(_om().queued_strikes.size())
	game.order_executor.volley_struck.connect(listener)
	await game.order_executor.execute_orders(first.squad.get_leader())
	game.order_executor.volley_struck.disconnect(listener)

	assert_array(standing_at_blow).override_failure_message(
			"the marks did not go one blow at a time: %s" % str(standing_at_blow)).contains_exactly([1, 0])
	assert_bool(_om().queued_strikes.is_empty()).is_true()


# --- Knobs ------------------------------------------------------------------------------------------

func test_the_badge_size_knob_reaches_a_standing_badge() -> void:
	var hero := _spawn(PLAYER, Vector2i(2, 2), true)
	var foe := _spawn(ENEMY, Vector2i(3, 2))
	_queue_attack(hero, foe.movement.cell)
	await _settle()
	var before_size := _badge_sprites()[0].pixel_size

	GameKnobs.write_static(_scene, "STRIKE_BADGE_SIZE", StrikeMarks2D.STRIKE_BADGE_SIZE * 2.0)
	await _settle()
	var after_size := _badge_sprites()[0].pixel_size
	assert_bool(absf(after_size - before_size) > 0.0001).override_failure_message(
			"the badge size knob moved nothing on a standing badge").is_true()
	assert_float(after_size).is_equal_approx(StrikeMarks2D.STRIKE_BADGE_SIZE / float(StrikeMarks2D.BADGE_TEXELS), 0.0001)
