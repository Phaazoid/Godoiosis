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
# Tuning SAVES as of #253: a named LookPreset under Resources/LookPresets/ captures the scene-mood
# knobs, and loading one makes it the baseline everything else measures against. Copy Values still
# exists beside it and still diffs the AUTHORED scene, because its output is paste-ready lines FOR
# Battle3D.tscn -- diffed against a loaded preset those lines would not reproduce what you see.
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

	# --- Camera ---
	{"group": "Camera", "node": "CameraRig/Pitch", "prop": "rotation_degrees:x", "label": "Board pitch", "min": -85.0, "max": -10.0, "step": 0.5,
		"tip": "How far the camera looks DOWN at the board. Shallow shows more of the sprites' faces and more sky; steep reads like a map. Press Re-fit camera after moving it -- the framing maths only re-runs on a board load."},
	{"group": "Camera", "node": "CameraRig/Pitch/Camera", "prop": "fov", "label": "FOV", "min": 12.0, "max": 70.0, "step": 0.5,
		"tip": "Field of view. Low values flatten perspective toward an orthographic, model-railway look (the HD-2D diorama trick); high values exaggerate depth and bend the board's edges. Press Re-fit camera after moving it."},
	{"group": "Camera", "node": ".", "prop": "opening_view_cells", "label": "Opening shot (cells)", "min": 6.0, "max": 64.0, "step": 1.0,
		"tip": "How many cells wide the view is when a mission OPENS, centred on your own units. It does not limit zoom -- the whole board still does -- it only decides where the game starts you."},
	{"group": "Camera", "node": "CameraRig", "prop": "min_distance", "label": "Zoom-in limit", "min": 2.0, "max": 20.0, "step": 0.25,
		"tip": "How close the camera may get. Too close and sprites outrun their own pixel density."},
	{"group": "Camera", "node": "CameraRig", "prop": "zoom_step", "label": "Zoom step", "min": 0.25, "max": 5.0, "step": 0.05,
		"tip": "How far one notch of the mouse wheel moves the camera."},
	{"group": "Camera", "node": "CameraRig", "prop": "smoothing", "label": "Camera smoothing", "min": 1.0, "max": 24.0, "step": 0.1,
		"tip": "How fast the camera catches up to where it has been told to go. Higher is snappier and more responsive; lower glides, which reads as cinematic until you are trying to play."},
	{"group": "Camera", "node": "CameraRig", "prop": "pan_speed", "label": "Pan speed", "min": 1.0, "max": 30.0, "step": 0.5,
		"tip": "How fast WASD slides the camera across the board, in world units per second."},
	{"group": "Camera", "node": "CameraRig", "prop": "orbit_sensitivity", "label": "Orbit sensitivity", "min": 0.02, "max": 1.0, "step": 0.01,
		"tip": "Degrees the view swings per pixel of mouse travel while dragging to orbit."},
	{"group": "Camera", "node": "CameraRig", "prop": "pan_margin_cells", "label": "Pan margin (cells)", "min": 0.0, "max": 12.0, "step": 0.5,
		"tip": "How far past the board's edge you may pan before being stopped. Some slack keeps a corner unit from being pinned against the screen edge."},
	{"group": "Camera", "node": "CameraRig", "prop": "fit_margin_cells", "label": "Fit margin (cells)", "min": 0.0, "max": 8.0, "step": 0.25,
		"tip": "Breathing room left around the board whenever the camera frames it, so the edge tiles are not flush against the screen."},
	{"group": "Camera", "node": "CameraRig", "prop": "zoom_out_slack", "label": "Zoom-out slack", "min": 0.5, "max": 3.0, "step": 0.05,
		"tip": "How far past the whole board you may zoom out. 1.0 means the board exactly fills the view at full zoom-out; above 1 lets you pull back and see it sitting in the world."},

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

	# --- Board markup ---
	# fill_lift and lift_step raise every ground marker together, arrows included. A lift the
	# ARROWS own alone (#227) needs its own export on BoardOverlays -- not in this slice.
	{"group": "Board markup", "node": "BoardOverlays", "prop": "fill_lift", "label": "Marker lift", "min": 0.0, "max": 0.5, "step": 0.001,
		"tip": "How far every ground marker floats above the tile's top face. Enough to beat z-fighting (the flickering where two surfaces share a plane) and no more -- too much and the markup visibly hovers."},
	{"group": "Board markup", "node": "BoardOverlays", "prop": "lift_step", "label": "Per-layer lift step", "min": 0.0, "max": 0.05, "step": 0.0005,
		"tip": "Extra lift per sort layer, so stacked markers never land on exactly the same plane and fight. Also what keeps path arrows drawing over the move fill rather than through it."},
	{"group": "Board markup", "node": "BoardOverlays", "prop": "bracket_arm", "label": "Bracket arm", "min": 0.05, "max": 0.5, "step": 0.005,
		"tip": "Length of each arm of the corner bracket that marks the hovered cell. Short arms read as corner ticks; long ones close into a full box."},
	{"group": "Board markup", "node": "BoardOverlays", "prop": "bracket_thickness", "label": "Bracket thickness", "min": 0.005, "max": 0.2, "step": 0.001,
		"tip": "How chunky the hover bracket's arms are. Thin reads precise, thick reads legible at a distance."},
	{"group": "Board markup", "node": "BoardOverlays", "prop": "bracket_scale", "label": "Bracket scale", "min": 0.9, "max": 1.3, "step": 0.005,
		"tip": "Size of the whole hover bracket relative to one cell. Just above 1 makes it sit proud of the tile edge so it is not swallowed by the tile art."},
	{"group": "Board markup", "node": "BoardOverlays", "prop": "invalid_bracket_color", "label": "Invalid bracket tint",
		"tip": "What the hover bracket turns over a cell the 2D game calls invalid -- unwalkable, occupied, or a paint the tile brush would refuse. It mirrors the 2D cursor's own verdict rather than deciding for itself."},
	{"group": "Board markup", "node": "BoardOverlays", "prop": "billboard_lift", "label": "Icon height", "min": 0.0, "max": 3.0, "step": 0.01,
		"tip": "How high a selection icon floats above the cell it marks. High enough to clear the unit standing there, low enough not to read as belonging to the cell behind."},
	{"group": "Board markup", "node": "BoardOverlays", "prop": "billboard_pixel_size", "label": "Icon pixel size", "min": 0.004, "max": 0.1, "step": 0.001,
		"tip": "World size of ONE pixel of a billboard icon. 1/32 matches the tile art's density; mixing densities is the loudest amateur tell in HD-2D, so change this only with the art in view."},

	# --- Effects ---
	{"group": "Effects", "node": "BoardMirror", "prop": "flame_lift", "label": "Flame lift", "min": 0.0, "max": 2.0, "step": 0.01,
		"tip": "How high the fire billboard's centre sits above a burning tile. Raising it makes fire read as standing up off the ground rather than lying on it."},
	{"group": "Effects", "node": "BoardMirror", "prop": "flame_size:x", "label": "Flame width", "min": 0.1, "max": 2.0, "step": 0.01,
		"tip": "Width of the fire billboard in world units, where 1.0 is exactly one cell across."},
	{"group": "Effects", "node": "BoardMirror", "prop": "flame_size:y", "label": "Flame height", "min": 0.1, "max": 2.0, "step": 0.01,
		"tip": "Height of the fire billboard in world units. Taller than wide reads as a flame; square reads as a scorch."},
	{"group": "Effects", "node": "BoardMirror", "prop": "flame_ground_gap", "label": "Flame ground gap", "min": 0.0, "max": 0.5, "step": 0.005,
		"tip": "Gap between the base of the flame and the tile surface. A small gap stops the flame z-fighting the ground it stands on; too large and the fire floats."},
	{"group": "Effects", "node": "BoardMirror", "prop": "flame_writes_depth", "label": "Flame writes depth",
		"tip": "Whether the flame writes into the depth buffer. On, it occludes what is behind it correctly but can cut a hard edge against overlapping sprites; off, it always draws as a soft overlay and never clips."},
	{"group": "Effects", "node": "BoardMirror", "prop": "flame_light_energy", "label": "Flame light energy", "min": 0.0, "max": 8.0, "step": 0.05,
		"tip": "Brightness of the real point light each fire casts. This is what makes fire LIGHT the board -- units, walls and neighbouring tiles -- rather than merely glow on its own tile."},
	{"group": "Effects", "node": "BoardMirror", "prop": "flame_light_range", "label": "Flame light range", "min": 0.5, "max": 12.0, "step": 0.1,
		"tip": "How far a fire's light reaches, in world units (roughly cells). Range and energy together decide whether a burning tile lights a room or just its own corner."},
	{"group": "Effects", "node": "BoardMirror", "prop": "brush_ghost_alpha", "label": "Brush ghost alpha", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "Opacity of the dev tile brush's preview block -- the ghost showing what you are about to paint. Dev-only; players never see it."},
]

