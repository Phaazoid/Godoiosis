extends VBoxContainer
class_name LookTool

# The dev-tools Look tab (#212): the one live surface for the HD-2D stack's aesthetic values.
# Every KNOBS entry names a property that ALREADY EXISTS on the running Battle3D world -- an
# @export on a presentation node, or a field of a sub_resource authored in Battle3D.tscn -- and
# both are reached the same way, via get_indexed/set_indexed. Nothing here stores a value; this
# is a surface onto values that stay where they always lived. Adding a knob is one table line.
#
# The host is PUSHED in by battle3d._ready (attach_host), never looked up: no part of the game
# subtree gains an upward path to the 3D scene, and launching Main.tscn flat -- a real shipping
# target -- simply never attaches one, which this reports instead of crashing.
#
# Tuning is LIVE ONLY. Copy Values dumps whatever moved off the authored baseline as paste-ready
# GDScript and the clipboard is the handoff (#212's own call); nothing here writes a file.
#
# A knob may only name a property that is authored and READ. Anything the game writes back per
# frame -- the rig's yaw, dof_blur_near/far_distance (re-derived from focus_band_*), max_distance,
# orbit_button, manual_input_enabled -- would give a slider that moves and silently reverts, the
# one failure that makes a tuning panel untrustworthy. tests/dev/test_look_tool.gd pins that by
# writing, waiting a frame, and reading back.

