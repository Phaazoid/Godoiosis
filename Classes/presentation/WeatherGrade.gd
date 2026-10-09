extends CanvasLayer
class_name WeatherGrade

# The weather's own grade (#1269): a full-screen rect on weather_grade.gdshader, on a canvas layer
# BELOW the 2D game's (0), so it reads the finished 3D frame -- after the board's own look -- and never
# the HUD, the cards or the white-out above. A WeatherMirror child, driven by it every frame.
#
# It writes nothing but its own material: no Environment property, no Look knob, so a board's look and
# a weather's grade can never fight (tests/presentation/test_weather_mirror.gd keeps it that way). A
# weather change EASES over the look's grade_fade rather than snapping, and the rect is hidden while
# the grade is identity, so a clear board pays for no full-screen pass.

const LAYER := -1
const SHADER := preload("res://Classes/presentation/weather_grade.gdshader")
# Where the eased values sit, close enough to their target to count as arrived.
const SETTLED := 0.002

var _rect: ColorRect
var _material: ShaderMaterial
# What is drawn now: saturation, brightness, tint (alpha = amount), veil, and the veil's colour.
var saturation := 1.0
var brightness := 1.0
var tint := Color(1.0, 1.0, 1.0, 0.0)
var veil := 0.0
var veil_color := Color(0.92, 0.94, 0.97)
var _drift := Vector2.ZERO


func _init() -> void:
	layer = LAYER
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rect.material = _material
	_rect.visible = false
	add_child(_rect)


# Ease toward `look`'s grade (identity when null) over its fade, and drift the veil along the wind.
func drive(look: WeatherLook, wind: Vector2, delta: float) -> void:
	var fade := look.grade_fade if look != null else 1.0
	var k := 1.0 if fade <= 0.0 else 1.0 - exp(-4.0 * delta / fade)
	saturation = lerpf(saturation, look.grade_saturation if look != null else 1.0, k)
	brightness = lerpf(brightness, look.grade_brightness if look != null else 1.0, k)
	tint = tint.lerp(look.grade_tint if look != null else Color(1.0, 1.0, 1.0, 0.0), k)
	veil = lerpf(veil, look.veil if look != null else 0.0, k)
	if look != null:
		veil_color = veil_color.lerp(look.veil_color, k)
		var across := -signf(wind.x) if absf(wind.x) > 0.001 else -1.0
		_drift += Vector2(across, 0.15) * look.veil_speed * delta * 2.5
	if shows():
		_material.set_shader_parameter("saturation", saturation)
		_material.set_shader_parameter("brightness", brightness)
		_material.set_shader_parameter("tint", tint)
		_material.set_shader_parameter("veil", veil)
		_material.set_shader_parameter("veil_color", veil_color)
		_material.set_shader_parameter("veil_offset", _drift)
	_rect.visible = shows()


# Whether anything is graded at all.
func shows() -> bool:
	return absf(saturation - 1.0) > SETTLED or absf(brightness - 1.0) > SETTLED or tint.a > SETTLED \
			or veil > SETTLED


func rect() -> ColorRect:
	return _rect
