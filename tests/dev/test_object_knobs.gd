# The Objects tab's save path (#272 slice 1). Two halves, and they fail in very different ways.
#
# The MECHANISM half is a pure string transform, so it is tested as one -- no file, no host. The bug
# worth catching there is not a wrong write, it is a write that does not happen: a property the
# rewriter cannot find must come back as "" so the caller reports a failure, never as the source
# unchanged, which a caller would happily save and call success.
#
# The LAW half pins the two claims the whole feature rests on, both measured rather than assumed:
# every ObjectKnobs property really is declared as an @export default in its own script, and
# Battle3D.tscn overrides none of them. If either stops being true, Save writes a line nobody reads
# and the panel says it worked -- exactly the silent failure the mechanism half is shaped to avoid,
# arriving by the other door.
#
# The scene is read as TEXT rather than instantiated: which script a node carries and whether it
# carries an override are both questions the .tscn answers directly, and doing it this way keeps
# these cases in tests/dev rather than dragging in a live 3D scene for a string check. That is a
# deliberate second statement of "which file owns this knob" -- the point is for it to disagree out
# loud if the panel's own derivation ever drifts.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"

const PLAIN := """extends Node3D

@export var block_height_scale := 1.0
@export var other := 2.0
"""

const WITH_SETTER := """extends Node3D

@export var cover_scale := 0.5: set = _set_cover_scale
"""

const TYPED := """extends Node3D

@export var cover_scale: float = 0.5
"""

const VECTOR := """extends Node3D

@export var flame_size := Vector2(0.5, 0.7): set = _set_flame_size
"""


# --- The rewriter ------------------------------------------------------------------------

func test_a_plain_export_default_is_rewritten() -> void:
	var out := ObjectKnobs.rewrite_export_default(PLAIN, "block_height_scale", "0.62")
	assert_str(out).contains("@export var block_height_scale := 0.62")
	# The neighbouring declaration is untouched: a rewrite edits ONE line, not the block around it.
	assert_str(out).contains("@export var other := 2.0")


# Two of the three knobs own a setter, and the setter is what makes them live knobs at all -- a
# rewrite that dropped the suffix would leave a slider that moves nothing on the board.
func test_a_setter_suffix_survives_the_rewrite() -> void:
	var out := ObjectKnobs.rewrite_export_default(WITH_SETTER, "cover_scale", "0.62")
	assert_str(out).is_equal("""extends Node3D

@export var cover_scale := 0.62: set = _set_cover_scale
""")


func test_a_typed_export_default_is_rewritten() -> void:
	var out := ObjectKnobs.rewrite_export_default(TYPED, "cover_scale", "0.62")
	assert_str(out).contains("@export var cover_scale: float = 0.62")


# A multi-argument literal must not be mistaken for the start of the setter suffix.
func test_a_vector_literal_is_rewritten_whole() -> void:
	var out := ObjectKnobs.rewrite_export_default(VECTOR, "flame_size", "Vector2(0.4, 0.9)")
	assert_str(out).is_equal("""extends Node3D

@export var flame_size := Vector2(0.4, 0.9): set = _set_flame_size
""")


# THE case. Returning the source unchanged would be indistinguishable from a successful no-change
# save, so "not found" has to be representable as something a caller cannot mistake for success.
func test_an_unknown_property_returns_empty_rather_than_the_source() -> void:
	var out := ObjectKnobs.rewrite_export_default(PLAIN, "renamed_since", "0.62")
	assert_str(out).override_failure_message(
		"a property the rewriter cannot find must return \"\", or a no-op write reads as a save").is_empty()


# A component path (flame_size:x) has no declaration line of its own -- "x = 0.4" is not a thing a
# script can say. Refused loudly rather than half-written.
func test_a_component_path_is_refused() -> void:
	assert_str(ObjectKnobs.rewrite_export_default(VECTOR, "flame_size:x", "0.4")).is_empty()


