# The Game tab (#373): the board markup, unit readout and camera handling that left the Moods tab
# when they got a Save. Three kinds of law, and they fail in three different ways.
#
# THE LIVE LAWS come with the knobs from test_moods_tool.gd, unchanged in substance. "Every knob
# resolves" catches a row left pointing at a renamed property. "A written knob survives two frames"
# is the one that matters: a knob may only name a property that is authored and READ, never one the
# game writes back per frame, or the slider moves and silently reverts -- and TWO frames, because
# process_frame resumes this coroutine BEFORE node _process runs, so one await proves nothing about
# what _process does with the value. Both carry the inert-write guard: a nudge that never registered
# would sail through the survival check testing nothing.
#
# THE SAVE LAWS pin what makes writing back legal at all, measured rather than assumed: every
# property knob is declared in its own node's script, the scene overrides none of them, and every
# class knob is findable in the const table or static var it names. If one stops being true, Save
# writes a line nobody reads and the panel reports success.
#
# THE PANEL LAWS are structural: a group with no sub-tab draws nowhere the dev would look, which is
# indistinguishable from the knob not existing.
#
# The host arriving at all is a WIRE, not two ends: the suite instantiates the real Battle3D scene
# and lets battle3d._ready push it, rather than calling attach_host itself.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"

var _scene: Node3D
var _game: GameTool
# The reach colours and the ring alpha are STATIC vars, i.e. process-global: a case that tunes one
# would leak into every later case AND every later suite in the run. Snapshot and restore per case.
var _static_snapshot: Array = []


func before_test() -> void:
	_static_snapshot = [OverlayManager.ATTACK_MODULATE, OverlayManager.HEAL_ATTACK_MODULATE,
		OverlayManager.SQUAD_RING_ALPHA, OverlayManager.KNOCKBACK_MODULATE,
		OverlayManager.MOVE_ARROW_MODULATE, OverlayManager.INVALID_ARROW_MODULATE,
		OverlayManager.TRAILING_ARROW_MODULATE, MissionStatusPanel.URGENT_ROUNDS]
	var packed := load(SCENE_PATH) as PackedScene
	_scene = packed.instantiate() as Node3D
	_scene.auto_play = false   # no board needed: every knob is a scene property or a class value
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	var dev_overlay := _scene.get_node("Main/DevOverlay") as DevOverlay
	_game = dev_overlay.game_tool


func after_test() -> void:
	OverlayManager.ATTACK_MODULATE = _static_snapshot[0]
	OverlayManager.HEAL_ATTACK_MODULATE = _static_snapshot[1]
	OverlayManager.SQUAD_RING_ALPHA = _static_snapshot[2]
	OverlayManager.KNOCKBACK_MODULATE = _static_snapshot[3]
	OverlayManager.MOVE_ARROW_MODULATE = _static_snapshot[4]
	OverlayManager.INVALID_ARROW_MODULATE = _static_snapshot[5]
	OverlayManager.TRAILING_ARROW_MODULATE = _static_snapshot[6]
	MissionStatusPanel.URGENT_ROUNDS = _static_snapshot[7]
	get_tree().root.remove_child(_scene)
	_scene.free()


# --- Helpers -------------------------------------------------------------------------------

func _knob(node: String, prop: String) -> Dictionary:
	for knob: Dictionary in GameKnobs.KNOBS:
		if knob["node"] == node and knob["prop"] == prop:
			return knob
	return {}


func _class_knob(key: String, value: Variant) -> Dictionary:
	for knob: Dictionary in GameKnobs.CLASS_KNOBS:
		if knob.get(key) == value:
			return knob
	return {}


# A different, legal value for whatever kind this knob holds.
func _nudged(knob: Dictionary, value: Variant) -> Variant:
	# An `options` knob is an enum INDEX and carries no min/max to walk, so it has to be answered
	# before the numeric fall-through reaches for them -- the same branch DevWidgets.add_knob_row
	# takes first, and for the same reason.
	if knob.has("options"):
		var options: Array = knob["options"]
		return (int(value) + 1) % options.size()
	match typeof(value):
		TYPE_BOOL:
			return not value
		TYPE_COLOR:
			var color: Color = value
			return Color(color.r, color.g, color.b, fposmod(color.a + 0.3, 1.0))
		_:
			var low: float = knob["min"]
			var high: float = knob["max"]
			var current: float = value
			var step: float = (high - low) * 0.1
			return current - step if current + step > high else current + step


