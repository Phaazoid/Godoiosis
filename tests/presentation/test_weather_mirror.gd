# The weather's drawing (#1260), at the seams a headless run CAN see. Whether the rain looks right is
# the dev's eye and tools/weather_probe's pixels; what is pinned here is that each channel is WIRED:
#
#   - the cull box reaches every emitter (#656 shipped a particle invisible for want of exactly this);
#   - a look draws only what it drops: snow turns rain off, and rain snow (#1269); fog draws its pass
#     and cards and neither (#1285), and sorts under every piece of markup;
#   - a storm's flash reaches the screen through battle3d's white-out on an ordinary frame;
#   - a clear board draws nothing, and the board's weather is what the mirror draws;
#   - the box arithmetic carries the authored births whatever the amount;
#   - the sky glow can never fight a Look preset, because no Look knob names what it writes;
#   - the board's wind (#1286) reaches every fall, the specks, the clouds and the plants, and saves;
#   - an aurora (#1298) draws its curtains, light and motes and nothing else, eases out, sorts under the
#     markup, cycles its colours through all three at once, and holds its pulse under #217's setting; a
#     bolt's corona is its look's element, and a strike is aimed where the camera looks.
extends GdUnitTestSuite

const SCENE: PackedScene = preload("res://Scenes/Battle3D/Battle3D.tscn")
const MISSION := "res://Scenarios/missions/TheFord.tres"
# A board with plants on it, for the wind's sway (#1286).
const PLANTED := "res://Scenarios/missions/Level_1.tres"

var _scene: Node3D


func before() -> void:
	_scene = SCENE.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	_scene.game.scenario_manager.load_scenario(MISSION)
	await await_idle_frame()


func after() -> void:
	if _scene != null:
		_scene.game.scenario_manager.current_weather = Weather.Kind.CLEAR
		_scene.game.scenario_manager.current_wind = Wind.Kind.CALM
		get_tree().root.remove_child(_scene)
		_scene.free()


func after_test() -> void:
	_scene.game.scenario_manager.current_weather = Weather.Kind.CLEAR
	_scene.game.scenario_manager.current_wind = Wind.Kind.CALM
	_scene.game.scenario_manager.current_wind_direction = Wind.Direction.EAST
	var mirror: WeatherMirror = _scene._weather
	mirror._process(0.0)
	await await_idle_frame()


func _mirror() -> WeatherMirror:
	var mirror: WeatherMirror = _scene._weather
	assert_object(mirror).override_failure_message("the scene built no weather mirror").is_not_null()
	return mirror


# The sweep battle3d runs whenever the board's extent moves must reach every emitter, and the box it
# sets must hold the board AND its lifted stage copy -- a stale box draws nothing and no other case sees
# it. Walked off the node's CHILDREN, not its own list, so an emitter left out of that list reds here.
func test_the_cull_box_reaches_every_emitter() -> void:
	var mirror := _mirror()
	var board: AABB = _scene._board_volume()
	assert_bool(board.has_volume()).override_failure_message("fixture: the mission built no board").is_true()
	_scene._cover_effects(board)
	var systems := mirror.find_children("*", "GPUParticles3D", true, false)
	systems.append_array((_scene._wind as WindMirror).find_children("*", "GPUParticles3D", true, false))
	assert_int(systems.size()).override_failure_message("fixture: the mirror built no emitters").is_greater(2)
	for node in systems:
		var box := (node as GPUParticles3D).visibility_aabb
		assert_bool(box.encloses(BoardSpace.effect_volume(board, 0.0))).override_failure_message(
				"%s's cull box does not hold the board and its stage: %s" % [node.name, box]).is_true()


func test_the_board_weather_is_what_the_mirror_draws_and_clear_draws_nothing() -> void:
	var mirror := _mirror()
	_scene.game.scenario_manager.current_weather = Weather.Kind.RAIN
	mirror._process(0.016)
	assert_bool(mirror._rain.emitting and mirror._rain.visible).override_failure_message(
			"the board is raining and the mirror drew no rain").is_true()
	assert_bool(mirror._wet.visible).is_true()
	_scene.game.scenario_manager.current_weather = Weather.Kind.CLEAR
	mirror._process(0.016)
	assert_bool(mirror._rain.emitting or mirror._rain.visible or mirror._wet.visible \
			or mirror._puddles.visible or mirror._splash.visible or mirror._snow.visible \
			or mirror._fog_pass.visible or mirror._fog_cards.visible or mirror.aurora()._curtains.visible \
			or mirror.aurora()._light.visible or mirror.aurora()._motes.visible).override_failure_message(
			"a clear board still draws weather").is_false()