# Board-markup colours (#212 slice 2). A DECLARED second table rather than a widening of KNOBS:
# those entries address a property path through get_indexed/set_indexed, these address a LAYER
# through an accessor pair, and one table meaning both would hide the difference that matters.
#
# Which layers appear here is measured, not chosen. `set_layer_modulate` REPLACES a layer's albedo,
# so any layer something already drives per frame would take a knob that silently reverts -- the
# lying-slider class. Excluded for that reason: ATTACK's 3D side and AIM (OverlayMirror rewrites
# both from the 2D every poll) and HOVER (battle3d._sync_bracket_tint). ZONE_PATROL/ZONE_HIGHLIGHT
# are excluded as authoring-only -- invisible during real play, and they READ OverlayManager's
# constants, so a knob would fork a value that is deliberately one (dev call).
#
# `reach` entries are the exception that proves it: ATTACK has no 3D-only colour to tune, because
# the 3D mirrors the 2D's modulate rather than holding an answer. Tuning it moves BOTH stacks.
const LAYER_KNOBS: Array[Dictionary] = [
	{"group": "Board markup colours", "label": "Move fill", "layer": BoardOverlays.Layer.MOVE,
		"tip": "The tiles a unit can reach while you are ordering a move. Alpha is the dial that matters most -- markup has to read as gameplay information without burying the terrain under it."},
	{"group": "Board markup colours", "label": "Invalid-move fill", "layer": BoardOverlays.Layer.INVALID_MOVE,
		"tip": "Tiles inside a unit's movement range that it still may not stop on -- out of its leader's cohesion range, or already occupied. Clicking one does nothing, so this colour is the only warning."},
	{"group": "Board markup colours", "label": "Squad fill", "layer": BoardOverlays.Layer.SQUAD,
		"tip": "Marks the members of the currently selected squad."},
	{"group": "Board markup colours", "label": "Squad-range fill", "layer": BoardOverlays.Layer.SQUAD_RANGE,
		"tip": "The leader's cohesion range -- how far squadmates may stray before the plan is refused. Shares its colour with Squad fill by default, since they are two halves of the same idea."},
	{"group": "Board markup colours", "label": "Capture zone", "layer": BoardOverlays.Layer.ZONE_CAPTURE,
		"tip": "A painted objective zone that can be captured. Stays visible for the whole battle -- this is live objective information, not authoring scaffolding."},
	{"group": "Board markup colours", "label": "Extraction zone", "layer": BoardOverlays.Layer.ZONE_EXTRACTION,
		"tip": "A painted zone your units must reach to extract. Also visible all battle."},
	{"group": "Board markup colours", "label": "Attack reach (2D+3D)", "reach": "ATTACK_MODULATE",
		"tip": "The reach fill while aiming a damaging attack. Red reads as hostile, which is the whole reason a healing pick paints green instead."},
	{"group": "Board markup colours", "label": "Heal reach (2D+3D)", "reach": "HEAL_ATTACK_MODULATE",
		"tip": "The same reach fill when the pick HEALS. Forked off the attack's own heals flag, so an attack cannot paint the wrong colour for what it does."},
]

