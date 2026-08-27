extends Object
class_name LookKnobs

# WHAT the HD-2D look is made of, and how to read, write, capture and apply it (#253 part 2).
# Static and pure -- the MissionRules / LethalityRules shape.
#
# It lives here rather than in Classes/dev/ because a MISSION carries a look now: ScenarioData
# names a preset and battle3d applies it on every board load, which is shipping-build code. The
# Moods tab (Classes/dev/MoodsTool.gd) is a SURFACE onto this table, not its owner.
#
# Every KNOBS entry names a property that ALREADY EXISTS on the running Battle3D world -- an
# @export on a presentation node, or a field of a sub_resource authored in Battle3D.tscn -- and
# both are reached the same way, via get_indexed/set_indexed. Nothing here stores a value.
#
# A knob may only name a property that is authored and READ. Anything the game writes back per
# frame -- the rig's yaw, dof_blur_near/far_distance (re-derived from focus_band_*), max_distance,
# orbit_button, manual_input_enabled -- would give a slider that moves and silently reverts, the
# one failure that makes a tuning panel untrustworthy. tests/dev/test_moods_tool.gd pins that by
# writing, waiting two frames, and reading back.
#
# WHAT IS NOT HERE, and where it went. This table is scene MOOD, entire -- so a preset captures
# every row of it and there is no exclusion list (#373 deleted `PRESET_EXCLUDED` by emptying it).
# Board markup, the unit readout, camera HANDLING and the brush ghost were all excluded from
# presets and all left for GameKnobs, which gave them the Save a preset could never be; world
# construction and terrain effects left earlier, for ObjectKnobs (#272). A knob added here now
# joins presets automatically, which is right for a look knob and is why the question to ask of a
# new one is "may one board differ from another about this?" -- if not, it belongs in another table.

const PRESET_DIR := "res://Resources/LookPresets/"

# The fallback authority (dev, 2026-08-15). A SEPARATE file from Day.tres, and outside PRESET_DIR
# on purpose: outside, it cannot appear in the load dropdown, Delete can never target it, and
# Save As cannot shadow it -- all structural rather than a filename anyone could get wrong.
# It ships byte-identical to Day and is MEANT to diverge; they answer two different questions
# (an editable day mood vs what every board falls back to), which is a declared duplication.
const DEFAULT_PATH := "res://Resources/DefaultLook.tres"
# The file's own preset_name. Named rather than typed at the one call site because the Moods tab's
# Update default RE-CAPTURES this file (#386), and a capture under a different name would quietly
# rename the default rather than overwrite it.
const DEFAULT_NAME := "Default"