func _row_for(label_text: String) -> HBoxContainer:
	return _find_row(_game, label_text)


func _find_row(node: Node, label_text: String) -> HBoxContainer:
	for child in node.get_children():
		var box := child as HBoxContainer
		if box != null and box.get_child_count() > 0:
			var label := box.get_child(0) as Label
			if label != null and label.text == label_text:
				return box
		var found := _find_row(child, label_text)
		if found != null:
			return found
	return null


func _read_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


# --- The live laws -------------------------------------------------------------------------

func test_battle3d_hands_the_game_tab_its_host() -> void:
	assert_bool(_game.has_host()).is_true()


# --- V cycles the hover selector's depth (#427 slice 2 follow-up) --------------------
#
# Here rather than in test_height_brush.gd because the key needs the REAL 3D scene: it resolves the
# overlays through GameKnobs.SELECTOR_DEPTH, the same entry the panel row edits, so a case driving a
# bare brush would prove nothing about the thing it moves.

func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


func _overlays_3d() -> BoardOverlays:
	return _scene.get_node("BoardOverlays") as BoardOverlays


func test_v_cycles_the_selector_depth_with_dev_mode_OFF() -> void:
	# The gate that makes it a play key. The selector is up in ordinary play, so a key requiring an
	# armed terrain brush -- or dev mode at all -- would leave the thing visible and the key dead.
	var game: Node2D = _scene.get_node("Main/GameContainer/GameView/Game")
	var dev_on: bool = game.dev_mode_enabled
	assert_bool(dev_on).override_failure_message(
			"the case is not testing what it claims: dev mode is already on").is_false()
	var before: BoardOverlays.SelectorDepth = _overlays_3d().selector_depth

	game.dev_controller.handle_dev_key(_key(KEY_V))

	assert_int(_overlays_3d().selector_depth).override_failure_message(
			"V did not reach the selector outside dev mode").is_not_equal(before)


func test_v_reaches_the_selector_from_the_dev_tools_window_too() -> void:
	# The two-windows rule, which has bitten five times: a key reaches only the FOCUSED OS window, so
	# a binding handled in the game subtree alone is dead exactly where authoring leaves you. This
	# drives the overlay's own arm, so the FORWARD is asserted rather than assumed.
	var dev_overlay := _scene.get_node("Main/DevOverlay") as DevOverlay
	var before: BoardOverlays.SelectorDepth = _overlays_3d().selector_depth

	dev_overlay._input(_key(KEY_V))

	assert_int(_overlays_3d().selector_depth).override_failure_message(
			"V pressed in the dev-tools window never reached the selector").is_not_equal(before)


func test_every_knob_resolves_against_the_real_scene() -> void:
	var unresolved: Array[String] = []
	for knob: Dictionary in GameKnobs.KNOBS:
		if typeof(LookKnobs.read(_scene, knob)) == TYPE_NIL:
			unresolved.append("%s:%s" % [knob["node"], knob["prop"]])
	assert_array(unresolved).override_failure_message(
		"Knobs pointing at nothing: %s" % ", ".join(unresolved)).is_empty()


func test_every_class_knob_resolves() -> void:
	var unresolved: Array[String] = []
	for knob: Dictionary in GameKnobs.CLASS_KNOBS:
		if typeof(GameKnobs.read_class(_scene, knob)) == TYPE_NIL:
			unresolved.append(knob["label"])
	assert_array(unresolved).override_failure_message(
		"Class knobs pointing at nothing: %s" % ", ".join(unresolved)).is_empty()