const HEADING_COLOR := Color(1, 0.83, 0.4, 1)   # the Scenario tab's heading gold

# Which SUB-TAB each group lands on (dev, 2026-08-14: ~60 rows in one scroll is too much for a
# 900x360 window, so split to about a windowful each). A map rather than a key on every knob, so
# adding a knob stays one line and adding a GROUP is one line here -- and a group with no tab is a
# group that silently vanishes from the panel, which is why a law test pins the mapping complete.
# Declaration order below is the tab order.
const GROUP_TABS: Dictionary[String, String] = {
	"Lighting": "Lighting",
	"Sky": "Lighting",
	"Post": "Post",
	"Fog": "Fog & DoF",
	"Depth of field": "Fog & DoF",
	"Camera": "Camera",
	"Board markup": "Markup",
	"Board markup colours": "Markup",
	"Effects": "Effects",
}

# --- Presets (#253 part 1) ---------------------------------------------------------------

const PRESET_DIR := "res://Resources/LookPresets/"
const AUTHORED_ENTRY := "(authored scene)"   # dropdown row 0: the way back to Battle3D.tscn

# A preset is SCENE MOOD, not game settings (dev, 2026-08-15). Everything in KNOBS is captured
# unless it is named here; LAYER_KNOBS is out wholesale, so a preset never touches board-markup
# colour. Excluded for three separate reasons, all the same rule -- a MISSION must not be able to
# change these, because they are things the player learns once and keeps:
#   * camera HANDLING -- how the camera drags, not how the board is framed. Pitch/FOV/opening
#     shot/fit margin ARE framing and stay in.
#   * board MARKUP -- gameplay legibility. Its geometry as much as its colour.
#   * the brush ghost -- dev chrome; players never see it.
# The default is IN: a knob added later joins presets unless someone lists it here, which is right
# for a look knob and wrong for a future handling one. A law test pins every key to a real knob, so
# a renamed property fails loudly instead of silently un-excluding itself.
const PRESET_EXCLUDED: Array[String] = [
	"CameraRig|min_distance",
	"CameraRig|zoom_step",
	"CameraRig|smoothing",
	"CameraRig|pan_speed",
	"CameraRig|orbit_sensitivity",
	"CameraRig|pan_margin_cells",
	"CameraRig|zoom_out_slack",
	"BoardOverlays|fill_lift",
	"BoardOverlays|lift_step",
	"BoardOverlays|bracket_arm",
	"BoardOverlays|bracket_thickness",
	"BoardOverlays|bracket_scale",
	"BoardOverlays|invalid_bracket_color",
	"BoardOverlays|billboard_lift",
	"BoardOverlays|billboard_pixel_size",
	"BoardMirror|brush_ghost_alpha",
]

var _host: Node3D                # the Battle3D scene; pushed in, never looked up
var _authored: Array = []        # the scene's own value per KNOBS index, read once on attach
var _baseline: Array = []        # what Reset returns to: _authored, or a loaded preset over it
var _layer_baseline: Array = []  # the same, per LAYER_KNOBS index (presets never touch these)
var _loaded_preset := ""         # dropdown-relative name; "" = the authored scene
var _tabs: TabContainer
var _tab_rows: Dictionary[String, VBoxContainer] = {}   # tab title -> its row container
var _status: Label
var _preset_name_input: LineEdit
var _preset_dropdown: OptionButton
var _update_button: Button
var _delete_button: Button


