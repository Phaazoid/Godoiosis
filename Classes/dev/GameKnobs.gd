extends Object
class_name GameKnobs

# WHAT the game's own presentation constants are -- board markup, the unit readout, camera handling,
# dev chrome, world construction and the fire effect -- and how a tuned one is KEPT (#373, widened
# by #380 when the Objects tab's globals moved in). Static and pure; LookKnobs' opposite number.
# ObjectKnobs is now purely per-TYPE (TileSet custom-data fields); this table is the game constants,
# entire.
#
# The split it exists to make. A LookPreset is a mission's MOOD: one board may look unlike another,
# so a board names a preset and wears it. Everything here is the same in every mission forever --
# how high an icon floats, how thick a health bar is, how fast the camera pans -- so there is
# nothing for a board to carry, and every one of these rows was already excluded from presets. What
# they had no door to was PERSISTENCE: the Moods tab's only "keep this" button writes a preset, which
# deliberately omits them, so tuning one and liking it left nowhere to put it. They live here now,
# with a Save that writes the authored value, and LEAVING is what makes the preset exclusion
# structural rather than a name on a list -- the shape #272 used when prop geometry left LookKnobs.
#
# In Classes/dev/ for ObjectKnobs' reason: no shipping code reads it. A mission carries a look; it
# does not carry the HUD's geometry.
#
# TWO TABLES, because a game constant is authored two ways. KNOBS names a property on a node in the
# running Battle3D world, read and written through LookKnobs.read/write -- only the TABLE forks, the
# property access does not. CLASS_KNOBS names a value authored at CLASS level instead: an entry of
# BoardOverlays' const LAYERS table, or a static var on OverlayManager. Neither has a node property
# to address, which is why they cannot share one table however alike they look in the panel.
#
# The rule KNOBS inherits from LookKnobs and does not relax: a knob may only name a property that is
# authored and READ. Anything the game writes back per frame gives a slider that moves and silently
# reverts. tests/dev/test_game_knobs.gd pins that by writing, waiting two frames and reading back.