# node = path relative to the host ("." = the host); prop = colon-joined property path.
# A float knob carries min/max/step; bool and Color infer their widget from the live value;
# options = an int-backed enum, labels in declaration order.
const KNOBS: Array[Dictionary] = [
	# --- Lighting ---
	{"group": "Lighting", "node": "Sun", "prop": "light_energy", "label": "Sun energy", "min": 0.0, "max": 6.0, "step": 0.01,
		"tip": "How bright the sun is. Multiplies its colour rather than replacing it, and the whole scene's exposure keys off this -- a big move here usually wants Exposure re-checked too."},
	{"group": "Lighting", "node": "Sun", "prop": "light_color", "label": "Sun colour",
		"tip": "The sun's tint. Warm reads as late day, cool as overcast or moonlight. Brightness is Sun energy, not here -- keep this near white unless you want the light itself coloured."},
	{"group": "Lighting", "node": "Sun", "prop": "rotation_degrees:x", "label": "Sun elevation", "min": -90.0, "max": 0.0, "step": 0.5,
		"tip": "How high the sun sits. Near 0 is on the horizon, throwing long raking shadows; -90 is directly overhead, giving short shadows and flat-reading surfaces."},
	{"group": "Lighting", "node": "Sun", "prop": "rotation_degrees:y", "label": "Sun azimuth", "min": -180.0, "max": 180.0, "step": 0.5,
		"tip": "Which direction the sun comes FROM. Swings shadows around the board without changing how long they are -- that is Sun elevation's job."},
	{"group": "Lighting", "node": "Sun", "prop": "shadow_enabled", "label": "Shadows",
		"tip": "Whether the sun casts shadows at all. A useful A/B when judging whether a shape reads because of the lighting or because of the sprite itself."},
	# The #226 pair: units reading as hovering is most likely peter-panning, chased by eye.
	{"group": "Lighting", "node": "Sun", "prop": "shadow_bias", "label": "Shadow bias", "min": 0.0, "max": 0.5, "step": 0.001,
		"tip": "Pushes a shadow away from the surface casting it, to stop that surface shadowing itself (acne -- a stippled, crawling look). Too high and the shadow detaches from the feet, which is what makes units read as hovering (#226)."},
	{"group": "Lighting", "node": "Sun", "prop": "shadow_normal_bias", "label": "Shadow normal bias", "min": 0.0, "max": 4.0, "step": 0.01,
		"tip": "The same trade as Shadow bias, but offsetting along the surface's facing instead of toward the light. Tuned together with it: one fixes acne on flat ground, the other on slopes."},
	{"group": "Lighting", "node": "Sun", "prop": "shadow_opacity", "label": "Shadow opacity", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "How dark a shadow goes. 1 is as dark as the ambient light allows; 0 makes shadows invisible without turning the shadow pass off."},
	{"group": "Lighting", "node": "Sun", "prop": "directional_shadow_max_distance", "label": "Shadow draw distance", "min": 10.0, "max": 300.0, "step": 1.0,
		"tip": "How far from the camera the sun still draws shadows. Lower concentrates the same shadow resolution on what is near, so shadows sharpen -- but push it too low and distant shadows vanish outright."},

	# --- Sky ---
	{"group": "Sky", "node": "WorldEnvironment", "prop": "environment:sky:sky_material:sky_top_color", "label": "Sky top",
		"tip": "The sky straight overhead. It feeds AMBIENT light as well as the visible sky, so it tints everything the sun does not hit directly -- the shadows most of all."},
	{"group": "Sky", "node": "WorldEnvironment", "prop": "environment:sky:sky_material:sky_horizon_color", "label": "Sky horizon",
		"tip": "The sky at the horizon line. The gradient between this and Sky top carries most of a sky's mood; a warm horizon under a cool top reads as dawn or dusk."},
	{"group": "Sky", "node": "WorldEnvironment", "prop": "environment:sky:sky_material:ground_horizon_color", "label": "Ground horizon",
		"tip": "The half of the procedural sky BELOW the horizon. Barely visible at this camera pitch, but it still bounces into ambient, so it warms or cools the underside of everything."},

	# --- Post ---
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:tonemap_mode", "label": "Tonemap", "options": ["Linear", "Reinhard", "Filmic", "ACES", "AgX"],
		"tip": "How light brighter than white gets squeezed into a displayable image. Linear just clips, so highlights blow out flat. Reinhard is soft and slightly washed. Filmic and ACES roll highlights off with more contrast. AgX is the flattest and most modern, and desaturates bright colour least."},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:tonemap_exposure", "label": "Exposure", "min": 0.1, "max": 4.0, "step": 0.01,
		"tip": "Overall brightness applied BEFORE tonemapping, like a camera's exposure. Prefer this over Brightness for a general 'more light' -- it keeps the highlight roll-off intact instead of flattening it."},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:tonemap_white", "label": "White point", "min": 0.1, "max": 4.0, "step": 0.01,
		"tip": "Which input brightness maps to pure white. Raise it to keep detail in bright areas for longer; lower it to blow highlights out sooner and harder."},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:glow_enabled", "label": "Glow",
		"tip": "Whether bright areas bleed light into their surroundings at all. The whole bloom stack on or off -- the four dials below do nothing while this is off."},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:glow_intensity", "label": "Glow intensity", "min": 0.0, "max": 4.0, "step": 0.01,
		"tip": "How strong the bloom is on anything that passes the threshold. The 'how much' dial."},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:glow_strength", "label": "Glow strength", "min": 0.0, "max": 2.0, "step": 0.01,
		"tip": "How far the bloom spreads before fading out. The 'how wide' dial -- bigger values give a softer, hazier halo around the same bright pixel."},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:glow_bloom", "label": "Glow bloom", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "Adds glow to EVERYTHING, not just what passes the threshold. Small values only, unless a hazy dream look is what you are after -- this is the one that quietly fogs the whole image."},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:glow_hdr_threshold", "label": "Glow HDR threshold", "min": 0.0, "max": 4.0, "step": 0.01,
		"tip": "How bright a pixel must be before it glows at all. Lower catches more of the scene (and can make ordinary lit ground shimmer); raise it to keep glow on genuine highlights like the flame."},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:ssao_enabled", "label": "SSAO",
		"tip": "Screen-space ambient occlusion: darkens creases and contact points that ambient light would struggle to reach. A cheap, strong cue for where things MEET -- especially a sprite's feet and the ground."},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:ssao_radius", "label": "SSAO radius", "min": 0.1, "max": 8.0, "step": 0.05,
		"tip": "How far around a point the effect looks for things blocking ambient light, in world units. Small values darken only tight corners; large values shade broad areas and start to look like dirt."},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:ssao_intensity", "label": "SSAO intensity", "min": 0.0, "max": 8.0, "step": 0.05,
		"tip": "How dark the occlusion goes. The most visible SSAO dial and the easiest to overdo -- past a point everything looks smudged with soot."},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:ssao_power", "label": "SSAO power", "min": 0.1, "max": 8.0, "step": 0.05,
		"tip": "The falloff curve. Higher values keep the darkening tight to the contact point instead of spreading it evenly across the radius."},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:adjustment_enabled", "label": "Colour adjust",
		"tip": "Whether the final brightness / contrast / saturation pass runs. The three dials below do nothing while this is off."},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:adjustment_brightness", "label": "Brightness", "min": 0.1, "max": 3.0, "step": 0.01,
		"tip": "Flat multiplier on the FINISHED image. Blunter than Exposure because it lifts blacks along with everything else -- reach for Exposure first."},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:adjustment_contrast", "label": "Contrast", "min": 0.1, "max": 3.0, "step": 0.01,
		"tip": "Pushes the finished image away from mid-grey. Above 1 deepens shadows and brightens highlights; below 1 flattens toward grey."},
	{"group": "Post", "node": "WorldEnvironment", "prop": "environment:adjustment_saturation", "label": "Saturation", "min": 0.0, "max": 3.0, "step": 0.01,
		"tip": "Colour intensity of the finished image. 0 is greyscale, 1 is untouched. A small lift is the cheapest way to make pixel art pop; too much and the palette turns to candy."},

	# --- Fog ---
	# The sunset preset reading as a forest fire is the case #212 was filed over.
	{"group": "Fog", "node": "WorldEnvironment", "prop": "environment:volumetric_fog_enabled", "label": "Volumetric fog",
		"tip": "A real volume of fog that light scatters THROUGH, not a flat colour laid over the image -- which is why lights carry visible shafts through it. Forward+ only, and the reason the renderer is not Mobile."},
	{"group": "Fog", "node": "WorldEnvironment", "prop": "environment:volumetric_fog_density", "label": "Fog density", "min": 0.0, "max": 0.2, "step": 0.001,
		"tip": "How thick the fog is. Tiny numbers go a long way -- this is the dial that made the sunset preset read as a forest fire, which is what got this whole panel filed (#212)."},
	{"group": "Fog", "node": "WorldEnvironment", "prop": "environment:volumetric_fog_albedo", "label": "Fog albedo",
		"tip": "The fog's own colour -- what it scatters back at you. Warm fog under a low sun reads as smoke or dust; cool fog reads as mist."},
	{"group": "Fog", "node": "WorldEnvironment", "prop": "environment:volumetric_fog_anisotropy", "label": "Fog anisotropy", "min": -0.9, "max": 0.9, "step": 0.01,
		"tip": "Which way the fog throws light. Positive scatters it forward, so a bright haze gathers around whatever is lighting it; negative scatters back toward the source; 0 scatters evenly in all directions."},

	# --- Camera framing ---
	# FRAMING only: how the board is composed, which is mood and travels with a preset. How the
	# camera DRAGS -- zoom limits, pan speed, smoothing, orbit sensitivity -- left for GameKnobs
	# with the rest of the game settings (#373), which is what makes "a mission may not re-teach
	# the controls" structural rather than a name on an exclusion list.
	# Addresses the RIG's own property since #586, not the Pitch node's rotation: the player can tilt
	# now, so _process eases that rotation every frame and a knob naming it would be the slider that
	# moves and silently reverts. This is the baseline the tilt deviates FROM, and R returns to.
	{"group": "Camera framing", "node": "CameraRig", "prop": "board_pitch_degrees", "label": "Board pitch", "min": -85.0, "max": -10.0, "step": 0.5,
		"tip": "How far the camera looks DOWN at the board when a mission OPENS. Shallow shows more of the sprites' faces and more sky; steep reads like a map. Press Re-fit camera after moving it -- the framing maths only re-runs on a board load.\n\nThe player may tilt away from this with the orbit drag and R brings them back to it, so this is the angle the board is COMPOSED at rather than the only one it is ever seen at. How far their hand may take it is two Game-tab knobs, not a mood."},
	{"group": "Camera framing", "node": "CameraRig/Pitch/Camera", "prop": "fov", "label": "FOV", "min": 12.0, "max": 70.0, "step": 0.5,
		"tip": "Field of view. Low values flatten perspective toward an orthographic, model-railway look (the HD-2D diorama trick); high values exaggerate depth and bend the board's edges. Press Re-fit camera after moving it."},
	{"group": "Camera framing", "node": ".", "prop": "opening_view_cells", "label": "Opening shot (cells)", "min": 6.0, "max": 64.0, "step": 1.0,
		"tip": "How many cells wide the view is when a mission OPENS, centred on your own units. It does not limit zoom -- the whole board still does -- it only decides where the game starts you.\n\nInert on a board that authors its own camera start (Scenario tab, #234): an authored pose says where, which way and how far, so there is no width left to derive."},
	{"group": "Camera framing", "node": "CameraRig", "prop": "fit_margin_cells", "label": "Fit margin (cells)", "min": 0.0, "max": 8.0, "step": 0.25,
		"tip": "Breathing room left around the board whenever the camera frames it, so the edge tiles are not flush against the screen."},

	# --- Depth of field ---
	# The BANDS are the knobs; the distances they produce are re-derived per frame off the live
	# camera distance, which is what stopped close zooms drifting the board into the near blur.
	{"group": "Depth of field", "node": "CameraRig", "prop": "focus_band_near", "label": "Near band", "min": 0.5, "max": 20.0, "step": 0.1,
		"tip": "How far IN FRONT of the focus point stays sharp; the near blur begins past it. The rig re-derives the actual focus distances every frame from the live camera distance, which is why those are not knobs -- static ones drifted the board into the near blur on a close zoom."},
	{"group": "Depth of field", "node": "CameraRig", "prop": "focus_band_far", "label": "Far band", "min": 0.5, "max": 20.0, "step": 0.1,
		"tip": "The same, BEHIND the focus point: how far back stays sharp before the far blur begins. Narrow both bands for the strongest miniature effect."},
	{"group": "Depth of field", "node": "CameraRig/Pitch/Camera", "prop": "attributes:dof_blur_amount", "label": "Blur amount", "min": 0.0, "max": 0.5, "step": 0.005,
		"tip": "How strong the blur gets once a pixel is outside the sharp band. The headline tilt-shift / miniature-diorama dial, and the one most worth sweeping slowly."},
	{"group": "Depth of field", "node": "CameraRig/Pitch/Camera", "prop": "attributes:dof_blur_near_enabled", "label": "Near blur",
		"tip": "Whether anything CLOSER than the sharp band blurs at all. Off is worth trying -- near blur is the half most likely to read as a smeared foreground rather than as depth."},
	{"group": "Depth of field", "node": "CameraRig/Pitch/Camera", "prop": "attributes:dof_blur_near_transition", "label": "Near transition", "min": 0.1, "max": 20.0, "step": 0.1,
		"tip": "How gradually the near blur ramps in. Small values give a hard edge where sharp becomes blurred; large values fade it in over distance."},
	{"group": "Depth of field", "node": "CameraRig/Pitch/Camera", "prop": "attributes:dof_blur_far_enabled", "label": "Far blur",
		"tip": "Whether anything BEYOND the sharp band blurs at all. This is the half that sells the diorama, by making the far edge of the board read as distant."},
	{"group": "Depth of field", "node": "CameraRig/Pitch/Camera", "prop": "attributes:dof_blur_far_transition", "label": "Far transition", "min": 0.1, "max": 20.0, "step": 0.1,
		"tip": "How gradually the far blur ramps in. Too abrupt and you can see the band's edge crossing the board as a line."},
]