# node = path relative to the host ("." = the host); prop = colon-joined property path.
# A float knob carries min/max/step; bool and Color infer their widget from the live value;
# options = an int-backed enum, labels in declaration order.
const KNOBS: Array[Dictionary] = [
	# --- Lighting ---
	{"group": "Lighting", "node": "Sun", "prop": "light_energy", "label": "Sun energy", "min": 0.0, "max": 6.0, "step": 0.01},
	{"group": "Lighting", "node": "Sun", "prop": "light_color", "label": "Sun colour"},
	{"group": "Lighting", "node": "Sun", "prop": "rotation_degrees:x", "label": "Sun elevation", "min": -90.0, "max": 0.0, "step": 0.5},
	{"group": "Lighting", "node": "Sun", "prop": "rotation_degrees:y", "label": "Sun azimuth", "min": -180.0, "max": 180.0, "step": 0.5},
	{"group": "Lighting", "node": "Sun", "prop": "shadow_enabled", "label": "Shadows"},
	# The #226 pair: units reading as hovering is most likely peter-panning, chased by eye.
	{"group": "Lighting", "node": "Sun", "prop": "shadow_bias", "label": "Shadow bias", "min": 0.0, "max": 0.5, "step": 0.001},
	{"group": "Lighting", "node": "Sun", "prop": "shadow_normal_bias", "label": "Shadow normal bias", "min": 0.0, "max": 4.0, "step": 0.01},
	{"group": "Lighting", "node": "Sun", "prop": "shadow_opacity", "label": "Shadow opacity", "min": 0.0, "max": 1.0, "step": 0.01},
	{"group": "Lighting", "node": "Sun", "prop": "directional_shadow_max_distance", "label": "Shadow draw distance", "min": 10.0, "max": 300.0, "step": 1.0},

	# --- Sky ---
	{"group": "Sky", "node": "WorldEnvironment", "prop": "environment:sky:sky_material:sky_top_color", "label": "Sky top"},
	{"group": "Sky", "node": "WorldEnvironment", "prop": "environment:sky:sky_material:sky_horizon_color", "label": "Sky horizon"},
	{"group": "Sky", "node": "WorldEnvironment", "prop": "environment:sky:sky_material:ground_horizon_color", "label": "Ground horizon"},

	# --- Post ---
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:tonemap_mode", "label": "Tonemap", "options": ["Linear", "Reinhard", "Filmic", "ACES", "AgX"]},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:tonemap_exposure", "label": "Exposure", "min": 0.1, "max": 4.0, "step": 0.01},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:tonemap_white", "label": "White point", "min": 0.1, "max": 4.0, "step": 0.01},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:glow_enabled", "label": "Glow"},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:glow_intensity", "label": "Glow intensity", "min": 0.0, "max": 4.0, "step": 0.01},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:glow_strength", "label": "Glow strength", "min": 0.0, "max": 2.0, "step": 0.01},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:glow_bloom", "label": "Glow bloom", "min": 0.0, "max": 1.0, "step": 0.01},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:glow_hdr_threshold", "label": "Glow HDR threshold", "min": 0.0, "max": 4.0, "step": 0.01},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:ssao_enabled", "label": "SSAO"},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:ssao_radius", "label": "SSAO radius", "min": 0.1, "max": 8.0, "step": 0.05},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:ssao_intensity", "label": "SSAO intensity", "min": 0.0, "max": 8.0, "step": 0.05},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:ssao_power", "label": "SSAO power", "min": 0.1, "max": 8.0, "step": 0.05},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:adjustment_enabled", "label": "Colour adjust"},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:adjustment_brightness", "label": "Brightness", "min": 0.1, "max": 3.0, "step": 0.01},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:adjustment_contrast", "label": "Contrast", "min": 0.1, "max": 3.0, "step": 0.01},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:adjustment_saturation", "label": "Saturation", "min": 0.0, "max": 3.0, "step": 0.01},

	# --- Fog ---
	# The sunset preset reading as a forest fire is the case #212 was filed over.
	{"group": "Fog", "node": "WorldEnvironment", "prop": "environment:volumetric_fog_enabled", "label": "Volumetric fog"},
	{"group": "Fog", "node": "WorldEnvironment", "prop": "environment:volumetric_fog_density", "label": "Fog density", "min": 0.0, "max": 0.2, "step": 0.001},
	{"group": "Fog", "node": "WorldEnvironment", "prop": "environment:volumetric_fog_albedo", "label": "Fog albedo"},
	{"group": "Fog", "node": "WorldEnvironment", "prop": "environment:volumetric_fog_anisotropy", "label": "Fog anisotropy", "min": -0.9, "max": 0.9, "step": 0.01},

	# --- Camera ---
	{"group": "Camera", "node": "CameraRig/Pitch", "prop": "rotation_degrees:x", "label": "Board pitch", "min": -85.0, "max": -10.0, "step": 0.5},
	{"group": "Camera", "node": "CameraRig/Pitch/Camera", "prop": "fov", "label": "FOV", "min": 12.0, "max": 70.0, "step": 0.5},
	{"group": "Camera", "node": ".", "prop": "opening_view_cells", "label": "Opening shot (cells)", "min": 6.0, "max": 64.0, "step": 1.0},
	{"group": "Camera", "node": "CameraRig", "prop": "min_distance", "label": "Zoom-in limit", "min": 2.0, "max": 20.0, "step": 0.25},
	{"group": "Camera", "node": "CameraRig", "prop": "zoom_step", "label": "Zoom step", "min": 0.25, "max": 5.0, "step": 0.05},
	{"group": "Camera", "node": "CameraRig", "prop": "smoothing", "label": "Camera smoothing", "min": 1.0, "max": 24.0, "step": 0.1},
	{"group": "Camera", "node": "CameraRig", "prop": "pan_speed", "label": "Pan speed", "min": 1.0, "max": 30.0, "step": 0.5},
	{"group": "Camera", "node": "CameraRig", "prop": "orbit_sensitivity", "label": "Orbit sensitivity", "min": 0.02, "max": 1.0, "step": 0.01},
	{"group": "Camera", "node": "CameraRig", "prop": "pan_margin_cells", "label": "Pan margin (cells)", "min": 0.0, "max": 12.0, "step": 0.5},
	{"group": "Camera", "node": "CameraRig", "prop": "fit_margin_cells", "label": "Fit margin (cells)", "min": 0.0, "max": 8.0, "step": 0.25},
	{"group": "Camera", "node": "CameraRig", "prop": "zoom_out_slack", "label": "Zoom-out slack", "min": 0.5, "max": 3.0, "step": 0.05},

	# --- Depth of field ---
	# The BANDS are the knobs; the distances they produce are re-derived per frame off the live
	# camera distance, which is what stopped close zooms drifting the board into the near blur.
	{"group": "Depth of field", "node": "CameraRig", "prop": "focus_band_near", "label": "Near band", "min": 0.5, "max": 20.0, "step": 0.1},
	{"group": "Depth of field", "node": "CameraRig", "prop": "focus_band_far", "label": "Far band", "min": 0.5, "max": 20.0, "step": 0.1},
	{"group": "Depth of field", "node": "CameraRig/Pitch/Camera", "prop": "attributes:dof_blur_amount", "label": "Blur amount", "min": 0.0, "max": 0.5, "step": 0.005},
	{"group": "Depth of field", "node": "CameraRig/Pitch/Camera", "prop": "attributes:dof_blur_near_enabled", "label": "Near blur"},
	{"group": "Depth of field", "node": "CameraRig/Pitch/Camera", "prop": "attributes:dof_blur_near_transition", "label": "Near transition", "min": 0.1, "max": 20.0, "step": 0.1},
	{"group": "Depth of field", "node": "CameraRig/Pitch/Camera", "prop": "attributes:dof_blur_far_enabled", "label": "Far blur"},
	{"group": "Depth of field", "node": "CameraRig/Pitch/Camera", "prop": "attributes:dof_blur_far_transition", "label": "Far transition", "min": 0.1, "max": 20.0, "step": 0.1},

	# --- Board markup ---
	# fill_lift and lift_step raise every ground marker together, arrows included. A lift the
	# ARROWS own alone (#227) needs its own export on BoardOverlays -- not in this slice.
	{"group": "Board markup", "node": "BoardOverlays", "prop": "fill_lift", "label": "Marker lift", "min": 0.0, "max": 0.5, "step": 0.001},
	{"group": "Board markup", "node": "BoardOverlays", "prop": "lift_step", "label": "Per-layer lift step", "min": 0.0, "max": 0.05, "step": 0.0005},
	{"group": "Board markup", "node": "BoardOverlays", "prop": "bracket_arm", "label": "Bracket arm", "min": 0.05, "max": 0.5, "step": 0.005},
	{"group": "Board markup", "node": "BoardOverlays", "prop": "bracket_thickness", "label": "Bracket thickness", "min": 0.005, "max": 0.2, "step": 0.001},
	{"group": "Board markup", "node": "BoardOverlays", "prop": "bracket_scale", "label": "Bracket scale", "min": 0.9, "max": 1.3, "step": 0.005},
	{"group": "Board markup", "node": "BoardOverlays", "prop": "invalid_bracket_color", "label": "Invalid bracket tint"},
	{"group": "Board markup", "node": "BoardOverlays", "prop": "billboard_lift", "label": "Icon height", "min": 0.0, "max": 3.0, "step": 0.01},
	{"group": "Board markup", "node": "BoardOverlays", "prop": "billboard_pixel_size", "label": "Icon pixel size", "min": 0.004, "max": 0.1, "step": 0.001},

	# --- Effects ---
	{"group": "Effects", "node": "BoardMirror", "prop": "flame_lift", "label": "Flame lift", "min": 0.0, "max": 2.0, "step": 0.01},
	{"group": "Effects", "node": "BoardMirror", "prop": "flame_size:x", "label": "Flame width", "min": 0.1, "max": 2.0, "step": 0.01},
	{"group": "Effects", "node": "BoardMirror", "prop": "flame_size:y", "label": "Flame height", "min": 0.1, "max": 2.0, "step": 0.01},
	{"group": "Effects", "node": "BoardMirror", "prop": "flame_ground_gap", "label": "Flame ground gap", "min": 0.0, "max": 0.5, "step": 0.005},
	{"group": "Effects", "node": "BoardMirror", "prop": "flame_writes_depth", "label": "Flame writes depth"},
	{"group": "Effects", "node": "BoardMirror", "prop": "flame_light_energy", "label": "Flame light energy", "min": 0.0, "max": 8.0, "step": 0.05},
	{"group": "Effects", "node": "BoardMirror", "prop": "flame_light_range", "label": "Flame light range", "min": 0.5, "max": 12.0, "step": 0.1},
	{"group": "Effects", "node": "BoardMirror", "prop": "brush_ghost_alpha", "label": "Brush ghost alpha", "min": 0.0, "max": 1.0, "step": 0.01},
]

