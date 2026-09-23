# An element state worn on a unit's sprite (#358). Two halves, and the split is what a headless
# suite can see:
#
# - StatusArt is PURE: an Image in, an effect map out. Every rule about where rime sits and where an
#   icicle may hang is asserted here on hand-drawn art, never on an authored sprite (the content razor).
# - The WIRE runs through the real Battle3D scene: a state on the model reaches a material on the
#   sprite that stands for the unit, fading as it goes -- the real sprite, or the ghost when one
#   stands in.
#
# What NO case here can see is whether any of it LOOKS right: the dummy renderer draws nothing. The
# shader's match with the engine's own sprite is measured by tools/sprite_parity/, which needs a
# window; that half is the dev's to play.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const WET := Elemental.State.WET
const CHILLED := Elemental.State.CHILLED

# Uniforms the replica half declares with the engine's own defaults; nothing pushes them, and that
# is the point -- they are what keeps the override identical to the engine's material.
const BASE_UNIFORMS: Array[String] = ["albedo", "roughness", "specular", "metallic"]

var _board := SharedBoard.new(SCENE_PATH)
var game: Node2D
var _unit_mirror: UnitMirror


func before() -> void:
	await _board.open(self, _clear_the_board)


func _clear_the_board() -> void:
	_board.game.scenario_manager.clear_board()
	_board.game.game_state = _board.game.GameState.IDLE


func before_test() -> void:
	await _board.reset(self)
	game = _board.game
	_unit_mirror = _board.scene.get_node("UnitMirror") as UnitMirror


func after_test() -> void:
	Engine.time_scale = 1.0
	await _board.check(self)


func after() -> void:
	_board.close()


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).is_not_null()   # fixture setup, not the claim under test
	return unit


func _param(material: ShaderMaterial, key: String) -> float:
	var value: float = material.get_shader_parameter(key)
	return value


# A figure drawn in '#' on '.': a head, a torso, an arm held out to the left, and two legs.
func _figure() -> Image:
	return _art([
		"............",
		"....####....",
		"....####....",
		".########...",
		"....####....",
		"....####....",
		"....####....",
		"....####....",
		"....#..#....",
		"....#..#....",
		"....#..#....",
		"....#..#....",
	])


func _art(rows: Array[String]) -> Image:
	var image := Image.create(rows[0].length(), rows.size(), false, Image.FORMAT_RGBA8)
	for y in rows.size():
		for x in rows[y].length():
			if rows[y][x] == "#":
				image.set_pixel(x, y, Color(0.5, 0.4, 0.3, 1.0))
	return image