# --- Identity ---------------------------------------------------------------------------

# The key a preset stores a knob under. DERIVED from what already makes a row unique, so there is
# no extra table column to keep in step -- and deliberately not the label, which reworded twice
# while this panel was being built. A preset stores key -> value and NEVER the property path:
# KNOBS is the one answer to "which property is Sun energy", so a path in a preset file would be
# a second one, and renaming a property would mean editing every preset instead of one table row.
static func preset_key(knob: Dictionary) -> String:
	return "%s|%s" % [knob["node"], knob["prop"]]


# EVERY knob, since #373 -- this table is scene mood entire, so there is nothing left to filter.
# It survives as a named answer to "what does a preset capture" rather than being inlined at its
# two call sites, because that question is one a future knob will ask again.
static func preset_knobs() -> Array[Dictionary]:
	return KNOBS


static func preset_path(preset_name: String) -> String:
	return "%s%s.tres" % [PRESET_DIR, preset_name]


# ResourceDir, never DirAccess: a source-extension filter matches nothing in an exported build
# (#141). Display names, i.e. what a dropdown shows.
static func saved_presets() -> Array[String]:
	var names: Array[String] = []
	for file: String in ResourceDir.files_with_extension(PRESET_DIR, ".tres"):
		names.append(file.trim_suffix(".tres"))
	return names


