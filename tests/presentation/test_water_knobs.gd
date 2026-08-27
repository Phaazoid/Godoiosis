# The water knobs' WIRE (#552): does moving one actually reach the surface?
#
# The tuning values are GLOBAL shader uniforms rather than parameters on the meshlib's material,
# because writing to that material would mutate a generated artifact at runtime. The cost of that
# choice is a hand-written push per knob, and a knob nobody pushed is the born-dead slider #264
# shipped and #380 named -- it moves, it saves, and nothing on the board changes. Neither end is
# visible from the other: the @export and the uniform are in different files and different
# languages, and a mismatched name is silent, since GLSL reads an unset global as zero.
#
# WHERE THE LINE IS DRAWN, and it is drawn by the engine rather than by preference. Measured under
# --headless: the globals REGISTER (RenderingServer.global_shader_parameter_get_list returns all
# nine) but the dummy renderer stores no values, so global_shader_parameter_get answers null
# whatever anyone sets. So the readback cannot be the assertion. What these cases pin instead is
# every hop that can DRIFT -- nine setters, nine names, nine registrations -- by overriding the one
# funnel they all pass through; the funnel's own single line into RenderingServer is the one hop no
# headless test can watch, and it is one line with no name in it to get wrong.
extends GdUnitTestSuite


# Records what BoardMirror pushes instead of letting it reach a renderer that is not listening.
class SpyMirror extends BoardMirror:
	var pushed: Dictionary[String, float] = {}

	func _push_water(uniform: StringName, value: float) -> void:
		pushed[String(uniform)] = value


var _mirror: SpyMirror


func before_test() -> void:
	_mirror = SpyMirror.new()


func after_test() -> void:
	if _mirror.is_inside_tree():
		get_tree().root.remove_child(_mirror)
	_mirror.free()
	await await_idle_frame()


# The knob table is the authority on which knobs exist, so this reads its Water rows rather than
# keeping a second list here to fall out of step with.
func _water_props() -> PackedStringArray:
	var out := PackedStringArray()
	for knob: Dictionary in GameKnobs.KNOBS:
		if knob["group"] == "Water" and knob["node"] == "BoardMirror":
			out.append(knob["prop"])
	return out


func test_every_water_knob_reaches_a_uniform_of_its_own_name() -> void:
	var props := _water_props()
	assert_int(props.size()).override_failure_message(
			"no Water knobs declared; the case is vacuous").is_greater(0)
	# A DISTINCT value each, well away from any default, so a knob wired to the wrong uniform shows
	# up as the wrong number rather than agreeing with its neighbour by coincidence.
	var sent: Dictionary[String, float] = {}
	for i in props.size():
		var value := 0.131 + float(i) * 0.017
		sent[props[i]] = value
		_mirror.pushed.clear()
		_mirror.set(props[i], value)
		assert_array(_mirror.pushed.keys()).override_failure_message(
				"setting BoardMirror.%s pushed %s -- a knob writes ITS OWN uniform and nothing " \
				% [props[i], _mirror.pushed.keys()] + "else").contains_exactly([props[i]])
		# A gdUnit assertion does not halt, so a wrong-name push has to be stepped over or the
		# clean failure above arrives wearing a script error from the lookup below.
		if not _mirror.pushed.has(props[i]):
			continue
		assert_float(_mirror.pushed[props[i]]).override_failure_message(
				"BoardMirror.%s pushed a value it was not given" % props[i]) \
				.is_equal_approx(value, 0.0001)
	# And the property kept what it was handed -- a setter that pushes but forgets to store leaves
	# the panel snapping back to the old number on its next refresh.
	for prop: String in sent:
		var held: float = _mirror.get(prop)
		assert_float(held).override_failure_message(
				"BoardMirror.%s pushed its value and did not keep it" % prop) \
				.is_equal_approx(sent[prop], 0.0001)


# _ready pushes the lot, and it has to: until something writes them the board wears project.godot's
# saved values, so an @export default edited in source would be ignored until someone happened to
# touch that slider. This is the case that catches a knob left out of _push_all_water.
func test_entering_the_tree_pushes_every_declared_default() -> void:
	_mirror.pushed.clear()
	get_tree().root.add_child(_mirror)
	await await_idle_frame()
	for prop in _water_props():
		var declared: float = _mirror.get(prop)
		assert_bool(_mirror.pushed.has(prop)).override_failure_message(
				"_ready pushed no uniform '%s' -- the board would wear project.godot's saved " \
				% prop + "value until someone moved that slider").is_true()
		# A gdUnit assertion does not halt, so the missing key has to be stepped over or the clean
		# failure above arrives wearing a script error from the lookup below.
		if not _mirror.pushed.has(prop):
			continue
		assert_float(_mirror.pushed[prop]).override_failure_message(
				"_ready pushed '%s' as something other than its own declared default" % prop) \
				.is_equal_approx(declared, 0.0001)


# The third leg, and the only one the RenderingServer will still answer headless: a global the
# shader names must actually be REGISTERED, or the shader refuses to compile at first render --
# which is a failure no test asserting on materials would see.
func test_every_water_uniform_is_registered_with_the_renderer() -> void:
	var registered := RenderingServer.global_shader_parameter_get_list()
	for prop in _water_props():
		assert_bool(registered.has(StringName(prop))).override_failure_message(
				"'%s' is not a registered global shader parameter -- project.godot's " % prop \
				+ "[shader_globals] and the knob table disagree").is_true()