func test_a_written_knob_survives_the_next_frame() -> void:
	var wanted: Array = []
	var inert: Array[String] = []
	for knob: Dictionary in GameKnobs.KNOBS:
		var value: Variant = LookKnobs.read(_scene, knob)
		if typeof(value) == TYPE_NIL:
			continue
		LookKnobs.write(_scene, knob, _nudged(knob, value))
		# Compare against what the property ACCEPTED, never against what was asked for: engine
		# floats are single-precision, so a double asked for and the float stored differ in the
		# last bits and every one of these would read as a revert.
		var stored: Variant = LookKnobs.read(_scene, knob)
		if stored == value:
			inert.append("%s:%s" % [knob["node"], knob["prop"]])
			continue
		wanted.append({"knob": knob, "want": stored})
	# A knob whose nudge never registered would sail through the survival check below without
	# testing anything -- a set_indexed that silently does nothing looks identical to a value that
	# held. Fail on it separately rather than letting it hide.
	assert_array(inert).override_failure_message(
		"Knobs that did not take a write at all: %s" % ", ".join(inert)).is_empty()
	await await_idle_frame()
	await await_idle_frame()
	var reverted: Array[String] = []
	for entry: Dictionary in wanted:
		var knob: Dictionary = entry["knob"]
		if LookKnobs.read(_scene, knob) != entry["want"]:
			reverted.append("%s:%s" % [knob["node"], knob["prop"]])
	assert_array(reverted).override_failure_message(
		"Knobs the game writes back (a slider here would lie): %s" % ", ".join(reverted)).is_empty()


# The same law for the layer half, and the reason that list is measured rather than chosen.
# set_layer_modulate REPLACES a layer's albedo, so a layer something drives per frame would take a
# knob that silently reverts -- OverlayMirror._process is exactly what has to get a turn here.
func test_a_tuned_layer_colour_survives_the_mirror_poll() -> void:
	var wanted: Array = []
	var inert: Array[String] = []
	for knob: Dictionary in GameKnobs.CLASS_KNOBS:
		if not knob.has("layer"):
			continue   # the statics are asserted separately: the 2D owns them
		var before: Color = GameKnobs.read_class(_scene, knob)
		GameKnobs.write_class(_scene, knob,
			Color(before.r, before.g, before.b, fposmod(before.a + 0.3, 1.0)))
		var stored: Variant = GameKnobs.read_class(_scene, knob)
		if LookKnobs.same_value(stored, before):
			inert.append(knob["label"])
			continue
		wanted.append({"knob": knob, "want": stored})
	assert_array(inert).override_failure_message(
		"Layer knobs that did not take a write at all: %s" % ", ".join(inert)).is_empty()
	await await_idle_frame()
	await await_idle_frame()
	var reverted: Array[String] = []
	for entry: Dictionary in wanted:
		var knob: Dictionary = entry["knob"]
		if not LookKnobs.same_value(GameKnobs.read_class(_scene, knob), entry["want"]):
			reverted.append(knob["label"])
	assert_array(reverted).override_failure_message(
		"Layers the mirror writes back (a knob here would lie): %s" % ", ".join(reverted)).is_empty()


# ATTACK has no 3D-only value: the mirror pushes the 2D's modulate into the 3D every poll, so the
# knob's real target is the 2D static var and BOTH stacks move. Asserted end to end.
func test_the_attack_reach_knob_moves_both_stacks() -> void:
	var knob := _class_knob("static", "ATTACK_MODULATE")
	var tuned := Color(0.2, 0.4, 0.9, 0.6)
	GameKnobs.write_class(_scene, knob, tuned)
	assert_that(OverlayManager.attack_reach_color(null)).is_equal(tuned)   # the authority
	var om: OverlayManager = _scene.game.overlay_manager
	assert_that(om.attack_overlay.modulate).is_equal(tuned)                # the 2D, refreshed
	await await_idle_frame()
	await await_idle_frame()
	var overlays := _scene.get_node("BoardOverlays") as BoardOverlays
	assert_that(overlays.layer_modulate(BoardOverlays.Layer.ATTACK)).is_equal(tuned)   # the 3D


# The panel's own WIRE. Every other case calls the table's write directly, so without this the rows
# could be built completely disconnected and the whole suite would stay green -- two ends, no wire.
func test_dragging_a_slider_moves_the_live_property() -> void:
	var knob := _knob("BoardOverlays", "billboard_lift")
	var row := _row_for(knob["label"])
	assert_object(row).is_not_null()
	var slider := row.get_child(1) as HSlider
	var before: float = LookKnobs.read(_scene, knob)
	slider.value = before + 0.05
	assert_float(LookKnobs.read(_scene, knob)).is_equal_approx(before + 0.05, 0.0005)


# The same wire for a class knob, which reaches its value through a store rather than a property --
# a row that draws the right number and drives nothing would look identical.
func test_dragging_the_ring_alpha_slider_moves_the_static() -> void:
	var row := _row_for("Ring opacity")
	assert_object(row).is_not_null()
	var slider := row.get_child(1) as HSlider
	slider.value = 0.42
	assert_float(OverlayManager.SQUAD_RING_ALPHA).is_equal_approx(0.42, 0.0001)