# Every weather shader PARSES, and declares each parameter the mirror sets on it. A headless run draws
# nothing, so a shader that fails to compile is otherwise only a line in the log (#1269 shipped one
# to its first run), and a parameter set on a uniform that does not exist is dropped in silence.
func test_every_weather_shader_parses_and_declares_what_the_mirror_sets() -> void:
	var mirror := _mirror()
	var mask := ["mask", "mask_origin", "cell_size", "box_min", "box_max", "floor_y", "keep"]
	var wind: WindMirror = _scene._wind
	var art := WeatherArt.fog_noise()
	var sway := ["texture_albedo", "wind_heading", "lean", "flutter", "sway_speed", "sway_time"]
	var fog := ["mask", "mask_origin", "cell_size", "fog_field", "fog_noise", "layer_amount", "layer_depth",
			"pool_amount", "bank_amount", "bank_height", "bank_size", "breakup", "fog_drift"]
	var wanted := {
		mirror._rain_process: mask + ["velocity"],
		mirror._rain_draw: ["streak", "size", "tint"],
		mirror._splash_process: mask,
		mirror._splash_draw: ["strip", "tint", "frames"],
		mirror._snow_process: mask + ["velocity", "sway", "swirl", "swirl_scale", "settle", "big", "lift"],
		mirror._snow_draw: ["flakes", "size", "tint"],
		mirror._drift_process: mask + ["velocity", "hover"],
		mirror._drift_draw: ["streak", "size", "tint", "age_fade"],
		mirror.grade()._material: ["saturation", "brightness", "tint", "veil", "veil_color", "veil_offset"],
		mirror._fog_process: fog + ["box_min", "box_max", "keep", "velocity", "lift", "sink", "dissolve", "frames"],
		mirror._fog_draw: ["wisps", "tint", "size", "frames"],
		mirror._fog_pass_material: fog + ["tint", "strength", "pixel_steps", "art_pixels", "slab_low", "slab_high"],
		wind._speck_process: ["mask", "mask_origin", "cell_size", "box_min", "box_max", "keep", "wind", "flutter",
				"height", "leaves", "leaf_frames", "dust_frames"],
		wind._speck_draw: ["specks", "leaf_tint", "dust_tint", "size", "leaf_frames", "dust_frames", "tumbles"],
		wind._cloud_material: ["cloud_noise", "drift", "cover", "darkness", "cloud_size", "softness", "pixel_steps",
				"art_pixels", "cell_size"],
		mirror.aurora()._curtain_material: ["noise_tex", "color_low", "color_high", "strength", "bands", "spacing",
				"band_width", "wave", "wave_length", "time", "rays", "ray_spacing", "pulse", "angle", "centre",
				"pixel_steps", "art_pixels", "cell_size"],
		mirror.aurora()._mote_process: ["mask", "mask_origin", "cell_size", "box_min", "box_max", "keep", "rise",
				"wander", "wind", "height"],
		mirror.aurora()._mote_draw: ["tint", "texel", "shape"],
		BoardMirror.sway_material(art, false): sway,
		BoardMirror.sway_material(art, true): sway,
	}
	for material: ShaderMaterial in wanted:
		var names: Array[String] = []
		for entry: Dictionary in material.shader.get_shader_uniform_list():
			names.append(String(entry["name"]))
		var path := material.shader.resource_path
		assert_int(names.size()).override_failure_message(
				"%s exposes no uniforms -- it failed to parse" % path).is_greater(0)
		for name: String in wanted[material]:
			assert_bool(names.has(name)).override_failure_message(
					"the mirror sets '%s' on %s, which declares no such uniform" % [name, path]).is_true()


# What a look drops decides what is drawn, both ways: a snow board draws flakes and no rain, splash,
# sheen or puddle, and a rain board no flakes.
func test_a_look_draws_only_what_it_drops() -> void:
	var mirror := _mirror()
	assert_object(WeatherLook.for_kind(Weather.Kind.SNOW)).override_failure_message(
			"fixture: snow has no look file").is_not_null()
	_scene.game.scenario_manager.current_weather = Weather.Kind.SNOW
	mirror._process(0.016)
	var snow_drawn := mirror._snow.emitting and mirror._snow.visible and mirror._snow_cover.visible \
			and mirror._snow_cover.texture_albedo != null
	var rain_on_snow := mirror._rain.emitting or mirror._rain.visible or mirror._splash.visible \
			or mirror._wet.visible or mirror._puddles.visible
	_scene.game.scenario_manager.current_weather = Weather.Kind.RAIN
	mirror._process(0.016)
	var snow_on_rain := mirror._snow.emitting or mirror._snow.visible or mirror._snow_cover.visible
	assert_bool(snow_drawn).override_failure_message("the board is snowing and the mirror drew no snow").is_true()
	assert_bool(rain_on_snow).override_failure_message("a snow board draws rain").is_false()
	assert_bool(snow_on_rain).override_failure_message("a rain board draws snow").is_false()


# The wire to the board (#1269): a look that caps props turns the board's billboard caps and the cap
# decal on, one that does not leaves them off, and leaving the snow takes them down. Read off the
# BOARD's own state, so a forgotten injection in battle3d reds here.
func test_a_capping_snow_reaches_the_board_and_leaving_it_clears() -> void:
	var mirror := _mirror()
	var board := _scene.get_node("BoardMirror") as BoardMirror
	var capping := WeatherLook.for_kind(Weather.Kind.SNOW)
	var bare := WeatherLook.for_kind(Weather.Kind.LIGHT_SNOW)
	assert_bool(capping != null and capping.caps_props and bare != null and not bare.caps_props) \
			.override_failure_message("fixture: snow should cap props and light snow should not").is_true()
	_scene.game.scenario_manager.current_weather = Weather.Kind.SNOW
	mirror._process(0.016)
	var on := board.prop_caps_shown() and mirror._caps.visible
	_scene.game.scenario_manager.current_weather = Weather.Kind.LIGHT_SNOW
	mirror._process(0.016)
	var off_light := not board.prop_caps_shown() and not mirror._caps.visible
	var buried_light := board.tufts_buried()   # any snow buries the grass (#1278)
	_scene.game.scenario_manager.current_weather = Weather.Kind.SNOW
	mirror._process(0.016)
	_scene.game.scenario_manager.current_weather = Weather.Kind.CLEAR
	mirror._process(0.016)
	var off_clear := not board.prop_caps_shown() and not mirror._caps.visible and not board.tufts_buried()
	assert_bool(buried_light).override_failure_message("a light snow left the grass standing").is_true()
	assert_bool(on).override_failure_message("a capping snow reached no cap").is_true()
	assert_bool(off_light).override_failure_message("a snow that caps nothing still caps").is_true()
	assert_bool(off_clear).override_failure_message("the caps outlived the snow").is_true()


