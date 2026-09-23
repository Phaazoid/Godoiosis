# What a worn element state throws into the WORLD around a unit (#358 slice 2): a Wet unit's drips
# and their splashes, a Chilled unit's cold mist and frost breath. Two halves, split by what a
# headless suite can see:
#
# - The RULES are pure and asserted on hand-drawn art and stated numbers: where a texel of the art is
#   in the world, which texels are the body's edges, a drip that lands exactly as its life ends, a
#   breath that leaves toward the way the unit faces.
# - The WIRE runs through the real Battle3D scene: a state on the model reaches the emitters, from
#   the sprite that stands for the unit, on the mirror's own clock, inside the board's cull box.
#
# A GPU particle is simulated on the card and never read back, so every wire case reads the
# emitters' own CPU-side record (StatusParticles.emitted / last_position / last_velocity). What NO
# case here can see is whether any of it LOOKS right -- that is the dev's to play.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const WET := Elemental.State.WET
const CHILLED := Elemental.State.CHILLED
const DRIP := StatusParticles.Kind.DRIP
const SPLASH := StatusParticles.Kind.SPLASH
const MIST := StatusParticles.Kind.MIST
const BREATH := StatusParticles.Kind.BREATH

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


func _spawn(cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, PLAYER), cell)
	assert_object(unit).is_not_null()   # fixture setup, not the claim under test
	return unit


func _emitter(kind: StatusParticles.Kind) -> StatusParticles:
	return _unit_mirror.status_world().emitter(kind)


# The billboard's horizontal axis and the way toward the viewer, asked of the camera exactly as
# StatusWorld asks it.
func _right() -> Vector3:
	return Vector3.UP.cross(_toward()).normalized()


func _toward() -> Vector3:
	return _unit_mirror.get_viewport().get_camera_3d().global_transform.basis.z


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


# A sprite showing the figure, hung from its feet as a map still is, standing somewhere that is not
# the origin so a missing global_position would show.
func _figure_sprite(art: Texture2D, feet_row: float) -> UnitSprite3D:
	var sprite := UnitSprite3D.new()
	add_child(sprite)
	sprite.texture = art
	sprite.offset = Vector2(0.0, feet_row)
	sprite.position = Vector3(1.0, 2.0, 3.0)
	return sprite


# --- Where a texel of the art is in the world -----------------------------------------------

func test_the_feet_texel_is_where_the_sprite_stands() -> void:
	var sprite := _figure_sprite(ImageTexture.create_from_image(_figure()), 6.0)
	var feet := sprite.texel_to_world(Vector2(6.0, 12.0), Vector3.RIGHT)
	assert_vector(feet).is_equal_approx(sprite.global_position, Vector3.ONE * 0.0001)
	sprite.free()


# The same rule art_top_height has always answered, read from the other end: the top of the ink.
func test_the_top_of_the_ink_agrees_with_art_top_height() -> void:
	var sprite := _figure_sprite(ImageTexture.create_from_image(_figure()), 6.0)
	var top := sprite.texel_to_world(Vector2(6.0, 1.0), Vector3.RIGHT)
	assert_float(top.y - sprite.global_position.y).is_equal_approx(sprite.art_top_height(), 0.0001)
	sprite.free()


func test_flipping_the_art_mirrors_a_texel_about_the_pivot() -> void:
	var sprite := _figure_sprite(ImageTexture.create_from_image(_figure()), 6.0)
	var arm := Vector2(1.5, 3.5)
	var drawn := sprite.texel_to_world(arm, Vector3.RIGHT) - sprite.global_position
	sprite.flip_h = true
	var flipped := sprite.texel_to_world(arm, Vector3.RIGHT) - sprite.global_position
	assert_float(drawn.x).override_failure_message(
			"the arm held out to the left should sit left of the pivot").is_less(0.0)
	assert_float(flipped.x).is_equal_approx(-drawn.x, 0.0001)
	assert_float(flipped.y).is_equal_approx(drawn.y, 0.0001)
	sprite.free()


