extends Object
class_name LookKnobs

# WHAT the HD-2D look is made of, and how to read, write, capture and apply it (#253 part 2).
# Static and pure -- the MissionRules / LethalityRules shape.
#
# It lives here rather than in Classes/dev/ because a MISSION carries a look now: ScenarioData
# names a preset and battle3d applies it on every board load, which is shipping-build code. The
# Look tab (Classes/dev/LookTool.gd) is a SURFACE onto this table, not its owner.
#
# Every KNOBS entry names a property that ALREADY EXISTS on the running Battle3D world -- an
# @export on a presentation node, or a field of a sub_resource authored in Battle3D.tscn -- and
# both are reached the same way, via get_indexed/set_indexed. Nothing here stores a value.
#
# A knob may only name a property that is authored and READ. Anything the game writes back per
# frame -- the rig's yaw, dof_blur_near/far_distance (re-derived from focus_band_*), max_distance,
# orbit_button, manual_input_enabled -- would give a slider that moves and silently reverts, the
# one failure that makes a tuning panel untrustworthy. tests/dev/test_look_tool.gd pins that by
# writing, waiting two frames, and reading back.
#
# Board-markup COLOURS are deliberately not here: they address a layer through an accessor pair
# rather than a property path, they are excluded from presets anyway, and only the panel tunes
# them -- so LookTool.LAYER_KNOBS stays where the surface that uses it lives.

const PRESET_DIR := "res://Resources/LookPresets/"