# The ground drift runs while its rate is above zero, and only then -- the dev's blizzard has it, the
# gentler snows author none. Driven off the look's own knob, so no authored rate is pinned.
func test_the_ground_drift_runs_only_at_a_rate() -> void:
	var mirror := _mirror()
	var look := WeatherLook.for_kind(Weather.Kind.BLIZZARD)
	assert_object(look).override_failure_message("fixture: the blizzard has no look file").is_not_null()
	var was := look.drift_rate
	_scene.game.scenario_manager.current_weather = Weather.Kind.BLIZZARD
	_scene.game.scenario_manager.current_wind = Wind.Kind.STRONG_WIND
	look.drift_rate = 1.5
	mirror._process(0.016)
	var running := mirror._drift.emitting and mirror._drift.visible
	look.drift_rate = 0.0
	mirror._process(0.016)
	var stopped := not mirror._drift.emitting and not mirror._drift.visible
	# A calm board has nothing for the drift to stream along (#1286), whatever the rate.
	look.drift_rate = 1.5
	_scene.game.scenario_manager.current_wind = Wind.Kind.CALM
	mirror._process(0.016)
	var calm := mirror._drift.emitting or mirror._drift.visible
	look.drift_rate = was
	assert_bool(running).override_failure_message("a drift rate drew no drift").is_true()
	assert_bool(stopped).override_failure_message("a zero drift rate still drew drift").is_true()
	assert_bool(calm).override_failure_message("a calm board still drew ground drift").is_false()


# A look's puddles switch is honoured by the decal (light rain authors none, the dev's ruling).
func test_a_look_without_puddles_draws_none() -> void:
	var mirror := _mirror()
	var look := WeatherLook.for_kind(Weather.Kind.RAIN)
	var was := look.puddles
	_scene.game.scenario_manager.current_weather = Weather.Kind.RAIN
	look.puddles = false
	mirror._process(0.016)
	var hidden := not mirror._puddles.visible
	look.puddles = true
	mirror._process(0.016)
	var shown := mirror._puddles.visible
	look.puddles = was
	assert_bool(hidden).override_failure_message("a look with no puddles still drew them").is_true()
	assert_bool(shown).override_failure_message("a look with puddles drew none").is_true()


# Driven through battle3d._process, the frame path, rather than through the composition -- test_arc_slice2's
# own lesson: a case calling _push_whiteout directly passes with the frame-path push deleted.
func test_a_strike_reaches_the_screen_and_clears() -> void:
	var mirror := _mirror()
	_scene.game.scenario_manager.current_weather = Weather.Kind.THUNDERSTORM
	var look := WeatherLook.for_kind(Weather.Kind.THUNDERSTORM)
	assert_bool(look.lightning).override_failure_message(
			"fixture: the thunderstorm's look strikes no lightning").is_true()
	mirror._process(0.016)
	mirror._next_strike = mirror._clock
	mirror._process(0.016)
	_scene._process(0.0)
	var lit: bool = _scene._whiteout != null and _scene._whiteout.visible
	var bolts := mirror._bolts._bolts.size()
	mirror._strike_at = -INF
	mirror._process(0.016)
	_scene._process(0.0)
	var dark: bool = _scene._whiteout != null and _scene._whiteout.visible
	assert_bool(lit).override_failure_message("a strike's flash never reached the screen").is_true()
	assert_int(bolts).override_failure_message("a strike drew no bolt").is_greater(0)
	assert_bool(dark).override_failure_message("the flash never cleared").is_false()


func test_the_box_arithmetic_carries_the_authored_births() -> void:
	for spec: Array in [[120.0, 2.5], [3.0, 0.3], [9000.0, 4.0]]:
		var per_second: float = spec[0]
		var life: float = spec[1]
		var amount := WeatherMirror.amount_for(per_second, life)
		for padded in [amount, int(amount * 1.5), amount * 4]:
			var keep := WeatherMirror.keep_for(per_second, life, padded)
			assert_float(keep * float(padded) / life).override_failure_message(
					"a system of %d carries the wrong births" % padded).is_equal_approx(per_second, per_second * 0.02 + 0.5)
			assert_float(keep).is_less_equal(1.0)


# Under #217's setting a strike is one soft swell: never past half, and no second rise.
func test_a_safe_strike_is_one_soft_swell() -> void:
	var peak := 0.0
	var falling := false
	var rose_again := false
	var last := 0.0
	for i in 81:
		var level := WeatherMirror.strike_level(float(i) * 0.01, true)
		peak = maxf(peak, level)
		if level < last:
			falling = true
		elif falling and level > last + 0.0001:
			rose_again = true
		last = level
	assert_float(peak).is_less_equal(0.5)
	assert_bool(rose_again).override_failure_message("the safe strike flickered").is_false()
	assert_float(WeatherMirror.strike_level(2.0, false)).is_equal(0.0)


# The glow writes ProceduralSkyMaterial.energy_multiplier. A Look knob naming it would put a preset and
# the storm on one property, each overwriting the other -- #278's fight, before #278 exists to referee.
func test_no_look_knob_names_what_the_storm_writes() -> void:
	for knob: Dictionary in LookKnobs.KNOBS:
		assert_bool(String(knob.get("prop", "")).contains("energy_multiplier")).override_failure_message(
				"Look knob %s names the sky energy the storm's glow writes" % knob.get("label")).is_false()