# StatusArt names texels in the SHEET's pixels, and an atlas frame shows only part of the sheet.
func test_an_atlas_frame_maps_the_sheets_texels() -> void:
	var frame := AtlasTexture.new()
	frame.atlas = ImageTexture.create_from_image(_figure())
	frame.region = Rect2(4, 6, 6, 6)
	var sprite := _figure_sprite(frame, 3.0)
	# The bottom-centre of the frame, named in the sheet's pixels.
	var feet := sprite.texel_to_world(Vector2(7.0, 12.0), Vector3.RIGHT)
	assert_vector(feet).is_equal_approx(sprite.global_position, Vector3.ONE * 0.0001)
	assert_that(StatusArt.frame_of(frame)).is_equal(Rect2(4, 6, 6, 6))
	sprite.free()


# --- What the art scan names ------------------------------------------------------------------

func test_the_edges_are_the_body_texels_with_open_air_beside_or_below() -> void:
	var art := _figure()
	var map := StatusArt.build(art)
	var inside := 0
	for y in art.get_height():
		for x in art.get_width():
			if not _opaque(art, x, y):
				continue
			var open := not _opaque(art, x - 1, y) or not _opaque(art, x + 1, y) or not _opaque(art, x, y + 1)
			assert_bool(map.edges.has(Vector2i(x, y))).override_failure_message(
					"%s is %s edge" % [Vector2i(x, y), "an" if open else "no"]).is_equal(open)
			if not open:
				inside += 1
	assert_int(inside).override_failure_message(
			"the figure has no inside texel, so the scan never had to leave one out").is_greater(0)
	assert_that(map.ink).is_equal(BoardMirror.opaque_bounds(art, Rect2i(Vector2i.ZERO, art.get_size())))
	assert_int(map.rows.size()).is_equal(map.ink.size.y)
	assert_that(map.rows[0]).override_failure_message("the head's row").is_equal(Vector2i(4, 7))
	assert_that(map.rows[2]).override_failure_message("the arm's row").is_equal(Vector2i(1, 8))


# --- The rules the emitters are handed -----------------------------------------------------

func test_a_drip_lands_exactly_as_its_life_ends() -> void:
	var start := Vector3(0.3, 2.0, -1.0)
	var velocity := StatusWorld.drip_velocity(start, 0.5, 0.4)
	var landed := start + velocity * 0.4
	assert_float(landed.y).is_equal_approx(0.5, 0.0001)
	assert_float(velocity.x).is_equal(0.0)
	assert_float(velocity.z).is_equal(0.0)
	assert_vector(StatusWorld.drip_velocity(start, 3.0, 0.4)).override_failure_message(
			"a drip that starts below the ground climbed up to it").is_equal(Vector3.ZERO)


func test_a_breath_leaves_toward_the_way_the_unit_faces() -> void:
	assert_bool(StatusWorld.faces_right(false)).is_equal(UnitSprite3D.ART_FACES_SCREEN_RIGHT)
	assert_bool(StatusWorld.faces_right(true)).is_equal(not UnitSprite3D.ART_FACES_SCREEN_RIGHT)


# Across is a share of the art IN THAT ROW, never of the whole box: the figure's arm held out widens
# the box, and a share of the box would put the mouth out along the arm.
func test_the_breath_anchor_is_a_share_of_its_own_row() -> void:
	var map := StatusArt.build(_figure())
	StatusLook.chill_breath_x = 0.5
	StatusLook.chill_breath_y = 0.0
	# The head's row: columns 4..7.
	assert_that(StatusWorld.breath_anchor(map, Rect2(0, 0, 12, 12))).is_equal(Vector2(6.0, 1.0))
	# The arm's row, two rows down: columns 1..8, so the same share lands elsewhere.
	StatusLook.chill_breath_y = 2.5 / 11.0   # mid-row, clear of a float landing on its edge
	var arm := StatusWorld.breath_anchor(map, Rect2(0, 0, 12, 12))
	assert_float(arm.x).is_equal_approx(5.0, 0.0001)
	# A frame showing only part of the sheet falls back to its own box.
	StatusLook.chill_breath_y = 0.25
	assert_that(StatusWorld.breath_anchor(map, Rect2(4, 0, 8, 8))).is_equal(Vector2(8.0, 2.0))


