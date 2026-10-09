extends Node

# The render probe for the weather (#1260). The suite pins what WeatherMirror decides on the CPU --
# the mask, the box arithmetic, the puddle cells, the strike plans -- and none of what the GPU then
# does with it: a particles shader, a decal and a white-out are never read back, and the dummy
# renderer draws nothing. This loads a real mission into the real Battle3D and measures:
#
#   - that the RAIN draws at all (pixels that move against a clear control frame);
#   - that the GROUND changes under it with the drops switched off (the decals alone);
#   - that a STORM strike reaches the screen (the white-out) and draws its bolt;
#   - that each SNOW strength draws flakes, more of them the harder it snows (#1269).
#
#     godot --path . res://tools/weather_probe/weather_probe.tscn
#
# It needs a real window, prints one verdict line per check, and saves each frame to
# user://weather_probe/ for an eye check. It writes nothing under res://.

const MISSION := "res://Scenarios/missions/TheFord.tres"
const OUT_DIR := "user://weather_probe"

var _scene: Node3D
var _game
var _clock := 0.0


func _process(delta: float) -> void:
	_clock += delta


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	get_tree().root.size = Vector2i(1280, 720)
	_scene = (load("res://Scenes/Battle3D/Battle3D.tscn") as PackedScene).instantiate() as Node3D
	_scene.auto_play = false
	add_child(_scene)
	await _wait(0.5)
	_game = _scene.game
	_scene.load_mission(MISSION)
	await _wait(0.5)
	# The board, unobstructed: no lesson dialog over it, no title or pre-mission screen in front of it.
	Dialogic.end_timeline()
	_game.mission_controller.call("_close_mission_select")
	if _game.mission_controller.has_method("commit_deployment") and _game.mission_controller.get("_deploying"):
		_game.mission_controller.commit_deployment()
	await _wait(1.5)
	var failures := 0
	var clear := await _grab("clear")
	# The board moves on its own (water, flames, idle units), so the rain is measured against how much
	# two CLEAR frames the same time apart already differ.
	await _wait(2.0)
	var baseline := _diff(clear, await _grab("clear_later"))
	print("  baseline: %d px differ between two clear frames" % baseline)
	failures += await _rain(clear, baseline)
	failures += await _ground(clear)
	failures += await _storm()
	failures += await _snow(clear)
	_game.scenario_manager.current_weather = Weather.Kind.CLEAR
	print("WEATHER PROBE: %s" % ("OK" if failures == 0 else "%d CHECK(S) FAILED" % failures))
	get_tree().quit(1 if failures > 0 else 0)


func _rain(clear: Image, baseline: int) -> int:
	_game.scenario_manager.current_weather = Weather.Kind.HEAVY_RAIN
	await _wait(2.0)
	var rain := await _grab("heavy_rain")
	var moved := _diff(clear, rain)
	var mirror: WeatherMirror = _scene._weather
	print("  rain: %d px differ from the clear frame (baseline %d); a system of %d drops"
			% [moved, baseline, mirror._rain.amount])
	for kind: Weather.Kind in [Weather.Kind.LIGHT_RAIN, Weather.Kind.RAIN]:
		_game.scenario_manager.current_weather = kind
		await _wait(1.5)
		await _grab(Weather.name_of(kind).to_lower())
	return 0 if moved > baseline * 2 + 2000 else 1


# The decals alone: drops and rings switched off, so what is left differing is the ground.
func _ground(clear: Image) -> int:
	_game.scenario_manager.current_weather = Weather.Kind.HEAVY_RAIN
	var look := WeatherLook.for_kind(Weather.Kind.HEAVY_RAIN)
	var density := look.density
	var splashes := look.splashes
	look.density = 0.0
	look.splashes = false
	await _wait(1.6)
	var wet := await _grab("ground_only")
	var darker := 0
	for y in range(0, clear.get_height(), 2):
		for x in range(0, clear.get_width(), 2):
			if wet.get_pixel(x, y).get_luminance() < clear.get_pixel(x, y).get_luminance() - 0.03:
				darker += 1
	look.density = density
	look.splashes = splashes
	print("  ground: %d sampled px darker with only the decals on" % darker)
	return 0 if darker > 500 else 1


func _storm() -> int:
	_game.scenario_manager.current_weather = Weather.Kind.THUNDERSTORM
	await _wait(1.0)
	var mirror: WeatherMirror = _scene._weather
	mirror._next_strike = mirror._clock
	await _wait(0.03)
	var flash := mirror.flash_level()
	var lit: bool = _scene._whiteout != null and _scene._whiteout.visible
	var bolts := mirror._bolts.bolts_drawn
	await _grab("strike")
	await _wait(0.2)
	await _grab("strike_after")
	print("  storm: flash %.2f, white-out showing %s, %d bolt surface(s) drawn, side light %s"
			% [flash, lit, bolts, mirror._side.visible])
	return 0 if flash > 0.0 and lit and bolts > 0 else 1


# Flakes are near-white pixels the clear frame did not have; a blizzard must draw more than light snow.
func _snow(clear: Image) -> int:
	var counts := {}
	var mirror: WeatherMirror = _scene._weather
	for kind: Weather.Kind in [Weather.Kind.LIGHT_SNOW, Weather.Kind.SNOW, Weather.Kind.BLIZZARD]:
		_game.scenario_manager.current_weather = kind
		await _wait(3.0)
		var frame := await _grab(Weather.name_of(kind).to_lower())
		_save_zoom(frame, Weather.name_of(kind).to_lower() + "_zoom")
		var flakes := 0
		for y in range(0, clear.get_height(), 2):
			for x in range(0, clear.get_width(), 2):
				var now := frame.get_pixel(x, y)
				if now.get_luminance() > clear.get_pixel(x, y).get_luminance() + 0.15 and now.s < 0.25:
					flakes += 1
		counts[kind] = flakes
		var look := WeatherLook.for_kind(kind)
		var box: Dictionary = mirror._view_box(maxf(look.fall_speed, 0.5), Vector2(look.wind_x, look.wind_z),
				look.swirl_scale + look.flake_sway)
		var wanted := look.density * float(box["area"]) * mirror._snow.lifetime
		print("  %s: %d sampled px whitened; a system of %d flakes for %d wanted (box %.0f m2, fall %.1fs)"
				% [Weather.name_of(kind), flakes, mirror._snow.amount, int(wanted), box["area"], box["fall"]])
	var light: int = counts[Weather.Kind.LIGHT_SNOW]
	var blizzard: int = counts[Weather.Kind.BLIZZARD]
	return 0 if light > 20 and blizzard > light else 1


# The middle of the frame at 4x, for an eye check of pixel-sized things.
func _save_zoom(frame: Image, label: String) -> void:
	var w := frame.get_width() / 4
	var h := frame.get_height() / 4
	var crop := frame.get_region(Rect2i((frame.get_width() - w) / 2, (frame.get_height() - h) / 2, w, h))
	crop.resize(w * 4, h * 4, Image.INTERPOLATE_NEAREST)
	crop.save_png("%s/%s.png" % [OUT_DIR, label])


func _grab(label: String) -> Image:
	for i in 3:
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [OUT_DIR, label])
	print("  saved %s" % ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, label]))
	return image


func _diff(a: Image, b: Image) -> int:
	var count := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var d := a.get_pixel(x, y) - b.get_pixel(x, y)
			if maxf(maxf(absf(d.r), absf(d.g)), absf(d.b)) > 4.0 / 255.0:
				count += 1
	return count


func _wait(seconds: float) -> void:
	var until := _clock + seconds
	while _clock < until:
		await get_tree().process_frame