# The cold grade (#1269): a grading weather shows it, easing in rather than snapping, and a clear or
# ungraded one hides it -- no full-screen pass while nothing is graded. It sits BELOW the 2D game's
# canvas layer, which is what keeps the HUD ungraded (measured on the real renderer by the probe).
func test_the_grade_eases_in_under_a_grading_weather_and_hides_at_identity() -> void:
	var mirror := _mirror()
	var grade := mirror.grade()
	assert_int(grade.layer).override_failure_message("the grade is not under the game's canvas layer") \
			.is_less(0)
	var kind := Weather.Kind.CLEAR
	for candidate: Weather.Kind in Weather.Kind.values():
		var look := WeatherLook.for_kind(candidate)
		if look != null and look.grades() and look.grade_fade > 0.0:
			kind = candidate
			break
	assert_int(kind).override_failure_message("fixture: no weather grades the board").is_not_equal(Weather.Kind.CLEAR)
	var look := WeatherLook.for_kind(kind)
	_scene.game.scenario_manager.current_weather = kind
	mirror._process(look.grade_fade * 0.1)
	var partway := grade.saturation
	mirror._process(look.grade_fade * 10.0)
	assert_bool(grade.rect().visible).override_failure_message("a grading weather drew no grade").is_true()
	assert_float(grade.saturation).is_equal_approx(look.grade_saturation, 0.01)
	if not is_equal_approx(look.grade_saturation, 1.0):
		assert_bool(absf(partway - look.grade_saturation) > 0.01).override_failure_message(
				"the grade snapped to the weather rather than easing in").is_true()
	_scene.game.scenario_manager.current_weather = Weather.Kind.CLEAR
	mirror._process(look.grade_fade * 10.0)
	assert_bool(grade.rect().visible).override_failure_message("a clear board still draws a grade").is_false()
	_scene.game.scenario_manager.current_weather = Weather.Kind.RAIN
	mirror._process(10.0)
	assert_bool(WeatherLook.for_kind(Weather.Kind.RAIN).grades()).override_failure_message(
			"fixture: rain grades the board, so it cannot show the identity case").is_false()
	assert_bool(grade.rect().visible).override_failure_message("an ungraded rain drew a grade").is_false()


# The grade writes only its own material, and no Look knob may reach the node it is drawn on.
func test_no_look_knob_names_the_weathers_grade() -> void:
	for knob: Dictionary in LookKnobs.KNOBS:
		assert_bool(String(knob.get("node", "")).contains("Weather")).override_failure_message(
				"Look knob %s names a node the weather draws on" % knob.get("label")).is_false()


# No weather decal reaches a wall (#1278). Godot remaps the surface-to-decal angle to 0..1 before
# its normal fade, so a vertical face sits at 0.5: a fade below that paints every cliff (0.35 left
# 13% of the snow on them, measured on the dev's board). A threshold of the engine's, not a feel value.
func test_no_weather_decal_reaches_a_wall() -> void:
	var mirror := _mirror()
	var decals := mirror.find_children("*", "Decal", true, false)
	assert_int(decals.size()).override_failure_message("fixture: the mirror built no decals").is_greater(3)
	for node in decals:
		assert_float((node as Decal).normal_fade).override_failure_message(
				"%s fades at %.2f, so it paints walls" % [node.name, (node as Decal).normal_fade]).is_greater(0.5)


# The snow's relief (#1278) rides the cover decal as its normal map at any strength above 0, and is
# taken off at 0. A slider repaint waits for the drag to settle, so each change is given two frames,
# the second past the settle.
func test_the_snow_relief_reaches_the_cover_and_zero_takes_it_off() -> void:
	var mirror := _mirror()
	var look := WeatherLook.for_kind(Weather.Kind.SNOW)
	var was := look.snow_relief
	_scene.game.scenario_manager.current_weather = Weather.Kind.SNOW
	look.snow_relief = 4.0
	mirror._process(0.016)
	var raised := mirror._snow_cover.texture_normal != null
	look.snow_relief = 0.0
	mirror._process(0.016)
	mirror._process(WeatherMirror.COVER_SETTLE + 0.05)
	var flat := mirror._snow_cover.texture_normal == null
	look.snow_relief = was
	assert_bool(raised).override_failure_message("a snow with relief drew a flat cover").is_true()
	assert_bool(flat).override_failure_message("a relief of 0 left the cover raised").is_true()


# A fog board (#1285) draws the fog's pass and cards, with where fog may stand handed to both, and no
# rain or snow; a rain board after it draws no fog.
func test_a_fog_board_draws_its_pass_and_cards_and_nothing_else() -> void:
	var mirror := _mirror()
	assert_object(WeatherLook.for_kind(Weather.Kind.FOG)).override_failure_message(
			"fixture: fog has no look file").is_not_null()
	_scene.game.scenario_manager.current_weather = Weather.Kind.FOG
	mirror._process(0.016)
	var drawn := mirror._fog_pass.visible and mirror._fog_cards.emitting and mirror._fog_cards.visible
	var field_in := mirror._fog_pass_material.get_shader_parameter("fog_field") != null \
			and mirror._fog_process.get_shader_parameter("fog_field") != null
	var other := mirror._rain.visible or mirror._snow.visible or mirror._wet.visible or mirror._snow_cover.visible
	_scene.game.scenario_manager.current_weather = Weather.Kind.RAIN
	mirror._process(0.016)
	var fog_on_rain := mirror._fog_pass.visible or mirror._fog_cards.emitting or mirror._fog_cards.visible
	assert_bool(drawn).override_failure_message("the board is foggy and the mirror drew no fog").is_true()
	assert_bool(field_in).override_failure_message("the fog drew with nowhere to stand").is_true()
	assert_bool(other).override_failure_message("a fog board draws rain or snow").is_false()
	assert_bool(fog_on_rain).override_failure_message("a rain board draws fog").is_false()


# The ruling that markup and rings draw over fog (#1285): both of the fog's draws sort under every
# BoardOverlays layer, the outline a layer draws one under its own sort included, and under the gas
# floor -- and the mirror's materials carry those priorities, so the table is not a comment.
func test_the_fog_sorts_under_every_piece_of_markup() -> void:
	var mirror := _mirror()
	var lowest := BoardOverlays.GAS_FLOOR_SORT
	for layer: BoardOverlays.Layer in BoardOverlays.LAYERS:
		lowest = mini(lowest, int(BoardOverlays.LAYERS[layer]["sort"]) - 1)
	for priority: int in [mirror._fog_pass_material.render_priority, mirror._fog_draw.render_priority]:
		assert_int(priority).override_failure_message(
				"a fog draw sorts at %d, not under the lowest markup at %d" % [priority, lowest]).is_less(lowest)
	assert_int(mirror._fog_pass_material.render_priority).is_equal(BoardOverlays.FOG_RENDER_PRIORITY)
	assert_int(mirror._fog_draw.render_priority).is_equal(BoardOverlays.FOG_CARD_RENDER_PRIORITY)


