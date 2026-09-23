# Only the GROUND takes a decal (#358's damp blot). A Decal paints every instance its cull_mask meets,
# and the ground -- a GridMap -- cannot be re-layered off layer 1, so the ground owns that layer and
# everything else the board draws must be on another. A forgotten `layers =` means the blot quietly
# darkens that thing, and nothing else would ever notice: the suite cannot see a pixel.
#
# The walk is over the LIVE scene rather than the source, so a visual built somewhere no grep looked
# is still asked. Each kind the grep did find is raised first and asked for by name, so the law
# cannot pass over a board that happened to draw none of them.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const PROLOG := "res://Scenarios/missions/Prolog.tres"
const GROUND := BoardOverlays.GROUND_RENDER_LAYER
const UNIT := BoardOverlays.UNIT_RENDER_LAYER

var _board := SharedBoard.new(SCENE_PATH)
var _scene: Node3D
var _game: Node2D


func before() -> void:
	await _board.open(self)


func before_test() -> void:
	await _board.reset(self)
	_scene = _board.scene
	_game = _board.game


func after_test() -> void:
	await _board.check(self)


func after() -> void:
	_board.close()


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


func test_nothing_but_the_ground_is_on_the_ground_layer() -> void:
	_scene.load_mission(PROLOG)
	await _settle()
	_game.game_state = _game.GameState.DEV_MODE
	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	var overlays := _scene.get_node("BoardOverlays") as BoardOverlays
	var units := _scene.get_node("UnitMirror") as UnitMirror

	# Raise every kind the site list names, so each is on the board to be asked.
	var hole := _an_inland_cell()
	assert_bool(hole != GridUtils.NO_CELL).override_failure_message(
			"no cell here has ground on all four sides, so no lip can be dug").is_true()
	_game.grid.erase(hole)
	await _settle()
	mirror.call("_ensure_brush_ghost")
	var bracket: MeshInstance3D = overlays.call("_make_bracket", Color.WHITE)
	var wearer: Unit = null
	for child in _game.units_root.get_children():
		wearer = child as Unit
		if wearer != null:
			break
	assert_object(wearer).override_failure_message("Prolog placed nobody to wear a state").is_not_null()
	StatusLook.status_fade_time = 0.0
	StatusLook.wet_blot_spread_time = 0.0
	wearer.add_element_state(Elemental.State.WET)
	units.reconcile(0.1)

	var burning: Array[Vector2i] = _game.terrain_states.burning_cells()
	assert_bool(not burning.is_empty() and mirror.fire_marker_at(burning[0]) != null) \
			.override_failure_message("no flame is standing, so a flame's layer is never asked").is_true()
	assert_int(mirror.prop_count()).override_failure_message(
			"no prop is standing, so a prop's layer is never asked").is_greater(0)
	assert_object(units.status_world().blot_for(wearer.get_instance_id())).override_failure_message(
			"no damp patch was laid, so the decal this law protects is not even on the board").is_not_null()

	var lips := 0
	var particles := 0
	for node in _descendants(_scene):
		var drawn := node as GeometryInstance3D
		if drawn == null:
			continue
		if drawn is StatusParticles:
			particles += 1
		var on_ground := (drawn.layers & GROUND) != 0
		if on_ground:
			lips += 1
			assert_bool(drawn.has_meta(BoardMirror.LIP_PART_META)).override_failure_message(
					"%s is on the ground layer, so the damp patch would paint it" % _scene.get_path_to(drawn)) \
					.is_true()
		assert_bool(on_ground and (drawn.layers & UNIT) != 0).override_failure_message(
				"%s is on both the ground and the unit layer" % _scene.get_path_to(drawn)).is_false()
	assert_int(lips).override_failure_message(
			"the dug hole grew no lip, so the ground's own non-GridMap pieces were never asked").is_greater(0)
	assert_int(particles).override_failure_message(
			"no status emitter was found, so the particles' layer was never asked").is_greater(0)
	bracket.free()


func _descendants(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in root.get_children():
		out.append(child)
		out.append_array(_descendants(child))
	return out


func _an_inland_cell() -> Vector2i:
	for cell: Vector2i in _game.grid.get_used_cells():
		var ringed := true
		for dir in GridUtils.CARDINAL_DIRECTIONS:
			if not GridUtils.has_ground(_game.grid, cell + dir):
				ringed = false
				break
		if ringed:
			return cell
	return GridUtils.NO_CELL