func _ready() -> void:
	_build_preset_row()
	var buttons := HBoxContainer.new()
	buttons.add_child(_button("Copy changed values",
		"Copy every value moved off the SCENE's authored setting to the clipboard, as paste-ready\nGDScript. Always measured against Battle3D.tscn, never against a loaded preset -- these lines\nare what you paste INTO the scene, so a preset-relative diff would not reproduce what you see.",
		_on_copy_pressed))
	buttons.add_child(_button("Reset",
		"Put every knob back to the loaded preset, or to the scene's authored values when no preset\nis loaded", _on_reset_pressed))
	buttons.add_child(_button("Re-fit camera",
		"Pitch and FOV feed the framing maths, which only runs on a board load -- press this after moving either",
		_on_refit_pressed))
	add_child(buttons)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	# Buttons and status sit ABOVE the sub-tabs and outside them, so they are reachable from every
	# tab (dev ask) -- Reset and Re-fit are panel-wide, not per-group.
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_tabs)
	for tab_title: String in _tab_titles():
		var scroll := ScrollContainer.new()
		scroll.name = tab_title
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_tabs.add_child(scroll)
		var rows := VBoxContainer.new()
		rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(rows)
		_tab_rows[tab_title] = rows
	refresh_preset_dropdown()   # after _status exists: a refusal has somewhere to print
	_rebuild()


# Called by battle3d._ready. The 2D game boots first (Godot readies children before parents), so
# the tab always builds its no-host state and then rebuilds here.
func attach_host(host: Node3D) -> void:
	_host = host
	_authored.clear()
	for knob: Dictionary in KNOBS:
		_authored.append(read(knob))   # authored by definition: nothing has moved one yet
	_baseline = _authored.duplicate()  # no preset loaded yet, so Reset means "back to the scene"
	_layer_baseline.clear()
	for knob: Dictionary in LAYER_KNOBS:
		_layer_baseline.append(read_layer(knob))
	_rebuild()


# --- Board-markup colours ---------------------------------------------------------------

func _overlays() -> BoardOverlays:
	if _host == null:
		return null
	return _host.get_node_or_null(^"BoardOverlays") as BoardOverlays


# A reach colour is a STATIC var, and Object.get/set are instance methods -- there is no reflecting
# on the class, so the two names are matched explicitly. An unknown one is a loud failure rather
# than a silently dead knob.
func read_layer(knob: Dictionary) -> Variant:
	if knob.has("reach"):
		match knob["reach"]:
			"ATTACK_MODULATE": return OverlayManager.ATTACK_MODULATE
			"HEAL_ATTACK_MODULATE": return OverlayManager.HEAL_ATTACK_MODULATE
		push_error("LookTool: unknown reach colour %s" % knob["reach"])
		return null
	var overlays := _overlays()
	if overlays == null:
		return null
	return overlays.layer_modulate(knob["layer"])


func write_layer(knob: Dictionary, color: Color) -> void:
	if knob.has("reach"):
		# The static var IS the authority; the live 2D fill is re-derived from it so the tuned
		# colour shows now rather than at the next aim (the 3D mirrors that fill, not the var).
		match knob["reach"]:
			"ATTACK_MODULATE": OverlayManager.ATTACK_MODULATE = color
			"HEAL_ATTACK_MODULATE": OverlayManager.HEAL_ATTACK_MODULATE = color
			_:
				push_error("LookTool: unknown reach colour %s" % knob["reach"])
				return
		var om: OverlayManager = _overlay_manager()
		if om != null:
			om.refresh_attack_reach_color()
		return
	var overlays := _overlays()
	if overlays != null:
		overlays.set_layer_modulate(knob["layer"], color)


func _overlay_manager() -> OverlayManager:
	if _host == null:
		return null
	var game: Node2D = _host.game
	if game == null:
		return null
	return game.overlay_manager as OverlayManager


func layer_baseline_of(index: int) -> Variant:
	if index < 0 or index >= _layer_baseline.size():
		return null
	return _layer_baseline[index]


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


# What Reset returns to -- the loaded preset if there is one, else the authored scene.
func baseline_of(index: int) -> Variant:
	if index < 0 or index >= _baseline.size():
		return null
	return _baseline[index]


# What the SCENE was authored with, whatever is loaded. Copy Values' reference point, because its
# output is lines you paste into Battle3D.tscn.
func authored_of(index: int) -> Variant:
	if index < 0 or index >= _authored.size():
		return null
	return _authored[index]


# --- Building the rows ------------------------------------------------------------------

# Tab titles in GROUP_TABS declaration order, de-duplicated -- the order the sub-tabs appear in.
func _tab_titles() -> Array[String]:
	var titles: Array[String] = []
	for group: String in GROUP_TABS:
		var title: String = GROUP_TABS[group]
		if not titles.has(title):
			titles.append(title)
	return titles


# Where a group's rows go. A group missing from GROUP_TABS would otherwise draw nowhere at all,
# so it lands on the first tab and says so; the law test is what stops that shipping.
func _rows_for_group(group: String) -> VBoxContainer:
	if not GROUP_TABS.has(group):
		push_error("LookTool: group '%s' has no tab in GROUP_TABS" % group)
		return _tab_rows[_tab_titles()[0]]
	return _tab_rows[GROUP_TABS[group]]