static func default_preset() -> LookPreset:
	var preset := load(DEFAULT_PATH) as LookPreset
	if preset == null:
		push_error("LookKnobs: the default look is missing or unreadable at %s" % DEFAULT_PATH)
	return preset


# "" -> the default. A name that no longer resolves -> the default, LOUDLY: silently rendering a
# mission with whatever the scene happens to hold is exactly the missions doctrine's failure shape
# (a declared-but-missing objective reads PENDING rather than vanishing), because a broken map
# must say so instead of quietly becoming a different playable one.
static func resolve(preset_name: String) -> LookPreset:
	if preset_name == "":
		return default_preset()
	var path := preset_path(preset_name)
	if not ResourceLoader.exists(path):
		push_error("LookKnobs: this board names look preset '%s', which no longer exists -- falling back to the default" % preset_name)
		return default_preset()
	var preset := load(path) as LookPreset
	if preset == null:
		push_error("LookKnobs: '%s' did not load as a LookPreset -- falling back to the default" % preset_name)
		return default_preset()
	return preset


# --- Reading and writing against a host --------------------------------------------------

static func target_of(host: Node3D, knob: Dictionary) -> Node:
	if host == null:
		return null
	var path: String = knob["node"]
	if path == ".":
		return host
	return host.get_node_or_null(NodePath(path))