# The mission clock's threshold (#101) needs a RE-APPLY, unlike most statics here: the status panel
# is push-refreshed from MissionController's write points, so with nothing happening on the board --
# which is exactly when this slider is being dragged -- the row would keep its old tint. #324's
# rule, and the failure mode is a slider that moves a value nobody can see move.
func test_moving_the_clock_threshold_repaints_a_countdown_already_on_screen() -> void:
	var game_2d: Node2D = _scene.game
	var mission: MissionController = game_2d.mission_controller
	mission.lose_conditions.assign(
		[MissionRules.LoseCondition.ROUND_LIMIT] as Array[MissionRules.LoseCondition])
	mission.round_limit = 3
	MissionStatusPanel.URGENT_ROUNDS = 0   # three rounds left is calm at this threshold
	game_2d.refresh_mission_status()
	var calm := _clock_row_color(game_2d)

	GameKnobs.write_static(_scene, "URGENT_ROUNDS", 3)   # ...and urgent at this one

	assert_bool(_clock_row_color(game_2d).is_equal_approx(calm)) \
		.override_failure_message("the static moved but the row did not repaint -- the slider does nothing until the next turn") \
		.is_false()


func _clock_row_color(game_2d: Node2D) -> Color:
	var panel: MissionStatusPanel = game_2d.mission_status_panel
	for child in panel._rows.get_children():
		var label: Label = child as Label
		if label.text.begins_with("Time"):
			return label.modulate
	fail("no clock row on the mission-status panel -- the fixture never rendered one")
	return Color.BLACK


# --- The panel laws ------------------------------------------------------------------------

func test_every_knob_group_has_a_sub_tab() -> void:
	var orphans: Array[String] = []
	for knob: Dictionary in GameKnobs.KNOBS + GameKnobs.CLASS_KNOBS:
		var group: String = knob["group"]
		if not GameKnobs.GROUP_TABS.has(group) and not orphans.has(group):
			orphans.append(group)
	assert_array(orphans).override_failure_message(
		"Knob groups with no sub-tab (their rows would vanish): %s" % ", ".join(orphans)).is_empty()


func test_every_knob_has_a_row_somewhere_in_the_panel() -> void:
	var missing: Array[String] = []
	for knob: Dictionary in GameKnobs.KNOBS + GameKnobs.CLASS_KNOBS:
		if typeof(_value_of(knob)) == TYPE_BOOL:
			continue   # checkboxes are not HBox-with-label rows
		if _row_for(knob["label"]) == null:
			missing.append(knob["label"])
	assert_array(missing).override_failure_message(
		"Knobs with no row drawn anywhere: %s" % ", ".join(missing)).is_empty()


func _value_of(knob: Dictionary) -> Variant:
	return GameKnobs.read_class(_scene, knob) if knob.has("layer") or knob.has("static") \
		else LookKnobs.read(_scene, knob)


func test_every_knob_has_a_tooltip() -> void:
	var untipped: Array[String] = []
	for knob: Dictionary in GameKnobs.KNOBS + GameKnobs.CLASS_KNOBS:
		if String(knob.get("tip", "")).strip_edges() == "":
			untipped.append(knob["label"])
	assert_array(untipped).override_failure_message(
		"Knobs with no tooltip: %s" % ", ".join(untipped)).is_empty()


# A tooltip is a plain Label with no autowrap, so an unwrapped one runs off the screen.
func test_no_tooltip_line_runs_too_long() -> void:
	var wide: Array[String] = []
	for knob: Dictionary in GameKnobs.KNOBS + GameKnobs.CLASS_KNOBS:
		for line: String in _game.tip_for(knob).split("\n"):
			if line.length() > 90:   # the wrapper targets 74; this catches a wrap that never ran
				wide.append(knob["label"])
				break
	assert_array(wide).override_failure_message(
		"Tooltips with an unwrapped line: %s" % ", ".join(wide)).is_empty()


# A slider has mouse_filter STOP, so Godot asks IT for the tooltip and never walks up to the label.
func test_the_tooltip_reaches_the_slider_you_hover() -> void:
	var knob := _knob("BoardOverlays", "billboard_lift")
	var slider := _row_for(knob["label"]).get_child(1) as HSlider
	assert_str(slider.tooltip_text).is_equal(_game.tip_for(knob))
	assert_str(slider.tooltip_text).is_not_empty()


