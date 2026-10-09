# What the snow does to props (#1269, #1278). A block prop takes the weather's cap decal (its layer is
# pinned by test_only_the_ground_takes_a_decal); a BILLBOARD prop wears an overlay of SnowCapArt; tall
# grass and flowers are BURIED. All through BoardMirror.set_snow. Pinned here: the art is cut from its
# own FRAME (a packed tileset's neighbour is not air), the one door shows and hides every overlay and
# every blade, a prop built in snow is dressed at once, and the tufts' density rule still thins the
# field when it is not snowing. Whether any of it LOOKS right is the probe's and the dev's eye.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
# A board with billboard props (trees, lanterns) and tufts both.
const MISSION := "res://Scenarios/missions/Level_1.tres"
const SNOW := Color(0.9, 0.93, 1.0)

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
	(_scene.get_node("BoardMirror") as BoardMirror).set_snow(false, Color.WHITE, false)
	await _board.check(self)


func after() -> void:
	_board.close()


# Two frames stacked in one sheet, both solid: asked of the sheet, the lower frame's top row has ink
# above it and would wear no cap. Asked of its own frame, it does.
func test_a_cap_is_cut_from_its_own_frame_not_its_sheet() -> void:
	var sheet := Image.create_empty(4, 8, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.3, 0.5, 0.2, 1.0))
	var frame := AtlasTexture.new()
	frame.atlas = ImageTexture.create_from_image(sheet)
	frame.region = Rect2(0, 4, 4, 4)
	var cap := SnowCapArt.cap_for(frame)
	assert_object(cap).override_failure_message("a solid frame under a solid one wears no cap").is_not_null()
	var image := cap.get_image()
	assert_vector(Vector2(image.get_size())).is_equal(Vector2(4, 4))
	for x in 4:
		assert_float(image.get_pixel(x, 0).a).override_failure_message("top row, column %d bare" % x).is_equal(1.0)
		assert_float(image.get_pixel(x, 1).a).override_failure_message(
				"the row under the top took no snow at column %d" % x).is_equal(1.0)
		assert_float(image.get_pixel(x, 3).a).override_failure_message(
				"snow reached the bottom of the art at column %d" % x).is_equal(0.0)


func test_a_frame_with_no_ink_has_no_cap() -> void:
	var sheet := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	assert_object(SnowCapArt.cap_for(ImageTexture.create_from_image(sheet))).is_null()


func test_the_one_door_shows_and_hides_every_billboard_cap_and_no_tuft_wears_one() -> void:
	var mirror := await _open()
	mirror.set_snow(true, SNOW, false)
	var shown := _caps(mirror)
	assert_int(shown["boards"]).override_failure_message("fixture: the board stands no billboard prop") \
			.is_greater(0)
	assert_int(shown["capped"]).override_failure_message(
			"%d billboard props and only %d wear a cap" % [shown["boards"], shown["capped"]]).is_equal(shown["boards"])
	assert_int(shown["wrong_colour"]).override_failure_message("a cap is not the snow's colour").is_equal(0)
	assert_int(shown["tufts"]).override_failure_message("fixture: the board stands no tuft").is_greater(0)
	assert_int(shown["tuft_caps"]).override_failure_message("tall grass wears a snow cap").is_equal(0)
	mirror.set_snow(false, SNOW, false)
	assert_int(_caps(mirror)["capped"]).override_failure_message("a cap still shows with caps off").is_equal(0)


func test_a_prop_built_in_snow_is_dressed_at_once() -> void:
	var mirror := await _open()
	mirror.set_snow(true, SNOW, true)
	mirror.drop_props()
	mirror.sync(_game.grid, _game.board_heights)
	var shown := _caps(mirror)
	assert_int(shown["boards"]).override_failure_message("fixture: the rebuild stood no billboard prop") \
			.is_greater(0)
	assert_int(shown["capped"]).override_failure_message("a prop rebuilt under snow came back bare") \
			.is_equal(shown["boards"])
	assert_int(shown["tufts"]).override_failure_message("fixture: the rebuild stood no tuft").is_greater(0)
	assert_int(shown["tufts_up"]).override_failure_message("a tuft rebuilt under snow came back standing") \
			.is_equal(0)


# Tall grass and flowers hide while it snows and come back after (#1278), and the density rule (#904)
# still thins the field when it is not snowing -- one rule answers whether a blade shows.
func test_snow_buries_every_tuft_and_clear_weather_brings_them_back() -> void:
	var mirror := await _open()
	var standing: int = _caps(mirror)["tufts_up"]
	assert_int(standing).override_failure_message("fixture: no blade stands before the snow").is_greater(0)
	mirror.set_snow(false, SNOW, true)
	assert_int(_caps(mirror)["tufts_up"]).override_failure_message("a blade stands in the snow").is_equal(0)
	mirror.set_snow(false, SNOW, false)
	assert_int(_caps(mirror)["tufts_up"]).override_failure_message("the snow left and the field stayed bare") \
			.is_equal(standing)
	var density := mirror.tuft_density
	mirror.tuft_density = 0.0
	var thinned: int = _caps(mirror)["tufts_up"]
	mirror.tuft_density = density
	assert_int(thinned).override_failure_message("the density rule no longer thins the field").is_equal(0)


func _open() -> BoardMirror:
	_scene.load_mission(MISSION)
	await await_idle_frame()
	await await_idle_frame()
	return _scene.get_node("BoardMirror") as BoardMirror


# Every billboard body standing, how many wear a showing cap, and the tufts' plants likewise. A body
# whose art holds no ink at the top would wear none, and none of the shipped props is such art.
func _caps(mirror: BoardMirror) -> Dictionary:
	var out := {"boards": 0, "capped": 0, "wrong_colour": 0, "tufts": 0, "tuft_caps": 0, "tufts_up": 0}
	for root: Node3D in mirror._props.values():
		for child in root.get_children():
			var sprite := child as Sprite3D
			if sprite == null:
				continue
			var cap := sprite.get_node_or_null(BoardMirror.SNOW_CAP_NAME) as Sprite3D
			var showing := cap != null and cap.visible
			if sprite.has_meta(BoardMirror.TUFT_META):
				out["tufts"] += 1
				out["tuft_caps"] += 1 if showing else 0
				out["tufts_up"] += 1 if sprite.visible else 0
				continue
			out["boards"] += 1
			if showing:
				out["capped"] += 1
				if not cap.modulate.is_equal_approx(SNOW):
					out["wrong_colour"] += 1
	return out