# node = path relative to the host ("." = the host); prop = colon-joined property path.
# A float knob carries min/max/step; bool and Color infer their widget from the live value.
const KNOBS: Array[Dictionary] = [
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
	# A group of one, and filed truthfully rather than folded into the markup above it: the ghost is
	# the only row on this tab a player never sees.
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
	# --- The element-state row (#357) ---
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "state_icon_texels", "label": "State icon size", "min": 2.0, "max": 32.0, "step": 1.0,
		"tip": "Size of each element-state icon above the health bar, in texels -- 16 is one cell. The source art is 32px (wet) and 16px (the frozen-tile stand-in for chilled), so powers of two land on exact reductions and anything else will shimmer as the camera moves. This is the first dial to reach for if the icons stop reading at play distance."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "state_icon_gap_texels", "label": "State row clearance", "min": 0.0, "max": 16.0, "step": 1.0,
		"tip": "Gap between the top of the health bar's outline and the bottom of the state icons, in texels. Zero stacks them flush against the bar so the two read as one display; push it up to separate what a unit IS from how hurt it is, at the cost of climbing toward the selection icons above."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "state_icon_spacing_texels", "label": "State icon spacing", "min": 0.0, "max": 16.0, "step": 1.0,
		"tip": "Gap between neighbouring state icons, in texels. Only visible on a unit holding more than one state, which today means wet AND chilled at once -- with two states the row cannot crowd, and this is the dial that matters when the vocabulary grows."},
	# --- The rescue clock beside the downed glyph (#322) ---
	# No SIZE row on purpose: the digits are the HP number's height, which is not tunable apart from
	# it. See UnitMirror's own note -- a dial whose readable range is only its top end is worse than
	# none, and "Number size" already moves both.
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "downed_count_gap_texels", "label": "Downed clock inset", "min": 0.0, "max": 16.0, "step": 1.0,
		"tip": "Gap between the last icon in the row and the turns-left digits, in texels. Zero puts the number flush against the glyph so the two read as one badge; widen it and the count starts reading as its own thing floating beside the body."},

	# --- Camera handling ---
	# How the camera DRAGS, never how the board is framed: pitch, FOV, the opening shot and the fit
	# margin are mood and stayed in LookKnobs, where a preset still captures them. Framing is also
	# the half Battle3D.tscn authors -- it overrides fov -- which is why these seven are the ones
	# with an @export default to write and those four are not.
	{"group": "Camera handling", "node": "CameraRig", "prop": "min_distance", "label": "Zoom-in limit", "min": 2.0, "max": 20.0, "step": 0.25,
		"tip": "How close the camera may get. Too close and sprites outrun their own pixel density."},
	{"group": "Camera handling", "node": "CameraRig", "prop": "zoom_step", "label": "Zoom step", "min": 0.25, "max": 5.0, "step": 0.05,
		"tip": "How far one notch of the mouse wheel moves the camera."},
	{"group": "Camera handling", "node": "CameraRig", "prop": "smoothing", "label": "Camera smoothing", "min": 1.0, "max": 24.0, "step": 0.1,
		"tip": "How fast the camera catches up to where it has been told to go. Higher is snappier and more responsive; lower glides, which reads as cinematic until you are trying to play."},
	{"group": "Camera handling", "node": "CameraRig", "prop": "pan_speed", "label": "Pan speed", "min": 1.0, "max": 30.0, "step": 0.5,
		"tip": "How fast WASD slides the camera across the board, in world units per second."},
	{"group": "Camera handling", "node": "CameraRig", "prop": "orbit_sensitivity", "label": "Orbit sensitivity", "min": 0.02, "max": 1.0, "step": 0.01,
		"tip": "Degrees the view swings per pixel of mouse travel while dragging to orbit."},
	{"group": "Camera handling", "node": "CameraRig", "prop": "pan_margin_cells", "label": "Pan margin (cells)", "min": 0.0, "max": 12.0, "step": 0.5,
		"tip": "How far past the board's edge you may pan before being stopped. Some slack keeps a corner unit from being pinned against the screen edge."},
	{"group": "Camera handling", "node": "CameraRig", "prop": "zoom_out_slack", "label": "Zoom-out slack", "min": 0.5, "max": 3.0, "step": 0.05,
		"tip": "How far past the whole board you may zoom out. 1.0 means the board exactly fills the view at full zoom-out; above 1 lets you pull back and see it sitting in the world."},

	# --- World (#380, from the Objects tab's Globals) ---
	# How the world's own furniture is drawn -- art conventions matched to the tile art once and
	# then constant for the whole game. The per-type fields on the Objects tab override these; a
	# global here is the DEFAULT a tile that says nothing falls back to.
	{"group": "World", "node": "BoardMirror", "prop": "block_height_scale", "label": "Prop block height", "min": 0.2, "max": 2.5, "step": 0.01,
		"tip": "How tall a solid prop -- crate, chest, rock, pot -- stands relative to its own sprite. 1.0 is the height measured off the art; because the art is drawn in 3/4 it includes some of the object's own lid, so the honest measurement usually reads a little tall."},
	{"group": "World", "node": "BoardMirror", "prop": "tuft_scale", "label": "Grass tuft scale", "min": 0.0, "max": 2.0, "step": 0.01,
		"tip": "How tall the plants on a grass tile stand -- the flowers and weeds that pop up off a tile which is also still painted flat. 1.0 draws each one at the size the art draws it. Only the height changes: where they sit in the cell comes off the art."},
	# The lamp defaults (#255's light, #380's rows -- these four had NO surface anywhere before
	# this). Tuning one re-lights every standing lamp through BoardMirror's sweep; a lamp whose
	# tile authors its own light deliberately does not move, since an authored override wins.
	{"group": "World", "node": "BoardMirror", "prop": "prop_light_color", "label": "Prop light colour",
		"tip": "The colour a lit object casts by default -- the warm lamp tone. A tile that authors its own Light colour ignores this; everything else re-lights live as you drag."},
	{"group": "World", "node": "BoardMirror", "prop": "prop_light_energy", "label": "Prop light brightness", "min": 0.0, "max": 8.0, "step": 0.05,
		"tip": "How bright a lit object burns by default. The per-type Light energy field on the Objects tab overrides this for one object; this is what every other lamp uses."},
	{"group": "World", "node": "BoardMirror", "prop": "prop_light_range", "label": "Prop light range", "min": 0.5, "max": 12.0, "step": 0.1,
		"tip": "How far a lit object's light reaches by default, in world units (roughly cells). Range and brightness together decide whether a lamp lights a room or just its own corner."},
	{"group": "World", "node": "BoardMirror", "prop": "prop_light_height", "label": "Prop light height", "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "How high above the cell a lit object's light source sits by default. A wall lamp's flame is near its top; a brazier's is lower. This is where the LIGHT is, not where the art is."},

	# --- Fire (#324's knobs; out of Look in #272, here from Objects in #380) ---
	# A terrain STATE rather than an authored object, but the same KIND of value: how the world's
	# own furniture is drawn, matched once and constant after. flame_count is the one INT-backed
	# knob and its range is load-bearing -- the write-back law nudges by a tenth of the range, so
	# anything narrower than 10 rounds back to where it started and reads as a dead slider.
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_lift", "label": "Flame lift", "min": 0.0, "max": 2.0, "step": 0.01,
		"tip": "How high the fire billboard's centre sits above a burning tile. Raising it makes fire read as standing up off the ground rather than lying on it."},
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_size:x", "label": "Flame width", "min": 0.1, "max": 2.0, "step": 0.01,
		"tip": "Width of the fire billboard in world units, where 1.0 is exactly one cell across. Width and height share one declaration, so saving either writes both."},
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_size:y", "label": "Flame height", "min": 0.1, "max": 2.0, "step": 0.01,
		"tip": "Height of the fire billboard in world units. Taller than wide reads as a flame; square reads as a scorch. Width and height share one declaration, so saving either writes both."},
	# The only INT-backed knob here, and its range is load-bearing: a slider write is nudged by a
	# tenth of the range, so anything narrower than 10 rounds back to where it started.
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_count", "label": "Flame count", "min": 1.0, "max": 12.0, "step": 1.0,
		"tip": "How many separate flames a burning cell stands up. One is a sprite standing on a tile; three or more spread across the square is a tile that is on fire. Every flame is another quad and another draw, so this is the knob that costs something on a board with a lot of fire."},
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_spread", "label": "Flame spread", "min": 0.0, "max": 0.6, "step": 0.01,
		"tip": "How far off the cell's centre the smaller flames sit, in cells -- 0.5 reaches the tile's edge. At zero they stack in the middle and the fire reads as one clump again."},
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_fps", "label": "Flame fps", "min": 0.0, "max": 30.0, "step": 0.5,
		"tip": "How fast the flame's frames play. The art is eight looping frames, so this is the whole speed of the fire: low reads as a slow lick, high as a roar. Zero holds a frame without freezing the light."},
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_flicker", "label": "Flame flicker", "min": 0.0, "max": 0.6, "step": 0.01,
		"tip": "How hard the fire's LIGHT breathes, as a fraction of its energy -- 0.2 swings it a fifth either way. This is what makes a burning tile feel lit by something alive rather than by a lamp; zero is a steady lamp."},
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_camera_offset", "label": "Flame camera push", "min": 0.0, "max": 0.5, "step": 0.005,
		"tip": "How far each flame is pushed toward the camera, in cells. A flame and a unit sprite on one cell are the same camera-facing plane, so without this they speckle against each other wherever someone stands in fire; push too far and the fire visibly leaves its own tile. A clearance rather than a taste call -- it defends against a geometric coincidence."},
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_animated", "label": "Flame animated",
		"tip": "Off holds the fire on one frame at steady light -- a still flame, not a missing one. This is the authored game constant; the PLAYER's photosensitivity toggle (#217) ANDs on top of it in BoardMirror._flame_animating, the one composed reader."},
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_ground_gap", "label": "Flame ground gap", "min": 0.0, "max": 0.5, "step": 0.005,
		"tip": "Gap between the base of the flame and the tile surface. A small gap stops the flame z-fighting the ground it stands on; too large and the fire floats."},
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_writes_depth", "label": "Flame writes depth",
		"tip": "Whether the flame writes into the depth buffer. On, it occludes what is behind it correctly but can cut a hard edge against overlapping sprites; off, it always draws as a soft overlay and never clips."},
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_light_energy", "label": "Flame light energy", "min": 0.0, "max": 8.0, "step": 0.05,
		"tip": "Brightness of the real point light each fire casts. This is what makes fire LIGHT the board -- units, walls and neighbouring tiles -- rather than merely glow on its own tile."},
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_light_range", "label": "Flame light range", "min": 0.5, "max": 12.0, "step": 0.1,
		"tip": "How far a fire's light reaches, in world units (roughly cells). Range and energy together decide whether a burning tile lights a room or just its own corner."},
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_light_color", "label": "Flame light colour",
		"tip": "The colour a fire casts onto everything around it. Its twin one row down is what the flame itself gives off; this one is what the neighbours are lit BY, the way Prop light colour is for lamps."},
	# The per-source half of glow (#420). Scene-wide bloom is a Moods knob and always will be -- one
	# Environment per board -- so what belongs here is only how hard THIS source burns.
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_glow_color", "label": "Flame glow colour",
		"tip": "The colour the flame itself gives off -- its emission, the thing the bloom pass picks up. Push it past white and the fire reads as hotter than its own art. This is the flame's own light, not what it throws onto the board: that is Flame light colour above."},
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_glow_energy", "label": "Flame glow strength", "min": 0.0, "max": 8.0, "step": 0.05,
		"tip": "How hard the flame glows. NOTHING blooms until it clears the mood's Glow HDR threshold on the Moods tab -- so if raising this only makes the fire brighter without haloing, that threshold is what to look at, not this."},

	# --- Cover (#326's bump; a Fire-shaped terrain state, moved off World by #420) ---
	{"group": "Cover", "node": "BoardMirror", "prop": "cover_scale", "label": "Cover bump scale", "min": 0.0, "max": 2.0, "step": 0.01,
		"tip": "How tall the mud bumps a dug-in Cover tile pops up stand, relative to the icon that draws them. 1.0 is the drawn size. Only the height changes: how many bumps there are and where they sit in the cell both come off the art."},

	# --- Playback (#259 rework: the animated shove) ---
	{"group": "Playback", "node": "UnitMirror", "prop": "shove_fall_speed", "label": "Shove fall speed", "min": 0.5, "max": 20.0, "step": 0.1,
		"tip": "How fast a shoved sprite's height settles in the 3D view, in world units/second -- the drop off a cliff and the roll down a ramp both ease at this rate. The slide across the ground is the Shove slide speed knob beside it."},
]