# The fog takes the sky's horizon colour by the look's share of it, and none at 0 -- read, so a night
# look darkens the fog without either writing the other.
func test_the_fog_takes_the_sky_by_its_share() -> void:
	var look := WeatherLook.new()
	look.fog_color = Color(1.0, 1.0, 1.0)
	var night := Color(0.1, 0.12, 0.2)
	look.sky_tint = 0.0
	assert_bool(WeatherMirror.fog_tint(look, night).is_equal_approx(Color(1.0, 1.0, 1.0))).override_failure_message(
			"a fog that takes none of the sky still changed colour").is_true()
	look.sky_tint = 1.0
	assert_bool(WeatherMirror.fog_tint(look, night).is_equal_approx(night)).override_failure_message(
			"a fog that takes all of the sky is not the sky's colour").is_true()


# The fog's cards are born over the BOARD, never the view (#1285): setting a particle system's amount
# restarts it, and an amount sized off the camera re-dealt every card on every zoom -- the clouds jumping
# to new shapes. The camera is moved far out and back under a fog, the mirror re-run each time, and the
# card system must keep its amount and lifetime throughout.
func test_zooming_never_re_deals_the_fog_cards() -> void:
	var mirror := _mirror()
	_scene.game.scenario_manager.current_weather = Weather.Kind.FOG
	mirror._process(0.016)
	var amount := mirror._fog_cards.amount
	var lifetime := mirror._fog_cards.lifetime
	assert_int(amount).override_failure_message("fixture: the fog sized no cards").is_greater(1)
	var camera: Camera3D = mirror.camera
	assert_object(camera).override_failure_message("fixture: the mirror has no camera").is_not_null()
	var was := camera.global_position
	for rise: float in [30.0, 60.0, 0.0]:
		camera.global_position = was + Vector3(0.0, rise, 0.0)
		mirror._process(0.016)
		assert_int(mirror._fog_cards.amount).override_failure_message(
				"the cards were re-dealt by a camera %.0f higher: amount %d -> %d" % [
				rise, amount, mirror._fog_cards.amount]).is_equal(amount)
		assert_float(mirror._fog_cards.lifetime).is_equal(lifetime)
	camera.global_position = was


# The card's sink and dissolve dials reach its material (#1285): the parse case proves the shader
# DECLARES them, this proves the mirror FEEDS them, so a dial that moves nothing cannot ship.
func test_the_card_sink_and_dissolve_dials_reach_the_cards() -> void:
	var mirror := _mirror()
	var look := WeatherLook.for_kind(Weather.Kind.FOG)
	assert_object(look).override_failure_message("fixture: fog has no look file").is_not_null()
	var was_sink := look.card_sink
	var was_dissolve := look.card_dissolve
	look.card_sink = 0.77
	look.card_dissolve = 2.5
	_scene.game.scenario_manager.current_weather = Weather.Kind.FOG
	mirror._process(0.016)
	var sink: float = mirror._fog_process.get_shader_parameter("sink")
	var dissolve: float = mirror._fog_process.get_shader_parameter("dissolve")
	look.card_sink = was_sink
	look.card_dissolve = was_dissolve
	assert_float(sink).override_failure_message("the Card sink dial never reached the cards").is_equal_approx(0.77, 0.0001)
	assert_float(dissolve).override_failure_message("the Card dissolve dial never reached the cards").is_equal_approx(2.5, 0.0001)


# ---- The aurora (#1298) ------------------------------------------------------------------------

# Clears the board and lets every aurora part ease all the way out, so the next case starts dark.
func _clear_aurora(mirror: WeatherMirror) -> void:
	_scene.game.scenario_manager.current_weather = Weather.Kind.CLEAR
	mirror._process(60.0)
	mirror._process(0.016)


# The first weather the board can name that draws an aurora: which kinds do is authored.
func _aurora_kind(lightning: bool) -> Weather.Kind:
	for kind: Weather.Kind in Weather.Kind.values():
		var look := WeatherLook.for_kind(kind)
		if look != null and look.fall == WeatherLook.Fall.AURORA and look.lightning == lightning:
			return kind
	return Weather.Kind.CLEAR


# An aurora board draws its curtains, its light and its motes, with the ground mask handed to the motes,
# and no rain, snow or fog. Leaving it EASES them out -- still drawn a moment after, gone once the fade has
# run -- and a clear board draws none of them.
func test_an_aurora_board_draws_its_three_parts_and_eases_out() -> void:
	var mirror := _mirror()
	var kind := _aurora_kind(false)
	assert_int(kind).override_failure_message("fixture: no weather draws an aurora").is_not_equal(Weather.Kind.CLEAR)
	var look := WeatherLook.for_kind(kind)
	var aurora := mirror.aurora()
	_scene.game.scenario_manager.current_weather = kind
	mirror._process(0.016)
	mirror._process(look.grade_fade + 0.1)
	var drawn := aurora._curtains.visible and aurora._light.visible and aurora._motes.visible \
			and aurora._motes.emitting
	var level := aurora.level()
	var masked := aurora._mote_process.get_shader_parameter("mask") != null
	var other := mirror._rain.visible or mirror._snow.visible or mirror._wet.visible or mirror._snow_cover.visible \
			or mirror._fog_pass.visible or mirror._fog_cards.visible
	_scene.game.scenario_manager.current_weather = Weather.Kind.CLEAR
	mirror._process(look.grade_fade * 0.25)
	var easing := aurora._curtains.visible and aurora.level() > 0.0 and aurora.level() < level
	mirror._process(look.grade_fade + 0.1)
	var gone := not (aurora._curtains.visible or aurora._light.visible or aurora._motes.visible)
	assert_bool(drawn).override_failure_message("the board wears an aurora and the mirror drew no aurora").is_true()
	assert_float(level).override_failure_message("the aurora never came all the way in").is_equal_approx(1.0, 0.001)
	assert_bool(masked).override_failure_message("the motes rose with no ground to rise off").is_true()
	assert_bool(other).override_failure_message("an aurora board draws rain, snow or fog").is_false()
	assert_bool(easing).override_failure_message("leaving the aurora popped it rather than easing it out").is_true()
	assert_bool(gone).override_failure_message("the aurora outlived its weather").is_true()