# --- The wire: a state on the model reaches the emitters ----------------------------------

# Every drip falls from an overhang the art scan names, lands on the surface under it, and throws its
# splash there -- AFTER its fall, never at the moment it leaves.
func test_a_wet_unit_drips_and_each_drip_splashes_where_it_lands() -> void:
	var unit := _spawn(Vector2i(2, 2))
	await _settle()
	var sprite := _unit_mirror.sprite_for(unit)
	var hangs := StatusWorld.in_frame(StatusArt.map_for(sprite.texture).overhangs,
			StatusArt.frame_of(sprite.texture))
	assert_int(hangs.size()).override_failure_message(
			"the fixture's art overhangs nowhere, so no drip can fall and this case sees nothing").is_greater(0)
	StatusLook.status_fade_time = 0.0
	StatusLook.wet_drip_rate = 10.0
	StatusLook.wet_drip_fall_time = 0.2
	StatusLook.wet_splash_count = 3
	var drips := _emitter(DRIP)
	var splashes := _emitter(SPLASH)
	var world := _unit_mirror.status_world()
	unit.add_element_state(WET)
	var dripped := drips.emitted
	var splashed := splashes.emitted
	var owed := world.pending_splashes()
	_unit_mirror.reconcile(1.0)
	assert_int(drips.emitted - dripped).is_equal(10)
	assert_int(splashes.emitted).override_failure_message(
			"a splash landed while its drip was still falling").is_equal(splashed)
	assert_int(world.pending_splashes() - owed).is_equal(10)

	var starts: Array[Vector3] = []
	for hang in hangs:
		starts.append(sprite.texel_to_world(Vector2(hang.x + 0.5, hang.y + 1.0), _right())
				+ _toward() * sprite.pixel_size)
	var from_an_overhang := false
	for start in starts:
		from_an_overhang = from_an_overhang or start.is_equal_approx(drips.last_position)
	assert_bool(from_an_overhang).override_failure_message(
			"the last drip left from %s, which is under no overhang the scan names" % [drips.last_position]).is_true()
	var landed := drips.last_position + drips.last_velocity * StatusLook.wet_drip_fall_time
	var ground := StatusWorld.ground_under(UnitMirror.cell_under(unit), landed, game.board_heights)
	assert_float(landed.y).is_equal_approx(ground, 0.0001)

	StatusLook.wet_drip_rate = 0.0
	_unit_mirror._process(0.3)
	assert_int(splashes.emitted - splashed).is_equal(10 * 3)
	assert_int(world.pending_splashes()).is_equal(owed)
	# ParticleFan lifts a droplet half a texel off the plane it is born on.
	assert_float(splashes.last_position.y).is_equal_approx(ground + sprite.pixel_size * 0.5, 0.0001)


func test_a_chilled_unit_mists_and_breathes_and_never_drips() -> void:
	var unit := _spawn(Vector2i(2, 2))
	await _settle()
	StatusLook.status_fade_time = 0.0
	StatusLook.chill_mist_rate = 10.0
	StatusLook.chill_mist_life = 1.0
	StatusLook.chill_breath_period = 0.5
	StatusLook.chill_breath_count = 3
	var dripped := _emitter(DRIP).emitted
	var misted := _emitter(MIST).emitted
	var breathed := _emitter(BREATH).emitted
	unit.add_element_state(CHILLED)
	for i in 4:
		_unit_mirror._process(0.25)
	assert_int(_emitter(MIST).emitted).is_greater(misted)
	assert_int(_emitter(BREATH).emitted).override_failure_message(
			"a second of chill at a half-second period drew no breath").is_greater(breathed)
	assert_int(_emitter(DRIP).emitted).override_failure_message("a Chilled unit dripped").is_equal(dripped)
	# A puff sinks to the ground as it ends.
	var mist := _emitter(MIST)
	var ended := mist.last_position + mist.last_velocity * StatusLook.chill_mist_life
	var ground := StatusWorld.ground_under(UnitMirror.cell_under(unit), ended, game.board_heights)
	assert_float(ended.y).is_equal_approx(ground + _unit_mirror.sprite_for(unit).pixel_size * 0.5, 0.0001)