# Board-markup values that are NOT node properties (#212 slice 2, moved here whole by #373). A
# DECLARED second table rather than a widening of KNOBS: a layer's colour is an entry of the const
# LAYERS table and a reach colour is a static var, so neither can be addressed as node:property, and
# both are written back to a different kind of line.
#
# Which LAYERS entries appear here is measured, not chosen. `set_layer_modulate` REPLACES a layer's
# albedo, so any layer something already drives per frame would take a knob that silently reverts --
# the lying-slider class. Excluded for that reason: ATTACK's 3D side and AIM (OverlayMirror rewrites
# both from the 2D every poll) and HOVER (battle3d._sync_bracket_tint). ZONE_PATROL/ZONE_HIGHLIGHT
# are excluded as authoring-only -- invisible during real play, and they READ OverlayManager's
# constants, so a knob would fork a value that is deliberately one (dev call).
#
# `static` entries are the exception that proves it: ATTACK has no 3D-only colour to tune, because
# the 3D mirrors the 2D's modulate rather than holding an answer. Tuning it moves BOTH stacks.

# Where the class-level stores are declared -- above the table because a row may name its own
# script home. Named once, here, because the Save has to write these files and a second spelling
# of "which file holds LAYERS" would go stale the first time one moved. Checked by a law.
const OVERLAYS_SCRIPT := "res://Classes/presentation/BoardOverlays.gd"
const OVERLAY_MANAGER_SCRIPT := "res://Classes/board/OverlayManager.gd"
const MOVEMENT_SCRIPT := "res://Classes/units/MovementComponent.gd"
const ACTION_MENU_SCRIPT := "res://Classes/ui/ActionMenuController.gd"