# The fallback authority (dev, 2026-08-15). A SEPARATE file from Day.tres, and outside PRESET_DIR
# on purpose: outside, it cannot appear in the load dropdown, Delete can never target it, and
# Save As cannot shadow it -- all structural rather than a filename anyone could get wrong.
# It ships byte-identical to Day and is MEANT to diverge; they answer two different questions
# (an editable day mood vs what every board falls back to), which is a declared duplication.
const DEFAULT_PATH := "res://Resources/DefaultLook.tres"

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
		"tip": "How many cells wide the view is when a mission OPENS, centred on your own units. It does not limit zoom -- the whole board still does -- it only decides where the game starts you.\n\nInert on a board that authors its own camera start (Scenario tab, #234): an authored pose says where, which way and how far, so there is no width left to derive."},
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

	# --- Dev chrome ---
	# There used to be an EFFECTS group here, and everything in it has MOVED to ObjectKnobs (#272),
	# in two passes and for one reason: none of it was scene mood. Prop geometry went first as world
	# construction; the whole FIRE block followed on the dev's ruling that a terrain effect's look is
	# a game value like the rest. Leaving is what makes those rulings structural rather than entries
	# on PRESET_EXCLUDED, and it is what gives them a Save that writes their authored default.
	# The one survivor is dev chrome, so it is filed as that and rides the Markup sub-tab -- a group
	# of one deserves a truthful heading, not a tab of its own.
	{"group": "Dev chrome", "node": "BoardMirror", "prop": "brush_ghost_alpha", "label": "Brush ghost alpha", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "Opacity of the dev tile brush's preview block -- the ghost showing what you are about to paint. Dev-only; players never see it."},
	# --- Unit HUD (#229) ---
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "hud_lift", "label": "Readout clearance", "min": 0.0, "max": 1.5, "step": 0.01,
		"tip": "Gap between the top of the unit's visible ART and the bottom of the readout, in cells. Measured from the sprite's topmost opaque pixel rather than from its feet, so units drawn with different amounts of empty space above their heads all wear it at the same apparent height. The selection icons sit higher still; keep this well under their lift or the readout climbs past them."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "bar_width_texels", "label": "Bar width", "min": 4.0, "max": 128.0, "step": 1.0,
		"tip": "Width of the health bar in texels, at the same pixel density as every sprite -- 16 is one cell wide. The bar is pixel-snapped, so this also decides how finely it can show a fraction: at 20 wide, one texel is 5% of a unit's health."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "bar_height_texels", "label": "Bar height", "min": 1.0, "max": 16.0, "step": 1.0,
		"tip": "Thickness of the health bar in texels. Thin reads as a delicate HUD line and can vanish at distance; thick reads as a solid gauge and starts competing with the unit sprite for attention."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "bar_outline_texels", "label": "Bar outline", "min": 0.0, "max": 8.0, "step": 1.0,
		"tip": "Thickness of the black border around the bar, in texels. This is what separates the bar from whatever it happens to be floating over; 0 removes it, and on a busy board that usually costs more than it saves."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "bar_fill_color", "label": "Bar fill",
		"tip": "The health a unit still HAS. Flat -- it does not change hue as the bar shortens, since the length already says how hurt the unit is. Fully opaque by design: this is a gameplay descriptor, not scenery."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "bar_missing_color", "label": "Bar missing",
		"tip": "The health a unit has LOST, showing behind the fill. Read together, fill against missing is the whole gauge, so these two want to be as far apart as the palette allows."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "number_height_cells", "label": "Number size", "min": 0.02, "max": 0.6, "step": 0.005,
		"tip": "How tall the HP digits stand, in cells -- a size in the SCENE, not on screen, so it shrinks with the unit as you zoom out. The glyphs are rendered at a fixed high resolution and scaled down to this, so small stays crisp instead of turning to mush."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "number_outline_size", "label": "Number outline", "min": 0.0, "max": 24.0, "step": 1.0,
		"tip": "Thickness of the black outline behind the number, in GLYPH units -- so it holds its proportion when Number size changes, but what lands on screen is this scaled down with the text. Around 8 is one pixel of the game's own art and 16 is two; anything under about 5 is thinner than a single art pixel and will not separate white digits from a bright bar at all. Push it far enough and neighbouring digits bleed together, and at that point a black backing plate is the better answer than more outline."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "number_color", "label": "Number colour",
		"tip": "Colour of the HP digits. The outline is always black, so this is the fill; a tint here is the cheapest way to make the number read as part of the bar rather than as separate text."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "number_gap", "label": "Number inset", "min": 0.0, "max": 0.5, "step": 0.005,
		"tip": "How far in from the bar's left edge the digits start, in cells. The number sits ON the bar, so this is padding inside it rather than a gap beside it -- zero puts the first digit flush against the outline."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "number_shows_max", "label": "Number shows max",
		"tip": "On, the number reads '12/20'; off, just '12'. The bar already carries the fraction either way, so this is purely how much text you want floating over a head."},
	# --- The predicted readout (#313) ---
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "bar_doomed_color", "label": "Predicted loss",
		"tip": "The health the queued plan is about to TAKE, drawn over the fill between where the bar is now and where the plan leaves it. It has to read as a warning against the fill beside it without reading as damage that has already landed -- the notch is what says 'not yet'."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "bar_heal_color", "label": "Predicted gain",
		"tip": "The same span in the other direction: health a queued heal is about to give back, drawn over the missing backing. Wants to be unmistakably not-the-loss-colour, since the shape of the span is identical either way and only the colour says which."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "notch_color", "label": "Prediction notch",
		"tip": "The marker sitting AT the health the plan predicts. This is the one mark that says the bar is showing a future as well as a present, so it wants to stand off both the fill and the loss colour."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "notch_texels", "label": "Notch width", "min": 1.0, "max": 8.0, "step": 1.0,
		"tip": "Thickness of the prediction marker in texels, at the same pixel density as the bar. One texel is a hairline that can disappear at distance; wide enough and it stops reading as a mark on the bar and starts reading as a third segment of it."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "alarm_peak_color", "label": "Alarm peak",
		"tip": "What the predicted-loss span pulses TO when the plan predicts a named rung -- a down, a kill, or Crisis. It pulses back to the ordinary loss colour, so this is only the bright half of the cue; make it too close to that colour and the pulse stops registering."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "unhovered_shows_number", "label": "Unhovered bars show number",
		"tip": "Whether a readout that is up for any reason OTHER than hover -- a queued plan, or the always-show setting -- also carries the HP digits. Off by default: either one can put a bar over half the board or all of it, and pointing at any of them reveals its number anyway."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "crown_badge_scale", "label": "Crown badge scale", "min": 0.5, "max": 4.0, "step": 0.1,
		"tip": "Size of the leader's crown beside the health bar, as a multiple of the bar's height (#325 -- ring mode only; the squares style keeps its floating crown). At 1.0 the crown matches the bar line; push it up if the glyph turns to mush at distance."},
	# --- The element-state row (#357) ---
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "state_icon_texels", "label": "State icon size", "min": 2.0, "max": 32.0, "step": 1.0,
		"tip": "Size of each element-state icon above the health bar, in texels -- 16 is one cell. The source art is 32px (wet) and 16px (the frozen-tile stand-in for chilled), so powers of two land on exact reductions and anything else will shimmer as the camera moves. This is the first dial to reach for if the icons stop reading at play distance."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "state_icon_gap_texels", "label": "State row clearance", "min": 0.0, "max": 16.0, "step": 1.0,
		"tip": "Gap between the top of the health bar's outline and the bottom of the state icons, in texels. Zero stacks them flush against the bar so the two read as one display; push it up to separate what a unit IS from how hurt it is, at the cost of climbing toward the selection icons above."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "state_icon_spacing_texels", "label": "State icon spacing", "min": 0.0, "max": 16.0, "step": 1.0,
		"tip": "Gap between neighbouring state icons, in texels. Only visible on a unit holding more than one state, which today means wet AND chilled at once -- with two states the row cannot crowd, and this is the dial that matters when the vocabulary grows."},
]