func _rebuild() -> void:
	var showing := _tabs.current_tab   # a Reset must not bounce you off the tab you were tuning
	for rows: VBoxContainer in _tab_rows.values():
		for child in rows.get_children():
			rows.remove_child(child)
			child.queue_free()
	if _host == null:
		DevWidgets.add_label(_tab_rows[_tab_titles()[0]],
			"No 3D host attached - the flat 2D game has no look stack to tune.")
		return
	var group := ""
	for knob: Dictionary in KNOBS:
		var knob_group: String = knob["group"]
		var rows := _rows_for_group(knob_group)
		if knob_group != group:
			group = knob_group
			_add_heading(rows, group)
		_build_row(rows, knob)
	var layer_group: String = LAYER_KNOBS[0]["group"]
	var layer_rows := _rows_for_group(layer_group)
	_add_heading(layer_rows, layer_group)
	for knob: Dictionary in LAYER_KNOBS:
		var value: Variant = read_layer(knob)
		if typeof(value) != TYPE_COLOR:
			DevWidgets.add_label(layer_rows, "%s - UNRESOLVED" % knob["label"])
			push_error("LookTool layer knob does not resolve: %s" % knob["label"])
			continue
		var first := layer_rows.get_child_count()
		DevWidgets.add_color(layer_rows, knob["label"], value,
			func(picked: Color) -> void: write_layer(knob, picked))
		_apply_tip(layer_rows, first, tip_for(knob))
	_tabs.current_tab = clampi(showing, 0, maxi(0, _tabs.get_tab_count() - 1))


# The which-stack note is appended per KIND rather than typed into each tip, so it cannot drift
# out of step with the table it describes.
func tip_for(knob: Dictionary) -> String:
	var tip: String = knob.get("tip", "")
	if knob.has("layer"):
		tip += "\n\n3D ONLY -- the flat 2D board keeps its own colour. A declared divergence, and provisional: tune it, look at it, then decide whether 2D should follow."
	elif knob.has("reach"):
		tip += "\n\nMOVES BOTH STACKS -- the 3D mirrors the 2D's fill rather than holding a colour of its own, so this tunes OverlayManager and the flat 2D game changes with it."
	return DevWidgets.wrap_tooltip(tip)


# Every control the row added, so hovering the slider handle answers as well as the label.
func _apply_tip(rows: VBoxContainer, first_index: int, tip: String) -> void:
	for i in range(first_index, rows.get_child_count()):
		DevWidgets.apply_tooltip(rows.get_child(i), tip)


func _build_row(rows: VBoxContainer, knob: Dictionary) -> void:
	var value: Variant = read(knob)
	var label: String = knob["label"]
	# An unresolved knob is a table entry pointing at a renamed or moved property. Say so on the
	# panel AND in the log rather than drawing a row that edits nothing.
	if typeof(value) == TYPE_NIL:
		DevWidgets.add_label(rows, "%s - UNRESOLVED (%s:%s)" % [label, knob["node"], knob["prop"]])
		push_error("LookTool knob does not resolve: %s:%s" % [knob["node"], knob["prop"]])
		return
	var first := rows.get_child_count()
	if knob.has("options"):
		var options: Array = knob["options"]
		var current: int = int(value)
		var current_label: String = options[current] if current >= 0 and current < options.size() else ""
		DevWidgets.add_option(rows, label, options, current_label,
			func(picked: String) -> void: write(knob, options.find(picked)))
	else:
		match typeof(value):
			TYPE_BOOL:
				DevWidgets.add_checkbox(rows, label, value,
					func(on: bool) -> void: write(knob, on))
			TYPE_COLOR:
				DevWidgets.add_color(rows, label, value,
					func(picked: Color) -> void: write(knob, picked))
			_:
				var low: float = knob["min"]
				var high: float = knob["max"]
				var step: float = knob["step"]
				DevWidgets.add_slider(rows, label, value, low, high, step,
					func(moved: float) -> void: write(knob, moved))
	_apply_tip(rows, first, tip_for(knob))


func _add_heading(rows: VBoxContainer, text: String) -> void:
	if rows.get_child_count() > 0:
		rows.add_child(HSeparator.new())
	var heading := Label.new()
	heading.text = text
	heading.add_theme_color_override("font_color", HEADING_COLOR)
	rows.add_child(heading)