const HEADING_COLOR := Color(1, 0.83, 0.4, 1)   # the Scenario tab's heading gold

var _host: Node3D                # the Battle3D scene; pushed in, never looked up
var _baseline: Array = []        # the authored value per KNOBS index, read once on attach
var _rows: VBoxContainer
var _status: Label


func _ready() -> void:
	var buttons := HBoxContainer.new()
	buttons.add_child(_button("Copy changed values",
		"Copy every value moved off its authored setting to the clipboard, as paste-ready GDScript",
		_on_copy_pressed))
	buttons.add_child(_button("Reset to authored",
		"Put every knob back to the value the scene was authored with", _on_reset_pressed))
	buttons.add_child(_button("Re-fit camera",
		"Pitch and FOV feed the framing maths, which only runs on a board load -- press this after moving either",
		_on_refit_pressed))
	add_child(buttons)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	_rebuild()


# Called by battle3d._ready. The 2D game boots first (Godot readies children before parents), so
# the tab always builds its no-host state and then rebuilds here.
func attach_host(host: Node3D) -> void:
	_host = host
	_baseline.clear()
	for knob: Dictionary in KNOBS:
		_baseline.append(read(knob))   # authored by definition: nothing has moved one yet
	_rebuild()


func has_host() -> bool:
	return _host != null


