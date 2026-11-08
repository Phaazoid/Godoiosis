# VeinMirror (#696): the vein store reaching the 3D drawing, on the real Battle3D host. What is asserted
# is what the mirror builds -- which habit's mesh holds crystals, where they stand, what the stain's
# decal is handed -- never how it looks; that is the dev's to judge (the PR's How to check this).
#
# Every case paints through the store (VeinField.set_kind) or a knob's own door (GameKnobs.write_static)
# and waits for the poll -- a mirror that only works when a test calls it goes red here.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const PROLOG := "res://Scenarios/missions/Prolog.tres"
# The stain redraws at most every VeinMirror.STAIN_SETTLE seconds; this many frames is well past it.
const STAIN_FRAMES := 120

var _board := SharedBoard.new(SCENE_PATH)
var _scene: Node3D
var _game: Node2D
var _veins: VeinMirror
# The VeinLook rows a case writes: STATICS, so a case that moves one moves it for the process.
var _saved: Dictionary[String, Variant] = {}


func before() -> void:
	await _board.open(self)


func before_test() -> void:
	await _board.reset(self)
	_scene = _board.scene
	_game = _board.game
	_veins = _scene.get_node("VeinMirror") as VeinMirror
	_saved.clear()


func after_test() -> void:
	for name: String in _saved:
		GameKnobs.write_static(_scene, name, _saved[name])
	await _board.check(self)


func after() -> void:
	_board.close()


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


func _field() -> VeinField:
	return _game.vein_field


func _write(name: String, value: Variant) -> void:
	if not _saved.has(name):
		_saved[name] = GameKnobs.read_static(name)
	GameKnobs.write_static(_scene, name, value)


# A cell with ground on all eight sides, so the stain and the crystals have whole ground around them.
func _loaded_cell() -> Vector2i:
	_scene.load_mission(PROLOG)
	await _settle()
	for cell: Vector2i in _game.grid.get_used_cells():
		var ringed := true
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if not GridUtils.has_ground(_game.grid, cell + Vector2i(dx, dy)):
					ringed = false
		if ringed and _game._board().unit_at_cell(cell) == null:
			return cell
	assert_bool(false).override_failure_message(
		"no free cell here is ringed by ground, so no case can paint around one").is_true()
	return GridUtils.NO_CELL


func _stain() -> void:
	for i in STAIN_FRAMES:
		await await_idle_frame()


func test_an_empty_board_grows_nothing() -> void:
	await _loaded_cell()
	assert_int(_veins.crystal_count()).is_equal(0)
	assert_bool(_veins.stain_node().visible).is_false()


func test_a_painted_vein_grows_its_own_habit_and_erasing_takes_it() -> void:
	var cell := await _loaded_cell()
	_field().set_kind(cell, Vein.Kind.WATER)
	await _settle()
	assert_int(_veins.crystal_count(Vein.Kind.WATER)).is_greater(0)
	assert_int(_veins.crystal_count()).is_equal(_veins.crystal_count(Vein.Kind.WATER))
	assert_object(_veins.mesh_of(Vein.Kind.WATER).mesh).is_not_null()
	assert_object(_veins.mesh_of(Vein.Kind.FIRE).mesh).is_null()

	_field().set_kind(cell, Vein.Kind.NONE)
	await _settle()
	assert_int(_veins.crystal_count()).is_equal(0)
	assert_object(_veins.mesh_of(Vein.Kind.WATER).mesh).is_null()


# Alkahest wears the five element habits it mixes, and no lightning.
func test_an_alkahest_vein_grows_only_the_habits_it_mixes() -> void:
	var cell := await _loaded_cell()
	for dx in range(-1, 2):
		_field().set_kind(cell + Vector2i(dx, 0), Vein.Kind.ALKAHEST)
	await _settle()
	assert_int(_veins.crystal_count()).is_greater(0)
	assert_int(_veins.crystal_count(Vein.Kind.LIGHTNING)).is_equal(0)
	var mixed := 0
	for habit: Vein.Kind in VeinMirror.ALKAHEST_MIX:
		mixed += _veins.crystal_count(habit)
	assert_int(mixed).is_equal(_veins.crystal_count())


# A rebuild with nothing moved puts every crystal back where it was: the seed is the cell's.
func test_a_rebuild_never_reshuffles_the_crystals() -> void:
	var cell := await _loaded_cell()
	_field().set_kind(cell, Vein.Kind.EARTH)
	await _settle()
	var first: AABB = _veins.mesh_of(Vein.Kind.EARTH).mesh.get_aabb()
	_veins.rebuild()
	assert_bool(_veins.mesh_of(Vein.Kind.EARTH).mesh.get_aabb().is_equal_approx(first)).is_true()