# The ruling that markup draws over the weather, for the aurora: its curtains sort under every layer and
# under the clouds' slot and the fog, and its motes take the specks' slot, which never draws beside them.
func test_the_aurora_sorts_under_every_piece_of_markup() -> void:
	var aurora := _mirror().aurora()
	var lowest := BoardOverlays.GAS_FLOOR_SORT
	for layer: BoardOverlays.Layer in BoardOverlays.LAYERS:
		lowest = mini(lowest, int(BoardOverlays.LAYERS[layer]["sort"]) - 1)
	var curtains := aurora._curtain_material.render_priority
	assert_int(curtains).is_equal(BoardOverlays.AURORA_RENDER_PRIORITY)
	assert_int(curtains).override_failure_message("the curtains sort over the markup").is_less(lowest)
	assert_int(curtains).override_failure_message("the curtains sort over the cloud shadows")\
			.is_less(BoardOverlays.CLOUD_RENDER_PRIORITY)
	assert_int(aurora._mote_draw.render_priority).is_equal(BoardOverlays.MOTE_RENDER_PRIORITY)
	assert_int(aurora._mote_draw.render_priority).is_less(lowest)


# ONE colour cycle reaches all three: once the clock is inside the second scheme, the curtains hold its
# pair, the motes its fringe eased toward white, and the light a colour between its two -- and none of
# them the first scheme's. Read off what each draws with.
func test_the_colour_cycle_reaches_the_curtains_the_light_and_the_motes() -> void:
	var mirror := _mirror()
	var kind := _aurora_kind(false)
	var look := WeatherLook.for_kind(kind)
	var was_blend := look.scheme_blend
	look.scheme_blend = 0.2
	var aurora := mirror.aurora()
	_scene.game.scenario_manager.current_weather = kind
	mirror._process(0.016)
	var a_low: Color = aurora._curtain_material.get_shader_parameter("color_low")
	mirror._process(look.scheme_seconds * 1.25 - 0.016)
	var low: Color = aurora._curtain_material.get_shader_parameter("color_low")
	var high: Color = aurora._curtain_material.get_shader_parameter("color_high")
	var mote: Color = aurora._mote_draw.get_shader_parameter("tint")
	var light := aurora._light.light_color
	look.scheme_blend = was_blend
	_clear_aurora(mirror)
	assert_bool(look.scheme_a_low.is_equal_approx(look.scheme_b_low)).override_failure_message(
			"fixture: schemes A and B share a colour, so no case can tell them apart").is_false()
	assert_bool(a_low.is_equal_approx(look.scheme_a_low)).override_failure_message(
			"the curtains did not open on the first scheme").is_true()
	assert_bool(low.is_equal_approx(look.scheme_b_low) and high.is_equal_approx(look.scheme_b_fringe)) \
			.override_failure_message("the curtains never reached the second scheme: %s / %s" % [low, high]).is_true()
	var whitened := look.scheme_b_fringe.lerp(Color.WHITE, AuroraLights.MOTE_WHITEN)
	assert_bool(Color(mote.r, mote.g, mote.b).is_equal_approx(whitened)).override_failure_message(
			"the motes never took the second scheme's fringe: %s" % mote).is_true()
	for channel in 3:
		var a: float = look.scheme_b_low[channel]
		var b: float = look.scheme_b_fringe[channel]
		assert_float(light[channel]).override_failure_message("the light is not in the second scheme: %s" % light)\
				.is_between(minf(a, b) - 0.001, maxf(a, b) + 0.001)


# A look's mote shape reaches what the motes are drawn as: dots one way, streaks the other.
func test_the_mote_shape_reaches_the_motes() -> void:
	var mirror := _mirror()
	var kind := _aurora_kind(false)
	var look := WeatherLook.for_kind(kind)
	var was := look.mote_shape
	_scene.game.scenario_manager.current_weather = kind
	look.mote_shape = WeatherLook.MoteShape.STREAKS
	mirror._process(0.016)
	var streaks: float = mirror.aurora()._mote_draw.get_shader_parameter("shape")
	look.mote_shape = WeatherLook.MoteShape.DOTS
	mirror._process(0.016)
	var dots: float = mirror.aurora()._mote_draw.get_shader_parameter("shape")
	look.mote_shape = was
	_clear_aurora(mirror)
	assert_float(streaks).override_failure_message("a streak look drew dots").is_equal(1.0)
	assert_float(dots).override_failure_message("a dot look drew streaks").is_equal(0.0)