func test_a_wet_unit_neither_mists_nor_breathes() -> void:
	var unit := _spawn(Vector2i(2, 2))
	await _settle()
	StatusLook.status_fade_time = 0.0
	StatusLook.chill_mist_rate = 10.0
	StatusLook.chill_breath_period = 0.5
	var misted := _emitter(MIST).emitted
	var breathed := _emitter(BREATH).emitted
	unit.add_element_state(WET)
	for i in 4:
		_unit_mirror._process(0.25)
	assert_int(_emitter(MIST).emitted).is_equal(misted)
	assert_int(_emitter(BREATH).emitted).is_equal(breathed)


func test_a_dry_unit_throws_nothing() -> void:
	var unit := _spawn(Vector2i(2, 2))
	await _settle()
	assert_bool(unit.element_states.is_empty()).override_failure_message(
			"the fixture unit arrived wearing a state, so this case cannot see the dry path").is_true()
	StatusLook.wet_drip_rate = 10.0
	StatusLook.chill_mist_rate = 10.0
	StatusLook.chill_breath_period = 0.5
	# The three a unit throws itself; a splash is a drip's, and an earlier case's may still be due.
	var sources: Array[StatusParticles.Kind] = [DRIP, MIST, BREATH]
	var counts: Array[int] = []
	for kind in sources:
		counts.append(_emitter(kind).emitted)
	for i in 4:
		_unit_mirror._process(0.25)
	var after: Array[int] = []
	for kind in sources:
		after.append(_emitter(kind).emitted)
	assert_array(after).is_equal(counts)


# The schedule runs on the mirror's SCALED clock, so a hitstop stops it with the world. A new
# time_scale reaches _process one frame late (measured on 4.7.1, test_unit_status), so the count is
# read after that frame and must then HOLD.
func test_nothing_is_thrown_while_time_is_stopped() -> void:
	var unit := _spawn(Vector2i(2, 2))
	await _settle()
	StatusLook.status_fade_time = 0.0
	StatusLook.chill_mist_rate = 30.0
	unit.add_element_state(CHILLED)
	Engine.time_scale = 0.0
	await await_idle_frame()
	var held := _emitter(MIST).emitted
	await _settle()
	await _settle()
	var later := _emitter(MIST).emitted
	Engine.time_scale = 1.0
	assert_int(later).override_failure_message("mist was thrown while time was stopped").is_equal(held)
	# Frames, not seconds: a headless frame's delta is whatever the machine gives it.
	for i in 240:
		await await_idle_frame()
		if _emitter(MIST).emitted > later:
			break
	assert_int(_emitter(MIST).emitted).override_failure_message(
			"no mist once time ran again, so the hold above proved nothing").is_greater(later)


# The ghost ruling: while a planning ghost stands in for the unit, the world half comes off the GHOST.
func test_a_queued_move_hands_the_drips_to_the_ghost() -> void:
	var unit := _spawn(Vector2i(2, 2))
	await _settle()
	StatusLook.status_fade_time = 0.0
	StatusLook.wet_drip_rate = 10.0
	unit.add_element_state(WET)
	_unit_mirror.reconcile()
	game.enter_move_mode(unit)
	game.selected_unit = unit
	game._on_left_click(Vector2i(3, 2))
	await _settle()
	var real := _unit_mirror.sprite_for(unit)
	assert_bool(real.visible).override_failure_message(
			"the real sprite is still up, so no ghost stands in and this case is vacuous").is_false()
	var ghost: UnitSprite3D = null
	for each in _unit_mirror.ghosts():
		if each.visible and _unit_mirror.ghost_unit_id(each) == unit.get_instance_id():
			ghost = each
	assert_object(ghost).is_not_null()
	var dripped := _emitter(DRIP).emitted
	_unit_mirror.reconcile(1.0)
	assert_int(_emitter(DRIP).emitted).is_greater(dripped)
	var at := _emitter(DRIP).last_position
	var to_ghost := Vector2(at.x - ghost.global_position.x, at.z - ghost.global_position.z).length()
	var to_real := Vector2(at.x - real.global_position.x, at.z - real.global_position.z).length()
	assert_float(to_ghost).override_failure_message(
			"the drip fell %s from the ghost and %s from the hidden sprite" % [to_ghost, to_real]).is_less(to_real)