# A preset is SCENE MOOD, not game settings (dev, 2026-08-15). Everything in KNOBS is captured
# unless it is named here; LAYER_KNOBS is out wholesale, so a preset never touches board-markup
# colour. Excluded for three separate reasons, all the same rule -- a MISSION must not be able to
# change these, because they are things the player learns once and keeps:
#   * camera HANDLING -- how the camera drags, not how the board is framed. Pitch/FOV/opening
#     shot/fit margin ARE framing and stay in.
#   * board MARKUP -- gameplay legibility. Its geometry as much as its colour.
#   * the brush ghost -- dev chrome; players never see it.
# PROP GEOMETRY used to be a fourth reason and is now OUT OF THIS TABLE ENTIRELY (#272): block
# height, tuft scale and cover-bump scale live in ObjectKnobs, so "a mission cannot restyle world
# construction" is structural rather than three names on this list. #264's block_height_scale is
# what proved the default-IN rule has teeth -- it self-joined presets and had to be ruled on -- and
# that ruling is why those three left rather than why they are listed.
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
	# The two flame carve-outs that used to sit here -- the #217 accessibility switch and the #298
	# plane-separation clearance -- left with the rest of the fire block for ObjectKnobs (#272).
	# Both reasons still hold and are simply no longer expressible here: a preset cannot reach a
	# knob that is not in this table at all.
	# #229's readout is game MARKUP, not scene mood — the same side of that line as the board
	# overlays above, and for the same reason: a mission should not be able to hide a unit's health
	# by wearing a look. Excluded wholesale, which also keeps the shipped presets valid under
	# test_look_presets' "names every in-scope knob" law. #313's prediction rides the same bar and
	# answers the same way: a plan's consequences are the least hideable thing on the board.
	"UnitMirror|hud_lift",
	"UnitMirror|bar_width_texels",
	"UnitMirror|bar_height_texels",
	"UnitMirror|bar_outline_texels",
	"UnitMirror|bar_fill_color",
	"UnitMirror|bar_missing_color",
	"UnitMirror|number_height_cells",
	"UnitMirror|number_outline_size",
	"UnitMirror|number_color",
	"UnitMirror|number_gap",
	"UnitMirror|number_shows_max",
	"UnitMirror|bar_doomed_color",
	"UnitMirror|bar_heal_color",
	"UnitMirror|notch_color",
	"UnitMirror|notch_texels",
	"UnitMirror|alarm_peak_color",
	"UnitMirror|unhovered_shows_number",
	"UnitMirror|crown_badge_scale",
	"UnitMirror|state_icon_texels",
	"UnitMirror|state_icon_gap_texels",
	"UnitMirror|state_icon_spacing_texels",
]

# --- Identity ---------------------------------------------------------------------------

# The key a preset stores a knob under. DERIVED from what already makes a row unique, so there is
# no extra table column to keep in step -- and deliberately not the label, which reworded twice
# while this panel was being built. A preset stores key -> value and NEVER the property path:
# KNOBS is the one answer to "which property is Sun energy", so a path in a preset file would be
# a second one, and renaming a property would mean editing every preset instead of one table row.
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
	for knob: Dictionary in KNOBS:
		var key := preset_key(knob)
		if PRESET_EXCLUDED.has(key):
			continue
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
	# Look tab has a Re-fit button. Without this a loaded preset frames with the old camera.
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