static func read(host: Node3D, knob: Dictionary) -> Variant:
	var target := target_of(host, knob)
	if target == null:
		return null
	return target.get_indexed(NodePath(knob["prop"]))


static func write(host: Node3D, knob: Dictionary, value: Variant) -> void:
	var target := target_of(host, knob)
	if target == null:
		return
	target.set_indexed(NodePath(knob["prop"]), value)


# Every in-scope knob, always -- a preset is self-contained, so re-tuning Battle3D.tscn later can
# never silently move a saved mood (dev call). The twin cost is that a preset saved today does not
# mention a knob added tomorrow, which apply() reports rather than hiding.
static func capture(host: Node3D, preset_name: String) -> LookPreset:
	var preset := LookPreset.new()
	preset.preset_name = preset_name
	if host == null:
		return preset
	for knob: Dictionary in preset_knobs():
		var value: Variant = read(host, knob)
		if typeof(value) != TYPE_NIL:
			preset.values[preset_key(knob)] = value
	return preset


# Returns {"missing": Array[String] of knob labels, "unknown": Array[String] of dead keys} so the
# caller can SAY both. A knob the preset PREDATES falls back to the default's value and is still
# named -- written, never left alone, so a load lands on the same look whatever was on screen
# first; without that, preset B silently inherits preset A for every knob B predates.
static func apply(host: Node3D, preset: LookPreset) -> Dictionary:
	var missing: Array[String] = []
	var unknown: Array[String] = []
	if host == null or preset == null:
		return {"missing": missing, "unknown": unknown}
	var fallback: Dictionary = {}
	var default_look := default_preset()
	if default_look != null and default_look != preset:
		fallback = default_look.values
	var applied := {}
	for knob: Dictionary in preset_knobs():
		var key := preset_key(knob)
		if preset.values.has(key):
			applied[key] = true
			write(host, knob, preset.values[key])
			continue
		missing.append(knob["label"])
		if fallback.has(key):
			write(host, knob, fallback[key])
	for key: String in preset.values:
		if not applied.has(key):
			unknown.append(key)
	# Pitch and FOV feed framing maths that only re-runs on a board load -- the same reason the
	# Moods tab has a Re-fit button. Without this a loaded preset frames with the old camera.
	if host.has_method("fit_camera"):
		host.fit_camera()
	return {"missing": missing, "unknown": unknown}


# "Has this moved?" -- approximate for floats, because a value written and read straight back is
# not always bit-identical: engine properties store single-precision, and a euler component
# round-trips through a basis. An exact compare reported the sun and board pitch as still changed
# immediately after a Reset had put them back.
static func same_value(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_FLOAT:
			return is_equal_approx(a, b)
		TYPE_COLOR:
			return (a as Color).is_equal_approx(b)
		TYPE_VECTOR2:
			return (a as Vector2).is_equal_approx(b)
		TYPE_VECTOR3:
			return (a as Vector3).is_equal_approx(b)
	return a == b