# #656's shipped-invisible bug: an emitter the board's sweep does not reach draws NOTHING.
func test_the_boards_cull_sweep_reaches_every_emitter() -> void:
	var box := AABB(Vector3(-3.0, -2.0, -5.0), Vector3(40.0, 9.0, 31.0))
	_board.scene.call("_cover_effects", box)
	var expected := BoardSpace.effect_volume(box, StatusParticles.CULL_MARGIN)
	for emitter in _unit_mirror.status_world().emitters():
		var covered := AABB(emitter.visibility_aabb.position + emitter.global_position,
				emitter.visibility_aabb.size)
		assert_bool(covered.is_equal_approx(expected)).override_failure_message(
				"%s is culled to %s, not the board's %s" % [emitter.name, covered, expected]).is_true()
	_board.scene.call("_cover_effects", _board.scene.call("_board_volume"))


# --- The damp blot (a ground-only Decal) ----------------------------------------------------

func test_a_blot_image_is_one_irregular_hard_edged_patch() -> void:
	for variant in StatusWorld.BLOT_VARIANTS:
		var image := StatusWorld.blot_image(variant)
		assert_bool(image.get_data() == StatusWorld.blot_image(variant).get_data()).override_failure_message(
				"variant %d came out differently twice" % variant).is_true()
		var solid := 0
		var clear := 0
		for y in image.get_height():
			for x in image.get_width():
				var alpha := image.get_pixel(x, y).a
				assert_bool(alpha == 0.0 or alpha == 1.0).override_failure_message(
						"variant %d has a soft texel at %s" % [variant, Vector2i(x, y)]).is_true()
				if alpha > 0.0:
					solid += 1
				else:
					clear += 1
		assert_int(solid).override_failure_message("variant %d is empty" % variant).is_greater(0)
		assert_int(clear).override_failure_message("variant %d is a full square" % variant).is_greater(0)
	assert_bool(StatusWorld.blot_image(0).get_data() == StatusWorld.blot_image(1).get_data()) \
			.override_failure_message("two variants are the same patch").is_false()


func test_a_wet_unit_leaves_a_ground_only_patch_at_its_feet() -> void:
	var unit := _spawn(Vector2i(2, 2))
	await _settle()
	StatusLook.status_fade_time = 0.0
	StatusLook.wet_blot_spread_time = 0.0
	unit.add_element_state(WET)
	_unit_mirror.reconcile(0.1)
	var blot := _unit_mirror.status_world().blot_for(unit.get_instance_id())
	assert_object(blot).override_failure_message("a Wet unit left no damp patch").is_not_null()
	assert_int(blot.cull_mask).override_failure_message(
			"the patch paints more than the ground, so it would muddy the squad ring and every prop") \
			.is_equal(BoardOverlays.GROUND_RENDER_LAYER)
	var sprite := _unit_mirror.sprite_for(unit)
	assert_vector(blot.global_position).is_equal_approx(sprite.global_position - sprite.art_offset,
			Vector3.ONE * 0.0001)
	assert_float(blot.albedo_mix).is_greater(0.0)


func test_a_dry_unit_leaves_no_patch() -> void:
	var unit := _spawn(Vector2i(2, 2))
	await _settle()
	_unit_mirror.reconcile(1.0)
	assert_object(_unit_mirror.status_world().blot_for(unit.get_instance_id())).is_null()