func _button(text: String, tooltip: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(on_pressed)
	return button


# --- Presets ----------------------------------------------------------------------------

# The key a preset stores a knob under. DERIVED from what already makes a row unique, so there is
# no extra table column to keep in step -- and deliberately not the label, which reworded twice
# while this panel was being built. A preset stores key -> value and NEVER the property path:
# KNOBS is the one answer to "which property is Sun energy", so a path in a preset file would be a
# second one, and renaming a property would mean editing every preset instead of one table row.
static func preset_key(knob: Dictionary) -> String:
	return "%s|%s" % [knob["node"], knob["prop"]]


static func preset_knobs() -> Array[Dictionary]:
	var wanted: Array[Dictionary] = []
	for knob: Dictionary in KNOBS:
		if not PRESET_EXCLUDED.has(preset_key(knob)):
			wanted.append(knob)
	return wanted


static func preset_path(preset_name: String) -> String:
	return "%s%s.tres" % [PRESET_DIR, preset_name]


# ResourceDir, never DirAccess: a source-extension filter matches nothing in an exported build
# (#141). Display names, i.e. what the dropdown shows.
static func saved_presets() -> Array[String]:
	var names: Array[String] = []
	for file: String in ResourceDir.files_with_extension(PRESET_DIR, ".tres"):
		names.append(file.trim_suffix(".tres"))
	return names


func loaded_preset() -> String:
	return _loaded_preset


# Every in-scope knob, always -- a preset is self-contained, so re-tuning Battle3D.tscn later can
# never silently move a saved mood (dev call). The cost is the twin: a preset saved today does not
# mention a knob added tomorrow, which apply_preset reports rather than hiding.
func capture_preset(preset_name: String) -> LookPreset:
	var preset := LookPreset.new()
	preset.preset_name = preset_name
	if _host == null:
		return preset
	for knob: Dictionary in preset_knobs():
		var value: Variant = read(knob)
		if typeof(value) != TYPE_NIL:
			preset.values[preset_key(knob)] = value
	return preset


# Returns {"missing": Array[String] of knob labels, "unknown": Array[String] of dead keys} so the
# caller can SAY both. A knob the preset predates keeps its authored value; a saved key that no
# longer matches an in-scope knob is skipped. Neither is silent: a preset quietly rendering with
# whatever the scene happens to hold is the failure this reports its way out of.
func apply_preset(preset: LookPreset) -> Dictionary:
	var missing: Array[String] = []
	var unknown: Array[String] = []
	if _host == null or preset == null:
		return {"missing": missing, "unknown": unknown}
	var applied := {}
	_baseline = _authored.duplicate()
	for i in KNOBS.size():
		var knob: Dictionary = KNOBS[i]
		var key := preset_key(knob)
		if PRESET_EXCLUDED.has(key):
			continue
		if not preset.values.has(key):
			missing.append(knob["label"])
			# WRITTEN back to authored, not merely left alone: loading a preset has to land on the
			# same look whatever was on screen first, or preset B silently inherits preset A's
			# value for every knob B predates.
			var authored: Variant = authored_of(i)
			if typeof(authored) != TYPE_NIL:
				write(knob, authored)
			continue
		applied[key] = true
		write(knob, preset.values[key])
		# Read BACK: the baseline must be what the property ACCEPTED, not what was asked for, or
		# Reset chases a value the engine never stored and every knob reads as permanently moved.
		_baseline[i] = read(knob)
	for key: String in preset.values:
		if not applied.has(key):
			unknown.append(key)
	# Pitch and FOV feed framing maths that only re-runs on a board load -- the same reason the
	# Re-fit button exists. Without this a loaded preset frames the board with the old camera.
	_host.fit_camera()
	_rebuild()
	return {"missing": missing, "unknown": unknown}


func _build_preset_row() -> void:
	var top := HBoxContainer.new()
	var label := Label.new()
	label.text = "Preset"
	top.add_child(label)
	_preset_dropdown = OptionButton.new()
	_preset_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_dropdown.item_selected.connect(func(_index: int) -> void: _refresh_preset_buttons())
	top.add_child(_preset_dropdown)
	top.add_child(_button("Load", "Apply the picked preset to the live scene", _on_load_pressed))
	_update_button = _button("Update", "", _on_update_pressed)
	top.add_child(_update_button)
	_delete_button = _button("Delete", "", _on_delete_pressed)
	top.add_child(_delete_button)
	add_child(top)

	var bottom := HBoxContainer.new()
	_preset_name_input = LineEdit.new()
	_preset_name_input.placeholder_text = "New preset name"
	_preset_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_preset_name_input)
	bottom.add_child(_button("Save As",
		"Save every scene-mood knob under a new name. Camera handling, board markup and the brush\nghost are deliberately not captured -- those are game settings, not a mission's look.",
		_on_save_as_pressed))
	add_child(bottom)


# select_name is a display name. Empty re-selects whatever was showing, so a rebuild never silently
# moves Update's target.
func refresh_preset_dropdown(select_name := "") -> void:
	if select_name == "":
		select_name = DevWidgets.selected_name(_preset_dropdown)
	_preset_dropdown.clear()
	_preset_dropdown.add_item(AUTHORED_ENTRY)
	for preset_name: String in saved_presets():
		_preset_dropdown.add_item(preset_name)
	# add_item auto-selects index 0 -- force the match rather than inheriting it, or a deleted
	# preset leaves the selection silently pointing at the authored row.
	_preset_dropdown.select(-1)
	for i in _preset_dropdown.item_count:
		if _preset_dropdown.get_item_text(i) == select_name:
			_preset_dropdown.select(i)
			break
	if _preset_dropdown.selected < 0:
		# Falling back to row 0 is safe here and only here: the authored row is not a FILE, so
		# _refresh_preset_buttons reads it as no target and greys both Update and Delete. That is
		# the whole reason the auto-select trap bites elsewhere -- there, row 0 is a write target.
		_preset_dropdown.select(0)
	_refresh_preset_buttons()