# A colour knob is four sliders and a swatch, not a picker: ColorPickerButton froze the dev window
# solid the first time one was opened (dev, 2026-08-14). This tab is where every markup colour lives
# now, so the ban needs its law here rather than only next door.
func test_the_panel_builds_no_colorpicker_widgets() -> void:
	var offenders: Array[String] = []
	_walk_for_pickers(_game, offenders)
	assert_array(offenders).override_failure_message(
		"ColorPicker widgets in the Game tab (these freeze the dev window): %s"
		% ", ".join(offenders)).is_empty()


func _walk_for_pickers(node: Node, offenders: Array[String]) -> void:
	for child in node.get_children(true):   # include internal children
		if child is ColorPicker or child is ColorPickerButton:
			offenders.append("%s (%s)" % [child.name, child.get_class()])
		_walk_for_pickers(child, offenders)


func test_a_tab_with_no_host_degrades_instead_of_crashing() -> void:
	var lonely := GameTool.new()
	add_child(lonely)
	assert_bool(lonely.has_host()).is_false()
	assert_array(lonely.changed_indices()).is_empty()
	assert_array(lonely.changed_class_indices()).is_empty()
	lonely.queue_free()


# --- The save laws -------------------------------------------------------------------------
#
# Nothing here writes to disk. Each case asks the rewriter whether it COULD find what Save would
# aim at, against the real source -- which is the whole assumption, and the one that rots silently.

func test_every_knob_is_declared_in_the_script_its_node_carries() -> void:
	for knob: Dictionary in GameKnobs.KNOBS:
		var path := KnobSource.script_path_for(_scene, knob)
		assert_str(path).override_failure_message(
			"no script on node '%s' -- '%s' has nowhere to save to" % [knob["node"], knob["label"]]).is_not_empty()
		var prop := KnobSource.declaration_prop(knob)
		var rewritten := KnobSource.rewrite_declaration_default(_read_file(path), prop, "1.0")
		assert_str(rewritten).override_failure_message(
			"'%s' names %s:%s, but %s declares no default for %s -- Save would write nothing and report success"
				% [knob["label"], knob["node"], knob["prop"], path, prop]).is_not_empty()


# The other half, for the table that has no node to ask: a layer's entry and a static's declaration
# both have to still be there, in the file GameKnobs names.
func test_every_class_knob_is_findable_in_the_file_it_names() -> void:
	var overlays := _read_file(GameKnobs.OVERLAYS_SCRIPT)
	var manager := _read_file(GameKnobs.OVERLAY_MANAGER_SCRIPT)
	assert_str(overlays).override_failure_message(
		"could not read %s -- this law would pass vacuously" % GameKnobs.OVERLAYS_SCRIPT).is_not_empty()
	assert_str(manager).override_failure_message(
		"could not read %s -- this law would pass vacuously" % GameKnobs.OVERLAY_MANAGER_SCRIPT).is_not_empty()
	for knob: Dictionary in GameKnobs.CLASS_KNOBS:
		var rewritten := ""
		var what := ""
		if knob.has("static"):
			# A static row names its own script home since the #259 rework (default: the
			# OverlayManager file) -- the law reads the same key the Save routes by.
			var home: String = knob.get("script", GameKnobs.OVERLAY_MANAGER_SCRIPT)
			var source := manager if home == GameKnobs.OVERLAY_MANAGER_SCRIPT else _read_file(home)
			assert_str(source).override_failure_message(
				"could not read %s -- this law would pass vacuously" % home).is_not_empty()
			what = "static var %s in %s" % [knob["static"], home.get_file()]
			rewritten = KnobSource.rewrite_declaration_default(source, knob["static"], "1.0")
		else:
			var layer_name: String = BoardOverlays.Layer.keys()[knob["layer"]]
			what = "Layer.%s's entry in BoardOverlays.LAYERS" % layer_name
			rewritten = KnobSource.rewrite_layer_color(overlays, layer_name, "Color(1, 1, 1, 1)")
		assert_str(rewritten).override_failure_message(
			"'%s' has no %s left to write -- Save would report success having written nothing"
				% [knob["label"], what]).is_not_empty()