# --- Reading and writing a knob ---------------------------------------------------------

func target_of(knob: Dictionary) -> Node:
	if _host == null:
		return null
	var path: String = knob["node"]
	if path == ".":
		return _host
	return _host.get_node_or_null(NodePath(path))


func read(knob: Dictionary) -> Variant:
	var target := target_of(knob)
	if target == null:
		return null
	return target.get_indexed(NodePath(knob["prop"]))


func write(knob: Dictionary, value: Variant) -> void:
	var target := target_of(knob)
	if target == null:
		return
	target.set_indexed(NodePath(knob["prop"]), value)


func baseline_of(index: int) -> Variant:
	if index < 0 or index >= _baseline.size():
		return null
	return _baseline[index]


# --- Building the rows ------------------------------------------------------------------

func _rebuild() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	if _host == null:
		DevWidgets.add_label(_rows,
			"No 3D host attached - the flat 2D game has no look stack to tune.")
		return
	var group := ""
	for knob: Dictionary in KNOBS:
		var knob_group: String = knob["group"]
		if knob_group != group:
			group = knob_group
			_add_heading(group)
		_build_row(knob)


func _build_row(knob: Dictionary) -> void:
	var value: Variant = read(knob)
	var label: String = knob["label"]
	# An unresolved knob is a table entry pointing at a renamed or moved property. Say so on the
	# panel AND in the log rather than drawing a row that edits nothing.
	if typeof(value) == TYPE_NIL:
		DevWidgets.add_label(_rows, "%s - UNRESOLVED (%s:%s)" % [label, knob["node"], knob["prop"]])
		push_error("LookTool knob does not resolve: %s:%s" % [knob["node"], knob["prop"]])
		return
	if knob.has("options"):
		var options: Array = knob["options"]
		var current: int = int(value)
		var current_label: String = options[current] if current >= 0 and current < options.size() else ""
		DevWidgets.add_option(_rows, label, options, current_label,
			func(picked: String) -> void: write(knob, options.find(picked)))
		return
	match typeof(value):
		TYPE_BOOL:
			DevWidgets.add_checkbox(_rows, label, value,
				func(on: bool) -> void: write(knob, on))
		TYPE_COLOR:
			DevWidgets.add_color(_rows, label, value,
				func(picked: Color) -> void: write(knob, picked))
		_:
			var low: float = knob["min"]
			var high: float = knob["max"]
			var step: float = knob["step"]
			DevWidgets.add_slider(_rows, label, value, low, high, step,
				func(moved: float) -> void: write(knob, moved))