func _refresh_preset_buttons() -> void:
	var target := DevWidgets.selected_name(_preset_dropdown)
	if target == AUTHORED_ENTRY:
		target = ""   # not a file: nothing to update, nothing to delete
	DevWidgets.refresh_update_button(_update_button, target, "preset", update_block_reason())
	DevWidgets.refresh_delete_button(_delete_button, target, "preset")


# "" = allowed. Update only ever writes the LOADED preset back over its own file -- the 2026-08-11
# scenario rule, for the same reason: aiming Update at a preset you have not loaded overwrites it
# with a look you were never looking at.
func update_block_reason() -> String:
	var target := DevWidgets.selected_name(_preset_dropdown)
	if target == "" or target == AUTHORED_ENTRY:
		return ""
	if target != _loaded_preset:
		return "Load '%s' before updating it -- Update saves the live look back over its own file" % target
	return ""


func _on_load_pressed() -> void:
	if _host == null:
		return
	var target := DevWidgets.selected_name(_preset_dropdown)
	if target == "" or target == AUTHORED_ENTRY:
		_load_authored()
		return
	var preset := load(preset_path(target)) as LookPreset
	if preset == null:
		_status.text = "Could not load preset '%s'" % target
		push_error("LookTool: preset failed to load: %s" % preset_path(target))
		return
	var report := apply_preset(preset)
	_loaded_preset = target
	_refresh_preset_buttons()
	_status.text = _load_report(target, report)


# The way back to Battle3D.tscn's own look, and the reason the dropdown has a row 0: once Reset
# means "back to the loaded preset", the authored scene is otherwise unreachable.
func _load_authored() -> void:
	_baseline = _authored.duplicate()
	_loaded_preset = ""
	_on_reset_pressed()
	_refresh_preset_buttons()
	_status.text = "Loaded the scene's authored look. Reset now returns here."


func _load_report(target: String, report: Dictionary) -> String:
	var text := "Loaded preset '%s'. Reset now returns here." % target
	var missing: Array = report["missing"]
	if not missing.is_empty():
		text += ("\n%d knob(s) added since this preset was saved, left at the scene's value: %s."
			+ " Set them and press Update to back-add.") % [missing.size(), ", ".join(missing)]
	var unknown: Array = report["unknown"]
	if not unknown.is_empty():
		text += "\n%d saved value(s) no longer apply (knob removed or now excluded): %s." \
			% [unknown.size(), ", ".join(unknown)]
	return text


func _on_save_as_pressed() -> void:
	if _host == null:
		_status.text = "No 3D host attached - there is no look to save."
		return
	var entered := _preset_name_input.text.strip_edges()
	if entered == "":
		var msg := "Preset needs a name"
		push_warning(msg)
		_status.text = msg
		return
	# Flat folder, so no allow_slash: a '/' would land the file where the scan never looks (#168).
	if DevWidgets.refuse_illegal_name(entered, "preset", _status):
		return
	if entered == AUTHORED_ENTRY:
		_status.text = "'%s' is the dropdown's own name for the scene - pick another" % AUTHORED_ENTRY
		return
	if DevWidgets.refuse_existing_file(preset_path(entered), "preset", _status):
		return
	if not DevWidgets.save_over(capture_preset(entered), preset_path(entered), _status):
		return
	# Saving is also loading: the look on screen IS this preset now, so Reset should return to it.
	_baseline = _live_values()
	_loaded_preset = entered
	_preset_name_input.text = ""
	refresh_preset_dropdown(entered)
	_status.text = "Saved preset '%s' (%d knobs). Reset now returns here." % [entered, preset_knobs().size()]


func _on_update_pressed() -> void:
	var target := DevWidgets.selected_name(_preset_dropdown)
	if target == "" or target == AUTHORED_ENTRY:
		return
	# The handler is the real gate; the greyed button is only its surface (#166 shape).
	var reason := update_block_reason()
	if reason != "":
		_status.text = reason
		return
	# Confirmed as well as load-gated (the 2026-08-12 scenario call): the gate cannot catch a
	# mis-click at the file you DID load, which is exactly how a tuned look would be lost.
	DevWidgets.confirm(self, "Overwrite preset '%s' with the current look? The saved version is lost." % target,
		func() -> void: _update_confirmed(target))


func _update_confirmed(target: String) -> void:
	if not DevWidgets.save_over(capture_preset(target), preset_path(target), _status):
		return
	_baseline = _live_values()   # the file now says what is on screen, so Reset must too
	_status.text = "Updated preset '%s' (%d knobs)." % [target, preset_knobs().size()]


func _on_delete_pressed() -> void:
	var target := DevWidgets.selected_name(_preset_dropdown)
	if target == "" or target == AUTHORED_ENTRY:
		return
	DevWidgets.confirm_delete(self, "preset '%s'" % target, func() -> void: _delete_confirmed(target))


