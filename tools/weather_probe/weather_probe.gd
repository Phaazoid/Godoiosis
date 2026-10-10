extends Node

# The render probe for the weather (#1260). The suite pins what WeatherMirror decides on the CPU --
# the mask, the box arithmetic, the puddle cells, the strike plans -- and none of what the GPU then
# does with it: a particles shader, a decal and a white-out are never read back, and the dummy
# renderer draws nothing. This loads a real mission into the real Battle3D and measures:
#
#   - that the RAIN draws at all (pixels that move against a clear control frame);
#   - that the GROUND changes under it with the drops switched off (the decals alone);
#   - that a STORM strike reaches the screen (the white-out) and draws its bolt;
#   - that each SNOW strength draws flakes, more of them the harder it snows (#1269), and that its cold
#     grade greys the board while the HUD's pixels stay exactly as they were;
#   - that the blizzard's whiteout has no seams (#1278): drawn alone, no step between neighbours;
#   - that each FOG strength changes the board, leaves the HUD alone and puts nothing in the void well
#     past the board's edge (#1285: fog never hangs over nothing), and what it costs the GPU;
#   - that each WIND strength (#1286) changes a clear board on its own -- specks and cloud shadows --
#     more the harder it blows, leaves the HUD alone and the void past the edge untouched, and what the
#     cloud pass costs the GPU;
#   - that each AURORA strength (#1298) changes more of the board than the one below it, leaves the HUD
#     alone and, zoomed out with its grade and strikes held off, leaves the void past the edge untouched
#     (its curtains skip the sky and its motes die over the void), and what it costs the GPU.
#
#     godot --path . res://tools/weather_probe/weather_probe.tscn
#
# It needs a real window, prints one verdict line per check, and saves each frame to
# user://weather_probe/ for an eye check. It writes nothing under res://.

const MISSION := "res://Scenarios/missions/TheFord.tres"
# Snow is measured on grass: the Ford's pale stone hides a snow cover.
const SNOW_MISSION := "res://Scenarios/missions/Level_1.tres"
# Fog is measured on Terraces: it pools in the low field and the high terraces stand clear.
const FOG_MISSION := "res://Scenarios/missions/Terraces.tres"
# How far past the board's edge the void must be untouched, cells: a card is a little under three wide.
const FOG_CLEAR_MARGIN := 3.0
# A void pixel counts as touched past this much luminance: a card or the pass moves it far more.
const FOG_VOID_TOLERANCE := 0.02
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
	await _open(MISSION)
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
	failures += await _veil()
	failures += await _fog()
	failures += await _wind()
	failures += await _aurora()
	_game.scenario_manager.current_weather = Weather.Kind.CLEAR
	_game.scenario_manager.current_wind = Wind.Kind.CALM
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


# Flakes are near-white pixels the clear frame did not have; a blizzard must draw more than light snow,
# and every strength must whiten more than its flakes alone do (the cover).
func _snow(_ford_clear: Image) -> int:
	_game.scenario_manager.current_weather = Weather.Kind.CLEAR
	await _open(SNOW_MISSION)
	var clear := await _grab("snow_clear")
	var counts := {}
	var greyed := 0
	var hud_moved := 0
	var clear_sat := _saturation(clear)
	var mirror: WeatherMirror = _scene._weather
	for kind: Weather.Kind in [Weather.Kind.LIGHT_SNOW, Weather.Kind.SNOW, Weather.Kind.BLIZZARD]:
		_game.scenario_manager.current_weather = kind
		await _wait(3.0)
		var frame := await _grab(Weather.name_of(kind).to_lower())
		_save_zoom(frame, Weather.name_of(kind).to_lower() + "_zoom")
		_save_unit(frame, Weather.name_of(kind).to_lower() + "_unit")
		var flakes := 0
		for y in range(0, clear.get_height(), 2):
			for x in range(0, clear.get_width(), 2):
				var now := frame.get_pixel(x, y)
				if now.get_luminance() > clear.get_pixel(x, y).get_luminance() + 0.15 and now.s < 0.25:
					flakes += 1
		counts[kind] = flakes
		var sat := _saturation(frame)
		var moved := _hud_moved(clear, frame)
		hud_moved += moved
		if sat < clear_sat - 0.01:
			greyed += 1
		print("  %s: board saturation %.3f (clear %.3f), grade %s, veil %.2f, %d HUD px moved" % [
				Weather.name_of(kind), sat, clear_sat, mirror.grade().rect().visible, mirror.grade().veil, moved])
		var look := WeatherLook.for_kind(kind)
		var box: Dictionary = mirror.view_box(maxf(look.fall_speed, 0.5), mirror._wind(),
				look.swirl_scale + look.flake_sway)
		var wanted := look.density * float(box["area"]) * mirror._snow.lifetime
		print("  %s: %d sampled px whitened; a system of %d flakes for %d wanted (box %.0f m2, fall %.1fs)"
				% [Weather.name_of(kind), flakes, mirror._snow.amount, int(wanted), box["area"], box["fall"]])
	var light: int = counts[Weather.Kind.LIGHT_SNOW]
	var blizzard: int = counts[Weather.Kind.BLIZZARD]
	return 0 if light > 20 and blizzard > light and greyed == 3 and hud_moved == 0 else 1