const CLASS_KNOBS: Array[Dictionary] = [
	{"group": "Board markup colours", "label": "Move fill", "layer": BoardOverlays.Layer.MOVE,
		"tip": "The tiles a unit can reach while you are ordering a move. Alpha is the dial that matters most -- markup has to read as gameplay information without burying the terrain under it."},
	{"group": "Board markup colours", "label": "Invalid-move fill", "layer": BoardOverlays.Layer.INVALID_MOVE,
		"tip": "Tiles inside a unit's movement range that it still may not stop on -- out of its leader's cohesion range, or already occupied. Clicking one does nothing, so this colour is the only warning."},
	{"group": "Board markup colours", "label": "Squad fill", "layer": BoardOverlays.Layer.SQUAD,
		"tip": "The candidate bubble while FORMING a squad (Squad Up / Join Squad) -- the cells a recruit may be picked from. Membership itself is the ring/square markers, not this fill."},
	{"group": "Board markup colours", "label": "Squad-range fill", "layer": BoardOverlays.Layer.SQUAD_RANGE,
		"tip": "The leader's cohesion range -- how far squadmates may stray before the plan is refused. Shares its colour with Squad fill by default, since they are two halves of the same idea."},
	{"group": "Board markup colours", "label": "Capture zone", "layer": BoardOverlays.Layer.ZONE_CAPTURE,
		"tip": "A painted objective zone that can be captured. Stays visible for the whole battle -- this is live objective information, not authoring scaffolding."},
	{"group": "Board markup colours", "label": "Extraction zone", "layer": BoardOverlays.Layer.ZONE_EXTRACTION,
		"tip": "A painted zone your units must reach to extract. Also visible all battle."},
	{"group": "Board markup colours", "label": "Attack reach (2D+3D)", "static": "ATTACK_MODULATE",
		"tip": "The reach fill while aiming a damaging attack. Red reads as hostile, which is the whole reason a healing pick paints green instead."},
	{"group": "Board markup colours", "label": "Heal reach (2D+3D)", "static": "HEAL_ATTACK_MODULATE",
		"tip": "The same reach fill when the pick HEALS. Forked off the attack's own heals flag, so an attack cannot paint the wrong colour for what it does."},
	{"group": "Board markup colours", "label": "Blocked-reach dim (3D)", "static": "BLOCKED_REACH_DIM",
		"min": 0.1, "max": 1.0, "step": 0.01,
		"tip": "How much darker a reach cell past the attack's vertical tolerance draws in 3D, relative to the live reach colour. The 2D says the same thing with a hatched tile instead."},

	# The shove trail (2026-08-21). A predicted shove and an authored move drew identically -- both
	# plain white -- so this is what separates "what is about to be done to this unit" from "what it
	# chose". Tune it AGAINST the arrow palette, not just away from white: red already means a
	# refused order and green a member falling behind.
	{"group": "Board markup colours", "label": "Shove trail (2D+3D)", "static": "KNOCKBACK_MODULATE",
		"tip": "The knockback trail a predicted shove draws, and the drop pointer that hangs off it in 3D. Distinct from a planned move's arrow, which is an order the player authored -- a shove is a consequence. Takes effect on a preview already up."},

	# The three planned-move tints. They were hardcoded literals inside _arrow_modulate until the
	# trail art was desaturated (2026-08-21) -- while the art was cyan it carried most of the hue
	# and these only shaded it, so tuning them was near-pointless. On greyscale art they ARE the
	# colour, which is what makes them knobs.
	{"group": "Board markup colours", "label": "Move arrow", "static": "MOVE_ARROW_MODULATE",
		"tip": "A queued move's path arrow. Pre-set to the cyan the old art baked in, so this is what moves have always looked like -- now as a value you can move rather than a colour hidden in a PNG."},
	{"group": "Board markup colours", "label": "Refused-move arrow", "static": "INVALID_ARROW_MODULATE",
		"tip": "A queued move the plan has since refused -- out of the leader's cohesion range, or its destination taken. Reads brighter than before the art was desaturated, because the cyan used to multiply it down."},
	{"group": "Board markup colours", "label": "Trailing-move arrow", "static": "TRAILING_ARROW_MODULATE",
		"tip": "A Group Move member that stays in range but ends FURTHER from its leader than it started (Case 1) -- legal, but worth seeing. Same brightening as the refused colour above."},

	# The #325 rings. A float rather than a colour, and the reason this table is named for WHERE a
	# value lives rather than for what type it is: ring alpha is a static on OverlayManager, exactly
	# like the two reach colours above, and both stacks read it.
	{"group": "Squad markers", "label": "Ring opacity", "static": "SQUAD_RING_ALPHA",
		"min": 0.1, "max": 1.0, "step": 0.01,
		"tip": "Alpha of the per-squad membership rings under each member (the leader's crown, over the head, stays opaque). Takes effect on markers already up."},
	{"group": "Squad markers", "label": "Ring pulse brightness", "static": "SQUAD_RING_PULSE_GAIN",
		"min": 1.0, "max": 3.0, "step": 0.05,
		"tip": "How much brighter a squad ring goes at the top of its pulse while Join Squad is picking a squad. A gain on the ring's own hue, so a pulsing ring still reads as its squad's colour. 1.0 is no pulse at all. Takes effect on the next pick."},

	# The shove slide (#259 rework). A static on MovementComponent -- per-unit nodes, so no single
	# node property to address -- hence a class row with its own script home.
	{"group": "Playback", "label": "Shove slide speed", "static": "SHOVE_SLIDE_SPEED",
		"script": MOVEMENT_SCRIPT, "min": 60.0, "max": 960.0, "step": 10.0,
		"tip": "How fast a shoved unit slides along its knockback trail, in pixels/second (a walk is 120). Read at each shove, so a change applies from the next one."},

	# The void plummet (#431), the same shape one row along. The DEPTH is read twice -- by the fall
	# and by the preview pointer's length -- so this one slider moves both, which is the point.
	{"group": "Playback", "label": "Void fall depth", "static": "VOID_PLUMMET_CELLS",
		"script": MOVEMENT_SCRIPT, "min": 1.0, "max": 40.0, "step": 0.5,
		"tip": "How far a unit shoved into a hole keeps falling before it is removed, in cells below the lip. The plan-time drop arrow reaches exactly this far too, so raising it lengthens both. Read at each shove."},
	{"group": "Playback", "label": "Void fall time", "static": "VOID_PLUMMET_SECONDS",
		"script": MOVEMENT_SCRIPT, "min": 0.0, "max": 4.0, "step": 0.05,
		"tip": "How long that fall takes, in seconds. Zero removes the unit at the lip with no fall at all -- the pre-#431 behaviour. Does not affect the preview arrow, only the playback."},

	# The action ring (#467). Statics on a TRANSIENT node, which is why they are class knobs: the
	# menu exists only while the player holds it open, so there is no standing property for a KNOBS
	# row to name and nothing to re-apply a change to -- the next open reads them.
	#
	# The centre gap is wide and the bands are thin on the dev's call: the unit's sprite is what the
	# centre is FOR, and thin rings read as a menu rather than as a pie chart. Paint fraction is the
	# other half of that -- it narrows the drawn wedge WITHOUT moving a single hit boundary, since
	# the sectors always tile the full circle whatever they paint.
	{"group": "Action ring", "label": "Centre gap", "static": "RING_INNER_RADIUS",
		"script": ACTION_MENU_SCRIPT, "min": 30.0, "max": 200.0, "step": 1.0,
		"tip": "Radius from the unit's sprite out to the first ring of options. Wide enough that the sprite in the middle reads as the subject rather than as decoration."},
	{"group": "Action ring", "label": "Ring thickness", "static": "RING_THICKNESS",
		"script": ACTION_MENU_SCRIPT, "min": 12.0, "max": 90.0, "step": 1.0,
		"tip": "How deep each ring of options is. Thin reads as a menu; thick starts reading as a pie chart, which is the thing this menu is trying not to be."},
	{"group": "Action ring", "label": "Ring gap", "static": "RING_GAP",
		"script": ACTION_MENU_SCRIPT, "min": 0.0, "max": 40.0, "step": 1.0,
		"tip": "Empty space between one ring and the next one out. Enough to read as two rings, not so much that a submenu looks unrelated to what opened it."},
	{"group": "Action ring", "label": "Dead zone", "static": "DEAD_ZONE_RADIUS",
		"script": ACTION_MENU_SCRIPT, "min": 10.0, "max": 200.0, "step": 1.0,
		"tip": "Radius around the centre that selects NOTHING -- the only place a click cancels, since every other point on the screen belongs to some slice. Keep it inside the centre gap."},
	{"group": "Action ring", "label": "Wedge fill", "static": "PAINT_FRACTION",
		"script": ACTION_MENU_SCRIPT, "min": 0.15, "max": 1.0, "step": 0.01,
		"tip": "How much of its own slice a wedge actually paints, on the first ring. Below 1.0 leaves air between wedges. Purely a look: the slice you are pointing at does not change, only how much of it is drawn."},
	{"group": "Action ring", "label": "Widest wedge", "static": "MAX_WEDGE_DEGREES",
		"script": ACTION_MENU_SCRIPT, "min": 20.0, "max": 360.0, "step": 1.0,
		"tip": "Ceiling on how many degrees any one wedge PAINTS. Without it a submenu holding a single option balloons into a whole donut. It never moves a hit boundary -- the sectors still tile the circle, so the leftover angle belongs to the nearest wedge and the highlight says which."},
	{"group": "Action ring", "label": "Centre disc", "static": "CENTRE_COLOR",
		"script": ACTION_MENU_SCRIPT,
		"tip": "The disc the unit's sprite sits on. It is exactly the DEAD ZONE drawn, so its edge is a promise about where clicking selects nothing -- opaque enough to lift the sprite off the board behind it."},
	{"group": "Action ring", "label": "Centre rim", "static": "CENTRE_RIM_COLOR",
		"script": ACTION_MENU_SCRIPT,
		"tip": "The ring around that disc. Reads as the boundary between the unit and its options."},
	{"group": "Action ring", "label": "Centre rim width", "static": "CENTRE_RIM_WIDTH",
		"script": ACTION_MENU_SCRIPT, "min": 0.0, "max": 12.0, "step": 0.5,
		"tip": "How thick that rim is drawn. Zero removes it and leaves the bare disc."},
	{"group": "Action ring", "label": "Wedge fill falloff", "static": "PAINT_FRACTION_FALLOFF",
		"script": ACTION_MENU_SCRIPT, "min": 0.0, "max": 0.4, "step": 0.01,
		"tip": "How much less each ring further out paints than the one inside it, so a submenu builds out lighter instead of stacking full circles. Zero paints every ring the same."},
	{"group": "Action ring", "label": "Preview opacity", "static": "GHOST_ALPHA",
		"script": ACTION_MENU_SCRIPT, "min": 0.05, "max": 1.0, "step": 0.01,
		"tip": "Opacity of the ring PREVIEWED under the category you are hovering -- what you would open if you clicked. Faint enough to read as not-open-yet, solid enough to read at all."},
	{"group": "Action ring", "label": "Slice", "static": "SLICE_COLOR",
		"script": ACTION_MENU_SCRIPT,
		"tip": "An ordinary option's wedge. It sits over the board, so its alpha is what decides whether you can still see what you are acting on."},
	{"group": "Action ring", "label": "Slice (pointed at)", "static": "SLICE_SELECTED_COLOR",
		"script": ACTION_MENU_SCRIPT,
		"tip": "The one slice your angle currently picks. The pointer is routinely nowhere near the ring, so this highlight is the only feedback saying what a click would do."},
	{"group": "Action ring", "label": "Slice (unavailable)", "static": "SLICE_DISABLED_COLOR",
		"script": ACTION_MENU_SCRIPT,
		"tip": "An option the unit owns but cannot use right now -- a dry magazine, a carving it cannot pay for. It stays listed and says why, so this must read as present-but-dead, not as absent."},
]