func _opaque(image: Image, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height() \
			and image.get_pixel(x, y).a >= StatusArt.OPAQUE


func _ink_bottom(image: Image) -> int:
	var bottom := -1
	for y in image.get_height():
		for x in image.get_width():
			if _opaque(image, x, y):
				bottom = y
	return bottom


# --- StatusArt: where a state goes on the art -------------------------------------------------

func test_an_icicle_hangs_only_in_open_air_directly_under_an_overhang() -> void:
	var art := _figure()
	var map := StatusArt.build(art)
	var bottom := _ink_bottom(art)
	var icicle_texels := 0
	for y in art.get_height():
		for x in art.get_width():
			if map.image.get_pixel(x, y).g <= 0.0:
				continue
			icicle_texels += 1
			assert_bool(_opaque(art, x, y)).override_failure_message(
					"an icicle texel at %s sits on the body" % [Vector2i(x, y)]).is_false()
			assert_int(y).override_failure_message(
					"an icicle texel at %s reaches the feet row" % [Vector2i(x, y)]).is_less(bottom)
			# Walk up through open air to the overhang it hangs from.
			var up := y - 1
			while up >= 0 and not _opaque(art, x, up):
				up -= 1
			assert_int(up).override_failure_message(
					"the icicle texel at %s hangs from nothing" % [Vector2i(x, y)]).is_greater_equal(0)
			assert_bool(map.overhangs.has(Vector2i(x, up))).override_failure_message(
					"the icicle at %s does not hang from an overhang the map names" % [Vector2i(x, y)]).is_true()
	assert_int(icicle_texels).override_failure_message(
			"the figure grew no icicle at all, so nothing above was asked").is_greater(0)


func test_icicles_never_hang_side_by_side_and_are_capped() -> void:
	var map := StatusArt.build(_art([
		"..............",
		"##############",
		"..............",
		"..............",
		"..............",
		"..............",
		"......##......",
	]))
	assert_int(map.overhangs.size()).override_failure_message(
			"a whole plank of overhangs chose no icicle column").is_greater(0)
	assert_int(map.overhangs.size()).is_less_equal(StatusArt.MAX_ICICLES)
	for a: Vector2i in map.overhangs:
		for b: Vector2i in map.overhangs:
			if a != b:
				assert_int(absi(a.x - b.x)).override_failure_message(
						"icicles at columns %d and %d hang side by side" % [a.x, b.x]).is_greater_equal(2)


# Every named overhang is where one begins: its first icicle texel is the one directly under it.
func test_every_named_overhang_starts_an_icicle() -> void:
	var map := StatusArt.build(_figure())
	assert_int(map.overhangs.size()).is_greater(0)
	for hang: Vector2i in map.overhangs:
		var g := map.image.get_pixel(hang.x, hang.y + 1).g
		assert_float(g * StatusArt.ICICLE_SCALE).override_failure_message(
				"the overhang at %s names an icicle that does not start under it" % [hang]).is_equal_approx(1.0, 0.1)


func test_rime_settles_only_on_the_body_and_fully_on_its_top_edges() -> void:
	var art := _figure()
	var map := StatusArt.build(art)
	var tops := 0
	for y in art.get_height():
		for x in art.get_width():
			var rime := map.image.get_pixel(x, y).r
			if not _opaque(art, x, y):
				assert_float(rime).override_failure_message(
						"rime on open air at %s" % [Vector2i(x, y)]).is_equal(0.0)
				continue
			if not _opaque(art, x, y - 1):
				tops += 1
				assert_float(rime).override_failure_message(
						"the top edge at %s wears no full rime" % [Vector2i(x, y)]).is_equal_approx(1.0, 0.01)
	assert_int(tops).is_greater(0)


func test_the_same_art_always_maps_the_same_way() -> void:
	var first := StatusArt.build(_figure())
	var second := StatusArt.build(_figure())
	assert_bool(first.image.get_data() == second.image.get_data()).override_failure_message(
			"two scans of one image disagree, so the same art would frost differently").is_true()
	assert_array(first.overhangs).is_equal(second.overhangs)


# A frame animation draws an AtlasTexture whose UVs index the whole PARENT sheet, so the map a frame
# is drawn with has to be the parent's -- and the same object, or every frame re-scans the sheet.
func test_an_atlas_frame_maps_its_parent_sheet() -> void:
	var parent := ImageTexture.create_from_image(_figure())
	var frame := AtlasTexture.new()
	frame.atlas = parent
	frame.region = Rect2(0, 0, 6, 6)
	assert_object(StatusArt.sampled_texture(frame)).is_same(parent)
	assert_object(StatusArt.map_for(frame)).is_same(StatusArt.map_for(parent))


# --- The shader's contract with what pushes it ---------------------------------------------

# A ShaderMaterial stores a parameter it was handed whether or not the shader declares it, so a
# misspelled uniform reads back fine and draws nothing. The names are therefore checked against the
# shader's OWN list, in both directions: nothing pushed that is not declared, and nothing declared
# that is left at its default.
func test_every_status_uniform_is_pushed_and_every_push_is_a_uniform() -> void:
	var pushed := _pushed_names("res://Classes/presentation/StatusLook.gd")
	pushed.append_array(_pushed_names("res://Classes/presentation/UnitSprite3D.gd"))
	assert_int(pushed.size()).override_failure_message(
			"no set_shader_parameter found, so this law reads nothing").is_greater(0)
	for shader: Shader in [UnitSprite3D.STATUS_SHADER, UnitSprite3D.STATUS_GHOST_SHADER]:
		var declared: Array[String] = []
		for uniform: Dictionary in shader.get_shader_uniform_list():
			declared.append(String(uniform["name"]))
		for pushed_name in pushed:
			assert_bool(declared.has(pushed_name)).override_failure_message(
					"'%s' is pushed but %s declares no such uniform" % [pushed_name, shader.resource_path]).is_true()
		for declared_name in declared:
			if BASE_UNIFORMS.has(declared_name):
				continue
			assert_bool(pushed.has(declared_name)).override_failure_message(
					"%s declares '%s' and nothing ever sets it" % [shader.resource_path, declared_name]).is_true()


func _pushed_names(path: String) -> Array[String]:
	var source := FileAccess.get_file_as_string(path)
	var re := RegEx.create_from_string("set_shader_parameter\\(\"(\\w+)\"")
	var names: Array[String] = []
	for found: RegExMatch in re.search_all(source):
		var pushed_name := found.get_string(1)
		if not names.has(pushed_name):
			names.append(pushed_name)
	return names


# --- The wire: a state on the model reaches the sprite -------------------------------------

func test_a_wet_unit_wears_the_status_and_it_fades_in() -> void:
	var unit := _spawn(PLAYER, Vector2i(2, 2))
	await _settle()
	StatusLook.status_fade_time = 1.0
	unit.add_element_state(WET)
	_unit_mirror.reconcile(0.5)
	var level := _unit_mirror.status_level(unit)
	assert_bool(level.x > 0.0 and level.x < 1.0).override_failure_message(
			"half a fade in, the wet level reads %s -- it jumped rather than faded" % [level.x]).is_true()
	var sprite := _unit_mirror.sprite_for(unit)
	var material := sprite.status_material()
	assert_object(material).override_failure_message(
			"a Wet unit's sprite wears no status material").is_not_null()
	assert_object(material.shader).is_same(UnitSprite3D.STATUS_SHADER)
	assert_float(_param(material, "wet")).is_equal_approx(level.x, 0.0001)
	assert_object(material.get_shader_parameter("texture_albedo")).override_failure_message(
			"the material draws a texture the sprite is not showing").is_same(sprite.texture)
	_unit_mirror.reconcile(1.0)
	assert_float(_unit_mirror.status_level(unit).x).is_equal(1.0)


func test_a_unit_wearing_no_state_keeps_the_engine_material() -> void:
	var unit := _spawn(PLAYER, Vector2i(2, 2))
	await _settle()
	assert_bool(unit.element_states.is_empty()).override_failure_message(
			"the fixture unit arrived wearing a state, so this case cannot see the dry path").is_true()
	_unit_mirror.reconcile(1.0)
	assert_object(_unit_mirror.sprite_for(unit).material_override).is_null()


func test_a_state_that_ends_fades_out_and_hands_the_sprite_back() -> void:
	var unit := _spawn(PLAYER, Vector2i(2, 2))
	await _settle()
	StatusLook.status_fade_time = 1.0
	unit.add_element_state(WET)
	_unit_mirror.reconcile(2.0)
	unit.remove_element_state(WET)
	_unit_mirror.reconcile(0.5)
	var sprite := _unit_mirror.sprite_for(unit)
	assert_object(sprite.status_material()).override_failure_message(
			"the material left the instant the state did, so there was no fade out").is_not_null()
	_unit_mirror.reconcile(1.0)
	assert_object(sprite.material_override).override_failure_message(
			"a unit wearing nothing still carries the status material").is_null()
	assert_that(_unit_mirror.status_level(unit)).is_equal(Vector3.ZERO)


func test_icicles_grow_on_their_own_clock() -> void:
	var unit := _spawn(PLAYER, Vector2i(2, 2))
	await _settle()
	StatusLook.status_fade_time = 0.5
	StatusLook.icicle_grow_time = 2.0
	unit.add_element_state(CHILLED)
	_unit_mirror.reconcile(0.5)
	var level := _unit_mirror.status_level(unit)
	assert_float(level.y).is_equal(1.0)
	assert_bool(level.z > 0.0 and level.z < level.y).override_failure_message(
			"the icicles are at %s when the chill is fully in; they should still be growing" % [level.z]).is_true()
	assert_float(level.x).override_failure_message("Chilled alone raised the wet level").is_equal(0.0)


# The fade runs on the SCALED delta, so a hitstop's Engine.time_scale = 0 holds it where it is.
#
# Measured on 4.7.1: a new time_scale reaches _process ONE FRAME LATE -- the frame after setting 0
# still carries a real delta, and every frame after it carries 0. So the level is read after that
# frame and must then HOLD, rather than being asserted to have never moved.
func test_the_fade_stands_still_while_time_is_stopped() -> void:
	var unit := _spawn(PLAYER, Vector2i(2, 2))
	await _settle()
	unit.add_element_state(WET)
	Engine.time_scale = 0.0
	await await_idle_frame()
	var held := _unit_mirror.status_level(unit).x
	await _settle()
	var later := _unit_mirror.status_level(unit).x
	Engine.time_scale = 1.0
	assert_float(later).override_failure_message(
			"the fade advanced while time was stopped").is_equal(held)
	await _settle()
	await _settle()
	assert_float(_unit_mirror.status_level(unit).x).override_failure_message(
			"the fade never moved once time ran again, so the hold above proved nothing").is_greater(later)


# --- Ghosts ---------------------------------------------------------------------------------

func _ghost_for(unit: Unit) -> UnitSprite3D:
	for ghost in _unit_mirror.ghosts():
		if ghost.visible and _unit_mirror.ghost_unit_id(ghost) == unit.get_instance_id():
			return ghost
	return null


func test_a_queued_move_hands_the_status_to_the_ghost() -> void:
	var unit := _spawn(PLAYER, Vector2i(2, 2))
	await _settle()
	StatusLook.status_fade_time = 0.0
	unit.add_element_state(WET)
	_unit_mirror.reconcile()
	game.enter_move_mode(unit)
	game.selected_unit = unit
	game._on_left_click(Vector2i(3, 2))
	await _settle()
	assert_bool(_unit_mirror.sprite_for(unit).visible).override_failure_message(
			"the real sprite is still up, so no ghost stands in and this case is vacuous").is_false()
	var ghost := _ghost_for(unit)
	assert_object(ghost).override_failure_message(
			"no ghost is known to stand for the moving unit").is_not_null()
	var material := ghost.status_material()
	assert_object(material).override_failure_message(
			"the ghost standing in for a Wet unit wears nothing").is_not_null()
	assert_float(_param(material, "wet")).is_equal(1.0)
	assert_object(material.shader).is_same(UnitSprite3D.STATUS_GHOST_SHADER)
	assert_int(material.render_priority).override_failure_message(
			"the ghost's material lost the priority the engine would have given it (#317)").is_equal(ghost.render_priority)


func test_a_shoves_landing_ghost_wears_its_units_status() -> void:
	var foe := _spawn(ENEMY, Vector2i(3, 2))
	await _settle()
	StatusLook.status_fade_time = 0.0
	foe.add_element_state(CHILLED)
	_unit_mirror.reconcile()
	var path: Array[Vector2i] = [Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2)]
	var shoves: Array = [{"target": foe, "path": path, "to": Vector2i(5, 2)}]
	game.overlay_manager.show_knockback_preview(shoves)
	await _settle()
	var ghost := _ghost_for(foe)
	assert_object(ghost).override_failure_message(
			"no landing ghost is known to stand for the shoved unit").is_not_null()
	var material := ghost.status_material()
	assert_object(material).is_not_null()
	assert_float(_param(material, "chill")).is_equal(1.0)


func test_the_move_hover_stand_in_stays_plain() -> void:
	var unit := _spawn(PLAYER, Vector2i(2, 2))
	await _settle()
	StatusLook.status_fade_time = 0.0
	unit.add_element_state(WET)
	_unit_mirror.reconcile()
	game.enter_move_mode(unit)
	game.selected_unit = unit
	game.hover_presenter.update_hover_visuals(Vector2i(4, 2))
	await _settle()
	var shown := 0
	for ghost in _unit_mirror.ghosts():
		if not ghost.visible:
			continue
		shown += 1
		assert_int(_unit_mirror.ghost_unit_id(ghost)).override_failure_message(
				"the move-hover stand-in claims to BE the unit").is_equal(0)
		assert_object(ghost.material_override).override_failure_message(
				"the move-hover stand-in wears the unit's state").is_null()
	assert_int(shown).override_failure_message(
			"no hover stand-in reached the diorama, so this case saw nothing").is_greater(0)
	assert_object(_unit_mirror.sprite_for(unit).status_material()).override_failure_message(
			"the real sprite, still on screen beside the stand-in, lost its state").is_not_null()
	game.exit_current_mode()