# Each fog strength (#1285) changes the board against a clear frame and leaves the End Turn button's
# pixels as they were. Then, zoomed out with the grade held at identity, the void left of the board --
# past FOG_CLEAR_MARGIN cells -- must not change: fog never hangs over nothing. "Change" is past
# FOG_VOID_TOLERANCE in luminance, because the look's own volumetric fog dithers the background by a
# level from frame to frame (measured: one level, scattered, with no weather at all). A frame with no
# such void to look at fails rather than passing on nothing. GPU time is printed.
func _fog() -> int:
	_game.scenario_manager.current_weather = Weather.Kind.CLEAR
	await _open(FOG_MISSION)
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	await _wait(1.0)
	var clear := await _grab("fog_clear")
	var clear_gpu := await _gpu_ms(60)
	print("  fog: clear GPU %.2f ms" % clear_gpu)
	var failures := 0
	for kind: Weather.Kind in [Weather.Kind.MIST, Weather.Kind.FOG, Weather.Kind.THICK_FOG]:
		_game.scenario_manager.current_weather = kind
		await _wait(4.0)
		var name := Weather.name_of(kind).to_lower()
		var frame := await _grab(name)
		_save_zoom(frame, name + "_zoom")
		var gpu := await _gpu_ms(60)
		var changed := 0
		for y in range(0, clear.get_height(), 2):
			for x in range(0, clear.get_width(), 2):
				if absf(frame.get_pixel(x, y).get_luminance() - clear.get_pixel(x, y).get_luminance()) > 0.04:
					changed += 1
		var hud := _hud_moved(clear, frame)
		print("  %s: %d sampled px changed, %d HUD px moved; GPU %.2f ms (+%.2f)"
				% [Weather.name_of(kind), changed, hud, gpu, gpu - clear_gpu])
		if changed < 500 or hud > 0:
			failures += 1
	failures += await _fog_void()
	_game.scenario_manager.current_weather = Weather.Kind.CLEAR
	return 0 if failures == 0 else 1


# The wind (#1286), on grass under a clear sky: each strength against two calm frames the same time apart
# (the water and the idle units move on their own), more of the board moved the harder it blows, the HUD
# untouched, and then the void past the edge untouched by a gale.
func _wind() -> int:
	_game.scenario_manager.current_weather = Weather.Kind.CLEAR
	_game.scenario_manager.current_wind = Wind.Kind.CALM
	await _open(SNOW_MISSION)
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	await _wait(1.0)
	var calm := await _grab("wind_calm")
	var calm_gpu := await _gpu_ms(60)
	await _wait(4.0)
	var baseline := _lum_changed(calm, await _grab("wind_calm_later"))
	print("  wind: calm GPU %.2f ms, %d sampled px move on their own" % [calm_gpu, baseline])
	var failures := 0
	var counts := {}
	for kind: Wind.Kind in [Wind.Kind.BREEZE, Wind.Kind.STRONG_WIND, Wind.Kind.GALE]:
		_game.scenario_manager.current_wind = kind
		await _wait(4.0)
		var frame := await _grab("wind_" + Wind.name_of(kind).to_lower())
		var gpu := await _gpu_ms(60)
		var changed := _lum_changed(calm, frame)
		var hud := _hud_moved(calm, frame)
		counts[kind] = changed
		print("  %s: %d sampled px changed (calm moves %d), %d HUD px moved; GPU %.2f ms (%+.2f)"
				% [Wind.name_of(kind), changed, baseline, hud, gpu, gpu - calm_gpu])
		if changed < baseline + 300 or hud > 0:
			failures += 1
	if int(counts[Wind.Kind.GALE]) <= int(counts[Wind.Kind.BREEZE]):
		print("  wind: FAILED -- a gale moves no more of the board than a breeze")
		failures += 1
	failures += await _wind_void()
	_game.scenario_manager.current_wind = Wind.Kind.CALM
	return 0 if failures == 0 else 1