# Which SUB-TAB each group lands on. A map rather than a key on every row, so adding a knob stays
# one line and adding a GROUP is one line here -- and a group with no tab is a group that silently
# vanishes from the panel, which is why a law test pins the mapping complete. Declaration order
# below is the tab order.
const GROUP_TABS: Dictionary[String, String] = {
	"Board markup": "Markup",
	"Dev chrome": "Markup",
	"Board markup colours": "Colours",
	"Squad markers": "Colours",
	"Unit HUD": "Unit HUD",
	"Camera handling": "Camera",
	"World": "World",
	# Elemental VFX, not just fire (#420). Ice draws as a flat Layer.TERRAIN icon with no 3D effect
	# and so has nothing to put here yet; Cover arrives with fire because #326 ruled it the same
	# kind of thing -- a terrain STATE whose art draws objects. A new element is one line.
	"Fire": "Elemental",
	"Cover": "Elemental",
	"Playback": "Playback",
	"Action ring": "Action ring",
}

# Which table an edit came from, carried through the save report. The two tables share an index
# space, so a saved row's number alone cannot say whose baseline to move.
const KNOB_SOURCE := "knobs"
const CLASS_SOURCE := "class"


# --- Reading and writing a CLASS knob ------------------------------------------------------------
#
# KNOBS rows route through LookKnobs.read/write like everything else. These do not: there is no node
# property to address, so each store gets its answer here and nowhere else.

