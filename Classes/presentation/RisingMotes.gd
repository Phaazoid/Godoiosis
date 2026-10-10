extends Node3D
class_name RisingMotes

# Motes rising off the board: an aurora's (#1298) and an ashfall's embers (#1302), one of these each.
# One particle system on aurora_mote.gdshader, drawn by aurora_mote_draw.gdshader as dots or streaks,
# born anywhere over the board on the weather's ground mask and drifting with the wind. What colour
# they take, and when they rise, is the holder's.
#
# Born over the whole BOARD, never the view: setting a system's amount restarts it, so an amount sized
# off the camera re-dealt every mote on each zoom (#1301, the fog cards' #1289 lesson). The board is
# the box, so the count moves only when the board or a mote dial does.

const MAX_MOTES := 20000
# A mote's sideways wander, as a share of its rise: a dot drifts, a streak rises nearly straight.
const DOT_WANDER := 0.3
const STREAK_WANDER := 0.07
# The share of the board's wind a mote drifts with.
const MOTE_WIND := 0.5

var system: GPUParticles3D
var process: ShaderMaterial
var draw: ShaderMaterial


func _ready() -> void:
	process = WeatherMirror.process_material("res://Classes/presentation/aurora_mote.gdshader")
	draw = WeatherMirror.draw_material("res://Classes/presentation/aurora_mote_draw.gdshader")
	draw.render_priority = BoardOverlays.MOTE_RENDER_PRIORITY
	system = WeatherMirror.particles(self, process, draw, PlaneMesh.FACE_Z)


# How they are drawn: `tint`'s alpha fades them, and the look picks their shape and size.
func style(look: WeatherLook, tint: Color) -> void:
	draw.set_shader_parameter("tint", tint)
	draw.set_shader_parameter("texel", maxf(look.mote_size, 0.01) / UnitSprite3D.texels_per_unit)
	draw.set_shader_parameter("shape", 1.0 if look.mote_shape == WeatherLook.MoteShape.STREAKS else 0.0)


# Where and how fast they rise: over the weather's board rect, at the look's rate, rise, life and
# height, drifting with a share of the board's wind.
func place(look: WeatherLook, weather: WeatherMirror) -> void:
	var rect := weather.board_rect()
	if not rect.has_area():
		return
	var streaks := look.mote_shape == WeatherLook.MoteShape.STREAKS
	var life := maxf(look.mote_life, 0.2)
	var wind := weather.board_wind() * MOTE_WIND
	var lo := Vector2(rect.position) * BoardSpace.CELL_SIZE
	var hi := Vector2(rect.end) * BoardSpace.CELL_SIZE
	process.set_shader_parameter("box_min", Vector3(lo.x, 0.0, lo.y))
	process.set_shader_parameter("box_max", Vector3(hi.x, 0.0, hi.y))
	process.set_shader_parameter("rise", look.mote_rise)
	process.set_shader_parameter("wander", STREAK_WANDER if streaks else DOT_WANDER)
	process.set_shader_parameter("wind", wind)
	process.set_shader_parameter("height", look.mote_height)
	WeatherMirror.size_emitter(system, process, look.mote_rate * (hi.x - lo.x) * (hi.y - lo.y), life, MAX_MOTES)