# Under #217's setting the slow pulse the light and the curtains share holds at its mean; without it, it
# swells. Driven through the mirror, read off what the curtain and the light draw with.
func test_the_aurora_pulse_holds_under_photosensitivity() -> void:
	var mirror := _mirror()
	var kind := _aurora_kind(false)
	var look := WeatherLook.for_kind(kind)
	var was := look.light_pulse
	look.light_pulse = 0.5
	_scene.game.scenario_manager.current_weather = kind
	var aurora := mirror.aurora()
	mirror._process(look.grade_fade + 0.1)
	var swelling: Array[float] = []
	for step in 4:
		mirror._process(0.7)
		swelling.append(float(aurora._curtain_material.get_shader_parameter("pulse")))
	PlayerSettings.set_on(PlayerSettings.Setting.PHOTOSENSITIVITY, true)
	var held: Array[float] = []
	var energies: Array[float] = []
	for step in 4:
		mirror._process(0.7)
		held.append(float(aurora._curtain_material.get_shader_parameter("pulse")))
		energies.append(aurora._light.light_energy)
	PlayerSettings.reset_for_test()
	look.light_pulse = was
	_clear_aurora(mirror)
	var spread: float = swelling.max() - swelling.min()
	assert_float(spread).override_failure_message("fixture: the pulse never moved, so a hold cannot be seen")\
			.is_greater(0.05)
	for pulse in held:
		assert_float(pulse).override_failure_message("the pulse moved under photosensitivity").is_equal(1.0)
	for energy in energies:
		assert_float(energy).override_failure_message("the light swelled under photosensitivity")\
				.is_equal_approx(look.light_energy, 0.0001)


# A bolt's corona glows in its look's element (ElementPalette), carried per bolt: the same storm struck
# under two elements draws each in its own colour. Read off what the bolts drew, after a real strike.
func test_a_bolt_glows_in_its_looks_element() -> void:
	var mirror := _mirror()
	var look := WeatherLook.for_kind(Weather.Kind.THUNDERSTORM)
	var was := look.bolt_element
	_scene.game.scenario_manager.current_weather = Weather.Kind.THUNDERSTORM
	mirror._process(0.016)
	var drawn := {}
	for element: Elemental.Element in [Elemental.Element.AETHER, Elemental.Element.SHOCK]:
		look.bolt_element = element
		mirror._bolts.clear()
		mirror._next_strike = mirror._clock
		mirror._process(0.016)
		mirror._bolts._process(0.02)
		drawn[element] = mirror._bolts.coronas_drawn.duplicate()
	look.bolt_element = was
	_scene.game.scenario_manager.current_weather = Weather.Kind.CLEAR
	mirror._process(0.016)
	for element: Elemental.Element in drawn:
		var colours: Array = drawn[element]
		assert_int(colours.size()).override_failure_message("fixture: the strike drew no bolt").is_greater(0)
		assert_bool((colours[0] as Color).is_equal_approx(ElementPalette.color_for_element(element))) \
				.override_failure_message("a %s bolt glowed %s" % [Elemental.Element.keys()[element], colours[0]]).is_true()


# A strike falls from above where the camera LOOKS, asked at the strike -- an aurora storm with no motes
# runs no birth box, which is where the height used to be left over from (#1298's fix).
func test_a_strike_is_aimed_where_the_camera_looks_with_nothing_falling() -> void:
	var mirror := _mirror()
	var kind := _aurora_kind(true)
	assert_int(kind).override_failure_message("fixture: no aurora strikes").is_not_equal(Weather.Kind.CLEAR)
	var look := WeatherLook.for_kind(kind)
	var was_rate := look.mote_rate
	var was_aim := mirror.aim_source
	look.mote_rate = 0.0
	var aim_y := 25.0
	mirror.aim_source = func() -> Vector3: return Vector3(0.0, aim_y, 0.0)
	_scene.game.scenario_manager.current_weather = kind
	mirror._process(0.016)
	mirror._bolts.clear()
	mirror._next_strike = mirror._clock
	mirror._process(0.016)
	var top := -INF
	for bolt in mirror._bolts._bolts:
		for point in bolt.path:
			top = maxf(top, point.y)
	mirror.aim_source = was_aim
	look.mote_rate = was_rate
	_clear_aurora(mirror)
	assert_float(top).override_failure_message("the bolt fell from %.1f, not from above the aim" % top)\
			.is_equal_approx(aim_y + look.bolt_height, 2.0)


# ---- The wind (#1286) --------------------------------------------------------------------------

func _manager():
	return _scene.game.scenario_manager


# The board's wind is what every fall drifts with, and a calm board's rain falls straight: a weather has
# no wind of its own. Read off the material the mirror hands the GPU, so a wind_source battle3d forgot to
# hand on reds here.
func test_the_board_wind_reaches_the_falls_and_calm_falls_straight() -> void:
	var mirror := _mirror()
	var sm = _manager()
	sm.current_weather = Weather.Kind.RAIN
	sm.current_wind = Wind.Kind.GALE
	sm.current_wind_direction = Wind.Direction.SOUTH
	mirror._process(0.016)
	var blown: Variant = mirror._rain_process.get_shader_parameter("velocity")
	sm.current_wind = Wind.Kind.CALM
	mirror._process(0.016)
	var still: Variant = mirror._rain_process.get_shader_parameter("velocity")
	var want := WindLook.vector(Wind.Kind.GALE, Wind.Direction.SOUTH)
	assert_float(want.length()).override_failure_message("fixture: the gale blows nothing").is_greater(0.1)
	assert_bool(blown is Vector3 and still is Vector3).override_failure_message(
			"the mirror placed no rain (no view box?)").is_true()
	assert_vector(Vector2((blown as Vector3).x, (blown as Vector3).z)).override_failure_message(
			"the rain drifts %s under a gale blowing %s" % [blown, want]).is_equal_approx(want, Vector2.ONE * 0.001)
	assert_vector(Vector2((still as Vector3).x, (still as Vector3).z)).override_failure_message(
			"a calm board's rain still slants: %s" % still).is_equal_approx(Vector2.ZERO, Vector2.ONE * 0.001)


