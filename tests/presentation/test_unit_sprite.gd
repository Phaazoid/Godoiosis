# UnitSprite3D (#210): the component's contract — factory invariants (the HD-2D
# settings now live in code, not scene authoring), placement on standing points,
# the walk (finishes, updates cell, swaps the move sprite mid-walk and back), the
# downed swap, and the always-emits rule for degenerate paths. Camera-dependent
# facing is covered in test_walk_demo.gd where a real camera exists; here the
# facing helper's no-camera fallback keeps everything deterministic.
extends GdUnitTestSuite


func _texture(shade: float) -> ImageTexture:
	var img := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(shade, shade, shade))
	return ImageTexture.create_from_image(img)


func _data(with_map := true) -> UnitData:
	var data := UnitData.new()
	data.display_name = "Testy"
	if with_map:
		data.map_sprite = _texture(0.2)
	data.move_sprite = _texture(0.5)
	data.downed_sprite = _texture(0.8)
	return data


func test_factory_applies_the_hd2d_invariants() -> void:
	var sprite: UnitSprite3D = auto_free(UnitSprite3D.for_unit_data(_data()))
	assert_int(sprite.billboard).is_equal(BaseMaterial3D.BILLBOARD_FIXED_Y)
	assert_int(sprite.alpha_cut).is_equal(SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS)
	assert_bool(sprite.shaded).is_true()
	assert_int(sprite.texture_filter).is_equal(BaseMaterial3D.TEXTURE_FILTER_NEAREST)
	assert_int(sprite.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	assert_float(sprite.pixel_size).is_equal_approx(1.0 / 32.0, 0.0001)
	assert_object(sprite.texture).is_not_null()
	assert_str(sprite.display_name).is_equal("Testy")


func test_factory_falls_back_when_map_sprite_is_missing() -> void:
	var sprite: UnitSprite3D = auto_free(UnitSprite3D.for_unit_data(_data(false)))
	assert_object(sprite.texture).is_not_null()


func test_place_at_stands_on_the_cell() -> void:
	var sprite: UnitSprite3D = auto_free(UnitSprite3D.for_unit_data(_data()))
	sprite.place_at(Vector3i(3, 1, 4))
	assert_that(sprite.cell).is_equal(Vector3i(3, 1, 4))
	assert_that(sprite.position).is_equal(BoardSpace.standing_point(Vector3i(3, 1, 4)))


func test_walk_reaches_the_end_updates_cell_and_reports() -> void:
	var sprite: UnitSprite3D = auto_free(UnitSprite3D.for_unit_data(_data()))
	add_child(sprite)
	sprite.place_at(Vector3i(0, 0, 0))
	sprite.move_speed = 1000.0
	var monitor := assert_signal(sprite)
	sprite.walk_path([Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 0, 1)])
	await monitor.is_emitted("walk_finished")
	assert_that(sprite.cell).is_equal(Vector3i(1, 0, 1))
	assert_that(sprite.position).is_equal(BoardSpace.standing_point(Vector3i(1, 0, 1)))
	remove_child(sprite)


func test_walk_swaps_to_the_move_sprite_and_back() -> void:
	var data := _data()
	var sprite: UnitSprite3D = auto_free(UnitSprite3D.for_unit_data(data))
	add_child(sprite)
	sprite.place_at(Vector3i(0, 0, 0))
	sprite.move_speed = 2.0  # ~0.5s for the step: slow enough to observe mid-walk
	var monitor := assert_signal(sprite)
	sprite.walk_path([Vector3i(0, 0, 0), Vector3i(1, 0, 0)])
	await get_tree().process_frame
	await get_tree().process_frame
	assert_object(sprite.texture).is_same(data.move_sprite)
	await monitor.is_emitted("walk_finished")
	assert_object(sprite.texture).is_same(data.map_sprite)
	remove_child(sprite)


func test_degenerate_paths_still_report_finished() -> void:
	# Degenerate paths emit synchronously (no tween), so a plain counter beats a
	# signal monitor here — gdUnit's collector doesn't re-arm cleanly on one object.
	var sprite: UnitSprite3D = auto_free(UnitSprite3D.for_unit_data(_data()))
	var finished: Array[int] = [0]
	sprite.walk_finished.connect(func() -> void: finished[0] += 1)
	sprite.walk_path([])
	assert_int(finished[0]).is_equal(1)
	sprite.walk_path([Vector3i(2, 0, 2)])
	assert_int(finished[0]).is_equal(2)


func test_set_downed_swaps_both_ways() -> void:
	var data := _data()
	var sprite: UnitSprite3D = auto_free(UnitSprite3D.for_unit_data(data))
	sprite.set_downed(true)
	assert_object(sprite.texture).is_same(data.downed_sprite)
	sprite.set_downed(false)
	assert_object(sprite.texture).is_same(data.map_sprite)