# On the fog's board, zoomed out as its void check is (Level_1 fills the frame even zoomed out): a gale's
# specks die over the void and its shadows skip the sky, so the void past the edge is as calm left it.
func _wind_void() -> int:
	await _open(FOG_MISSION)
	var rig: CameraRig3D = _scene._rig
	var opening := rig._target_distance
	_game.scenario_manager.current_wind = Wind.Kind.CALM
	rig.set_zoom(opening * 2.0)
	await _wait(2.0)
	var calm := await _grab("wind_calm_wide")
	var void_rect := _void_left_of_board(FOG_CLEAR_MARGIN)
	var failures := 0
	if not void_rect.has_area():
		print("  wind void: FAILED -- no void left of the board in the wide frame to check")
		failures += 1
	else:
		_game.scenario_manager.current_wind = Wind.Kind.GALE
		await _wait(4.0)
		var frame := await _grab("wind_gale_wide")
		var in_void := 0
		var checked := 0
		for y in range(int(void_rect.position.y), int(void_rect.end.y), 2):
			for x in range(int(void_rect.position.x), int(void_rect.end.x), 2):
				checked += 1
				if absf(frame.get_pixel(x, y).get_luminance() - calm.get_pixel(x, y).get_luminance()) > FOG_VOID_TOLERANCE:
					in_void += 1
		print("  GALE void: %d of %d sampled px past the board's edge touched" % [in_void, checked])
		if in_void > 0:
			failures += 1
	_game.scenario_manager.current_wind = Wind.Kind.CALM
	rig.set_zoom(opening)
	return failures


const AURORAS: Array[Weather.Kind] = [Weather.Kind.FAINT_AURORA, Weather.Kind.AURORA, Weather.Kind.AETHERIC_STORM]


# The aurora (#1298), on the fog's board: each strength against the clear frame, more of the board changed
# the stronger it is, the HUD untouched; then the void past the edge, zoomed out, untouched by each.
func _aurora() -> int:
	_game.scenario_manager.current_weather = Weather.Kind.CLEAR
	_game.scenario_manager.current_wind = Wind.Kind.CALM
	await _open(FOG_MISSION)
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	await _wait(1.0)
	var clear := await _grab("aurora_clear")
	var clear_gpu := await _gpu_ms(60)
	print("  aurora: clear GPU %.2f ms" % clear_gpu)
	var failures := 0
	var last := -1
	for kind: Weather.Kind in AURORAS:
		_game.scenario_manager.current_weather = kind
		await _wait(4.0)
		var name := Weather.name_of(kind).to_lower()
		var frame := await _grab(name)
		_save_zoom(frame, name + "_zoom")
		var gpu := await _gpu_ms(60)
		var changed := _lum_changed(clear, frame)
		var hud := _hud_moved(clear, frame)
		print("  %s: %d sampled px changed, %d HUD px moved; GPU %.2f ms (%+.2f)"
				% [Weather.name_of(kind), changed, hud, gpu, gpu - clear_gpu])
		if changed < 500 or hud > 0 or changed <= last:
			failures += 1
		last = changed
	failures += await _aurora_void()
	_game.scenario_manager.current_weather = Weather.Kind.CLEAR
	return 0 if failures == 0 else 1


# Zoomed out as the fog's void check is, each aurora with its grade at identity and its strikes off (a
# bolt lands past the edge on purpose): what is left in the void would be the curtains or the motes.
func _aurora_void() -> int:
	var rig: CameraRig3D = _scene._rig
	var opening := rig._target_distance
	_game.scenario_manager.current_weather = Weather.Kind.CLEAR
	rig.set_zoom(opening * 2.0)
	await _wait(2.0)
	var clear := await _grab("aurora_clear_wide")
	var void_rect := _void_left_of_board(FOG_CLEAR_MARGIN)
	var failures := 0
	if not void_rect.has_area():
		print("  aurora void: FAILED -- no void left of the board in the wide frame to check")
		failures += 1
	for kind: Weather.Kind in ([] as Array[Weather.Kind] if failures > 0 else AURORAS):
		var look := WeatherLook.for_kind(kind)
		var held := [look.grade_saturation, look.grade_brightness, look.grade_tint, look.lightning]
		look.grade_saturation = 1.0
		look.grade_brightness = 1.0
		look.grade_tint = Color(1.0, 1.0, 1.0, 0.0)
		look.lightning = false
		_game.scenario_manager.current_weather = kind
		await _wait(4.0)
		var frame := await _grab(Weather.name_of(kind).to_lower() + "_wide")
		look.grade_saturation = held[0]
		look.grade_brightness = held[1]
		look.grade_tint = held[2]
		look.lightning = held[3]
		var in_void := 0
		var checked := 0
		for y in range(int(void_rect.position.y), int(void_rect.end.y), 2):
			for x in range(int(void_rect.position.x), int(void_rect.end.x), 2):
				checked += 1
				if absf(frame.get_pixel(x, y).get_luminance() - clear.get_pixel(x, y).get_luminance()) > FOG_VOID_TOLERANCE:
					in_void += 1
		print("  %s void: %d of %d sampled px past the board's edge touched" % [Weather.name_of(kind), in_void, checked])
		if in_void > 0:
			failures += 1
	_game.scenario_manager.current_weather = Weather.Kind.CLEAR
	rig.set_zoom(opening)
	return failures