static func read_class(host: Node3D, knob: Dictionary) -> Variant:
	if knob.has("static"):
		return read_static(knob["static"])
	var overlays := overlays_of(host)
	if overlays == null:
		return null
	return overlays.layer_modulate(knob["layer"])


static func write_class(host: Node3D, knob: Dictionary, value: Variant) -> void:
	if knob.has("static"):
		write_static(host, knob["static"], value)
		return
	var overlays := overlays_of(host)
	if overlays != null:
		overlays.set_layer_modulate(knob["layer"], value)


# Object.get/set are INSTANCE methods -- there is no reflecting on a class for a static var, so the
# names are matched explicitly. An unknown one is a loud failure rather than a silently dead knob.
static func read_static(name: String) -> Variant:
	match name:
		"ATTACK_MODULATE": return OverlayManager.ATTACK_MODULATE
		"HEAL_ATTACK_MODULATE": return OverlayManager.HEAL_ATTACK_MODULATE
		"BLOCKED_REACH_DIM": return OverlayManager.BLOCKED_REACH_DIM
		"SQUAD_RING_ALPHA": return OverlayManager.SQUAD_RING_ALPHA
		"SQUAD_RING_PULSE_GAIN": return OverlayManager.SQUAD_RING_PULSE_GAIN
		"KNOCKBACK_MODULATE": return OverlayManager.KNOCKBACK_MODULATE
		"MOVE_ARROW_MODULATE": return OverlayManager.MOVE_ARROW_MODULATE
		"INVALID_ARROW_MODULATE": return OverlayManager.INVALID_ARROW_MODULATE
		"TRAILING_ARROW_MODULATE": return OverlayManager.TRAILING_ARROW_MODULATE
		"SHOVE_SLIDE_SPEED": return MovementComponent.SHOVE_SLIDE_SPEED
		"VOID_PLUMMET_CELLS": return MovementComponent.VOID_PLUMMET_CELLS
		"VOID_PLUMMET_SECONDS": return MovementComponent.VOID_PLUMMET_SECONDS
		"MAX_WEDGE_DEGREES": return ActionMenuController.MAX_WEDGE_DEGREES
		"CENTRE_COLOR": return ActionMenuController.CENTRE_COLOR
		"CENTRE_RIM_COLOR": return ActionMenuController.CENTRE_RIM_COLOR
		"CENTRE_RIM_WIDTH": return ActionMenuController.CENTRE_RIM_WIDTH
		"RING_INNER_RADIUS": return ActionMenuController.RING_INNER_RADIUS
		"RING_THICKNESS": return ActionMenuController.RING_THICKNESS
		"RING_GAP": return ActionMenuController.RING_GAP
		"DEAD_ZONE_RADIUS": return ActionMenuController.DEAD_ZONE_RADIUS
		"PAINT_FRACTION": return ActionMenuController.PAINT_FRACTION
		"PAINT_FRACTION_FALLOFF": return ActionMenuController.PAINT_FRACTION_FALLOFF
		"GHOST_ALPHA": return ActionMenuController.GHOST_ALPHA
		"SLICE_COLOR": return ActionMenuController.SLICE_COLOR
		"SLICE_SELECTED_COLOR": return ActionMenuController.SLICE_SELECTED_COLOR
		"SLICE_DISABLED_COLOR": return ActionMenuController.SLICE_DISABLED_COLOR
	push_error("GameKnobs: unknown static '%s'" % name)
	return null