# The measured assumption the whole tab rests on. An override authored in the scene WINS over the
# script default, so the moment one exists Save writes a line the game never reads -- and the only
# symptom would be the dev tuning the same value twice.
func test_the_scene_overrides_no_game_knob_property() -> void:
	var scene := _read_file(SCENE_PATH)
	assert_str(scene).override_failure_message(
		"could not read %s -- this law would pass vacuously" % SCENE_PATH).is_not_empty()
	for knob: Dictionary in GameKnobs.KNOBS:
		var section := _node_section(scene, knob["node"])
		assert_bool(section.is_empty()).override_failure_message(
			"Battle3D.tscn has no node '%s'" % knob["node"]).is_false()
		var override := RegEx.create_from_string(
			"(?m)^%s[ \\t]*=" % KnobSource.declaration_prop(knob))
		assert_object(override.search(section)).override_failure_message(
			"Battle3D.tscn overrides %s:%s -- the script default Save writes is no longer what the game reads"
				% [knob["node"], knob["prop"]]).is_null()


# The lines belonging to one [node ...] block, up to the next one.
#
# "." is the ROOT, matching LookKnobs.target_of -- a knob's `node` has two readers and they have to
# spell the same vocabulary, or a legal value silently reads as "no such node" here and the law
# reports a missing node instead of the override it exists to find (#498, the first row to use it).
# The root has no name this can search for, but a .tscn always writes it as the FIRST [node block.
func _node_section(scene: String, node_name: String) -> String:
	if node_name == ".":
		var root := scene.find("[node name=\"")
		if root < 0:
			return ""
		var after_root := scene.find("\n[", root + 1)
		return scene.substr(root, -1 if after_root < 0 else after_root - root)
	var start := scene.find("[node name=\"%s\"" % node_name)
	if start < 0:
		return ""
	var next := scene.find("\n[", start + 1)
	return scene.substr(start, -1 if next < 0 else next - start)


# What Save would actually emit, without emitting it: the edits are built and inspected rather than
# applied. This is where a knob that moved tables, or a colour knob aimed at the wrong file, shows
# up as a line pointed somewhere nobody reads.
func test_a_moved_knob_builds_an_edit_aimed_at_its_own_declaration() -> void:
	var knob := _knob("BoardOverlays", "billboard_lift")
	LookKnobs.write(_scene, knob, 1.42)
	var moved := _game.changed_indices()
	assert_array(moved).is_not_empty()
	var edits := KnobSource.declaration_edits(_scene, GameKnobs.KNOBS, moved, GameKnobs.KNOB_SOURCE)
	var found := {}
	for an_edit: Dictionary in edits:
		found[an_edit["name"]] = an_edit
	assert_bool(found.has("billboard_lift")).is_true()
	var billboard: Dictionary = found["billboard_lift"]
	assert_str(billboard["path"]).is_equal(GameKnobs.OVERLAYS_SCRIPT)
	assert_str(billboard["literal"]).is_equal("1.42")


func test_a_moved_layer_colour_builds_an_edit_aimed_at_the_layers_table() -> void:
	var knob := _class_knob("layer", BoardOverlays.Layer.MOVE)
	GameKnobs.write_class(_scene, knob, Color(1, 1, 0, 0.35))
	var edits := GameKnobs.class_edits(_scene, _game.changed_class_indices())
	assert_array(edits).is_not_empty()
	var move_edit := {}
	for an_edit: Dictionary in edits:
		if an_edit["name"] == "MOVE":
			move_edit = an_edit
	assert_dict(move_edit).override_failure_message(
		"the moved MOVE fill built no edit at all").is_not_empty()
	assert_str(move_edit["path"]).is_equal(GameKnobs.OVERLAYS_SCRIPT)
	assert_int(move_edit["kind"]).is_equal(KnobSource.Kind.LAYER_COLOR)
	assert_str(move_edit["literal"]).is_equal("Color(1.0, 1.0, 0.0, 0.35)")


