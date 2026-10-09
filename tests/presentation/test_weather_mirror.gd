# The weather's drawing (#1260), at the seams a headless run CAN see. Whether the rain looks right is
# the dev's eye and tools/weather_probe's pixels; what is pinned here is that each channel is WIRED:
#
#   - the cull box reaches every emitter (#656 shipped a particle invisible for want of exactly this);
#   - a look draws only what it drops: snow turns rain off, and rain snow (#1269);
#   - a storm's flash reaches the screen through battle3d's white-out on an ordinary frame;
#   - a clear board draws nothing, and the board's weather is what the mirror draws;
#   - the box arithmetic carries the authored births whatever the amount;
#   - the sky glow can never fight a Look preset, because no Look knob names what it writes.
extends GdUnitTestSuite

const SCENE: PackedScene = preload("res://Scenes/Battle3D/Battle3D.tscn")
const MISSION := "res://Scenarios/missions/TheFord.tres"

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
		get_tree().root.remove_child(_scene)
		_scene.free()


func after_test() -> void:
	_scene.game.scenario_manager.current_weather = Weather.Kind.CLEAR
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
			or mirror._puddles.visible or mirror._splash.visible or mirror._snow.visible).override_failure_message(
			"a clear board still draws weather").is_false()


# Every weather shader PARSES, and declares each parameter the mirror sets on it. A headless run draws
# nothing, so a shader that fails to compile is otherwise only a line in the log (#1269 shipped one
# to its first run), and a parameter set on a uniform that does not exist is dropped in silence.
func test_every_weather_shader_parses_and_declares_what_the_mirror_sets() -> void:
	var mirror := _mirror()
	var mask := ["mask", "mask_origin", "cell_size", "box_min", "box_max", "floor_y", "keep"]
	var wanted := {
		mirror._rain_process: mask + ["velocity"],
		mirror._rain_draw: ["streak", "size", "tint"],
		mirror._splash_process: mask,
		mirror._splash_draw: ["strip", "tint", "frames"],
		mirror._snow_process: mask + ["velocity", "sway", "swirl", "swirl_scale", "settle", "big", "lift"],
		mirror._snow_draw: ["flakes", "size", "tint"],
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
