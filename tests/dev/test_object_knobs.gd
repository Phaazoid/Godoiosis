# The Objects tab's save path (#272 slice 1) -- what is left of it here, which is the half that is
# about THIS TABLE. The rewriter itself moved to KnobSource when #373 gave a second table the same
# Save, and its cases went with it (tests/dev/test_knob_source.gd).
#
# These pin the two claims the whole slice rests on, both measured rather than assumed:
# every ObjectKnobs property really is declared as an @export default in its own script, and
# Battle3D.tscn overrides none of them. If either stops being true, Save writes a line nobody reads
# and the panel says it worked -- exactly the silent failure the rewriter is shaped to avoid,
# arriving by the other door.
#
# The scene is read as TEXT rather than instantiated: which script a node carries and whether it
# carries an override are both questions the .tscn answers directly, and doing it this way keeps
# these cases in tests/dev rather than dragging in a live 3D scene for a string check. That is a
# deliberate second statement of "which file owns this knob" -- the point is for it to disagree out
# loud if the panel's own derivation ever drifts.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"

# --- The laws ----------------------------------------------------------------------------

func test_every_object_knob_is_declared_in_the_script_its_node_carries() -> void:
	var scene := _scene_text()
	for knob: Dictionary in ObjectKnobs.KNOBS:
		var path := _script_of_node(scene, knob["node"])
		assert_str(path).override_failure_message(
			"no script on node '%s' in Battle3D.tscn -- '%s' has nowhere to save to" % [knob["node"], knob["label"]]).is_not_empty()
		# The DECLARATION prop, which is what Save writes -- a component knob (flame_size:x) tunes
		# one axis of a property declared whole, and asking about the component here would red on a
		# table that is perfectly correct.
		var prop := KnobSource.declaration_prop(knob)
		var source := _read(path)
		var rewritten := KnobSource.rewrite_declaration_default(source, prop, "1.0")
		assert_str(rewritten).override_failure_message(
			"'%s' names %s:%s, but %s declares no @export default for %s -- Save would write nothing and report success"
				% [knob["label"], knob["node"], knob["prop"], path, prop]).is_not_empty()
		# And the line it produced is a line GDScript would accept. Finding the declaration is not
		# the same as writing it back correctly, and the real file carries a comment block above it
		# and a setter after it -- neither of which the hand-written fixtures above prove.
		var line := _declaration(rewritten, prop)
		assert_str(line).override_failure_message(
			"the rewrite of %s left no declaration behind" % prop).is_not_empty()
		assert_bool(line.contains(":= 1.0") or line.contains("= 1.0")).override_failure_message(
			"rewriting %s produced '%s', which does not carry the value asked for" % [prop, line]).is_true()


# The measured assumption the whole slice rests on. An override authored in the scene WINS over the
# script default, so the moment one exists Save writes a line the game never reads -- and the only
# symptom would be the dev tuning the same value twice.
func test_the_scene_overrides_no_object_knob_property() -> void:
	var scene := _scene_text()
	for knob: Dictionary in ObjectKnobs.KNOBS:
		var section := _node_section(scene, knob["node"])
		assert_bool(section.is_empty()).override_failure_message(
			"Battle3D.tscn has no node '%s'" % knob["node"]).is_false()
		var override := RegEx.create_from_string("(?m)^%s[ \\t]*=" % KnobSource.declaration_prop(knob))
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