func _delete_confirmed(target: String) -> void:
	if not DevWidgets.delete_saved_file(preset_path(target), "preset", _status):
		return
	if _loaded_preset == target:
		# The look on screen is untouched -- only its file is gone. Say so, and hand Reset back to
		# the scene rather than leaving it pointing at a preset that no longer exists.
		_baseline = _authored.duplicate()
		_loaded_preset = ""
		_status.text = "Deleted preset '%s'. The look on screen is unchanged; Reset now returns to the authored scene." % target
	refresh_preset_dropdown()


# The live value of every knob, per KNOBS index -- the baseline a just-saved preset establishes.
func _live_values() -> Array:
	var values: Array = _authored.duplicate()
	for i in KNOBS.size():
		if not PRESET_EXCLUDED.has(preset_key(KNOBS[i])):
			values[i] = read(KNOBS[i])
	return values


# --- The handoff ------------------------------------------------------------------------

func _on_copy_pressed() -> void:
	var moved := changed_values()
	if moved.is_empty():
		_status.text = "Nothing has moved off the scene's authored values yet."
		return
	DisplayServer.clipboard_set(_format(moved))
	var count := _value_count(moved)
	if _loaded_preset == "":
		_status.text = "Copied %d changed value(s) to the clipboard." % count
	else:
		# Say which, or the count reads as "what I tuned" when it is "preset + what I tuned".
		_status.text = ("Copied %d value(s) differing from Battle3D.tscn -- that is preset '%s' PLUS "
			+ "anything you moved since. Save As / Update is the handoff for a preset.") % [count, _loaded_preset]


func _on_reset_pressed() -> void:
	if _host == null:
		return
	for i in KNOBS.size():
		var authored: Variant = baseline_of(i)
		if typeof(authored) != TYPE_NIL:
			write(KNOBS[i], authored)
	for i in LAYER_KNOBS.size():
		var authored_color: Variant = layer_baseline_of(i)
		if typeof(authored_color) == TYPE_COLOR:
			write_layer(LAYER_KNOBS[i], authored_color)
	_rebuild()   # redraw every widget off the restored values -- one path, every widget kind
	if _loaded_preset == "":
		_status.text = "Every knob is back at its authored value."
	else:
		_status.text = "Every knob is back at preset '%s'." % _loaded_preset


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
		var authored: Variant = authored_of(i)
		if typeof(live) == TYPE_NIL or typeof(authored) == TYPE_NIL or same_value(live, authored):
			continue
		_record(groups, _paste_split(knob))
	for i in LAYER_KNOBS.size():
		var knob: Dictionary = LAYER_KNOBS[i]
		var live: Variant = read_layer(knob)
		var authored: Variant = layer_baseline_of(i)
		if typeof(live) != TYPE_COLOR or typeof(authored) != TYPE_COLOR or same_value(live, authored):
			continue
		_record(groups, _layer_paste_split(knob, live))
	return groups


# split = [paste header, dedup key, the finished line]. The key exists only so two knobs that
# emit the SAME line (flame_size:x and :y) collapse to one entry.
func _record(groups: Dictionary, split: Array) -> void:
	var header: String = split[0]
	if not groups.has(header):
		groups[header] = {}
	var entries: Dictionary = groups[header]
	entries[split[1]] = split[2]


# A layer colour is not authored at a property path, so it gets its own paste shape: the whole
# LAYERS row (sort and kind read off the live table, so the line is paste-ready as-is), or the
# static var declaration for a reach colour.
func _layer_paste_split(knob: Dictionary, live: Color) -> Array:
	if knob.has("reach"):
		var name: String = knob["reach"]
		return ["OverlayManager.gd", name,
			"static var %s := %s" % [name, literal_for(live)]]
	var layer: BoardOverlays.Layer = knob["layer"]
	var spec: Dictionary = BoardOverlays.LAYERS[layer]
	var layer_name: String = BoardOverlays.Layer.keys()[layer]
	var kind_name: String = BoardOverlays.Kind.keys()[spec["kind"]]
	return ["BoardOverlays.gd -> LAYERS", layer_name,
		'Layer.%s: {"color": %s, "sort": %d, "kind": Kind.%s},'
			% [layer_name, literal_for(live), spec["sort"], kind_name]]


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
	var prop: String = segments[i]
	return [header, prop, "%s = %s" % [prop, literal_for(current.get(prop))]]


func _format(groups: Dictionary) -> String:
	var out: PackedStringArray = PackedStringArray()
	for header: String in groups:
		out.append("# %s" % header)
		var entries: Dictionary = groups[header]
		for key: String in entries:
			out.append(entries[key])   # the split already built the finished line
		out.append("")
	return "\n".join(out).strip_edges()


func _value_count(groups: Dictionary) -> int:
	var total := 0
	for header: String in groups:
		var entries: Dictionary = groups[header]
		total += entries.size()
	return total


# "Has this moved?" -- approximate for floats, because a value written and read straight back is
# not always bit-identical: engine properties store single-precision, and a euler component
# round-trips through a basis. Exact compare reported the sun and board pitch as still changed
# immediately after Reset had put them back, and would do the same to a slider dragged out and
# returned. Every slider step here is orders of magnitude coarser than these tolerances.
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
