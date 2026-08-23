# The HD-2D look-dev scene (#203 / #176 Stage 0), pinned at its STRUCTURAL invariants:
# the renderer the stack needs, the sprite settings that make billboards depth-sort and
# cast shadows (the classic HD-2D gotchas), the post stack being wired, and the board
# having actual verticality. Deliberately NOT pinned: light energies, fog densities,
# DoF distances, preset colors, FOV/pitch values -- those are the tuning session's
# property (the Pacing rule: never pin a feel-tuned value). Contract-level bounds
# (perspective projection, pitched down, narrow FOV) stand in for them.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/LookDev/LookDev.tscn"

var _scene: Node3D


func before_test() -> void:
	_scene = (load(SCENE_PATH) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(_scene)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_scene)
	_scene.free()


func test_renderer_is_forward_plus() -> void:
	# Volumetric fog exists only on Forward+; the whole post stack rides this line.
	var method: String = ProjectSettings.get_setting("rendering/renderer/rendering_method")
	assert_str(method).is_equal("forward_plus")


func test_scene_instantiates_with_the_camera_contract() -> void:
	assert_object(_scene).is_not_null()
	var camera := _scene.get_node("CameraRig/Pitch/Camera") as Camera3D
	assert_object(camera).is_not_null()
	assert_int(camera.projection).is_equal(Camera3D.PROJECTION_PERSPECTIVE)
	assert_bool(camera.fov < 50.0).is_true()  # narrow FOV, not a specific number
	var pitch := _scene.get_node("CameraRig/Pitch") as Node3D
	assert_bool(pitch.rotation_degrees.x < -20.0).is_true()  # pitched down