# Sampled pixels whose luminance moved past the fog's own threshold.
func _lum_changed(a: Image, b: Image) -> int:
	var changed := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			if absf(b.get_pixel(x, y).get_luminance() - a.get_pixel(x, y).get_luminance()) > 0.04:
				changed += 1
	return changed


# Zoomed out to twice the opening distance so there is void beside the board to look at.
func _fog_void() -> int:
	var rig: CameraRig3D = _scene._rig
	var opening := rig._target_distance
	_game.scenario_manager.current_weather = Weather.Kind.CLEAR
	rig.set_zoom(opening * 2.0)
	await _wait(2.0)
	var clear := await _grab("fog_clear_wide")
	var void_rect := _void_left_of_board(FOG_CLEAR_MARGIN)
	var failures := 0
	if not void_rect.has_area():
		print("  fog void: FAILED -- no void left of the board in the wide frame to check")
		failures += 1
	for kind: Weather.Kind in ([] if failures > 0 else [Weather.Kind.MIST, Weather.Kind.FOG, Weather.Kind.THICK_FOG]):
		var look := WeatherLook.for_kind(kind)
		var grade := [look.grade_saturation, look.grade_brightness, look.grade_tint, look.grade_fade]
		look.grade_saturation = 1.0
		look.grade_brightness = 1.0
		look.grade_tint = Color(1.0, 1.0, 1.0, 0.0)
		look.grade_fade = 0.0
		_game.scenario_manager.current_weather = kind
		await _wait(4.0)
		var frame := await _grab(Weather.name_of(kind).to_lower() + "_wide")
		look.grade_saturation = grade[0]
		look.grade_brightness = grade[1]
		look.grade_tint = grade[2]
		look.grade_fade = grade[3]
		var in_void := 0
		var checked := 0
		for y in range(int(void_rect.position.y), int(void_rect.end.y), 2):
			for x in range(int(void_rect.position.x), int(void_rect.end.x), 2):
				checked += 1
				if absf(frame.get_pixel(x, y).get_luminance() - clear.get_pixel(x, y).get_luminance()) > FOG_VOID_TOLERANCE:
					in_void += 1
		print("  %s void: %d of %d sampled px past the board's edge touched" % [Weather.name_of(kind), in_void, checked])
		if in_void > 0:
			failures += 1
	_game.scenario_manager.current_weather = Weather.Kind.CLEAR
	rig.set_zoom(opening)
	return failures


# The screen columns left of the board grown by `margin` cells, under the checkout label and above the
# HUD corner: void a fog must never reach. Empty when the board fills the frame's left side.
func _void_left_of_board(margin: float) -> Rect2:
	var camera := get_viewport().get_camera_3d()
	var board: AABB = _scene._board_volume().grow(margin)
	var left := INF
	for i in 8:
		var corner := board.get_endpoint(i)
		if not camera.is_position_behind(corner):
			left = minf(left, camera.unproject_position(corner).x)
	var width := clampf(left, 0.0, float(get_viewport().get_visible_rect().size.x))
	return Rect2(0.0, 40.0, width, get_viewport().get_visible_rect().size.y - 140.0) if width > 8.0 else Rect2()


# The mean GPU time of the next `frames` frames, ms.
func _gpu_ms(frames: int) -> float:
	var total := 0.0
	var rid := get_viewport().get_viewport_rid()
	for i in frames:
		await RenderingServer.frame_post_draw
		total += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	return total / frames