# A calm board draws no wind; a blowing one draws its specks, on the weather's own ground mask, and its
# cloud shadows -- under a clear sky, the only sky it draws under (the case below).
func test_a_calm_board_draws_no_wind_and_a_blowing_one_draws_specks_and_clouds() -> void:
	var weather := _mirror()
	var wind: WindMirror = _scene._wind
	var sm = _manager()
	assert_object(WindLook.for_kind(Wind.Kind.STRONG_WIND)).override_failure_message(
			"fixture: the strong wind has no look file").is_not_null()
	sm.current_wind = Wind.Kind.CALM
	weather._process(0.016)
	wind._process(0.016)
	var calm := wind._specks.emitting or wind._specks.visible or wind._clouds.visible
	sm.current_wind = Wind.Kind.STRONG_WIND
	weather._process(0.016)
	wind._process(0.016)
	var specks := wind._specks.emitting and wind._specks.visible
	var clouds := wind._clouds.visible
	var mask: Variant = wind._speck_process.get_shader_parameter("mask")
	assert_bool(calm).override_failure_message("a calm board still draws wind").is_false()
	assert_bool(specks).override_failure_message("a strong wind blew no specks").is_true()
	assert_bool(clouds).override_failure_message("a strong wind drew no cloud shadows").is_true()
	assert_object(mask).override_failure_message("the specks were handed no ground mask").is_not_null()
	assert_object(mask).override_failure_message("the specks read a second mask, not the weather's").is_same(weather.mask())


# Under any other weather the wind draws neither its specks nor its cloud shadows: rain, snow and fog
# already fill the air, and an overcast sky casts no shadows (dev, 2026-10-10). Asked of every weather
# the board can name, through both mirrors; the plants and the falls still take the wind.
func test_the_wind_draws_specks_and_clouds_only_under_a_clear_sky() -> void:
	var weather := _mirror()
	var wind: WindMirror = _scene._wind
	var sm = _manager()
	sm.current_wind = Wind.Kind.STRONG_WIND
	for kind: Weather.Kind in Weather.Kind.values():
		if kind == Weather.Kind.CLEAR:
			continue
		sm.current_weather = kind
		weather._process(0.016)
		wind._process(0.016)
		assert_bool(wind._specks.emitting or wind._specks.visible).override_failure_message(
				"the wind blew specks through %s" % Weather.name_of(kind)).is_false()
		assert_bool(wind._clouds.visible).override_failure_message(
				"%s's sky still casts the wind's cloud shadows" % Weather.name_of(kind)).is_false()
	sm.current_weather = Weather.Kind.CLEAR
	weather._process(0.016)
	wind._process(0.016)
	assert_bool(wind._specks.emitting and wind._specks.visible).override_failure_message(
			"a clear sky blew no specks").is_true()
	assert_bool(wind._clouds.visible).override_failure_message("a clear sky cast no cloud shadows").is_true()


# The wind's drawing sorts under every piece of markup, the shadows under the fog too, so a move tile is
# never shaded or crossed.
func test_the_wind_sorts_under_every_piece_of_markup() -> void:
	var wind: WindMirror = _scene._wind
	var lowest := BoardOverlays.GAS_FLOOR_SORT
	for layer: BoardOverlays.Layer in BoardOverlays.LAYERS:
		lowest = mini(lowest, int(BoardOverlays.LAYERS[layer]["sort"]) - 1)
	for priority: int in [wind._cloud_material.render_priority, wind._speck_draw.render_priority]:
		assert_int(priority).override_failure_message(
				"a wind draw sorts at %d, not under the lowest markup at %d" % [priority, lowest]).is_less(lowest)
	assert_int(wind._cloud_material.render_priority).is_less(BoardOverlays.FOG_RENDER_PRIORITY)


# A plant leans while the wind blows and stands on the engine's own material when it drops. Asked of a
# real plant on a real board, through battle3d's own wire. The Ford stands none, so this loads a board
# with grass and trees on it.
func test_a_plant_leans_while_the_wind_blows_and_stands_when_calm() -> void:
	_scene.game.scenario_manager.load_scenario(PLANTED)
	await await_idle_frame()
	await await_idle_frame()
	var board: BoardMirror = _scene._board_mirror
	var plant: Sprite3D = null
	for root: Node3D in board._props.values():
		for child in root.get_children():
			if child is Sprite3D and child.has_meta(BoardMirror.SWAY_META):
				plant = child
				break
		if plant != null:
			break
	assert_object(plant).override_failure_message("fixture: the board stands no plant").is_not_null()
	var sm = _manager()
	sm.current_wind = Wind.Kind.GALE
	board._process(0.016)
	var leaning := plant.material_override as ShaderMaterial
	var lean: float = leaning.get_shader_parameter("lean") if leaning != null else 0.0
	sm.current_wind = Wind.Kind.CALM
	board._process(0.016)
	var calm := plant.material_override
	assert_object(leaning).override_failure_message("a gale left the plant on its own material").is_not_null()
	assert_object(leaning.shader).is_same(BoardMirror.SWAY_SHADER)
	assert_float(lean).override_failure_message("the gale handed the plant no lean").is_greater(0.0)
	assert_object(calm).override_failure_message("a calm board left the plant on the sway material").is_null()


# The board's wind saves with it and comes back on load, the weather's way.
func test_the_board_wind_saves_with_the_board() -> void:
	var sm = _manager()
	sm.current_wind = Wind.Kind.GALE
	sm.current_wind_direction = Wind.Direction.NORTH_WEST
	var data: ScenarioData = sm.capture_scenario("wind round trip")
	sm.current_wind = Wind.Kind.CALM
	sm.current_wind_direction = Wind.Direction.EAST
	sm.apply_scenario(data)
	await await_idle_frame()
	assert_int(data.wind).is_equal(Wind.Kind.GALE)
	assert_int(data.wind_direction).is_equal(Wind.Direction.NORTH_WEST)
	assert_int(sm.current_wind).override_failure_message("the wind did not come back on load").is_equal(Wind.Kind.GALE)
	assert_int(sm.current_wind_direction).is_equal(Wind.Direction.NORTH_WEST)