# --- The laws ----------------------------------------------------------------------------

func test_every_object_knob_is_declared_in_the_script_its_node_carries() -> void:
	var scene := _scene_text()
	for knob: Dictionary in ObjectKnobs.KNOBS:
		var path := _script_of_node(scene, knob["node"])
		assert_str(path).override_failure_message(
			"no script on node '%s' in Battle3D.tscn -- '%s' has nowhere to save to" % [knob["node"], knob["label"]]).is_not_empty()
		var source := _read(path)
		var rewritten := ObjectKnobs.rewrite_export_default(source, knob["prop"], "1.0")
		assert_str(rewritten).override_failure_message(
			"'%s' names %s:%s, but %s declares no @export default for it -- Save would write nothing and report success"
				% [knob["label"], knob["node"], knob["prop"], path]).is_not_empty()
		# And the line it produced is a line GDScript would accept. Finding the declaration is not
		# the same as writing it back correctly, and the real file carries a comment block above it
		# and a setter after it -- neither of which the hand-written fixtures above prove.
		var line := _declaration(rewritten, knob["prop"])
		assert_str(line).override_failure_message(
			"the rewrite of %s left no declaration behind" % knob["prop"]).is_not_empty()
		assert_bool(line.contains(":= 1.0") or line.contains("= 1.0")).override_failure_message(
			"rewriting %s produced '%s', which does not carry the value asked for" % [knob["prop"], line]).is_true()


# The measured assumption the whole slice rests on. An override authored in the scene WINS over the
# script default, so the moment one exists Save writes a line the game never reads -- and the only
# symptom would be the dev tuning the same value twice.
func test_the_scene_overrides_no_object_knob_property() -> void:
	var scene := _scene_text()
	for knob: Dictionary in ObjectKnobs.KNOBS:
		var section := _node_section(scene, knob["node"])
		assert_bool(section.is_empty()).override_failure_message(
			"Battle3D.tscn has no node '%s'" % knob["node"]).is_false()
		var override := RegEx.create_from_string("(?m)^%s[ \\t]*=" % knob["prop"])
		assert_object(override.search(section)).override_failure_message(
			"Battle3D.tscn overrides %s:%s -- the script default ObjectKnobs writes is no longer what the game reads"
				% [knob["node"], knob["prop"]]).is_null()


# --- Reading the scene as text -----------------------------------------------------------

func _scene_text() -> String:
	var text := _read(SCENE_PATH)
	assert_str(text).override_failure_message(
		"could not read %s -- every law below would pass vacuously" % SCENE_PATH).is_not_empty()
	return text


# The single @export line declaring a property, as it now stands.
func _declaration(source: String, prop: String) -> String:
	var re := RegEx.create_from_string("(?m)^@export[ \\t]+var[ \\t]+%s\\b.*$" % prop)
	var found := re.search(source)
	return "" if found == null else found.get_string(0)


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


# The lines belonging to one [node ...] block, up to the next one.
func _node_section(scene: String, node_name: String) -> String:
	var start := scene.find("[node name=\"%s\"" % node_name)
	if start < 0:
		return ""
	var next := scene.find("\n[", start + 1)
	return scene.substr(start, -1 if next < 0 else next - start)


# The path behind a node's script = ExtResource("id"), resolved through the header's ext_resource
# lines. "" when the node has no script.
func _script_of_node(scene: String, node_name: String) -> String:
	var section := _node_section(scene, node_name)
	var script_ref := RegEx.create_from_string("script[ \\t]*=[ \\t]*ExtResource\\(\"([^\"]+)\"\\)")
	var found := script_ref.search(section)
	if found == null:
		return ""
	var resource := RegEx.create_from_string(
		"\\[ext_resource[^\\]]*path=\"([^\"]+)\"[^\\]]*id=\"%s\"\\]" % found.get_string(1))
	var line := resource.search(scene)
	return "" if line == null else line.get_string(1)