# The crystals stand on the ground as it is now: raising the cell a level lifts them a level, through
# the heights store the poll watches.
func test_the_crystals_follow_a_height_change() -> void:
	var cell := await _loaded_cell()
	var heights: BoardHeights = _game.board_heights
	heights.set_cell(cell, heights.elevation_at(cell))   # flat first, so the rise below is the whole change
	_field().set_kind(cell, Vein.Kind.FIRE)
	await _settle()
	var before: AABB = _veins.mesh_of(Vein.Kind.FIRE).mesh.get_aabb()
	heights.set_cell(cell, heights.elevation_at(cell) + Terrain.UNITS_PER_LEVEL)
	await _settle()
	var after: AABB = _veins.mesh_of(Vein.Kind.FIRE).mesh.get_aabb()
	var rise := BoardSpace.world_y_of_height(Terrain.UNITS_PER_LEVEL) - BoardSpace.world_y_of_height(0)
	assert_float(after.position.y - before.position.y).is_equal_approx(rise, 0.0001)


# The stain is a decal over every vein, handed a texture once the throttle lets it redraw, and painting
# the ground alone.
func test_the_stain_covers_the_vein_and_only_the_ground() -> void:
	var cell := await _loaded_cell()
	_field().set_kind(cell, Vein.Kind.AETHER)
	await _stain()
	var decal := _veins.stain_node()
	assert_bool(decal.visible).is_true()
	assert_object(decal.texture_albedo).is_not_null()
	assert_int(decal.cull_mask).is_equal(BoardOverlays.GROUND_RENDER_LAYER)
	var box := AABB(decal.global_position - decal.size * 0.5, decal.size)
	var top := BoardSpace.surface_height_at(cell, 0.5, 0.5, _game.board_heights)
	assert_bool(box.has_point(Vector3(cell.x + 0.5, top, cell.y + 0.5))).override_failure_message(
		"the stain's box %s misses the vein's own cell %s" % [box, cell]).is_true()


func test_the_flat_view_stands_the_veins_down() -> void:
	var cell := await _loaded_cell()
	_field().set_kind(cell, Vein.Kind.AIR)
	await _settle()
	assert_bool(_veins.visible).is_true()
	var was: int = _scene.get("view")
	_scene.set("view", 1)   # View.FLAT_2D (HD_2D, FLAT_2D, CORNER)
	await _settle()
	assert_bool(_veins.visible).is_false()
	_scene.set("view", was)


# A new board takes the last one's veins with it (ScenarioManager.clear_board).
func test_a_cleared_board_clears_the_crystals() -> void:
	var cell := await _loaded_cell()
	_field().set_kind(cell, Vein.Kind.LIGHTNING)
	await _settle()
	assert_int(_veins.crystal_count()).is_greater(0)
	_game.scenario_manager.clear_board()
	await _settle()
	assert_int(_veins.crystal_count()).is_equal(0)


# ---- the Game tab's rows reach what already stands (#1373's question, for a static row) ----

func test_a_colour_row_repaints_the_crystals_already_standing() -> void:
	var cell := await _loaded_cell()
	_field().set_kind(cell, Vein.Kind.FIRE)
	await _settle()
	_write("vein_fire_color", Color(0.1, 0.9, 0.2))
	await _settle()
	var material := _veins.mesh_of(Vein.Kind.FIRE).material_override as StandardMaterial3D
	assert_bool(Color(material.albedo_color, 1.0).is_equal_approx(Color(0.1, 0.9, 0.2))).is_true()


func test_the_density_row_regrows_the_vein_already_standing() -> void:
	var cell := await _loaded_cell()
	_field().set_kind(cell, Vein.Kind.EARTH)
	await _settle()
	var before := _veins.crystal_count()
	_write("vein_density", 1.0)
	await _settle()
	assert_int(_veins.crystal_count()).is_less(before)
	assert_int(_veins.crystal_count()).is_less_equal(1)


func test_the_slope_row_reaches_the_standing_stain() -> void:
	var cell := await _loaded_cell()
	_field().set_kind(cell, Vein.Kind.WATER)
	await _settle()
	_write("vein_stain_slope", 0.6)
	await _settle()
	assert_float(_veins.stain_node().normal_fade).is_equal_approx(0.6, 0.0001)