# It spreads on its own time, and it DRIES on a longer one: the patch is still there after the drips
# have faded, and gone once the ground has dried.
func test_the_patch_spreads_then_outlives_the_drips_while_it_dries() -> void:
	var unit := _spawn(Vector2i(2, 2))
	await _settle()
	StatusLook.status_fade_time = 0.5
	StatusLook.wet_blot_spread_time = 2.0
	StatusLook.wet_blot_dry_time = 4.0
	var id := unit.get_instance_id()
	unit.add_element_state(WET)
	_unit_mirror.reconcile(1.0)
	var half := _unit_mirror.status_level(unit).w
	assert_bool(half > 0.0 and half < 1.0).override_failure_message(
			"half a spread in, the patch reads %s -- it jumped rather than spread" % [half]).is_true()
	var full_width := StatusLook.wet_blot_size * BoardSpace.CELL_SIZE
	assert_float(_unit_mirror.status_world().blot_for(id).size.x).is_less(full_width)
	_unit_mirror.reconcile(2.0)
	unit.remove_element_state(WET)
	_unit_mirror.reconcile(1.0)
	var level := _unit_mirror.status_level(unit)
	assert_float(level.x).override_failure_message("the drips have not faded, so this proves nothing") \
			.is_equal(0.0)
	assert_object(_unit_mirror.status_world().blot_for(id)).override_failure_message(
			"the patch vanished with the drips instead of drying").is_not_null()
	_unit_mirror.reconcile(4.0)
	assert_object(_unit_mirror.status_world().blot_for(id)).override_failure_message(
			"the patch never dried").is_null()


# A Wet unit standing in water leaves no patch on it -- and the unit is still Wet, still dripping.
func test_no_patch_is_left_on_water() -> void:
	var tile := _a_wadeable_water_tile()
	assert_bool(tile.is_empty()).override_failure_message(
			"the tileset has no wadeable water tile, so this case cannot stand a unit in water").is_false()
	var cell := Vector2i(2, 2)
	game.grid.paint(cell, int(tile["source"]), tile["coords"])
	await _settle()
	var unit := _spawn(cell)
	await _settle()
	StatusLook.status_fade_time = 0.0
	StatusLook.wet_blot_spread_time = 0.0
	unit.add_element_state(WET)
	_unit_mirror.reconcile(1.0)
	var level := _unit_mirror.status_level(unit)
	assert_float(level.x).override_failure_message("the unit is not wearing Wet, so this is vacuous") \
			.is_equal(1.0)
	assert_float(level.w).is_equal(0.0)
	assert_object(_unit_mirror.status_world().blot_for(unit.get_instance_id())).is_null()


func test_the_patch_follows_the_ghost_standing_in() -> void:
	var unit := _spawn(Vector2i(2, 2))
	await _settle()
	StatusLook.status_fade_time = 0.0
	StatusLook.wet_blot_spread_time = 0.0
	unit.add_element_state(WET)
	_unit_mirror.reconcile()
	game.enter_move_mode(unit)
	game.selected_unit = unit
	game._on_left_click(Vector2i(3, 2))
	await _settle()
	var ghost: UnitSprite3D = null
	for each in _unit_mirror.ghosts():
		if each.visible and _unit_mirror.ghost_unit_id(each) == unit.get_instance_id():
			ghost = each
	assert_object(ghost).override_failure_message("no ghost stands in, so this case is vacuous").is_not_null()
	_unit_mirror.reconcile(0.1)
	var blot := _unit_mirror.status_world().blot_for(unit.get_instance_id())
	assert_object(blot).is_not_null()
	assert_vector(blot.global_position).is_equal_approx(ghost.global_position, Vector3.ONE * 0.0001)


func _a_wadeable_water_tile() -> Dictionary:
	var tiles: TileSet = game.grid.tile_set
	for s in tiles.get_source_count():
		var source_id := tiles.get_source_id(s)
		var atlas := tiles.get_source(source_id) as TileSetAtlasSource
		if atlas == null:
			continue
		for i in atlas.get_tiles_count():
			var coords := atlas.get_tile_id(i)
			if atlas.get_tile_size_in_atlas(coords) != Vector2i.ONE:
				continue
			var data := atlas.get_tile_data(coords, 0)
			if GridUtils.terrain_kind_of(data) == Terrain.Kind.WATER and GridUtils.walkable_of(data):
				return {"source": source_id, "coords": coords}
	return {}