func test_sprites_are_billboarded_lit_pixel_quads() -> void:
	var units := _scene.get_node("Units")
	var sprites: Array[Node] = units.get_children()
	assert_bool(sprites.size() >= 3).is_true()
	for child in sprites:
		var sprite := child as Sprite3D
		assert_object(sprite).is_not_null()
		assert_bool(sprite is UnitSprite3D).is_true()  # stage 2: the component is the one author
		assert_object(sprite.texture).is_not_null()
		assert_int(sprite.billboard).is_equal(BaseMaterial3D.BILLBOARD_FIXED_Y)
		assert_int(sprite.alpha_cut).is_equal(SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS)
		assert_bool(sprite.shaded).is_true()
		assert_int(sprite.texture_filter).is_equal(BaseMaterial3D.TEXTURE_FILTER_NEAREST)
		assert_int(sprite.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
		assert_int(sprite.layers).is_equal(BoardOverlays.UNIT_RENDER_LAYER)  # the #213 mask contract
		# One pixel density everywhere: 32 texels per world unit (the authored convention).
		assert_float(sprite.pixel_size).is_equal_approx(1.0 / 32.0, 0.0001)


func test_board_cell_size_matches_the_declared_convention() -> void:
	# BoardSpace is the one metric; the GridMap's authored cell_size must agree or every
	# standing_point drifts off the rendered board. NOT a cube since #427 slice 2 — the vertical
	# index counts height UNITS, and a cell_size that stayed cubic would draw every column twice
	# as tall as the store says it is.
	var board := _scene.get_node("Board") as GridMap
	assert_that(board.cell_size).is_equal(
		Vector3(BoardSpace.CELL_SIZE, BoardSpace.ROW_HEIGHT, BoardSpace.CELL_SIZE))


func test_board_is_painted_with_verticality() -> void:
	var board := _scene.get_node("Board") as GridMap
	assert_object(board.mesh_library).is_not_null()
	assert_bool(board.mesh_library.get_item_list().size() >= 3).is_true()
	var cells: Array[Vector3i] = board.get_used_cells()
	assert_bool(cells.size() >= 100).is_true()
	var levels := {}
	for cell in cells:
		levels[cell.y] = true
	assert_bool(levels.size() >= 2).is_true()  # elevation exists; exact heights are content


func test_post_stack_is_wired() -> void:
	var world_env := _scene.get_node("WorldEnvironment") as WorldEnvironment
	var env := world_env.environment
	assert_object(env).is_not_null()
	assert_bool(env.glow_enabled).is_true()
	assert_bool(env.volumetric_fog_enabled).is_true()
	assert_bool(env.adjustment_enabled).is_true()
	assert_bool(env.ssao_enabled).is_true()
	assert_bool(env.tonemap_mode != Environment.TONE_MAPPER_LINEAR).is_true()
	var camera := _scene.get_node("CameraRig/Pitch/Camera") as Camera3D
	var attributes := camera.attributes as CameraAttributesPractical
	assert_object(attributes).is_not_null()
	assert_bool(attributes.dof_blur_far_enabled or attributes.dof_blur_near_enabled).is_true()


func test_sun_casts_shadows() -> void:
	var sun := _scene.get_node("Sun") as DirectionalLight3D
	assert_object(sun).is_not_null()
	assert_bool(sun.shadow_enabled).is_true()


func test_tile_materials_are_nearest_filtered_and_textured() -> void:
	# Every item that DRAWS anything, which since #427 slice 2 is not every item: the wedge filler
	# is deliberately empty (it declares occupancy for BoardPicker and renders nothing). Named
	# rather than skipped by geometry, so an ordinary block that lost its mesh still reds here.
	var board := _scene.get_node("Board") as GridMap
	var library := board.mesh_library
	var invisible := 0
	for item_id in library.get_item_list():
		var mesh := library.get_item_mesh(item_id)
		assert_object(mesh).is_not_null()
		if library.get_item_name(item_id) == BoardMirror.RAMP_FILL_ITEM_NAME:
			assert_int(mesh.get_surface_count()).override_failure_message(
					"the wedge filler grew geometry; it is meant to draw nothing").is_equal(0)
			invisible += 1
			continue
		assert_bool(mesh.get_surface_count() >= 1).override_failure_message(
				"'%s' draws nothing but is not the declared filler" % library.get_item_name(item_id)) \
			.is_true()
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as StandardMaterial3D
			assert_object(material).is_not_null()
			assert_object(material.albedo_texture).is_not_null()
			assert_int(material.texture_filter).is_equal(BaseMaterial3D.TEXTURE_FILTER_NEAREST)
	assert_int(invisible).override_failure_message(
			"the meshlib has no wedge filler at all; a tall ramp cannot declare its own rows") \
		.is_equal(1)


func test_every_bound_mood_resolves_to_the_preset_it_names() -> void:
	# The keys are RESOLUTION KEYS since #393, not indices into a local table, so the scene's
	# moods can go missing in a way the old copy could not: renaming or deleting a file under
	# Resources/LookPresets/ makes LookKnobs fall back to the default -- deliberately soft on a
	# board, where a broken map must still render, but the diorama's four are a fixed set and
	# nothing else would say they had gone.
	var names: Array[String] = _scene.PRESET_NAMES
	assert_int(names.size()).is_equal(4)
	for preset_name in names:
		var preset := LookKnobs.resolve(preset_name)
		assert_str(preset.preset_name).override_failure_message(
			"LookDev binds a key to '%s' but LookKnobs resolved '%s' -- that preset was renamed "
			% [preset_name, preset.preset_name]
			+ "or deleted, and the scene now silently wears the default instead."
		).is_equal(preset_name)


func test_a_mood_key_applies_the_WHOLE_mood_to_this_scene() -> void:
	# #393's actual claim: the SHARED applier reaches this host, entire -- not the nine properties
	# the retired local table wrote. Every expectation is read back off the preset FILE, so no
	# feel-tuned number is pinned and the dev may retune any mood freely; what is asserted is only
	# that the saved value ARRIVED. A signature over a few sampled properties cannot do this job --
	# rename `WorldEnvironment` in LookDev.tscn and LookKnobs.write silently no-ops that whole
	# group, while the sun alone still makes four distinct signatures.
	#
	# ONE knob is expected not to land, and counting them is what pins that: `opening_view_cells`
	# names a property the look-dev root does not have (the rig free-roams here, it never frames),
	# so write() no-ops on it exactly as on a missing node. Identified by its derived preset key,
	# never by its label -- LookKnobs says the labels are the part that gets reworded.
	var preset := LookKnobs.resolve(_scene.PRESET_NAMES[0])
	_scene.apply_preset(0)
	var skipped: Array[String] = []
	for knob: Dictionary in LookKnobs.preset_knobs():
		var key := LookKnobs.preset_key(knob)
		var live: Variant = LookKnobs.read(_scene, knob)
		if typeof(live) == TYPE_NIL:
			skipped.append(key)
			continue
		var saved: Variant = preset.values[key]
		assert_bool(LookKnobs.same_value(live, saved)).override_failure_message(
			"after applying '%s', %s reads %s but the preset saved %s -- the mood did not land"
			% [preset.preset_name, key, live, saved]
		).is_true()
	assert_array(skipped).override_failure_message(
		"expected exactly one knob with no home in this scene, got %s -- a node renamed in "
		% [skipped] + "LookDev.tscn drops its whole group silently, which is what this counts."
	).is_equal([".|opening_view_cells"])


func test_dof_focus_tracks_the_camera_distance() -> void:
	# The focus band is derived from the camera's live distance every frame (dev
	# note 2026-08-12: static distances let close zoom drift into the near-blur
	# band). Pinned as the RELATIONSHIP against the rig's own exported offsets --
	# the offsets and the blur amount stay tunable feel values.
	var rig := _scene.get_node("CameraRig") as Node3D
	var camera := _scene.get_node("CameraRig/Pitch/Camera") as Camera3D
	var attributes := camera.attributes as CameraAttributesPractical
	var band_near: float = rig.focus_band_near
	var band_far: float = rig.focus_band_far
	var initial_z := camera.position.z

	rig.set_zoom(7.0)
	for i in 5:
		await get_tree().process_frame

	assert_bool(camera.position.z < initial_z).is_true()  # the zoom actually moved
	assert_float(attributes.dof_blur_near_distance) \
			.is_equal_approx(maxf(0.5, camera.position.z - band_near), 0.01)
	assert_float(attributes.dof_blur_far_distance) \
			.is_equal_approx(camera.position.z + band_far, 0.01)


func test_toggles_flip_their_layer() -> void:
	var world_env := _scene.get_node("WorldEnvironment") as WorldEnvironment
	var env := world_env.environment
	var camera := _scene.get_node("CameraRig/Pitch/Camera") as Camera3D
	var attributes := camera.attributes as CameraAttributesPractical

	var fog_before := env.volumetric_fog_enabled
	_scene.toggle_fog()
	assert_bool(env.volumetric_fog_enabled).is_equal(not fog_before)

	var glow_before := env.glow_enabled
	_scene.toggle_glow()
	assert_bool(env.glow_enabled).is_equal(not glow_before)

	var dof_before := attributes.dof_blur_far_enabled
	_scene.toggle_dof()
	assert_bool(attributes.dof_blur_far_enabled).is_equal(not dof_before)
	assert_bool(attributes.dof_blur_near_enabled).is_equal(not dof_before)

	var vignette := _scene.get_node("UI/Vignette") as ColorRect
	var vignette_before := vignette.visible
	_scene.toggle_vignette()
	assert_bool(vignette.visible).is_equal(not vignette_before)

	var torch_light := _scene.get_node("Props/Torch/TorchLight") as OmniLight3D
	var flame := _scene.get_node("Props/Torch/Flame") as MeshInstance3D
	var torch_before := torch_light.visible
	_scene.toggle_torch()
	assert_bool(torch_light.visible).is_equal(not torch_before)
	assert_bool(flame.visible).is_equal(not torch_before)
