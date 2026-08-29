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

# Named because it has a SECOND reader: the V key (DevController._handle_selector_key) toggles the
# same property, and resolving it through this one entry is what stops the key and the panel row
# holding two spellings of where the selector's depth lives. Everything else in the table below is
# addressed only by the panel, so only this one needs a name.
const SELECTOR_DEPTH := {"group": "Board markup", "node": "BoardOverlays", "prop": "selector_depth",
	"label": "Selector depth", "options": ["Level (whole block)", "Half (one unit)"],
	"tip": "How much of a column the hover selector encloses. Level is one whole block, which is what it marked before a GridMap row became a half-level height unit; Half is one unit, for reading a half step apart from the level it sits in. Its top face sits on the cell's surface either way, so this only changes how far DOWN it reaches. V cycles it in play."}

# node = path relative to the host ("." = the host); prop = colon-joined property path.
# A float knob carries min/max/step; bool and Color infer their widget from the live value.
# A knob carrying `options` renders as a picker over an enum property instead (LookKnobs' tonemap).
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
	SELECTOR_DEPTH,
	{"group": "Board markup", "node": "BoardOverlays", "prop": "invalid_bracket_color", "label": "Invalid bracket tint",
		"tip": "What the hover bracket turns over a cell the 2D game calls invalid -- unwalkable, occupied, or a paint the tile brush would refuse. It mirrors the 2D cursor's own verdict rather than deciding for itself."},
	{"group": "Board markup", "node": "BoardOverlays", "prop": "billboard_lift", "label": "Icon height", "min": 0.0, "max": 3.0, "step": 0.01,
		"tip": "How high a selection icon floats above the cell it marks. High enough to clear the unit standing there, low enough not to read as belonging to the cell behind."},
	{"group": "Board markup", "node": "BoardOverlays", "prop": "billboard_pixel_size", "label": "Icon pixel size", "min": 0.004, "max": 0.1, "step": 0.001,
		"tip": "World size of ONE pixel of a billboard icon. 1/32 matches the tile art's density; mixing densities is the loudest amateur tell in HD-2D, so change this only with the art in view."},

	# --- Dev chrome ---
	# Filed truthfully rather than folded into the markup above it: these are the only rows on this
	# tab a player never sees.
	{"group": "Dev chrome", "node": "BoardMirror", "prop": "brush_ghost_alpha", "label": "Brush ghost alpha", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "Opacity of the dev tile brush's preview block -- the ghost showing what you are about to paint. Dev-only; players never see it."},
	# "." is the HOST itself (LookKnobs.target_of) — the first row to use it, because the plate is a
	# child of Battle3D's own UI layer and there is no sub-node that owns it.
	{"group": "Dev chrome", "node": ".", "prop": "help_plate_alpha", "label": "Top bar plate", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "Opacity of the dark plate behind the help line, the checkout stamp and the DEV MODE badge (#498). Zero removes it and the text goes back to washing out over pale terrain; past about 0.7 the plate stops reading as chrome and starts covering the board. The plate is fitted to the text, so this changes how hard it reads, never how much screen it takes. Dev-only."},
	{"group": "Dev chrome", "node": "BoardMirror", "prop": "brush_vertex_ghost_size", "label": "Corner marker size", "min": 0.05, "max": 0.6, "step": 0.01,
		"tip": "Edge of the corner tool's marker cube, as a fraction of a cell. It marks the POINT a drag has hold of, so it wants to be grabbable by eye without growing large enough to read as a tile -- past about a third of a cell it starts covering the corner it is pointing at. Dev-only."},

	# --- Unit HUD (#229) ---
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "hud_lift", "label": "Readout clearance", "min": 0.0, "max": 1.5, "step": 0.01,
		"tip": "Gap between the top of the unit's visible ART and the bottom of the readout, in cells. Measured from the sprite's topmost opaque pixel rather than from its feet, so units drawn with different amounts of empty space above their heads all wear it at the same apparent height. The selection icons sit higher still; keep this well under their lift or the readout climbs past them."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "hp_block_texels", "label": "HP cube size", "min": 2.0, "max": 16.0, "step": 1.0,
		"tip": "Edge of one HP cube in texels, at the same pixel density as every sprite -- 32 is one cell. This INCLUDES the black cage, so the coloured core is this minus twice the cage: at 5 with a 1-texel cage the core is 3 texels, which is about the floor for still reading as a bordered square rather than a dark speck."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "hp_block_border_texels", "label": "HP cube cage", "min": 0.0, "max": 4.0, "step": 1.0,
		"tip": "Thickness of the black frame around every face of a cube, in texels. It is what makes a cube read as a cube with no lighting on it, and neighbouring cubes SHARE it -- so this also closes the gap between them. Zero removes it and the grid becomes a row of flat squares; push it past a third of the cube size and there is no colour left to read."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "hp_blocks_per_row", "label": "HP cubes per row", "min": 1.0, "max": 30.0, "step": 1.0,
		"tip": "How many cubes before the grid wraps to another row. Ten is what makes the readout countable at a glance -- one full row plus four reads as 14 without counting. Fewer per row trades width for height, and height is the contested axis: the state icons and the crown are stacked above."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "hp_block_recess_texels", "label": "Lost cube depth", "min": 0.0, "max": 8.0, "step": 1.0,
		"tip": "How far back a LOST cube sits, in texels. The dent is a second cue beside the colour, so the readout still reads at distance and for anyone who finds green-against-red hard. Zero makes every cube flush and hands the dent to the shrink below -- which is where it sits by default, because depth and holding the grid still are incompatible: pushed back cubes stop reading as sunk the moment you orbit behind them."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "hp_block_recess_shrink", "label": "Lost cube shrink", "min": 0.1, "max": 1.0, "step": 0.05,
		"tip": "How much smaller a LOST cube gets, as a fraction of a standing one. This is what actually reads as a hole: depth alone leaves a same-sized square head-on, because there is no socket wall to see, so shrinking it is what pulls it away from its neighbours' cages. 1.0 removes the effect and leaves depth and colour to carry the dent between them."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "hp_block_recess_shade", "label": "Lost cube shade", "min": 0.1, "max": 1.0, "step": 0.05,
		"tip": "How far a LOST cube's colour is dimmed, as a multiplier on Cube missing -- it reads as the sunk cube sitting in shadow. At 1.0 it is exactly the authored colour, so this MODIFIES that one answer rather than becoming a rival to it: if you want a different red, move Cube missing, not this."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "hp_block_top_shade", "label": "Cube top shade", "min": 0.1, "max": 1.0, "step": 0.05,
		"tip": "How far the TOP face of every cube is darkened, as a multiplier on its own colour. This is the one thing telling the top apart from the front, and it is deliberately a shade rather than the absence of the black cage: taking the cage off the other five faces instead made the whole grid read as one green mass with black painted on, rather than as separate bricks. 1.0 removes the effect and the top matches the front exactly."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "hp_grid_faces_camera", "label": "Grid faces camera",
		"tip": "On, the whole readout turns to face the camera like a billboard. Off, it stays put on the board's own axes the way the rocks and props do, which means orbiting past one takes it edge-on and squashes it to a line. That is what keeping it in place MEANS rather than a fault; the question this dial asks is whether reading as a real 3D object is worth the angles where it stops being legible."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "bar_fill_color", "label": "Cube fill",
		"tip": "The health a unit still HAS -- the colour of a standing cube, and of the cubes that fly off when it loses one. Flat: it does not shift hue as the grid empties, since the COUNT already says how hurt the unit is. Fully opaque by design, because this is a gameplay descriptor rather than scenery."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "bar_missing_color", "label": "Cube missing",
		"tip": "The health a unit has LOST -- the colour of a shrunken cube. Read together, fill against missing is the whole gauge, so these two want to be as far apart as the palette allows; the shrink is what keeps it readable for anyone the pair itself does not separate."},
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
		"tip": "The health the queued plan is about to TAKE -- worn by the exact cubes that will go, between where the grid stands now and where the plan leaves it. It has to read as a warning against the fill beside it without reading as damage that has already landed, and the cubes still standing PROUD are what say 'not yet'."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "bar_heal_color", "label": "Predicted gain",
		"tip": "The same span in the other direction: health a queued heal is about to give back, drawn over the missing backing. Wants to be unmistakably not-the-loss-colour, since the shape of the span is identical either way and only the colour says which."},
	# No NOTCH rows: with one cube per point of HP, colouring the exact cubes the plan takes says
	# where it lands more precisely than a marker beside them could, so #313's notch is gone.
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
	# --- The cubes a unit LOSES (#314) ---
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "block_burst_speed", "label": "Cube burst speed", "min": 0.0, "max": 10.0, "step": 0.1,
		"tip": "How hard a lost cube is thrown out of its socket, in cells per second. This is the dial that decides whether losing health reads as an EVENT or as the grid quietly getting shorter -- too low and the cubes dribble off the bottom, too high and they are gone before the eye finds them."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "block_burst_spread", "label": "Cube burst spread", "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "How wide the fan is when several cubes leave at once. Zero throws every cube straight up, so a nine-damage hit leaves as one clump; higher spreads them sideways so you can see how many there were. The directions are fixed per cube rather than random, so the same hit always looks the same."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "block_spin_speed", "label": "Cube spin", "min": 0.0, "max": 30.0, "step": 0.5,
		"tip": "How fast a thrown cube tumbles, in radians per second. The tumble is what shows off the cage on every face and sells the cube as a solid object rather than a flat square -- at zero it is a sliding tile, and far too high it blurs into a flicker."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "block_gravity", "label": "Cube gravity", "min": 0.0, "max": 40.0, "step": 0.5,
		"tip": "Downward pull on a thrown cube, in cells per second squared. Read against burst speed rather than alone: the two together decide how high the arc goes and how long it hangs before the bounce."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "block_bounce", "label": "Cube bounce", "min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "How much of its fall a cube keeps on the way back up, once, when it hits the board beneath it. Zero lands it dead; 1 would return the whole drop. Only the FIRST touch bounces -- after that it rides through, so a busy pass never fills the board with rattling cubes."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "block_lifetime", "label": "Cube lifetime", "min": 0.1, "max": 4.0, "step": 0.05,
		"tip": "How long a thrown cube lives, in seconds; it fades out over the back half so the bounce is seen at full strength and only the settle disappears. Long enough to read the burst, short enough that a nine-unit AI pass does not leave the board littered."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "block_burst_stagger", "label": "Cube burst stagger", "min": 0.0, "max": 0.3, "step": 0.005,
		"tip": "Delay between one cube launching and the next, in seconds, so a multi-cube burst MARCHES through the grid instead of leaving all at once. A cube still waiting its turn sits in its own socket rather than hiding, so the grid breaks apart in sequence with no gap running ahead of the cubes. 0 fires the whole burst on a single frame, which is what a nine-damage hit used to look like."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "block_death_power", "label": "Death burst", "min": 1.0, "max": 5.0, "step": 0.1,
		"tip": "Multiplier on the burst when a unit DIES and its whole remaining grid detonates at once, rather than losing a few cubes to a hit. Going DOWN is not a death and gets the ordinary burst of everything above 1 HP, so this is only for the rarer outright kill."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "block_pop_time", "label": "Heal pop time", "min": 0.02, "max": 1.0, "step": 0.01,
		"tip": "How long a healed cube takes to rise back out of its dent, in seconds. It overshoots slightly on the way so it reads as popping rather than sliding. Deliberately quicker and quieter than a burst -- being healed should not upstage being hit."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "hp_pop_lift_texels", "label": "Heal pop travel", "min": 0.0, "max": 12.0, "step": 0.5,
		"tip": "How far a healed cube sinks before it springs back, in texels. Deliberately its OWN value rather than the lost-cube depth: tying it to that made the pop invisible the moment the depth was dialled to zero, since an animation whose distance is a knob that may legitimately be 0 has no distance at all. At 0 here the pop looks instant however long you give it."},
	{"group": "Unit HUD", "node": "UnitMirror", "prop": "hp_pop_stagger", "label": "Heal fill stagger", "min": 0.0, "max": 0.5, "step": 0.01,
		"tip": "How long each restored cube waits before its own rise, so a multi-point heal FILLS IN one socket at a time instead of popping as one block. The run goes lowest socket first, which is the burst order reversed -- the last cube knocked out is the first one back. Judge this against Heal pop time rather than on its own: near zero and every cube is mid-rise at once, which is one blob however slow you make it, while something like a fifth of the pop time reads as a wave. It is separate from Burst stagger because that one races a cube's whole flight and this one races a single rise."},

	# --- Camera handling ---
	# How the camera DRAGS, never how the board is framed: pitch, FOV, the opening shot and the fit
	# margin are mood and stayed in LookKnobs, where a preset still captures them. Framing is also
	# the half Battle3D.tscn authors -- it overrides fov -- which is why these six are the ones
	# with an @export default to write and those four are not. (Seven until the zoom-in floor was
	# removed outright, 2026-08-23 -- a knob cannot name a property that no longer exists.)
	{"group": "Camera handling", "node": "CameraRig", "prop": "zoom_step", "label": "Zoom step", "min": 0.25, "max": 5.0, "step": 0.05,
		"tip": "How far one notch of the mouse wheel moves the camera."},
	{"group": "Camera handling", "node": "CameraRig", "prop": "smoothing", "label": "Camera smoothing", "min": 1.0, "max": 24.0, "step": 0.1,
		"tip": "How fast the camera catches up to where it has been told to go. Higher is snappier and more responsive; lower glides, which reads as cinematic until you are trying to play."},
	{"group": "Camera handling", "node": "CameraRig", "prop": "glide_smoothing", "label": "Pan glide speed", "min": 1.0, "max": 24.0, "step": 0.1,
		"tip": "How fast the camera TRAVELS when something other than your hand moves it -- the flight back to your own view after a pass, the return to a unit you just gave an order to, R, and the rise into the torn-out diorama. Higher lands sooner, lower drifts. This is where to look if the end of every Execute reads as slow: the return is the most visible of them by far. Separate from Camera smoothing above, which is how the yaw and the zoom catch up under your own input."},
	{"group": "Camera handling", "node": "CameraRig", "prop": "pan_speed", "label": "Pan speed", "min": 1.0, "max": 30.0, "step": 0.5,
		"tip": "How fast WASD slides the camera across the board, in world units per second."},
	{"group": "Camera handling", "node": "CameraRig", "prop": "orbit_sensitivity", "label": "Orbit sensitivity", "min": 0.02, "max": 1.0, "step": 0.01,
		"tip": "Degrees the view swings per pixel of mouse travel while dragging to orbit. ONE rate for both axes -- turning and tilting are two halves of the same drag, and separate rates make a diagonal drag curve."},
	{"group": "Camera handling", "node": "CameraRig", "prop": "max_pitch_degrees", "label": "Tilt limit: shallow", "min": -60.0, "max": -5.0, "step": 1.0,
		"tip": "The FLATTEST the player's drag may take the camera, in degrees below the horizon. Nearer zero looks along the board rather than at it, so the far side stacks up and hides itself. This is a limit on the hand, not on the board: where a mission STARTS is Board pitch on the Moods tab, and R returns there."},
	{"group": "Camera handling", "node": "CameraRig", "prop": "min_pitch_degrees", "label": "Tilt limit: steep", "min": -90.0, "max": -40.0, "step": 1.0,
		"tip": "The STEEPEST the player's drag may take the camera. Steep is what lets you see into a one-cell hole -- it needs about -70 to read the floor of one two units deep. Past that the unit sprites are being looked at from overhead, which is the one angle billboard art is not drawn for, so this is where the HD-2D conceit gives out rather than where the maths does."},
	{"group": "Camera handling", "node": "CameraRig", "prop": "pan_margin_cells", "label": "Pan margin (cells)", "min": 0.0, "max": 12.0, "step": 0.5,
		"tip": "How far past the board's edge you may pan before being stopped. Some slack keeps a corner unit from being pinned against the screen edge."},
	{"group": "Camera handling", "node": "CameraRig", "prop": "playback_distance", "label": "Playback zoom distance", "min": 4.0, "max": 30.0, "step": 0.5,
		"tip": "How far out the camera sits when a pass or an AI turn takes it (#520). Applied ONCE as playback starts and then the wheel is yours again -- so this is where a fight opens from, not a leash."},
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

	# --- Water (#552) ---
	# World construction like Fire, not mood: a lake looks the same in every mission. These reach the
	# shader as global uniforms rather than material parameters, so each row moves the whole board's
	# water at once.
	#
	# EVERY value is PER TYPE (dev, 2026-08-27: "we need these dials separate for the different water
	# types. Otherwise, I can't tune them separately."). It replaced a fixed RATIO living in the
	# shader as constants -- a ratio between two authored things is itself an authored thing, so
	# burying it made a feel value with no surface. What is NOT here: how much lighter shallow water
	# is than deep. That is the two tiles' authored modulate, because it has to reach the flat view
	# as well and a knob on this node structurally cannot.
	{"group": "Water (deep)", "node": "BoardMirror", "prop": "water_deep_wave_speed", "label": "Wave speed", "min": 0.0, "max": 4.0, "step": 0.01,
		"tip": "How fast the light bands travel across deep water. Zero holds it still without flattening it -- the bands, the highlight and the body all stay, they simply stop moving."},
	{"group": "Water (deep)", "node": "BoardMirror", "prop": "water_deep_wave_scale", "label": "Wave scale", "min": 0.5, "max": 24.0, "step": 0.1,
		"tip": "How tightly packed deep water's bands are, in radians per cell -- roughly how many crests cross one tile. Low reads as a slow open lake, high as choppy."},
	{"group": "Water (deep)", "node": "BoardMirror", "prop": "water_deep_band_contrast", "label": "Band contrast", "min": 0.0, "max": 1.5, "step": 0.01,
		"tip": "How much deep water's moving bands lighten the tile's own colour. The visible half of the motion; its twin, Ripple, is the half you only see in the highlight."},
	{"group": "Water (deep)", "node": "BoardMirror", "prop": "water_deep_ripple", "label": "Ripple", "min": 0.0, "max": 2.0, "step": 0.01,
		"tip": "How hard deep water's wave bends the surface normal, which is what makes the SUN's highlight travel rather than sit still. Zero leaves a mirror-flat surface that still shows bands."},
	{"group": "Water (deep)", "node": "BoardMirror", "prop": "water_deep_roughness", "label": "Roughness", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "How diffuse deep water is. 1.0 is what every other ground uses and is why water had no specular response at all before #552. Tuned together with Specular and with the Moods tab's Sun elevation, which decides where the highlight falls."},
	{"group": "Water (deep)", "node": "BoardMirror", "prop": "water_deep_specular", "label": "Specular", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "How strong deep water's highlight is once Roughness lets there be one. Roughness sets how TIGHT the highlight is, this sets how BRIGHT."},
	{"group": "Water (deep)", "node": "BoardMirror", "prop": "water_deep_seam", "label": "Cell seam", "min": 0.0, "max": 0.6, "step": 0.005,
		"tip": "How darkly deep water draws its own cell boundaries. The waves run off world position so a lake is one continuous body, which erases the grid -- and on water the hover bracket is then the only thing showing where a tile ends. A deep expanse has nothing else breaking it up, so it usually wants more of this than shallow does."},
	{"group": "Water (deep)", "node": "BoardMirror", "prop": "water_deep_body_shade", "label": "Body shade", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "How much darker a deep block's WALLS and top rim read than its surface -- the body of the water rather than the face of it. Only visible where water meets a lower cell or the board's edge."},
	{"group": "Water (deep)", "node": "BoardMirror", "prop": "water_deep_foam_width", "label": "Foam width", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "How far in from the shore the surf reaches, in HALF-cells -- 1.0 arrives at the cell's own centre. Deep water usually meets a wall rather than a beach, so a NARROWER band than shallow's reads better: water stopping dead, not running out."},
	{"group": "Water (deep)", "node": "BoardMirror", "prop": "water_deep_foam_color", "label": "Foam colour",
		"tip": "The surf's own colour, and its ALPHA is how hard it lands. Deep water breaking against something wants the harder, brighter edge -- it is the one place on a deep expanse where a bright highlight is doing work rather than adding glare."},

	{"group": "Water (shallow)", "node": "BoardMirror", "prop": "water_shallow_wave_speed", "label": "Wave speed", "min": 0.0, "max": 6.0, "step": 0.01,
		"tip": "How fast shallow water's bands travel. It also carries the CAUSTICS, whose speed is derived from this rather than taking a dial of its own -- it is the same water moving."},
	{"group": "Water (shallow)", "node": "BoardMirror", "prop": "water_shallow_wave_scale", "label": "Wave scale", "min": 0.5, "max": 24.0, "step": 0.1,
		"tip": "How tightly packed shallow water's bands are, in radians per cell. Shallow water reads as busier than deep at the same number, so this is usually the higher of the pair."},
	{"group": "Water (shallow)", "node": "BoardMirror", "prop": "water_shallow_band_contrast", "label": "Band contrast", "min": 0.0, "max": 1.5, "step": 0.01,
		"tip": "How much shallow water's moving bands lighten the tile's own colour. Worth keeping lower than deep's once the bed is doing work -- bright hard bands over a visible bottom is what reads as ice."},
	{"group": "Water (shallow)", "node": "BoardMirror", "prop": "water_shallow_ripple", "label": "Ripple", "min": 0.0, "max": 2.0, "step": 0.01,
		"tip": "How hard shallow water's wave bends the surface normal, which is what makes the sun's highlight travel. High values scintillate, which fights the bed for attention."},
	{"group": "Water (shallow)", "node": "BoardMirror", "prop": "water_shallow_roughness", "label": "Roughness", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "How diffuse shallow water is. Rougher than deep is the usual reading -- a wadeable shallows is broken up, not glassy."},
	{"group": "Water (shallow)", "node": "BoardMirror", "prop": "water_shallow_specular", "label": "Specular", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "How strong shallow water's highlight is once Roughness lets there be one. A hard bright glint over a visible bottom is the ice reading; the bed wants to win here."},
	{"group": "Water (shallow)", "node": "BoardMirror", "prop": "water_shallow_seam", "label": "Cell seam", "min": 0.0, "max": 0.6, "step": 0.005,
		"tip": "How darkly shallow water draws its own cell boundaries. Usually lower than deep's -- the bed's mottle already breaks shallow water up, so it needs less help showing where a tile ends."},
	{"group": "Water (shallow)", "node": "BoardMirror", "prop": "water_shallow_body_shade", "label": "Body shade", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "How much darker a shallow block's WALLS and top rim read than its surface. Less than deep's is the physical reading: there is less water above you to darken it."},
	{"group": "Water (shallow)", "node": "BoardMirror", "prop": "water_shallow_bed", "label": "Bed", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "How much of the BOTTOM shows through. 0 is opaque water, 1 is clear. Deep water has no bed at all, and that asymmetry is most of how a wadeable tile is told apart from one that drowns you -- seeing the bed is also the difference between water and ICE."},
	{"group": "Water (shallow)", "node": "BoardMirror", "prop": "water_shallow_bed_color", "label": "Bed colour",
		"tip": "What the bottom is made of. Warm and desaturated is the point -- sand or silt under a cool surface is what reads as shallow WATER; a cool bed under a cool surface reads as a frozen pane. The water tints it on the way through, so this is the bed's own colour and not what you end up seeing."},
	{"group": "Water (shallow)", "node": "BoardMirror", "prop": "water_shallow_bed_grain", "label": "Bed grain", "min": 1.0, "max": 12.0, "step": 0.5,
		"tip": "Pebble size on the bottom, in art pixels. 1 is per-pixel silt, which at a playing camera distance averages out to nothing -- that is exactly why the first Bed knob appeared to do nothing at all."},
	{"group": "Water (shallow)", "node": "BoardMirror", "prop": "water_shallow_caustics", "label": "Caustics", "min": 0.0, "max": 2.0, "step": 0.01,
		"tip": "The rippling net of light on the bottom. It MOVES while the bed under it stays nailed to the board, and that contrast is the whole depth cue -- ice moves all of itself or none of it, so this is the one thing a frozen surface structurally cannot fake."},
	{"group": "Water (shallow)", "node": "BoardMirror", "prop": "water_shallow_caustics_scale", "label": "Caustics scale", "min": 1.0, "max": 30.0, "step": 0.5,
		"tip": "How tightly the light net is woven, in radians per cell. Low is a few broad shifting patches; high is a fine mesh. Worth keeping clearly different from Wave scale -- if the two agree, the bottom and the surface stop reading as separate layers."},
	{"group": "Water (shallow)", "node": "BoardMirror", "prop": "water_shallow_foam_width", "label": "Foam width", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "How far in from the shore the surf reaches, in HALF-cells -- 1.0 arrives at the cell's own centre, which is as far as a one-texel-per-cell mask can see. 0 turns foam off entirely. A shallow shore laps, so it can afford a wider softer band than deep water does."},
	{"group": "Water (shallow)", "node": "BoardMirror", "prop": "water_shallow_foam_color", "label": "Foam colour",
		"tip": "The surf's own colour, and its ALPHA is how hard it lands -- those are one decision, not two. Cool white is the safe read; pushing it warm makes shallow water read as a beach rather than a lake. Alpha 0 is the other way to turn foam off."},

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
const PACING_SCRIPT := "res://Classes/core/Pacing.gd"
const MISSION_STATUS_SCRIPT := "res://Classes/ui/MissionStatusPanel.gd"
const BOARD_SPACE_SCRIPT := "res://Classes/presentation/BoardSpace.gd"

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

	# The watched footprint (#413). It has to read as a THREAT while every range overlay is off, and
	# it is on screen for both sides at once, so its loudness is the one dial that decides whether
	# the board is legible or a christmas tree. Tune it against the reach fills, not away from white:
	# red already means a damaging reach, and a watch is a promise of exactly that.
	{"group": "Board markup colours", "label": "Watch footprint (2D+3D)", "static": "WATCH_MARK_COLOR",
		"tip": "The mark on every cell a standing Overwatch covers, yours and the enemy's alike. Always on screen while a watch is live, so this is the dial between 'unmissable' and 'noise'."},
	{"group": "Board markup colours", "label": "Watch mark size", "static": "WATCH_MARK_SCALE",
		"min": 0.25, "max": 2.0, "step": 0.05,
		"tip": "How big the watch mark draws relative to its cell. 1.0 is one cell exactly, which is what the art is authored at; smaller reads as a tick in the middle of the tile."},

	# AIMING a watch (#591), which is a different job from the mark above: these are on screen only
	# while the player is declaring, and what they have to say is "this is not an ordinary shot".
	# Tune them as a PAIR and against the reach fills -- the wash carries the glance and the footprint
	# has to stay legible on top of it, which is what the yellow-on-red pair does for a shot.
	{"group": "Board markup colours", "label": "Watch aim reach (2D+3D)", "static": "WATCH_REACH_MODULATE",
		"tip": "The reach fill while DECLARING an overwatch rather than firing. It replaces the red/green heal fork outright, on the grounds that you already know what you picked and cannot otherwise tell you are aiming a watch."},
	{"group": "Board markup colours", "label": "Watch aim footprint (2D+3D)", "static": "WATCH_HOVER_MODULATE",
		"tip": "The cells a watch aim would actually cover, drawn over the reach fill above -- the watch's answer to the yellow an ordinary aim uses. Its pulsed low point is derived from this, so there is no third colour to chase."},

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

	# The armed-Guard pair (#414 shield, #450 arrow). The statics existed from #414 and their own
	# comment called them the loudness knobs, but neither had ever had a row in any panel -- so the
	# one knob the dev asked for brought its two siblings with it rather than leaving a mark half
	# tunable. The arrow ships WHITE deliberately: see GUARD_LINK_MODULATE's declaration.
	{"group": "Board markup colours", "label": "Guard link arrow", "static": "GUARD_LINK_MODULATE",
		"tip": "The arrow running from a bodyguard to the unit it is covering. Starts neutral white, so this picker is the whole colour rather than a shade over one baked into the art. Tune it against the arrow palette -- cyan already means a queued move, red a refused one, green a member falling behind. Takes effect on links already on the board."},
	{"group": "Board markup colours", "label": "Guard link head inset", "static": "GUARD_LINK_HEAD_INSET",
		"min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "How far back from the ward's cell centre the link's arrowhead stops, in cells. 0 puts it on the shield, which is what the dev reported as unreadable; 0.5 parks it on the edge the pair shares and leaves three columns of overlap; about 0.7 clears the shield outright. Redraws links already on the board."},
	{"group": "Board markup colours", "label": "Guard ward shield", "static": "GUARD_RING_COLOR",
		"tip": "The shield decal under the unit a Guard is protecting -- the other half of the mark the arrow above points at. Neutral white by default now the art is real."},

	# The tile-pick flash (#116). A PERIOD and a peak ALPHA rather than a colour: the pick borrows
	# the reach layer, whose hue is already the two knobs above, so a flash that set its own colour
	# would be a second answer to what that layer looks like.
	{"group": "Board markup colours", "label": "Tile-pick flash alpha", "static": "PICK_FLASH_ALPHA",
		"min": 0.1, "max": 1.0, "step": 0.01,
		"tip": "How opaque the candidate tiles go at the top of their flash while a rescue is asking which bank to pull a body onto. It breathes between the layer's own alpha and this one, so the hue never changes. Takes effect on the next pick."},
	{"group": "Board markup colours", "label": "Tile-pick flash period", "static": "PICK_FLASH_PERIOD",
		"min": 0.05, "max": 2.0, "step": 0.05,
		"tip": "Seconds for HALF a flash cycle -- the time from the layer's own alpha up to the peak, then the same back down. Smaller is a faster blink. Takes effect on the next pick."},

	# The #325 rings. A float rather than a colour, and the reason this table is named for WHERE a
	# value lives rather than for what type it is: ring alpha is a static on OverlayManager, exactly
	# like the two reach colours above, and both stacks read it.
	{"group": "Squad markers", "label": "Ring opacity", "static": "SQUAD_RING_ALPHA",
		"min": 0.1, "max": 1.0, "step": 0.01,
		"tip": "Alpha of the per-squad membership rings under each member (the leader's crown, over the head, stays opaque). Takes effect on markers already up."},
	{"group": "Squad markers", "label": "Ring pulse brightness", "static": "SQUAD_RING_PULSE_GAIN",
		"min": 1.0, "max": 3.0, "step": 0.05,
		"tip": "How much brighter a squad ring goes at the top of its pulse while Join Squad is picking a squad. A gain on the ring's own hue, so a pulsing ring still reads as its squad's colour. 1.0 is no pulse at all. Takes effect on the next pick."},

	# The mission clock's urgency cue (#101). Statics on MissionStatusPanel, which is 2D UI under the
	# game's own ui_layer -- KNOBS resolves against the Battle3D host and structurally cannot reach
	# it, so a class row is the only form available, not a preference.
	{"group": "Mission HUD", "label": "Clock urgency threshold", "static": "URGENT_ROUNDS",
		"script": MISSION_STATUS_SCRIPT, "min": 0.0, "max": 10.0, "step": 1.0,
		"tip": "How many rounds must be left before the mission clock changes colour. This is the whole warning a player gets that they are running out of time -- the dev call was to colour the countdown rather than interrupt with a confirm, so set it high enough that the change lands while there is still something to do about it. Zero never warns."},
	{"group": "Mission HUD", "label": "Clock urgency tint", "static": "URGENT_COLOR",
		"script": MISSION_STATUS_SCRIPT,
		"tip": "What the countdown turns once it is inside the threshold above. Reads against the plain white of an objective still pending, so it has to say urgent without reading as the red that means a mission cannot be won at all."},

	# --- PLAYBACK, in six sections (dev, 2026-08-27) ------------------------------------------
	#
	# It was ONE group of thirty flat rows and unreadable at that length: "I also see a lot of
	# similar controls, per action... it might be best to have an actions section, where there's a
	# dropdown with each action in it". The split costs no machinery -- GROUP_TABS already maps
	# several groups onto one tab (Water does it) and _add_heading already fires per group -- so a
	# section is a group name, and the rows below simply have to stay contiguous within one.
	#
	# Two optional TAGS drive the page's filters, and a row carrying neither is always shown:
	#   "profile" -- "board" / "cinematic": which battle-zoom state this row is live under. The pairs
	#                read as a binary toggle rendered wrong ("having them as two options next to each
	#                other with value sliders makes them very hard to understand"), when they are one
	#                dial measured under each mode. The page shows one column at a time.
	#   "action"  -- an ActionType: which entry of the Actions dropdown owns this row.
	#
	# Both are inert to every existing law: the generic loops read only the keys they know, and
	# GameTool BUILDS every row either way and toggles visibility (see _apply_playback_filter).

	# THE PROFILE: the same three dials, once per battle-zoom state. Only the column matching the
	# toggle at the top of the page is shown, so a slider that would be inert is never in front of
	# you. The base beat is the ragged cell -- zoom OFF forks again on whose pass it is, zoom ON does
	# not (#410 rules the zoom fires for every combat) -- and it stays here rather than in Actions
	# below, per the dev: "if there's a base value that these sliders all execute against, that base
	# value shouldn't then be tied to one of the actions."
	{"group": "The profile", "label": "Base beat: your own Execute", "static": "PLAYER_ACTION",
		"profile": "board", "script": PACING_SCRIPT, "min": 0.0, "max": 2.0, "step": 0.05,
		"tip": "The floor under EVERY beat on your own pass -- what a blast waits before it plays, before anything it earns on top. Was 0.0 until 2026-08-26; no gap at all is what made health readouts flash in and out. Zero restores that."},
	{"group": "The profile", "label": "Base beat: an AI pass", "static": "AI_ACTION",
		"profile": "board", "script": PACING_SCRIPT, "min": 0.0, "max": 2.0, "step": 0.05,
		"tip": "The same floor on an AI faction's pass. Longer than yours on purpose: their plan is being read for the first time, yours was authored by the person watching it. The battle zoom has no such fork -- flip the toggle above to see its one row."},
	{"group": "The profile", "label": "Base beat", "static": "CINEMATIC_ACTION",
		"profile": "cinematic", "script": PACING_SCRIPT, "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "The floor under every beat with the battle zoom on. ONE row rather than two: the zoom does not fork on whose pass it is, because it fires for every combat, enemy assaults included."},
	{"group": "The profile", "label": "Drama", "static": "BOARD_DRAMA",
		"profile": "board", "script": PACING_SCRIPT, "min": 0.0, "max": 2.0, "step": 0.05,
		"tip": "How much of the Actions and Outcomes holds apply with the zoom off. SHIPS AT 0, which is why every hold row further down does nothing in this column -- the plain board is deliberately flat. Raise it to let a death land harder than a scratch here too. Lingers are NOT scaled by this."},
	{"group": "The profile", "label": "Drama", "static": "CINEMATIC_DRAMA",
		"profile": "cinematic", "script": PACING_SCRIPT, "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "The same multiplier with the zoom on, and this is the one dial for 'more dramatic' overall. At 0 the zoom paces flat; above 1 every big moment stretches together. Lingers are NOT scaled by this -- they are matched to an animation, not to a mood."},
	{"group": "The profile", "label": "Camera angle", "static": "BOARD_DIRECTION",
		"profile": "board", "script": PACING_SCRIPT, "min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "How far the camera turns to see each blast side-on with the zoom off. Ships at 0 -- square-on, exactly as the enemy phase has always played. At 1 it takes the full profile shot."},
	{"group": "The profile", "label": "Camera angle", "static": "CINEMATIC_DIRECTION",
		"profile": "cinematic", "script": PACING_SCRIPT, "min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "The same turn with the zoom on. 1 puts the attacker and their target across the frame instead of one behind the other; part-way is a hint of the angle without leaving the square-on read."},

	# THE ACTIONS SECTION (dev, 2026-08-27). One picker, two rows: what each verb waits BEFORE it
	# plays and how long the camera STAYS after. Attack is folded in as an entry of its own, which is
	# what the dev found missing -- "I don't see controls for holding the most common thing, a regular
	# attack" -- and the dropdown is what keeps this from being twenty flat rows: a verb that grows a
	# third dial costs no page.
	#
	# Attack's numbers are read by hold_for/linger_for's VOLLEY branch rather than by
	# coda_hold/coda_linger, which answer for side-channel verbs only. Same page, different lookup.
	{"group": "Actions", "label": "Hold: an attack", "static": "HOLD_ATTACK",
		"action": BaseAction.ActionType.ATTACK,
		"script": PACING_SCRIPT, "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "Base extra time for a blast that just does damage -- the FLOOR every Outcomes row is measured against. Holds do not stack, so a rung set below this one can never lengthen a beat. It had no row at all until 2026-08-27, which left the commonest beat in the game with nothing but the base beat."},
	{"group": "Actions", "label": "Linger: an attack", "static": "LINGER_ATTACK",
		"action": BaseAction.ActionType.ATTACK,
		"script": PACING_SCRIPT, "min": 0.0, "max": 4.0, "step": 0.05,
		"tip": "How long the camera stays after a hit lands, in seconds -- the pause that lets you watch the health cubes come off. Zero is the pre-2026-08-27 behaviour, where the pass cut away mid-burst. A death overrides this with its own longer linger on the Outcomes section."},
	{"group": "Actions", "label": "Hold: a rescue", "static": "HOLD_RESCUE",
		"action": BaseAction.ActionType.RESCUE,
		"script": PACING_SCRIPT, "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "Extra time when a body is picked up off the floor. Ships long: it is the loudest thing in the tail."},
	{"group": "Actions", "label": "Linger: a rescue", "static": "LINGER_RESCUE",
		"action": BaseAction.ActionType.RESCUE,
		"script": PACING_SCRIPT, "min": 0.0, "max": 4.0, "step": 0.05,
		"tip": "How long the camera stays once the body is up and hauled onto the tile you picked."},
	{"group": "Actions", "label": "Hold: a capture", "static": "HOLD_CAPTURE",
		"action": BaseAction.ActionType.CAPTURE,
		"script": PACING_SCRIPT, "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "Extra time when a zone is taken. Ships beside the rescue hold -- it is the moment a mission moves."},
	{"group": "Actions", "label": "Linger: a capture", "static": "LINGER_CAPTURE",
		"action": BaseAction.ActionType.CAPTURE,
		"script": PACING_SCRIPT, "min": 0.0, "max": 4.0, "step": 0.05,
		"tip": "How long the camera stays on a zone that has just changed hands."},
	{"group": "Actions", "label": "Hold: a rally", "static": "HOLD_RALLY",
		"action": BaseAction.ActionType.RALLY,
		"script": PACING_SCRIPT, "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "Extra time when Will comes back."},
	{"group": "Actions", "label": "Linger: a rally", "static": "LINGER_RALLY",
		"action": BaseAction.ActionType.RALLY,
		"script": PACING_SCRIPT, "min": 0.0, "max": 4.0, "step": 0.05,
		"tip": "How long the camera stays after Will comes back."},
	{"group": "Actions", "label": "Hold: an intimidate", "static": "HOLD_INTIMIDATE",
		"action": BaseAction.ActionType.INTIMIDATE,
		"script": PACING_SCRIPT, "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "Extra time when Will is drained out of someone."},
	{"group": "Actions", "label": "Linger: an intimidate", "static": "LINGER_INTIMIDATE",
		"action": BaseAction.ActionType.INTIMIDATE,
		"script": PACING_SCRIPT, "min": 0.0, "max": 4.0, "step": 0.05,
		"tip": "How long the camera stays on the unit whose Will just went."},
	{"group": "Actions", "label": "Hold: a guard arming", "static": "HOLD_GUARD",
		"action": BaseAction.ActionType.GUARD,
		"script": PACING_SCRIPT, "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "Extra time when a bodyguard takes up station. Arms last in the pass, after every hit it was resolved against has played."},
	{"group": "Actions", "label": "Linger: a guard arming", "static": "LINGER_GUARD",
		"action": BaseAction.ActionType.GUARD,
		"script": PACING_SCRIPT, "min": 0.0, "max": 4.0, "step": 0.05,
		"tip": "How long the camera stays on a bodyguard that has just taken station."},
	{"group": "Actions", "label": "Hold: a watch arming", "static": "HOLD_OVERWATCH",
		"action": BaseAction.ActionType.OVERWATCH,
		"script": PACING_SCRIPT, "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "Extra time when a unit takes up an overwatch. Sits beside the guard hold -- both are a unit settling into a stance rather than doing something."},
	{"group": "Actions", "label": "Linger: a watch arming", "static": "LINGER_OVERWATCH",
		"action": BaseAction.ActionType.OVERWATCH,
		"script": PACING_SCRIPT, "min": 0.0, "max": 4.0, "step": 0.05,
		"tip": "How long the camera stays on a unit that has just settled into a watch."},
	{"group": "Actions", "label": "Hold: a burrow", "static": "HOLD_BURROW",
		"action": BaseAction.ActionType.BURROW,
		"script": PACING_SCRIPT, "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "Extra time when a unit digs itself cover."},
	{"group": "Actions", "label": "Linger: a burrow", "static": "LINGER_BURROW",
		"action": BaseAction.ActionType.BURROW,
		"script": PACING_SCRIPT, "min": 0.0, "max": 4.0, "step": 0.05,
		"tip": "How long the camera stays on the cover a unit has just dug."},
	{"group": "Actions", "label": "Hold: a reload", "static": "HOLD_RELOAD",
		"action": BaseAction.ActionType.RELOAD,
		"script": PACING_SCRIPT, "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "Extra time for working the action. Ships short -- housekeeping, not drama."},
	{"group": "Actions", "label": "Linger: a reload", "static": "LINGER_RELOAD",
		"action": BaseAction.ActionType.RELOAD,
		"script": PACING_SCRIPT, "min": 0.0, "max": 4.0, "step": 0.05,
		"tip": "How long the camera stays after the action is worked. Ships short, like its hold."},
	{"group": "Actions", "label": "Hold: a rev", "static": "HOLD_REV",
		"action": BaseAction.ActionType.REV,
		"script": PACING_SCRIPT, "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "Extra time for spinning a chainsword up. Ships short, beside the reload."},
	{"group": "Actions", "label": "Linger: a rev", "static": "LINGER_REV",
		"action": BaseAction.ActionType.REV,
		"script": PACING_SCRIPT, "min": 0.0, "max": 4.0, "step": 0.05,
		"tip": "How long the camera stays on a chainsword that has just spun up."},

	# The OUTCOMES a blast earns extra time for, on top of the Actions floor above. Largest wins.
	{"group": "Outcomes", "label": "Hold: a unit goes down", "static": "HOLD_DOWN",
		"script": PACING_SCRIPT, "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "Extra time a blast earns for downing, killing, maiming or removing someone. Holds do NOT stack -- the largest single one wins -- so these numbers ARE the drama ranking. Set this under the shove hold and a shove outranks a death."},
	{"group": "Outcomes", "label": "Hold: Crisis", "static": "HOLD_CRISIS",
		"script": PACING_SCRIPT, "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "Extra time when someone stands up surged instead of falling. The loudest thing that can happen to a unit, so it ships as the longest hold."},
	{"group": "Outcomes", "label": "Hold: Iron Will save", "static": "HOLD_IRON_WILL",
		"script": PACING_SCRIPT, "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "Extra time when the Iron Will cap actually BIT -- that should have killed them and did not. The held breath, as against the blow that lands."},
	{"group": "Outcomes", "label": "Hold: a shove", "static": "HOLD_KNOCKBACK",
		"script": PACING_SCRIPT, "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "Extra time when the hit knocked its target back. Pre-set small: a shove is worth a moment, not the moment a death gets."},
	{"group": "Outcomes", "label": "Hold: counter turnover", "static": "HOLD_TURNOVER",
		"script": PACING_SCRIPT, "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "The act break between the attacker's last swing and the defending line's answer. Held once per pass, not per counter."},
	{"group": "Outcomes", "label": "Hold: a heal", "static": "HOLD_HEAL",
		"script": PACING_SCRIPT, "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "Extra time when HP came back -- a player-aimed heal or a reactive one. The table had no row for this until 2026-08-26, so a heal was the flattest thing a pass could contain."},

	{"group": "Outcomes", "label": "Linger: a unit goes down", "static": "LINGER_DOWN",
		"script": PACING_SCRIPT, "min": 0.0, "max": 4.0, "step": 0.05,
		"tip": "How long the camera STAYS after a blast that took someone out, in seconds. A death bursts the unit's whole remaining health grid at once rather than chipping a few cubes off it, so it is categorically longer to watch than the plain hit below -- which is why it is the one outcome with a linger of its own. Largest wins, exactly like the holds. NOT scaled by Drama: the burst animation runs in real time in both profiles."},

	# The beat table (#519, umbrella #410). Playback pacing had never had a door -- these are the
	# five #118 constants plus the battle-beat shape, all read at each pass, so a change applies
	# from the next Execute with nothing standing to re-apply it to.
	{"group": "Camera travel", "label": "Camera travel to the action", "static": "PLAYBACK_PAN",
		"script": PACING_SCRIPT, "min": 0.0, "max": 2.0, "step": 0.05,
		"tip": "How long the camera takes to reach the next blast, in seconds -- and therefore how long the action waits for it. Fixed duration, not speed, so a short hop and a long one read at the same pace. Zero snaps."},
	{"group": "Camera travel", "label": "Camera travel to a burning unit", "static": "ENVIRONMENT_PAN",
		"script": PACING_SCRIPT, "min": 0.0, "max": 2.0, "step": 0.05,
		"tip": "How long the camera takes to reach each unit in the end-of-turn effect pass -- today, everyone standing in fire. Its own number rather than a share of the blast travel above, because this phase is bookkeeping and paced against the others, not with them. Zero snaps."},
	{"group": "Camera travel", "label": "Hold: a unit burns", "static": "ENVIRONMENT_HOLD",
		"script": PACING_SCRIPT, "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "How long the camera stays on a burning unit AFTER its damage lands, in seconds. This is the pause that shows the health drop, so it is the dial for how legible the pass is. Does not fork on the battle zoom -- the board acts here, not a faction."},
	# What the camera does once it has ARRIVED (#520 diff 2b) -- the impact jolt and the resting
	# drift. The two split on the profile question and NOT the same way, which is the thing to know
	# before tuning: a jolt is matched to the health cubes bursting on their own real-time clock, so
	# it is flat and applies with the battle zoom off too; a sway is anticipation, so it dials out
	# with everything else on the plain board.
	{"group": "Camera flourish", "label": "Jolt: a hit lands", "static": "SHAKE_HIT",
		"script": PACING_SCRIPT, "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "How hard the camera is knocked when a blow takes health off someone, in cells. Fires on the health-cube burst itself, so the jolt and the cubes always agree about when the hit landed. Applies in BOTH profiles -- it is matched to an animation, not to the drama. Zero is no shake."},
	{"group": "Camera flourish", "label": "Jolt: a unit goes down", "static": "SHAKE_DOWN",
		"script": PACING_SCRIPT, "min": 0.0, "max": 2.0, "step": 0.01,
		"tip": "How hard the camera is knocked when a unit is killed or removed, in cells. A killing hit fires ONLY this one, never the hit jolt above -- so this is the whole of what a death feels like, not an extra on top."},
	{"group": "Camera flourish", "label": "Jolt: how fast it dies", "static": "SHAKE_DECAY",
		"script": PACING_SCRIPT, "min": 1.0, "max": 40.0, "step": 0.5,
		"tip": "How quickly a jolt fades out. Higher is snappier -- a sharp rap rather than a wobble. Shared by both jolts above, so they read as one camera with one weight."},
	{"group": "Camera flourish", "label": "Jolt: how fast it shakes", "static": "SHAKE_FREQUENCY",
		"script": PACING_SCRIPT, "min": 4.0, "max": 90.0, "step": 1.0,
		"tip": "How fast the jolt oscillates. Low reads as a heave, high as a rattle. With the decay above, these two are the whole character of an impact."},
	{"group": "Camera flourish", "label": "Sway: how far", "static": "SWAY_AMPLITUDE",
		"script": PACING_SCRIPT, "min": 0.0, "max": 0.5, "step": 0.01,
		"tip": "How far the camera drifts while it is resting on a shot, in cells -- the hand-held breath that keeps a held frame from reading as a screenshot. Zero is a locked-off camera."},
	{"group": "Camera flourish", "label": "Sway: how fast", "static": "SWAY_SPEED",
		"script": PACING_SCRIPT, "min": 0.1, "max": 5.0, "step": 0.05,
		"tip": "How fast that drift breathes. It is two waves at an irrational ratio rather than one, so the bob never quite repeats -- this sets the slower of them."},
	{"group": "Camera flourish", "label": "Sway strength (zoom off)", "static": "BOARD_SWAY",
		"profile": "board", "script": PACING_SCRIPT, "min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "How much of the sway applies on the plain board. Ships at 0 -- the board is as still as it has always been -- so wanting some breath down here later is this one number rather than a restructure."},
	{"group": "Camera flourish", "label": "Sway strength (zoom on)", "static": "CINEMATIC_SWAY",
		"profile": "cinematic", "script": PACING_SCRIPT, "min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "How much of the sway applies with the battle zoom on."},
	# Lethality-aware direction (#520 diff 2c). The push-in leans on the player's own zoom rather
	# than replacing it, so these move how far the director may lean -- never where the wheel sits.
	{"group": "Camera flourish", "label": "Shot: push-in on the loudest beat", "static": "DOLLY_IN",
		"profile": "cinematic", "script": PACING_SCRIPT, "min": 0.0, "max": 10.0, "step": 0.1,
		"tip": "How much closer the camera sits on a killing blow, in world units, at full emphasis. SUBTRACTED from wherever you have left the zoom, so the wheel keeps working underneath and the push-in comes off when the beat ends. Scaled by the directed-shot strength, so it is dead on the plain board."},
	{"group": "Camera flourish", "label": "Shot: how close the push-in may get", "static": "DOLLY_FLOOR",
		"script": PACING_SCRIPT, "min": 0.5, "max": 20.0, "step": 0.5,
		"tip": "The nearest the PUSH-IN alone may bring the camera. It never overrides your own zoom: if you are already closer than this, the push-in simply does nothing rather than pulling you back out. There is no floor on the wheel itself, by design -- this only stops the director flying through a unit."},
	{"group": "Camera flourish", "label": "Emphasis: a unit goes down", "static": "EMPHASIS_DOWN",
		"script": PACING_SCRIPT, "min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "How big a moment a death is, 0 to 1 -- the weight that drives the push-in. Loudest rung wins, so this is the top of the ladder. An ordinary hit earns 0 and is the baseline the rest are read against."},
	{"group": "Camera flourish", "label": "Emphasis: someone stands up surged", "static": "EMPHASIS_CRISIS",
		"script": PACING_SCRIPT, "min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "How big a Crisis is. Its own number rather than a share of the death rung: the two rankings may legitimately disagree, since a hold and a kill want different shots."},
	{"group": "Camera flourish", "label": "Emphasis: that should have killed them", "static": "EMPHASIS_IRON_WILL",
		"script": PACING_SCRIPT, "min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "How big a capped hit is -- the blow that should have been lethal and was not. It earns a long PAUSE from the holds table already; this is separately how much of a push-in it earns."},
	{"group": "Camera flourish", "label": "Freeze: a killing blow", "static": "HITSTOP_DOWN",
		"profile": "cinematic", "script": PACING_SCRIPT, "min": 0.0, "max": 0.5, "step": 0.01,
		"tip": "How long EVERYTHING stops when a unit is killed, in real seconds -- the whole world, not just the camera. Zero is no freeze. The health cubes stop with it and resume with it, so the pause after a death still covers the burst exactly."},
	{"group": "Camera flourish", "label": "Freeze strength (zoom off)", "static": "BOARD_HITSTOP",
		"profile": "board", "script": PACING_SCRIPT, "min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "How much of that freeze the plain board gets. Ships at 0 -- a freeze CREATES time rather than matching an animation, so unlike the jolt it is drama and dials out with everything else down here."},
	{"group": "Camera flourish", "label": "Freeze strength (zoom on)", "static": "CINEMATIC_HITSTOP",
		"profile": "cinematic", "script": PACING_SCRIPT, "min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "How much of that freeze applies with the battle zoom on."},
	{"group": "Camera flourish", "label": "Shot: how far the camera stoops", "static": "PITCH_DIVE",
		"profile": "cinematic", "script": PACING_SCRIPT, "min": 0.0, "max": 40.0, "step": 0.5,
		"tip": "How many degrees SHALLOWER than the board's own angle a directed shot sits, so the fight looms instead of being read from overhead. Clamped by the same tilt band the player's drag uses. Scaled by the directed-shot strength, so it is dead on the plain board for the same reason the side-on angle is."},

	{"group": "The tear-out", "label": "How long one tile flies", "static": "TEAR_OUT_FLIGHT",
		"profile": "cinematic", "script": PACING_SCRIPT, "min": 0.0, "max": 6.0, "step": 0.01,
		"tip": "How long a single tile takes to travel between its socket on the board and its place in the diorama. At 0 tiles appear where they are going instead of flying there."},
	{"group": "The tear-out", "label": "Window the tiles arrive within", "static": "TEAR_OUT_ARRIVAL",
		"profile": "cinematic", "script": PACING_SCRIPT, "min": 0.0, "max": 12.0, "step": 0.05,
		"tip": "The total time every tile must have STARTED within. The gap between one tile and the next is derived to fit this, so a twenty-cell brawl does not cost five times what a four-cell skirmish does -- this plays on every Execute."},
	{"group": "The tear-out", "label": "Longest gap between two tiles", "static": "TEAR_OUT_STAGGER_MAX",
		"profile": "cinematic", "script": PACING_SCRIPT, "min": 0.0, "max": 3.0, "step": 0.01,
		"tip": "A ceiling on the derived gap, so a small fight still gets a punchy one-two-three instead of smearing three tiles across the whole window. At 0 every tile leaves at once."},
	{"group": "The tear-out", "label": "How hard a tile slams in", "static": "TEAR_OUT_SLAM",
		"profile": "cinematic", "script": PACING_SCRIPT, "min": 1.0, "max": 16.0, "step": 0.1,
		"tip": "The shape of a tile's travel. 1 is constant speed; higher makes it hang back and then accelerate into the landing, which is what reads as a slam rather than a drift."},
	{"group": "The tear-out", "label": "White-out fade", "static": "TEAR_OUT_WHITEOUT",
		"profile": "cinematic", "script": PACING_SCRIPT, "min": 0.0, "max": 3.0, "step": 0.01,
		"tip": "How long the flash takes to come up, and again to go down. With the photosensitivity setting on this timing is unchanged but the flash is muted and eased instead of white."},
	{"group": "The tear-out", "label": "White-out hold", "static": "TEAR_OUT_HOLD",
		"profile": "cinematic", "script": PACING_SCRIPT, "min": 0.0, "max": 3.0, "step": 0.01,
		"tip": "How long the flash sits at full before the diorama is revealed behind it. This is the window the camera cut hides in."},
	{"group": "The tear-out", "label": "Camera holds with the board", "static": "TEAR_OUT_CAMERA_HOLD",
		"profile": "cinematic", "script": PACING_SCRIPT, "min": 0.0, "max": 6.0, "step": 0.05,
		"tip": "How long the camera stays down with the board, watching the tiles leave, before it rises after them. Only read when the camera-cuts-ahead experiment is OFF -- with it on the camera is already up there waiting."},

	{"group": "The tear-out", "label": "Hold: the board before it comes apart", "static": "TEAR_OUT_BRACE",
		"profile": "cinematic", "script": PACING_SCRIPT, "min": 0.0, "max": 6.0, "step": 0.05,
		"tip": "A beat on the intact board once the walking is done, before the ground starts to lift. At 0 the tear-out begins the instant the last unit stops moving."},
	{"group": "The tear-out", "label": "Hold: empty sky, before the first tile", "static": "TEAR_OUT_EMPTY_SKY",
		"profile": "cinematic", "script": PACING_SCRIPT, "min": 0.0, "max": 6.0, "step": 0.05,
		"tip": "How long the camera looks at the space where the diorama WILL be, with nothing in it yet, before the first tile rises into frame. This is the beat the camera-hold slider gets reached for by mistake -- that one is dead while the camera cuts ahead, and this one is not."},
	{"group": "The tear-out", "label": "Hold: the diorama, before the fight", "static": "TEAR_OUT_SETTLE",
		"profile": "cinematic", "script": PACING_SCRIPT, "min": 0.0, "max": 6.0, "step": 0.05,
		"tip": "A beat on the finished diorama after the last tile lands, before the first blow. At 0 the action starts the moment the ground stops moving."},
	{"group": "The tear-out", "label": "Hold: the diorama, after the fight", "static": "TEAR_OUT_AFTERMATH",
		"profile": "cinematic", "script": PACING_SCRIPT, "min": 0.0, "max": 6.0, "step": 0.05,
		"tip": "A beat on the diorama once the fighting is over, before the tiles drop back into their sockets -- so the aftermath is not immediately swept away by the board reassembling."},

	# The tear-out is its own section because it is CINEMATIC-ONLY by construction: _stage_the_fight
	# returns early on BOARD, so this slider is dead in the other column rather than merely unused.
	{"group": "The tear-out", "label": "How high the fight lifts off the board", "static": "STAGE_LIFT",
		"profile": "cinematic", "script": BOARD_SPACE_SCRIPT, "min": 0.0, "max": 60.0, "step": 0.5,
		"tip": "How far above the board the torn-out diorama sits, in cells. The fight plays up there and the tiles thud back into their sockets when it ends. At 0 the diorama sits inside the board it came from. Nothing stages at all with the battle zoom off."},

	# The shove slide (#259 rework). A static on MovementComponent -- per-unit nodes, so no single
	# node property to address -- hence a class row with its own script home.
	{"group": "Motion", "label": "Shove slide speed", "static": "SHOVE_SLIDE_SPEED",
		"script": MOVEMENT_SCRIPT, "min": 60.0, "max": 960.0, "step": 10.0,
		"tip": "How fast a shoved unit slides along its knockback trail, in pixels/second (a walk is 120). Read at each shove, so a change applies from the next one."},
	{"group": "Motion", "label": "Shove fall speed", "static": "SHOVE_FALL_SPEED",
		"script": MOVEMENT_SCRIPT, "min": 0.5, "max": 20.0, "step": 0.1,
		"tip": "How fast a shoved unit DROPS at a break in its slide, in cells/second -- off a cliff, off a ramp's lip, wherever the trail hangs a drop pointer. The slide pauses for exactly this long and then carries on, which is what makes it read as fly-then-fall instead of a teleport. Read at each fall."},

	# The void plummet (#431), the same shape one row along. The DEPTH is read twice -- by the fall
	# and by the preview pointer's length -- so this one slider moves both, which is the point.
	{"group": "Motion", "label": "Void fall depth", "static": "VOID_PLUMMET_CELLS",
		"script": MOVEMENT_SCRIPT, "min": 1.0, "max": 40.0, "step": 0.5,
		"tip": "How far a unit shoved into a hole keeps falling before it is removed, in cells below the lip. The plan-time drop arrow reaches exactly this far too, so raising it lengthens both. Read at each shove."},
	{"group": "Motion", "label": "Void fall time", "static": "VOID_PLUMMET_SECONDS",
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
	{"group": "Action ring", "label": "Readout panel", "static": "READOUT_BACKGROUND",
		"script": ACTION_MENU_SCRIPT,
		"tip": "The block behind the hovered slice's name and explanation, under the ring. It sits over a live board, so opacity here is legibility -- the first version had none and was painful to read."},
	{"group": "Action ring", "label": "Readout border", "static": "READOUT_BORDER",
		"script": ACTION_MENU_SCRIPT,
		"tip": "The outline around that block. Enough to separate it from whatever is behind it."},
	{"group": "Action ring", "label": "Readout border width", "static": "READOUT_BORDER_WIDTH",
		"script": ACTION_MENU_SCRIPT, "min": 0.0, "max": 8.0, "step": 0.5,
		"tip": "How thick that outline is drawn. Zero removes it."},
	{"group": "Action ring", "label": "Readout name", "static": "READOUT_TITLE_COLOR",
		"script": ACTION_MENU_SCRIPT,
		"tip": "The hovered slice's NAME, and every wedge label too. Kept fully opaque on purpose: the hierarchy against the explanation below is brightness, never transparency."},
	{"group": "Action ring", "label": "Readout detail", "static": "READOUT_DETAIL_COLOR",
		"script": ACTION_MENU_SCRIPT,
		"tip": "The explanation under that name -- what the option does, and why it is greyed when it is. Dimmer than the name, but still solid."},
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
# Which tab carries the battle-zoom toggle and the profile columns, and which group carries the
# action picker (#520 2b slice 2). Named here rather than spelled in GameTool, so the panel has no
# opinion about what a section is called -- the table stays the one declaration.
const PROFILE_TAB := "Playback"
const ACTION_GROUP := "Actions"


# The verbs the Actions section can show, in the order its picker lists them. DERIVED from the
# registry rather than written down: ATTACK first because it is the commonest beat by far, then
# SIDE_CHANNEL_ORDER's own order, which is also the order the tail plays in. A verb added to the
# registry appears here with no edit, and tests/law/test_action_registry.gd is what refuses one that
# arrives without its knobs.
static func tunable_actions() -> Array[BaseAction.ActionType]:
	var types: Array[BaseAction.ActionType] = [BaseAction.ActionType.ATTACK]
	types.append_array(BaseAction.SIDE_CHANNEL_ORDER)
	return types


# The picker's label for a verb, and its inverse. The enum's own key, title-cased -- so a new verb
# needs no name typed anywhere, and the two can never disagree about one.
static func action_label(type: BaseAction.ActionType) -> String:
	return String(BaseAction.ActionType.keys()[type]).capitalize()


static func action_for_label(label: String) -> BaseAction.ActionType:
	for type: BaseAction.ActionType in tunable_actions():
		if action_label(type) == label:
			return type
	return BaseAction.ActionType.ATTACK


const GROUP_TABS: Dictionary[String, String] = {
	"Board markup": "Markup",
	"Dev chrome": "Markup",
	"Board markup colours": "Colours",
	"Squad markers": "Colours",
	"Unit HUD": "Unit HUD",
	"Mission HUD": "Mission",
	"Camera handling": "Camera",
	"World": "World",
	# Water took its OWN sub-tab once every dial went per type (#552): twenty-one rows under the prop
	# lamps on World is a scroll rather than a panel. Two groups into one tab, and since a group draws
	# its own heading inside a tab it reads as Water (deep) / Water (shallow) -- which is also why the
	# split needs no third table, only a second group name.
	"Water (deep)": "Water",
	"Water (shallow)": "Water",
	# Elemental VFX, not just fire (#420). Ice draws as a flat Layer.TERRAIN icon with no 3D effect
	# and so has nothing to put here yet; Cover arrives with fire because #326 ruled it the same
	# kind of thing -- a terrain STATE whose art draws objects. A new element is one line.
	"Fire": "Elemental",
	"Cover": "Elemental",
	# Playback is SIX groups on one tab (dev, 2026-08-27) -- thirty flat rows was unreadable, and a
	# group is what draws a heading. Same two-groups-one-tab shape Water uses, three sections further.
	# Declaration order here is only the TAB order; the section order inside the tab is the KNOBS
	# table's own, which is why those rows are kept contiguous and in this same sequence.
	"The profile": "Playback",
	"Actions": "Playback",
	"Outcomes": "Playback",
	"Camera travel": "Playback",
	# ...and a SEVENTH since #520 diff 2b. Its own group rather than more rows under the travel one
	# because they answer different questions: that section is how long the camera takes to GET
	# somewhere, this is what it does once it is there.
	"Camera flourish": "Playback",
	"The tear-out": "Playback",
	"Motion": "Playback",
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
		"WATCH_MARK_COLOR": return OverlayManager.WATCH_MARK_COLOR
		"WATCH_MARK_SCALE": return OverlayManager.WATCH_MARK_SCALE
		"WATCH_REACH_MODULATE": return OverlayManager.WATCH_REACH_MODULATE
		"WATCH_HOVER_MODULATE": return OverlayManager.WATCH_HOVER_MODULATE
		"MOVE_ARROW_MODULATE": return OverlayManager.MOVE_ARROW_MODULATE
		"INVALID_ARROW_MODULATE": return OverlayManager.INVALID_ARROW_MODULATE
		"TRAILING_ARROW_MODULATE": return OverlayManager.TRAILING_ARROW_MODULATE
		"GUARD_LINK_MODULATE": return OverlayManager.GUARD_LINK_MODULATE
		"GUARD_LINK_HEAD_INSET": return OverlayManager.GUARD_LINK_HEAD_INSET
		"GUARD_RING_COLOR": return OverlayManager.GUARD_RING_COLOR
		"PICK_FLASH_ALPHA": return OverlayManager.PICK_FLASH_ALPHA
		"PICK_FLASH_PERIOD": return OverlayManager.PICK_FLASH_PERIOD
		"PLAYBACK_PAN": return Pacing.PLAYBACK_PAN
		"TEAR_OUT_BRACE": return Pacing.TEAR_OUT_BRACE
		"TEAR_OUT_EMPTY_SKY": return Pacing.TEAR_OUT_EMPTY_SKY
		"TEAR_OUT_SETTLE": return Pacing.TEAR_OUT_SETTLE
		"TEAR_OUT_AFTERMATH": return Pacing.TEAR_OUT_AFTERMATH
		"TEAR_OUT_FLIGHT": return Pacing.TEAR_OUT_FLIGHT
		"TEAR_OUT_ARRIVAL": return Pacing.TEAR_OUT_ARRIVAL
		"TEAR_OUT_STAGGER_MAX": return Pacing.TEAR_OUT_STAGGER_MAX
		"TEAR_OUT_SLAM": return Pacing.TEAR_OUT_SLAM
		"TEAR_OUT_WHITEOUT": return Pacing.TEAR_OUT_WHITEOUT
		"TEAR_OUT_HOLD": return Pacing.TEAR_OUT_HOLD
		"TEAR_OUT_CAMERA_HOLD": return Pacing.TEAR_OUT_CAMERA_HOLD
		"ENVIRONMENT_PAN": return Pacing.ENVIRONMENT_PAN
		"ENVIRONMENT_HOLD": return Pacing.ENVIRONMENT_HOLD
		"PLAYER_ACTION": return Pacing.PLAYER_ACTION
		"AI_ACTION": return Pacing.AI_ACTION
		"CINEMATIC_ACTION": return Pacing.CINEMATIC_ACTION
		"STAGE_LIFT": return BoardSpace.STAGE_LIFT
		"BOARD_DRAMA": return Pacing.BOARD_DRAMA
		"CINEMATIC_DRAMA": return Pacing.CINEMATIC_DRAMA
		"BOARD_DIRECTION": return Pacing.BOARD_DIRECTION
		"CINEMATIC_DIRECTION": return Pacing.CINEMATIC_DIRECTION
		"PITCH_DIVE": return Pacing.PITCH_DIVE
		"DOLLY_IN": return Pacing.DOLLY_IN
		"DOLLY_FLOOR": return Pacing.DOLLY_FLOOR
		"EMPHASIS_DOWN": return Pacing.EMPHASIS_DOWN
		"EMPHASIS_CRISIS": return Pacing.EMPHASIS_CRISIS
		"EMPHASIS_IRON_WILL": return Pacing.EMPHASIS_IRON_WILL
		"HITSTOP_DOWN": return Pacing.HITSTOP_DOWN
		"BOARD_HITSTOP": return Pacing.BOARD_HITSTOP
		"CINEMATIC_HITSTOP": return Pacing.CINEMATIC_HITSTOP
		"SHAKE_HIT": return Pacing.SHAKE_HIT
		"SHAKE_DOWN": return Pacing.SHAKE_DOWN
		"SHAKE_DECAY": return Pacing.SHAKE_DECAY
		"SHAKE_FREQUENCY": return Pacing.SHAKE_FREQUENCY
		"SWAY_AMPLITUDE": return Pacing.SWAY_AMPLITUDE
		"SWAY_SPEED": return Pacing.SWAY_SPEED
		"BOARD_SWAY": return Pacing.BOARD_SWAY
		"CINEMATIC_SWAY": return Pacing.CINEMATIC_SWAY
		"HOLD_ATTACK": return Pacing.HOLD_ATTACK
		"HOLD_DOWN": return Pacing.HOLD_DOWN
		"HOLD_CRISIS": return Pacing.HOLD_CRISIS
		"HOLD_IRON_WILL": return Pacing.HOLD_IRON_WILL
		"HOLD_KNOCKBACK": return Pacing.HOLD_KNOCKBACK
		"HOLD_TURNOVER": return Pacing.HOLD_TURNOVER
		"HOLD_HEAL": return Pacing.HOLD_HEAL
		"HOLD_RESCUE": return Pacing.HOLD_RESCUE
		"HOLD_RALLY": return Pacing.HOLD_RALLY
		"HOLD_INTIMIDATE": return Pacing.HOLD_INTIMIDATE
		"HOLD_RELOAD": return Pacing.HOLD_RELOAD
		"HOLD_REV": return Pacing.HOLD_REV
		"HOLD_BURROW": return Pacing.HOLD_BURROW
		"HOLD_CAPTURE": return Pacing.HOLD_CAPTURE
		"HOLD_GUARD": return Pacing.HOLD_GUARD
		"HOLD_OVERWATCH": return Pacing.HOLD_OVERWATCH
		"LINGER_ATTACK": return Pacing.LINGER_ATTACK
		"LINGER_DOWN": return Pacing.LINGER_DOWN
		"LINGER_RESCUE": return Pacing.LINGER_RESCUE
		"LINGER_RALLY": return Pacing.LINGER_RALLY
		"LINGER_INTIMIDATE": return Pacing.LINGER_INTIMIDATE
		"LINGER_RELOAD": return Pacing.LINGER_RELOAD
		"LINGER_REV": return Pacing.LINGER_REV
		"LINGER_BURROW": return Pacing.LINGER_BURROW
		"LINGER_CAPTURE": return Pacing.LINGER_CAPTURE
		"LINGER_GUARD": return Pacing.LINGER_GUARD
		"LINGER_OVERWATCH": return Pacing.LINGER_OVERWATCH
		"SHOVE_SLIDE_SPEED": return MovementComponent.SHOVE_SLIDE_SPEED
		"SHOVE_FALL_SPEED": return MovementComponent.SHOVE_FALL_SPEED
		"VOID_PLUMMET_CELLS": return MovementComponent.VOID_PLUMMET_CELLS
		"VOID_PLUMMET_SECONDS": return MovementComponent.VOID_PLUMMET_SECONDS
		"READOUT_BACKGROUND": return ActionMenuController.READOUT_BACKGROUND
		"READOUT_BORDER": return ActionMenuController.READOUT_BORDER
		"READOUT_BORDER_WIDTH": return ActionMenuController.READOUT_BORDER_WIDTH
		"READOUT_TITLE_COLOR": return ActionMenuController.READOUT_TITLE_COLOR
		"READOUT_DETAIL_COLOR": return ActionMenuController.READOUT_DETAIL_COLOR
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
		"URGENT_ROUNDS": return MissionStatusPanel.URGENT_ROUNDS
		"URGENT_COLOR": return MissionStatusPanel.URGENT_COLOR
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
		"WATCH_MARK_COLOR": OverlayManager.WATCH_MARK_COLOR = value
		"WATCH_MARK_SCALE": OverlayManager.WATCH_MARK_SCALE = value
		"WATCH_REACH_MODULATE": OverlayManager.WATCH_REACH_MODULATE = value
		"WATCH_HOVER_MODULATE": OverlayManager.WATCH_HOVER_MODULATE = value
		"MOVE_ARROW_MODULATE": OverlayManager.MOVE_ARROW_MODULATE = value
		"INVALID_ARROW_MODULATE": OverlayManager.INVALID_ARROW_MODULATE = value
		"TRAILING_ARROW_MODULATE": OverlayManager.TRAILING_ARROW_MODULATE = value
		"GUARD_LINK_MODULATE": OverlayManager.GUARD_LINK_MODULATE = value
		"GUARD_LINK_HEAD_INSET": OverlayManager.GUARD_LINK_HEAD_INSET = value
		"GUARD_RING_COLOR": OverlayManager.GUARD_RING_COLOR = value
		# Both are read when a pick OPENS, so there is never a standing flash to re-apply one to --
		# SHOVE_SLIDE_SPEED's early-return reasoning, and why neither needs a sweep.
		"PICK_FLASH_ALPHA": OverlayManager.PICK_FLASH_ALPHA = value
		"PICK_FLASH_PERIOD": OverlayManager.PICK_FLASH_PERIOD = value
		# The beat table (#519). Every one of these is read at the START of a pass, so there is never
		# a standing pause to re-apply one to -- SHOVE_SLIDE_SPEED's early return, same reason.
		"PLAYBACK_PAN":
			Pacing.PLAYBACK_PAN = value
			return
		"TEAR_OUT_BRACE":
			Pacing.TEAR_OUT_BRACE = value
		"TEAR_OUT_EMPTY_SKY":
			Pacing.TEAR_OUT_EMPTY_SKY = value
		"TEAR_OUT_SETTLE":
			Pacing.TEAR_OUT_SETTLE = value
		"TEAR_OUT_AFTERMATH":
			Pacing.TEAR_OUT_AFTERMATH = value
		"TEAR_OUT_FLIGHT":
			Pacing.TEAR_OUT_FLIGHT = value
		"TEAR_OUT_ARRIVAL":
			Pacing.TEAR_OUT_ARRIVAL = value
		"TEAR_OUT_STAGGER_MAX":
			Pacing.TEAR_OUT_STAGGER_MAX = value
		"TEAR_OUT_SLAM":
			Pacing.TEAR_OUT_SLAM = value
		"TEAR_OUT_WHITEOUT":
			Pacing.TEAR_OUT_WHITEOUT = value
		"TEAR_OUT_HOLD":
			Pacing.TEAR_OUT_HOLD = value
		"TEAR_OUT_CAMERA_HOLD":
			Pacing.TEAR_OUT_CAMERA_HOLD = value
		"ENVIRONMENT_PAN":
			Pacing.ENVIRONMENT_PAN = value
			return
		"ENVIRONMENT_HOLD":
			Pacing.ENVIRONMENT_HOLD = value
			return
		"PLAYER_ACTION":
			Pacing.PLAYER_ACTION = value
			return
		"AI_ACTION":
			Pacing.AI_ACTION = value
			return
		"CINEMATIC_ACTION":
			Pacing.CINEMATIC_ACTION = value
			return
		"STAGE_LIFT":
			BoardSpace.STAGE_LIFT = value
			return
		"BOARD_DRAMA":
			Pacing.BOARD_DRAMA = value
			return
		"CINEMATIC_DRAMA":
			Pacing.CINEMATIC_DRAMA = value
			return
		"BOARD_DIRECTION":
			Pacing.BOARD_DIRECTION = value
			return
		"CINEMATIC_DIRECTION":
			Pacing.CINEMATIC_DIRECTION = value
			return
		"DOLLY_IN":
			Pacing.DOLLY_IN = value
			return
		"DOLLY_FLOOR":
			Pacing.DOLLY_FLOOR = value
			return
		"EMPHASIS_DOWN":
			Pacing.EMPHASIS_DOWN = value
			return
		"EMPHASIS_CRISIS":
			Pacing.EMPHASIS_CRISIS = value
			return
		"EMPHASIS_IRON_WILL":
			Pacing.EMPHASIS_IRON_WILL = value
			return
		"HITSTOP_DOWN":
			Pacing.HITSTOP_DOWN = value
			return
		"BOARD_HITSTOP":
			Pacing.BOARD_HITSTOP = value
			return
		"CINEMATIC_HITSTOP":
			Pacing.CINEMATIC_HITSTOP = value
			return
		"PITCH_DIVE":
			Pacing.PITCH_DIVE = value
			return
		"SHAKE_HIT":
			Pacing.SHAKE_HIT = value
			return
		"SHAKE_DOWN":
			Pacing.SHAKE_DOWN = value
			return
		"SHAKE_DECAY":
			Pacing.SHAKE_DECAY = value
			return
		"SHAKE_FREQUENCY":
			Pacing.SHAKE_FREQUENCY = value
			return
		"SWAY_AMPLITUDE":
			Pacing.SWAY_AMPLITUDE = value
			return
		"SWAY_SPEED":
			Pacing.SWAY_SPEED = value
			return
		"BOARD_SWAY":
			Pacing.BOARD_SWAY = value
			return
		"CINEMATIC_SWAY":
			Pacing.CINEMATIC_SWAY = value
			return
		"HOLD_ATTACK":
			Pacing.HOLD_ATTACK = value
			return
		"HOLD_DOWN":
			Pacing.HOLD_DOWN = value
			return
		"HOLD_CRISIS":
			Pacing.HOLD_CRISIS = value
			return
		"HOLD_IRON_WILL":
			Pacing.HOLD_IRON_WILL = value
			return
		"HOLD_KNOCKBACK":
			Pacing.HOLD_KNOCKBACK = value
			return
		"HOLD_TURNOVER":
			Pacing.HOLD_TURNOVER = value
			return
		"HOLD_HEAL":
			Pacing.HOLD_HEAL = value
			return
		"HOLD_RESCUE":
			Pacing.HOLD_RESCUE = value
			return
		"HOLD_RALLY":
			Pacing.HOLD_RALLY = value
			return
		"HOLD_INTIMIDATE":
			Pacing.HOLD_INTIMIDATE = value
			return
		"HOLD_RELOAD":
			Pacing.HOLD_RELOAD = value
			return
		"HOLD_REV":
			Pacing.HOLD_REV = value
			return
		"HOLD_BURROW":
			Pacing.HOLD_BURROW = value
			return
		"HOLD_CAPTURE":
			Pacing.HOLD_CAPTURE = value
			return
		"HOLD_GUARD":
			Pacing.HOLD_GUARD = value
			return
		"HOLD_OVERWATCH":
			Pacing.HOLD_OVERWATCH = value
			return
		"LINGER_ATTACK":
			Pacing.LINGER_ATTACK = value
			return
		"LINGER_DOWN":
			Pacing.LINGER_DOWN = value
			return
		"LINGER_RESCUE":
			Pacing.LINGER_RESCUE = value
			return
		"LINGER_RALLY":
			Pacing.LINGER_RALLY = value
			return
		"LINGER_INTIMIDATE":
			Pacing.LINGER_INTIMIDATE = value
			return
		"LINGER_RELOAD":
			Pacing.LINGER_RELOAD = value
			return
		"LINGER_REV":
			Pacing.LINGER_REV = value
			return
		"LINGER_BURROW":
			Pacing.LINGER_BURROW = value
			return
		"LINGER_CAPTURE":
			Pacing.LINGER_CAPTURE = value
			return
		"LINGER_GUARD":
			Pacing.LINGER_GUARD = value
			return
		"LINGER_OVERWATCH":
			Pacing.LINGER_OVERWATCH = value
			return
		"SHOVE_SLIDE_SPEED":
			MovementComponent.SHOVE_SLIDE_SPEED = value
			return   # read at each shove -- nothing standing to re-apply
		"SHOVE_FALL_SPEED":
			MovementComponent.SHOVE_FALL_SPEED = value
			return   # read at each fall -- nothing standing to re-apply
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
		"READOUT_BACKGROUND":
			ActionMenuController.READOUT_BACKGROUND = value
			return
		"READOUT_BORDER":
			ActionMenuController.READOUT_BORDER = value
			return
		"READOUT_BORDER_WIDTH":
			ActionMenuController.READOUT_BORDER_WIDTH = value
			return
		"READOUT_TITLE_COLOR":
			ActionMenuController.READOUT_TITLE_COLOR = value
			return
		"READOUT_DETAIL_COLOR":
			ActionMenuController.READOUT_DETAIL_COLOR = value
			return
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
		# The mission clock (#101). These DO need a re-apply: the status panel is push-refreshed from
		# MissionController's write points, so with nothing happening on the board -- which is exactly
		# when the dev is dragging this -- the row would not repaint until the next turn. #324's rule.
		"URGENT_ROUNDS":
			MissionStatusPanel.URGENT_ROUNDS = int(value)   # a stepped slider hands a float
			_refresh_mission_status(host)
			return
		"URGENT_COLOR":
			MissionStatusPanel.URGENT_COLOR = value
			_refresh_mission_status(host)
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
		# The armed-Guard pair (#414/#450). Two sweeps, not one, because the halves live in different
		# stores -- the shield is a pooled OverlayIcon that _style_icon restyles, the link is a loose
		# arrow sprite. Both re-tint in place: neither store can rebuild a pair, since redrawing one
		# needs the unit list and this manager has none.
		"GUARD_LINK_MODULATE": manager.restyle_guard_link()
		"GUARD_RING_COLOR": manager.restyle_squad_markers()
		# The inset MOVES a sprite rather than re-tinting one, and neither store can rebuild a pair
		# from itself -- redrawing needs the unit list. So this one goes back to the game's own door
		# (#450 round 2), which is where every other write point already goes.
		"GUARD_LINK_HEAD_INSET": _refresh_guard_markers(host)
		# Written once when the marks are built, so a tuned value needs a re-apply or the slider moves
		# and nothing on the board does (#264's born-dead slider).
		"WATCH_MARK_COLOR", "WATCH_MARK_SCALE": manager.restyle_watch_marks()
		# No bespoke sweep for the three planned-move tints: redraw_planned_paths already tears
		# every arrow down and rebuilds it through _arrow_modulate, so it IS the re-apply.
		"MOVE_ARROW_MODULATE", "INVALID_ARROW_MODULATE", "TRAILING_ARROW_MODULATE":
			manager.redraw_planned_paths()
		_: manager.refresh_aim_colors()


# The mission-status HUD's re-apply. Its one door is game.refresh_mission_status (#134), which is
# where every other write point already goes -- no second repaint path for a knob.
static func _refresh_mission_status(host: Node3D) -> void:
	if host == null:
		return
	var game_2d: Node2D = host.game
	if game_2d == null:
		return
	game_2d.refresh_mission_status()


# The armed-Guard pair's re-apply, for the one knob that MOVES a marker instead of re-tinting it
# (#450). Same shape and same reason as the mission-status one above: game.refresh_guard_markers is
# already the door every write point uses, so a knob takes it rather than growing a second redraw.
static func _refresh_guard_markers(host: Node3D) -> void:
	if host == null:
		return
	var game_2d: Node2D = host.game
	if game_2d == null:
		return
	game_2d.refresh_guard_markers()


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