# Mean HSV saturation over the frame, the End Turn corner left out.
func _saturation(frame: Image) -> float:
	var hud := _hud_rect()
	var total := 0.0
	var count := 0
	for y in range(0, frame.get_height(), 4):
		for x in range(0, frame.get_width(), 4):
			if hud.has_point(Vector2(x, y)):
				continue
			total += frame.get_pixel(x, y).s
			count += 1
	return total / maxf(count, 1)


# How many of the End Turn button's pixels differ from the clear frame: the grade must leave the HUD.
func _hud_moved(clear: Image, frame: Image) -> int:
	var hud := _hud_rect().grow(-2)
	var moved := 0
	for y in range(int(hud.position.y), int(hud.end.y)):
		for x in range(int(hud.position.x), int(hud.end.x)):
			if not clear.get_pixel(x, y).is_equal_approx(frame.get_pixel(x, y)):
				moved += 1
	return moved


# The End Turn button itself -- its holder is a full-rect Control, so the rect is its Button child's.
func _hud_rect() -> Rect2:
	var holder: Control = _game.end_turn_button
	var button := holder.get_node_or_null("Button") as Control if holder != null else null
	if button == null or not button.is_visible_in_tree():
		return Rect2()
	return button.get_global_rect()


# The middle of the frame at 4x, for an eye check of pixel-sized things.
func _save_zoom(frame: Image, label: String) -> void:
	var w := frame.get_width() / 4
	var h := frame.get_height() / 4
	var crop := frame.get_region(Rect2i((frame.get_width() - w) / 2, (frame.get_height() - h) / 2, w, h))
	crop.resize(w * 4, h * 4, Image.INTERPOLATE_NEAREST)
	crop.save_png("%s/%s.png" % [OUT_DIR, label])


# The board, unobstructed: no lesson dialog over it, no title or pre-mission screen in front of it.
func _open(mission: String) -> void:
	_scene.load_mission(mission)
	await _wait(0.5)
	Dialogic.end_timeline()
	_game.mission_controller.call("_close_mission_select")
	if _game.mission_controller.has_method("commit_deployment") and _game.mission_controller.get("_deploying"):
		_game.mission_controller.commit_deployment()
	await _wait(1.5)


# The first unit's sprite at 6x, for an eye check of its cap and breath.
func _save_unit(frame: Image, label: String) -> void:
	var units: UnitMirror = _scene.get_node("UnitMirror")
	var camera := get_viewport().get_camera_3d()
	for child in _game.units_root.get_children():
		var unit := child as Unit
		var sprite := units.sprite_for(unit) if unit != null else null
		if sprite == null or not sprite.visible:
			continue
		var at := camera.unproject_position(sprite.global_position + Vector3.UP * 0.5)
		var box := Rect2i(Vector2i(at) - Vector2i(40, 40), Vector2i(80, 80)).intersection(
				Rect2i(Vector2i.ZERO, frame.get_size()))
		if box.size.x < 8 or box.size.y < 8:
			continue
		var crop := frame.get_region(box)
		crop.resize(box.size.x * 6, box.size.y * 6, Image.INTERPOLATE_NEAREST)
		crop.save_png("%s/%s.png" % [OUT_DIR, label])
		return


# The whiteout alone (#1278): drawn full strength over flat grey in a viewport of its own, its
# smooth noise moves a channel only a few levels from one pixel to the next. A seam -- two cells
# disagreeing about a shared corner -- is a jump far past that.
const VEIL_SEAM := 24.0

func _veil() -> int:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var back := CanvasLayer.new()
	back.layer = -2
	var grey := ColorRect.new()
	grey.color = Color(0.4, 0.4, 0.4)
	grey.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.add_child(grey)
	viewport.add_child(back)
	var grade := WeatherGrade.new()
	viewport.add_child(grade)
	var look := WeatherLook.new()
	look.veil = 1.0
	look.veil_color = Color(1.0, 1.0, 1.0)
	look.grade_fade = 0.0
	grade.drive(look, Vector2(1.0, 0.0), 1.0)
	for i in 3:
		await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.save_png("%s/veil_alone.png" % OUT_DIR)
	var worst := 0.0
	for y in range(0, image.get_height() - 1):
		for x in range(0, image.get_width() - 1):
			var here := image.get_pixel(x, y).r * 255.0
			worst = maxf(worst, absf(image.get_pixel(x + 1, y).r * 255.0 - here))
			worst = maxf(worst, absf(image.get_pixel(x, y + 1).r * 255.0 - here))
	viewport.queue_free()
	print("  veil: the largest step between neighbouring pixels is %.0f levels (a seam is past %.0f)"
			% [worst, VEIL_SEAM])
	return 0 if worst <= VEIL_SEAM else 1


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