# A reach colour is a static, so its edit is a DECLARATION aimed at the other file -- the one place
# the two class kinds visibly diverge, and the one most likely to be wired to the wrong file.
func test_a_moved_reach_colour_builds_a_declaration_edit_on_the_overlay_manager() -> void:
	var knob := _class_knob("static", "ATTACK_MODULATE")
	GameKnobs.write_class(_scene, knob, Color(0.2, 0.4, 0.9, 0.6))
	var edits := GameKnobs.class_edits(_scene, _game.changed_class_indices())
	var reach := {}
	for an_edit: Dictionary in edits:
		if an_edit["name"] == "ATTACK_MODULATE":
			reach = an_edit
	assert_dict(reach).override_failure_message(
		"the moved attack reach colour built no edit at all").is_not_empty()
	assert_str(reach["path"]).is_equal(GameKnobs.OVERLAY_MANAGER_SCRIPT)
	assert_int(reach["kind"]).is_equal(KnobSource.Kind.DECLARATION)


# --- Reset ---------------------------------------------------------------------------------

func test_nothing_is_reported_changed_until_something_moves() -> void:
	assert_array(_game.changed_indices()).is_empty()
	assert_array(_game.changed_class_indices()).is_empty()


func test_reset_puts_every_knob_and_colour_back() -> void:
	for knob: Dictionary in GameKnobs.KNOBS:
		var value: Variant = LookKnobs.read(_scene, knob)
		if typeof(value) != TYPE_NIL:
			LookKnobs.write(_scene, knob, _nudged(knob, value))
	for knob: Dictionary in GameKnobs.CLASS_KNOBS:
		var value: Variant = GameKnobs.read_class(_scene, knob)
		if typeof(value) != TYPE_NIL:
			GameKnobs.write_class(_scene, knob, _nudged(knob, value))
	assert_array(_game.changed_indices()).is_not_empty()
	assert_array(_game.changed_class_indices()).is_not_empty()
	_game._on_reset_pressed()
	assert_array(_game.changed_indices()).is_empty()
	assert_array(_game.changed_class_indices()).is_empty()
	await await_idle_frame()   # the rebuild's detached rows, or they read as orphans


# --- Saves ask first (#380's convention) -----------------------------------------------------
#
# The Game tab's save writes SOURCE FILES and the Objects tab's writes the shared tileset, so both
# ask before a byte moves -- the same convention every Update and Delete already carries, asserted
# per button in test_dev_tool_overwrite_guards.gd. These two live here because their fixtures need
# the Battle3D host that suite deliberately does not load. No case emits `confirmed`.

func _find_dialog(host: Node) -> ConfirmationDialog:
	for child in host.get_children():
		if child is ConfirmationDialog:
			return child as ConfirmationDialog
	return null


func test_save_to_source_asks_before_writing() -> void:
	var knob := _knob("BoardOverlays", "billboard_lift")
	var path := KnobSource.script_path_for(_scene, knob)
	var before := FileAccess.open(path, FileAccess.READ).get_as_text()
	LookKnobs.write(_scene, knob, 1.42)

	_game._on_save_pressed()

	assert_object(_find_dialog(_game)).is_not_null()
	# Nothing written while the question is open -- byte-identical, not just same mtime.
	assert_str(FileAccess.open(path, FileAccess.READ).get_as_text()).is_equal(before)
	assert_array(_game.changed_indices()).is_not_empty()   # still reported moved, not adopted


func test_save_cancel_writes_nothing_and_the_dialog_frees() -> void:
	var knob := _knob("BoardOverlays", "billboard_lift")
	var path := KnobSource.script_path_for(_scene, knob)
	var before := FileAccess.open(path, FileAccess.READ).get_as_text()
	LookKnobs.write(_scene, knob, 1.42)
	_game._on_save_pressed()
	var dialog := _find_dialog(_game)
	assert_object(dialog).is_not_null()

	dialog.canceled.emit()
	dialog.hide()
	await await_idle_frame()

	assert_str(FileAccess.open(path, FileAccess.READ).get_as_text()).is_equal(before)
	assert_object(_find_dialog(_game)).is_null()


func test_a_save_with_nothing_moved_never_reaches_a_dialog() -> void:
	_game._on_save_pressed()

	assert_object(_find_dialog(_game)).is_null()
	assert_str(_game._status.text).is_not_empty()


func test_save_object_fields_asks_before_writing() -> void:
	var dev_overlay := _scene.get_node("Main/DevOverlay") as DevOverlay
	var objects: ObjectTool = dev_overlay.object_tool
	assert_bool(objects.has_host()).is_true()

	objects._on_save_fields_pressed()

	assert_object(_find_dialog(objects)).is_not_null()