# The static IS the authority; what is already drawn is re-derived from it in the same breath, or a
# tuned value would not show until the next aim or the next squad change. #324's lesson: a knob on
# something RECONCILED rather than redrawn moves nothing until someone re-applies it.
static func write_static(host: Node3D, name: String, value: Variant) -> void:
	match name:
		"ATTACK_MODULATE": OverlayManager.ATTACK_MODULATE = value
		"HEAL_ATTACK_MODULATE": OverlayManager.HEAL_ATTACK_MODULATE = value
		"BLOCKED_REACH_DIM": OverlayManager.BLOCKED_REACH_DIM = value   # mirror reads it per frame; the refresh below is harmless
		"SQUAD_RING_ALPHA": OverlayManager.SQUAD_RING_ALPHA = value
		"SQUAD_RING_PULSE_GAIN": OverlayManager.SQUAD_RING_PULSE_GAIN = value
		"KNOCKBACK_MODULATE": OverlayManager.KNOCKBACK_MODULATE = value
		"MOVE_ARROW_MODULATE": OverlayManager.MOVE_ARROW_MODULATE = value
		"INVALID_ARROW_MODULATE": OverlayManager.INVALID_ARROW_MODULATE = value
		"TRAILING_ARROW_MODULATE": OverlayManager.TRAILING_ARROW_MODULATE = value
		"SHOVE_SLIDE_SPEED":
			MovementComponent.SHOVE_SLIDE_SPEED = value
			return   # read at each shove -- nothing standing to re-apply
		"VOID_PLUMMET_SECONDS":
			MovementComponent.VOID_PLUMMET_SECONDS = value
			return   # read at each shove -- nothing standing to re-apply
		"VOID_PLUMMET_CELLS":
			MovementComponent.VOID_PLUMMET_CELLS = value
			# Its SECOND reader is the preview pointer, which needs no re-apply either: OverlayMirror
			# rebuilds every knockback marker from the 2D sprites each frame and value-diffs, so a
			# standing preview re-lengthens on the next one. Not #324's redraw case.
			return
		# The action ring (#467). Every one of these takes SHOVE_SLIDE_SPEED's early return for the
		# same reason: the menu is transient and reads them at each open, so there is never a
		# standing ring to re-apply one to. That is also why they are statics rather than KNOBS
		# rows -- KNOBS names a property on a node in the running world, and this one is not there
		# except while the player is holding it open.
		"MAX_WEDGE_DEGREES":
			ActionMenuController.MAX_WEDGE_DEGREES = value
			return
		"CENTRE_COLOR":
			ActionMenuController.CENTRE_COLOR = value
			return
		"CENTRE_RIM_COLOR":
			ActionMenuController.CENTRE_RIM_COLOR = value
			return
		"CENTRE_RIM_WIDTH":
			ActionMenuController.CENTRE_RIM_WIDTH = value
			return
		"RING_INNER_RADIUS":
			ActionMenuController.RING_INNER_RADIUS = value
			return
		"RING_THICKNESS":
			ActionMenuController.RING_THICKNESS = value
			return
		"RING_GAP":
			ActionMenuController.RING_GAP = value
			return
		"DEAD_ZONE_RADIUS":
			ActionMenuController.DEAD_ZONE_RADIUS = value
			return
		"PAINT_FRACTION":
			ActionMenuController.PAINT_FRACTION = value
			return
		"PAINT_FRACTION_FALLOFF":
			ActionMenuController.PAINT_FRACTION_FALLOFF = value
			return
		"GHOST_ALPHA":
			ActionMenuController.GHOST_ALPHA = value
			return
		"SLICE_COLOR":
			ActionMenuController.SLICE_COLOR = value
			return
		"SLICE_SELECTED_COLOR":
			ActionMenuController.SLICE_SELECTED_COLOR = value
			return
		"SLICE_DISABLED_COLOR":
			ActionMenuController.SLICE_DISABLED_COLOR = value
			return
		_:
			push_error("GameKnobs: unknown static '%s'" % name)
			return
	var manager := overlay_manager_of(host)
	if manager == null:
		return
	match name:
		"SQUAD_RING_ALPHA": manager.restyle_squad_markers()
		"KNOCKBACK_MODULATE": manager.restyle_knockback_trail()
		# No bespoke sweep for the three planned-move tints: redraw_planned_paths already tears
		# every arrow down and rebuilds it through _arrow_modulate, so it IS the re-apply.
		"MOVE_ARROW_MODULATE", "INVALID_ARROW_MODULATE", "TRAILING_ARROW_MODULATE":
			manager.redraw_planned_paths()
		_: manager.refresh_attack_reach_color()