func _add_heading(text: String) -> void:
	if _rows.get_child_count() > 0:
		_rows.add_child(HSeparator.new())
	var heading := Label.new()
	heading.text = text
	heading.add_theme_color_override("font_color", HEADING_COLOR)
	_rows.add_child(heading)


func _button(text: String, tooltip: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(on_pressed)
	return button


# --- The handoff ------------------------------------------------------------------------

func _on_copy_pressed() -> void:
	var moved := changed_values()
	if moved.is_empty():
		_status.text = "Nothing has moved off its authored value yet."
		return
	DisplayServer.clipboard_set(_format(moved))
	_status.text = "Copied %d changed value(s) to the clipboard." % _value_count(moved)


func _on_reset_pressed() -> void:
	if _host == null:
		return
	for i in KNOBS.size():
		var authored: Variant = baseline_of(i)
		if typeof(authored) != TYPE_NIL:
			write(KNOBS[i], authored)
	_rebuild()   # redraw every widget off the restored values -- one path, every widget kind
	_status.text = "Every knob is back at its authored value."


func _on_refit_pressed() -> void:
	if _host == null:
		return
	_host.fit_camera()
	_status.text = "Camera re-framed on the current board."


# Only what MOVED, keyed by where it gets pasted: header -> {property: literal}. A property path
# that passes through a sub-resource is authored INSIDE that resource, so the header names the
# resource and the line is what goes in it. A vector component (flame_size:x) has no resource
# between it and the node, so the whole vector is emitted -- "x = 0.6" would mean nothing in a
# .tscn, and it also collapses the x and y knobs into the single line they share.
func changed_values() -> Dictionary:
	var groups := {}
	for i in KNOBS.size():
		var knob: Dictionary = KNOBS[i]
		var live: Variant = read(knob)
		var authored: Variant = baseline_of(i)
		if typeof(live) == TYPE_NIL or typeof(authored) == TYPE_NIL or live == authored:
			continue
		var split := _paste_split(knob)
		var header: String = split[0]
		if not groups.has(header):
			groups[header] = {}
		var entries: Dictionary = groups[header]
		entries[split[1]] = split[2]
	return groups


func _paste_split(knob: Dictionary) -> Array:
	var segments: PackedStringArray = String(knob["prop"]).split(":")
	var current: Object = target_of(knob)
	var owner_bits: PackedStringArray = PackedStringArray()
	var i := 0
	# Walk to the DEEPEST object in the chain: that is the thing the value is authored on.
	while i < segments.size() - 1:
		var next: Variant = current.get(segments[i])
		if not (next is Object):
			break
		owner_bits.append(segments[i])
		current = next as Object
		i += 1
	var node_path: String = knob["node"]
	var header := "Battle3D.tscn -> %s" % ("Battle3D" if node_path == "." else node_path)
	if owner_bits.size() > 0:
		header += ".%s" % ".".join(owner_bits)
	return [header, segments[i], literal_for(current.get(segments[i]))]


func _format(groups: Dictionary) -> String:
	var out: PackedStringArray = PackedStringArray()
	for header: String in groups:
		out.append("# %s" % header)
		var entries: Dictionary = groups[header]
		for prop: String in entries:
			out.append("%s = %s" % [prop, entries[prop]])
		out.append("")
	return "\n".join(out).strip_edges()


func _value_count(groups: Dictionary) -> int:
	var total := 0
	for header: String in groups:
		var entries: Dictionary = groups[header]
		total += entries.size()
	return total


static func literal_for(value: Variant) -> String:
	match typeof(value):
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_FLOAT:
			return String.num(value, 4)
		TYPE_COLOR:
			var color: Color = value
			return "Color(%s, %s, %s, %s)" % [String.num(color.r, 4), String.num(color.g, 4),
				String.num(color.b, 4), String.num(color.a, 4)]
		TYPE_VECTOR2:
			var vec2: Vector2 = value
			return "Vector2(%s, %s)" % [String.num(vec2.x, 4), String.num(vec2.y, 4)]
		TYPE_VECTOR3:
			var vec3: Vector3 = value
			return "Vector3(%s, %s, %s)" % [String.num(vec3.x, 4), String.num(vec3.y, 4),
				String.num(vec3.z, 4)]
	return str(value)