static func overlays_of(host: Node3D) -> BoardOverlays:
	if host == null:
		return null
	return host.get_node_or_null(^"BoardOverlays") as BoardOverlays


static func overlay_manager_of(host: Node3D) -> OverlayManager:
	if host == null:
		return null
	var game_2d: Node2D = host.game
	if game_2d == null:
		return null
	return game_2d.overlay_manager as OverlayManager


static func capture_class_baseline(host: Node3D) -> Array:
	var baseline: Array = []
	for knob: Dictionary in CLASS_KNOBS:
		baseline.append(read_class(host, knob))
	return baseline


static func changed_class_indices(host: Node3D, baseline: Array) -> PackedInt32Array:
	var moved: PackedInt32Array = PackedInt32Array()
	for i in CLASS_KNOBS.size():
		var live: Variant = read_class(host, CLASS_KNOBS[i])
		if typeof(live) == TYPE_NIL:
			continue
		if i >= baseline.size() or not LookKnobs.same_value(live, baseline[i]):
			moved.append(i)
	return moved


# --- Saving --------------------------------------------------------------------------------------

# The edits a set of moved CLASS rows needs. KnobSource applies them beside the declaration edits
# KNOBS produces, in one pass per file -- which matters here, since a marker's lift and a layer's
# colour are both authored in BoardOverlays.gd and two passes would read it twice.
#
# A layer's SORT and KIND are deliberately not touched: the rewriter replaces the entry's colour
# value alone, so the relationships #231 pinned cannot be moved by tuning a colour.
static func class_edits(host: Node3D, indices: PackedInt32Array) -> Array[Dictionary]:
	var edits: Array[Dictionary] = []
	for i: int in indices:
		var knob: Dictionary = CLASS_KNOBS[i]
		var literal := DevWidgets.literal_for(read_class(host, knob))
		if knob.has("static"):
			edits.append(KnobSource.edit(knob.get("script", OVERLAY_MANAGER_SCRIPT),
				KnobSource.Kind.DECLARATION,
				knob["static"], literal, knob["label"], i, CLASS_SOURCE))
			continue
		var layer_name: String = BoardOverlays.Layer.keys()[knob["layer"]]
		edits.append(KnobSource.edit(OVERLAYS_SCRIPT, KnobSource.Kind.LAYER_COLOR, layer_name,
			literal, knob["label"], i, CLASS_SOURCE))
	return edits


# One Save, both tables, one read-modify-write per file.
static func save_to_source(host: Node3D, indices: PackedInt32Array,
		class_indices: PackedInt32Array) -> Dictionary:
	var edits := KnobSource.declaration_edits(host, KNOBS, indices, KNOB_SOURCE)
	edits.append_array(class_edits(host, class_indices))
	return KnobSource.apply_edits(edits)


# The which-stack note is appended per KIND rather than typed into each tip, so it cannot drift out
# of step with the table it describes.
static func tip_for(knob: Dictionary) -> String:
	var tip: String = knob.get("tip", "")
	if knob.has("layer"):
		tip += "\n\n3D ONLY -- the flat 2D board keeps its own colour. A declared divergence, and provisional: tune it, look at it, then decide whether 2D should follow."
	elif knob.has("static"):
		tip += "\n\nMOVES BOTH STACKS -- this is one value both the 2D and the 3D read, so the flat game changes with it."
	return DevWidgets.wrap_tooltip(tip)
