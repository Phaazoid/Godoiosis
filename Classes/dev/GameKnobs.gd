extends Object
class_name GameKnobs

# WHAT the game's own presentation constants are -- board markup, the unit readout, camera handling,
# dev chrome, world construction and the fire effect -- and how a tuned one is KEPT (#373, widened
# by #380 when the Objects tab's globals moved in). Static and pure; LookKnobs' opposite number.
#
# THIS TABLE IS NO LONGER THE GAME CONSTANTS ENTIRE, and the distinction is which PAGE draws a row
# rather than what kind of value it is. #902 moved seven world-construction rows to
# ObjectKnobs.GLOBALS so they sit on the tile that falls back to them; they are the same
# node:property shape, saved by the same KnobSource into the same @export declaration, and the laws
# that are about that SHAPE walk both tables (tests/dev/test_game_knobs.gd's _declaration_tables).
# What stays here is everything a TILE is not how you would look for.
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
const SELECTOR_DEPTH := {"group": "Lift, brackets & icons", "node": "BoardOverlays", "prop": "selector_depth",
	"label": "Selector depth", "options": ["Level (whole block)", "Half (one unit)"],
	"tip": "How much of a column the hover selector encloses. Level is one whole block, which is what it marked before a GridMap row became a half-level height unit; Half is one unit, for reading a half step apart from the level it sits in. Its top face sits on the cell's surface either way, so this only changes how far DOWN it reaches. V cycles it in play."}

# node = path relative to the host ("." = the host); prop = colon-joined property path.
# A float knob carries min/max/step; bool and Color infer their widget from the live value.
# A knob carrying `options` renders as a picker over an enum property instead (LookKnobs' tonemap).
const KNOBS: Array[Dictionary] = [
	# --- Board markup ---
	# fill_lift and lift_step raise every ground marker together, arrows included. A lift the
	# ARROWS own alone (#227) needs its own export on BoardOverlays -- not in this slice.
	{"group": "Lift, brackets & icons", "node": "BoardOverlays", "prop": "fill_lift", "label": "Marker lift", "min": 0.0, "max": 0.5, "step": 0.001,
		"tip": "How far every ground marker floats above the tile's top face. Enough to beat z-fighting (the flickering where two surfaces share a plane) and no more -- too much and the markup visibly hovers."},
	{"group": "Lift, brackets & icons", "node": "BoardOverlays", "prop": "lift_step", "label": "Per-layer lift step", "min": 0.0, "max": 0.05, "step": 0.0005,
		"tip": "Extra lift per sort layer, so stacked markers never land on exactly the same plane and fight. Also what keeps path arrows drawing over the move fill rather than through it."},
	{"group": "Lift, brackets & icons", "node": "BoardOverlays", "prop": "bracket_arm", "label": "Bracket arm", "min": 0.05, "max": 0.5, "step": 0.005,
		"tip": "Length of each arm of the corner bracket that marks the hovered cell. Short arms read as corner ticks; long ones close into a full box."},
	{"group": "Lift, brackets & icons", "node": "BoardOverlays", "prop": "bracket_thickness", "label": "Bracket thickness", "min": 0.005, "max": 0.2, "step": 0.001,
		"tip": "How chunky the hover bracket's arms are. Thin reads precise, thick reads legible at a distance."},
	{"group": "Lift, brackets & icons", "node": "BoardOverlays", "prop": "bracket_scale", "label": "Bracket scale", "min": 0.9, "max": 1.3, "step": 0.005,
		"tip": "Size of the whole hover bracket relative to one cell. Just above 1 makes it sit proud of the tile edge so it is not swallowed by the tile art."},
	SELECTOR_DEPTH,
	{"group": "Lift, brackets & icons", "node": "BoardOverlays", "prop": "invalid_bracket_color", "label": "Invalid bracket tint",
		"tip": "What the hover bracket turns over a cell the 2D game calls invalid -- unwalkable, occupied, or a paint the tile brush would refuse. It mirrors the 2D cursor's own verdict rather than deciding for itself."},
	{"group": "Lift, brackets & icons", "node": "BoardOverlays", "prop": "billboard_lift", "label": "Icon height", "min": 0.0, "max": 3.0, "step": 0.01,
		"tip": "How high a selection icon floats above the cell it marks. High enough to clear the unit standing there, low enough not to read as belonging to the cell behind."},
	{"group": "Lift, brackets & icons", "node": "BoardOverlays", "prop": "billboard_pixel_size", "label": "Icon pixel size", "min": 0.004, "max": 0.1, "step": 0.001,
		"tip": "World size of ONE pixel of a billboard icon. 1/32 matches the tile art's density; mixing densities is the loudest amateur tell in HD-2D, so change this only with the art in view."},

	# The sight beam's SHAPE (#506); its colour is two rows in CLASS_KNOBS, because the verdict hue
	# is shared with the flat view and these three have no flat-view equivalent at all. Each one
	# re-applies on write through its own setter, so a standing beam changes under the slider.
	{"group": "Sight beam", "node": "BoardOverlays", "prop": "beam_width", "label": "Sight beam width", "min": 0.01, "max": 0.4, "step": 0.005,
		"tip": "How thick the aim's sight beam is, in cells -- it is a ribbon turned to face the camera, so this is a real world width that gets smaller with distance like everything else in the diorama. Thin reads as a laser sight, thick as a tracer round."},
	# The focus stroke around the hovered enemy (#710 slice 4) has its OWN width and brightness rather
	# than the beam's: the trio above is tuned for a laser, and at that width and bloom a stroke round
	# forty cells reads as a rope of light laid over the terrain. The edge falloff stays shared.
	{"group": "Enemy focus", "node": "BoardOverlays", "prop": "outline_width", "label": "Enemy focus outline width", "min": 0.005, "max": 0.2, "step": 0.005,
		"tip": "How thick the stroke round the hovered enemy's whole field is, in cells. It says WHOSE field you are looking at while the rest of the crowd is dimmed, so it wants to be legible and quiet rather than bright."},
	{"group": "Enemy focus", "node": "BoardOverlays", "prop": "outline_intensity", "label": "Enemy focus outline glow", "min": 0.2, "max": 4.0, "step": 0.05,
		"tip": "Brightness multiplier on that stroke. 1.0 draws it flat, which is what board markup wants; above about 1.2 it blooms and starts reading as an effect rather than as a boundary."},
	{"group": "Sight beam", "node": "BoardOverlays", "prop": "beam_softness", "label": "Sight beam edge", "min": 0.25, "max": 6.0, "step": 0.05,
		"tip": "How the beam fades from its bright middle to nothing at the edge. Around 1 is a flat, even ribbon; higher pulls the brightness into a narrow core with a soft halo around it, which is what stops it reading as a solid strip of geometry."},
	{"group": "Sight beam", "node": "BoardOverlays", "prop": "beam_intensity", "label": "Sight beam glow", "min": 0.5, "max": 6.0, "step": 0.05,
		"tip": "Brightness multiplier on the beam's colour. Past the scene's glow threshold (1.2 by default, on the Moods tab) the bloom takes over and the beam starts to burn -- which is the dial that makes it read as light rather than paint. Separate from the colour because a colour row cannot go above full white."},
	# The reach mark's own beam set and its motion (#1042, re-pointed by #1069). Neither a laser nor
	# a stroke: it is the one piece of board markup that travels.
	{"group": "Reach lines: the arc", "node": "BoardOverlays", "prop": "mark_width", "label": "Reach mark width", "min": 0.01, "max": 0.4, "step": 0.005,
		"tip": "How thick the mark from an enemy to the cell you are hovering is, in cells. Wider than the focus outline and thinner than the sight beam -- it has to read across the whole board without becoming the loudest thing on it. The cone's base is a MULTIPLE of this, so widening the mark widens its head too."},
	{"group": "Reach lines: the arc", "node": "BoardOverlays", "prop": "mark_intensity", "label": "Reach mark glow", "min": 0.2, "max": 6.0, "step": 0.05,
		"tip": "Brightness multiplier on the mark's SHAFT. Past the scene's glow threshold (1.2) it blooms. The solid cone has its own, deliberately: a ribbon fades out at its rim so it is far dimmer than this number over most of its area, where a solid is this bright everywhere."},
	{"group": "Reach lines: the arc", "node": "BoardOverlays", "prop": "bead_speed", "label": "Reach bead speed", "min": 0.0, "max": 12.0, "step": 0.1,
		"tip": "How fast the bright pulse runs from the enemy to the hovered cell, in cells per second. It is what says which end is which without the cone having to be read, so it wants to be unmistakable in direction and calm in pace. It runs through the cone as one sweep."},
	{"group": "Reach lines: the arc", "node": "BoardOverlays", "prop": "bead_length", "label": "Reach bead length", "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "How long that pulse is, in cells. Zero turns the bead off entirely and leaves a still mark with its cone."},
	{"group": "Reach lines: the arc", "node": "BoardOverlays", "prop": "bead_gap", "label": "Reach bead spacing", "min": 0.5, "max": 30.0, "step": 0.5,
		"tip": "How far apart successive pulses run, in cells. Shorter than the mark and you get a chain of them travelling at once; longer and there is exactly one at a time with a rest between."},
	# The SOLID cone's own three (#1069). Everything else about the mark -- length, base width,
	# colour, bow, inset -- was already tunable while it was a ribbon; these are what a volume needs
	# and a ribbon never did.
	{"group": "Reach lines: the cone", "node": "BoardOverlays", "prop": "cone_intensity", "label": "Reach cone glow", "min": 0.2, "max": 6.0, "step": 0.05,
		"tip": "Brightness multiplier on the cone alone. It starts LOWER than the shaft's on purpose: the shaft is a ribbon that fades to nothing at its rim, so most of it is far dimmer than its number, while the cone is a solid surface that is this bright edge to edge. Past the scene's glow threshold (1.2) the whole head blooms white and the shading below stops reading."},
	{"group": "Reach lines: the cone", "node": "BoardOverlays", "prop": "cone_shading", "label": "Reach cone shading", "min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "How dark a face pointing away from the light goes. 1.0 is flat -- a silhouette, which is what a cone looks like with no shading at all -- and 0 is hard black on the far side. This is the whole of what makes the head read as a 3D shape rather than a triangle, since board markup is never lit by the scene."},
	{"group": "Reach lines: the cone", "node": "BoardOverlays", "prop": "cone_facets", "label": "Reach cone facets", "min": 3, "max": 32, "step": 1,
		"tip": "How many flat faces the cone is built from. Low reads as a cut gem with obvious edges, high as a smooth round cone. At the size this draws on screen, somewhere in the low teens is usually all that survives the pixels."},
	# The squad's lines (#1070): one width and one glow for the range's stroke AND the tethers, which is
	# what makes them read as one system. The dashes and colours are class values in CLASS_KNOBS,
	# because the flat view draws them too; these two have no flat-view twin.
	{"group": "Squad lines", "node": "BoardOverlays", "prop": "squad_line_width", "label": "Squad line width (3D)", "min": 0.01, "max": 0.2, "step": 0.005,
		"tip": "How thick a tether and the dashed stroke round the squad's range are, in cells. The tether's arrowhead is a multiple of this (Reach cone width), so widening the line widens its head too."},
	{"group": "Squad lines", "node": "BoardOverlays", "prop": "squad_line_intensity", "label": "Squad line glow (3D)", "min": 0.2, "max": 4.0, "step": 0.05,
		"tip": "Brightness multiplier on the squad's lines. Around 1 draws them flat, which is what markup wants; past the scene's glow threshold (1.2) they bloom and start reading as an effect."},

	# --- Dev chrome ---
	# Filed truthfully rather than folded into the markup above it: these are the only rows on this
	# tab a player never sees.
	{"group": "Dev chrome", "node": "BoardMirror", "prop": "brush_ghost_alpha", "label": "Brush ghost alpha", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "Opacity of the dev tile brush's preview block -- the ghost showing what you are about to paint. Dev-only; players never see it."},
	# "." is the HOST itself (LookKnobs.target_of) — the first row to use it, because the plate is a
	# child of Battle3D's own UI layer and there is no sub-node that owns it.
	{"group": "Dev chrome", "node": ".", "prop": "readout_plate_alpha", "label": "Top bar plate", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "Opacity of the dark plate behind the checkout stamp and the DEV MODE badge (#498). Zero removes it and the text goes back to washing out over pale terrain; past about 0.7 the plate stops reading as chrome and starts covering the board. The plate is fitted to the text, so this changes how hard it reads, never how much screen it takes. Dev-only."},
	{"group": "Dev chrome", "node": "BoardMirror", "prop": "brush_vertex_ghost_size", "label": "Corner marker size", "min": 0.05, "max": 0.6, "step": 0.01,
		"tip": "Edge of the corner tool's marker cube, as a fraction of a cell. It marks the POINT a drag has hold of, so it wants to be grabbable by eye without growing large enough to read as a tile -- past about a third of a cell it starts covering the corner it is pointing at. Dev-only."},

	# --- Unit HUD (#229) ---
	{"group": "HP cubes", "node": "UnitMirror", "prop": "hud_lift", "label": "Readout clearance", "min": 0.0, "max": 1.5, "step": 0.01,
		"tip": "Gap between the top of the unit's visible ART and the bottom of the readout, in cells. Measured from the sprite's topmost opaque pixel rather than from its feet, so units drawn with different amounts of empty space above their heads all wear it at the same apparent height. The selection icons sit higher still; keep this well under their lift or the readout climbs past them."},
	{"group": "HP cubes", "node": "UnitMirror", "prop": "hp_block_texels", "label": "HP cube size", "min": 2.0, "max": 16.0, "step": 1.0,
		"tip": "Edge of one HP cube in texels, at the same pixel density as every sprite -- 32 is one cell. This INCLUDES the black cage, so the coloured core is this minus twice the cage: at 5 with a 1-texel cage the core is 3 texels, which is about the floor for still reading as a bordered square rather than a dark speck."},
	{"group": "HP cubes", "node": "UnitMirror", "prop": "hp_block_border_texels", "label": "HP cube cage", "min": 0.0, "max": 4.0, "step": 1.0,
		"tip": "Thickness of the black frame around every face of a cube, in texels. It is what makes a cube read as a cube with no lighting on it, and neighbouring cubes SHARE it -- so this also closes the gap between them. Zero removes it and the grid becomes a row of flat squares; push it past a third of the cube size and there is no colour left to read."},
	{"group": "HP cubes", "node": "UnitMirror", "prop": "hp_blocks_per_row", "label": "HP cubes per row", "min": 1.0, "max": 30.0, "step": 1.0,
		"tip": "How many cubes before the grid wraps to another row. Ten is what makes the readout countable at a glance -- one full row plus four reads as 14 without counting. Fewer per row trades width for height, and height is the contested axis: the state icons and the crown are stacked above."},
	{"group": "HP cubes", "node": "UnitMirror", "prop": "hp_block_recess_texels", "label": "Lost cube depth", "min": 0.0, "max": 8.0, "step": 1.0,
		"tip": "How far back a LOST cube sits, in texels. The dent is a second cue beside the colour, so the readout still reads at distance and for anyone who finds green-against-red hard. Zero makes every cube flush and hands the dent to the shrink below -- which is where it sits by default, because depth and holding the grid still are incompatible: pushed back cubes stop reading as sunk the moment you orbit behind them."},
	{"group": "HP cubes", "node": "UnitMirror", "prop": "hp_block_recess_shrink", "label": "Lost cube shrink", "min": 0.1, "max": 1.0, "step": 0.05,
		"tip": "How much smaller a LOST cube gets, as a fraction of a standing one. This is what actually reads as a hole: depth alone leaves a same-sized square head-on, because there is no socket wall to see, so shrinking it is what pulls it away from its neighbours' cages. 1.0 removes the effect and leaves depth and colour to carry the dent between them."},
	{"group": "HP cubes", "node": "UnitMirror", "prop": "hp_block_recess_shade", "label": "Lost cube shade", "min": 0.1, "max": 1.0, "step": 0.05,
		"tip": "How far a LOST cube's colour is dimmed, as a multiplier on Cube missing -- it reads as the sunk cube sitting in shadow. At 1.0 it is exactly the authored colour, so this MODIFIES that one answer rather than becoming a rival to it: if you want a different red, move Cube missing, not this."},
	{"group": "HP cubes", "node": "UnitMirror", "prop": "hp_block_top_shade", "label": "Cube top shade", "min": 0.1, "max": 1.0, "step": 0.05,
		"tip": "How far the TOP face of every cube is darkened, as a multiplier on its own colour. This is the one thing telling the top apart from the front, and it is deliberately a shade rather than the absence of the black cage: taking the cage off the other five faces instead made the whole grid read as one green mass with black painted on, rather than as separate bricks. 1.0 removes the effect and the top matches the front exactly."},
	{"group": "HP cubes", "node": "UnitMirror", "prop": "hp_grid_faces_camera", "label": "Grid faces camera",
		"tip": "On, the whole readout turns to face the camera like a billboard. Off, it stays put on the board's own axes the way the rocks and props do, which means orbiting past one takes it edge-on and squashes it to a line. That is what keeping it in place MEANS rather than a fault; the question this dial asks is whether reading as a real 3D object is worth the angles where it stops being legible."},
	{"group": "HP cubes", "node": "UnitMirror", "prop": "bar_fill_color", "label": "Cube fill",
		"tip": "The health a unit still HAS -- the colour of a standing cube, and of the cubes that fly off when it loses one. Flat: it does not shift hue as the grid empties, since the COUNT already says how hurt the unit is. Fully opaque by design, because this is a gameplay descriptor rather than scenery."},
	{"group": "HP cubes", "node": "UnitMirror", "prop": "bar_missing_color", "label": "Cube missing",
		"tip": "The health a unit has LOST -- the colour of a shrunken cube. Read together, fill against missing is the whole gauge, so these two want to be as far apart as the palette allows; the shrink is what keeps it readable for anyone the pair itself does not separate."},
	{"group": "HP number", "node": "UnitMirror", "prop": "number_height_cells", "label": "Number size", "min": 0.02, "max": 0.6, "step": 0.005,
		"tip": "How tall the HP digits stand, in cells -- a size in the SCENE, not on screen, so it shrinks with the unit as you zoom out. The glyphs are rendered at a fixed high resolution and scaled down to this, so small stays crisp instead of turning to mush."},
	{"group": "HP number", "node": "UnitMirror", "prop": "number_outline_size", "label": "Number outline", "min": 0.0, "max": 24.0, "step": 1.0,
		"tip": "Thickness of the black outline behind the number, in GLYPH units -- so it holds its proportion when Number size changes, but what lands on screen is this scaled down with the text. Around 8 is one pixel of the game's own art and 16 is two; anything under about 5 is thinner than a single art pixel and will not separate white digits from a bright bar at all. Push it far enough and neighbouring digits bleed together, and at that point a black backing plate is the better answer than more outline."},
	{"group": "HP number", "node": "UnitMirror", "prop": "number_color", "label": "Number colour",
		"tip": "Colour of the HP digits. The outline is always black, so this is the fill; a tint here is the cheapest way to make the number read as part of the bar rather than as separate text."},
	{"group": "HP number", "node": "UnitMirror", "prop": "number_gap", "label": "Number inset", "min": 0.0, "max": 0.5, "step": 0.005,
		"tip": "How far in from the bar's left edge the digits start, in cells. The number sits ON the bar, so this is padding inside it rather than a gap beside it -- zero puts the first digit flush against the outline."},
	{"group": "HP number", "node": "UnitMirror", "prop": "number_shows_max", "label": "Number shows max",
		"tip": "On, the number reads '12/20'; off, just '12'. The bar already carries the fraction either way, so this is purely how much text you want floating over a head."},
	# --- The predicted readout (#313) ---
	{"group": "Predicted change", "node": "UnitMirror", "prop": "bar_doomed_color", "label": "Predicted loss",
		"tip": "The health the queued plan is about to TAKE -- worn by the exact cubes that will go, between where the grid stands now and where the plan leaves it. It has to read as a warning against the fill beside it without reading as damage that has already landed, and the cubes still standing PROUD are what say 'not yet'."},
	{"group": "Predicted change", "node": "UnitMirror", "prop": "bar_heal_color", "label": "Predicted gain",
		"tip": "The same span in the other direction: health a queued heal is about to give back, drawn over the missing backing. Wants to be unmistakably not-the-loss-colour, since the shape of the span is identical either way and only the colour says which."},
	# No NOTCH rows: with one cube per point of HP, colouring the exact cubes the plan takes says
	# where it lands more precisely than a marker beside them could, so #313's notch is gone.
	{"group": "Predicted change", "node": "UnitMirror", "prop": "alarm_peak_color", "label": "Alarm peak",
		"tip": "What the predicted-loss span pulses TO when the plan predicts a named rung -- a down, a kill, or Crisis. It pulses back to the ordinary loss colour, so this is only the bright half of the cue; make it too close to that colour and the pulse stops registering."},
	# (Unhovered bars show number LEFT this table in #394 -- it is a player setting now, and a value
	# has one store. It is still tunable in play: CLASS_KNOBS below puts it on this same tab, as a
	# control that writes the real preference rather than a knob with a copy of it.)
	# --- The element-state row (#357) ---
	{"group": "State icons", "node": "UnitMirror", "prop": "state_icon_texels", "label": "State icon size", "min": 2.0, "max": 32.0, "step": 1.0,
		"tip": "Size of each element-state icon above the health bar, in texels -- 16 is one cell. The source art is 32px (wet) and 16px (the frozen-tile stand-in for chilled), so powers of two land on exact reductions and anything else will shimmer as the camera moves. This is the first dial to reach for if the icons stop reading at play distance."},
	{"group": "State icons", "node": "UnitMirror", "prop": "state_icon_gap_texels", "label": "State row clearance", "min": 0.0, "max": 16.0, "step": 1.0,
		"tip": "Gap between the top of the health bar's outline and the bottom of the state icons, in texels. Zero stacks them flush against the bar so the two read as one display; push it up to separate what a unit IS from how hurt it is, at the cost of climbing toward the selection icons above."},
	{"group": "State icons", "node": "UnitMirror", "prop": "state_icon_spacing_texels", "label": "State icon spacing", "min": 0.0, "max": 16.0, "step": 1.0,
		"tip": "Gap between neighbouring state icons, in texels. Only visible on a unit holding more than one state, which today means wet AND chilled at once -- with two states the row cannot crowd, and this is the dial that matters when the vocabulary grows."},
	# --- The rescue clock beside the downed glyph (#322) ---
	# No SIZE row on purpose: the digits are the HP number's height, which is not tunable apart from
	# it. See UnitMirror's own note -- a dial whose readable range is only its top end is worse than
	# none, and "Number size" already moves both.
	{"group": "State icons", "node": "UnitMirror", "prop": "downed_count_gap_texels", "label": "Downed clock inset", "min": 0.0, "max": 16.0, "step": 1.0,
		"tip": "Gap between the last icon in the row and the turns-left digits, in texels. Zero puts the number flush against the glyph so the two read as one badge; widen it and the count starts reading as its own thing floating beside the body."},
	# --- The cubes a unit LOSES (#314) ---
	{"group": "Cube burst", "node": "UnitMirror", "prop": "block_burst_speed", "label": "Cube burst speed", "min": 0.0, "max": 10.0, "step": 0.1,
		"tip": "How hard a lost cube is thrown out of its socket, in cells per second. This is the dial that decides whether losing health reads as an EVENT or as the grid quietly getting shorter -- too low and the cubes dribble off the bottom, too high and they are gone before the eye finds them."},
	{"group": "Cube burst", "node": "UnitMirror", "prop": "block_burst_spread", "label": "Cube burst spread", "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "How wide the fan is when several cubes leave at once. Zero throws every cube straight up, so a nine-damage hit leaves as one clump; higher spreads them sideways so you can see how many there were. The directions are fixed per cube rather than random, so the same hit always looks the same."},
	{"group": "Cube burst", "node": "UnitMirror", "prop": "block_spin_speed", "label": "Cube spin", "min": 0.0, "max": 30.0, "step": 0.5,
		"tip": "How fast a thrown cube tumbles, in radians per second. The tumble is what shows off the cage on every face and sells the cube as a solid object rather than a flat square -- at zero it is a sliding tile, and far too high it blurs into a flicker."},
	{"group": "Cube burst", "node": "UnitMirror", "prop": "block_gravity", "label": "Cube gravity", "min": 0.0, "max": 40.0, "step": 0.5,
		"tip": "Downward pull on a thrown cube, in cells per second squared. Read against burst speed rather than alone: the two together decide how high the arc goes and how long it hangs before the bounce."},
	{"group": "Cube burst", "node": "UnitMirror", "prop": "block_bounce", "label": "Cube bounce", "min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "How much of its fall a cube keeps on the way back up, once, when it hits the board beneath it. Zero lands it dead; 1 would return the whole drop. Only the FIRST touch bounces -- after that it rides through, so a busy pass never fills the board with rattling cubes."},
	{"group": "Cube burst", "node": "UnitMirror", "prop": "block_lifetime", "label": "Cube lifetime", "min": 0.1, "max": 4.0, "step": 0.05,
		"tip": "How long a thrown cube lives, in seconds; it fades out over the back half so the bounce is seen at full strength and only the settle disappears. Long enough to read the burst, short enough that a nine-unit AI pass does not leave the board littered."},
	{"group": "Cube burst", "node": "UnitMirror", "prop": "block_burst_stagger", "label": "Cube burst stagger", "min": 0.0, "max": 0.3, "step": 0.005,
		"tip": "Delay between one cube launching and the next, in seconds, so a multi-cube burst MARCHES through the grid instead of leaving all at once. A cube still waiting its turn sits in its own socket rather than hiding, so the grid breaks apart in sequence with no gap running ahead of the cubes. 0 fires the whole burst on a single frame, which is what a nine-damage hit used to look like."},
	{"group": "Cube burst", "node": "UnitMirror", "prop": "block_death_power", "label": "Death burst", "min": 1.0, "max": 5.0, "step": 0.1,
		"tip": "Multiplier on the burst when a unit DIES and its whole remaining grid detonates at once, rather than losing a few cubes to a hit. Going DOWN is not a death and gets the ordinary burst of everything above 1 HP, so this is only for the rarer outright kill."},
	{"group": "Heal pop", "node": "UnitMirror", "prop": "block_pop_time", "label": "Heal pop time", "min": 0.02, "max": 1.0, "step": 0.01,
		"tip": "How long a healed cube takes to rise back out of its dent, in seconds. It overshoots slightly on the way so it reads as popping rather than sliding. Deliberately quicker and quieter than a burst -- being healed should not upstage being hit."},
	{"group": "Heal pop", "node": "UnitMirror", "prop": "hp_pop_lift_texels", "label": "Heal pop travel", "min": 0.0, "max": 12.0, "step": 0.5,
		"tip": "How far a healed cube sinks before it springs back, in texels. Deliberately its OWN value rather than the lost-cube depth: tying it to that made the pop invisible the moment the depth was dialled to zero, since an animation whose distance is a knob that may legitimately be 0 has no distance at all. At 0 here the pop looks instant however long you give it."},
	{"group": "Heal pop", "node": "UnitMirror", "prop": "hp_pop_stagger", "label": "Heal fill stagger", "min": 0.0, "max": 0.5, "step": 0.01,
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
	{"group": "Camera handling", "node": "CameraRig", "prop": "pan_stray_screens", "label": "Pan stray (screens)", "min": 0.25, "max": 4.0, "step": 0.25,
		"tip": "How far past the board edge you may pan, measured in SCREENFULS at full zoom-out -- never in cells. 1.0 puts the wall a whole screen clear of the board at the widest view, and further out in screen terms the closer you zoom, so it is never felt near the stage. Turn it up if a deep inspection zoom still feels penned in."},
	{"group": "Camera handling", "node": "CameraRig", "prop": "zoom_out_slack", "label": "Zoom-out slack", "min": 0.5, "max": 3.0, "step": 0.05,
		"tip": "How far past the whole board you may zoom out. 1.0 means the board exactly fills the view at full zoom-out; above 1 lets you pull back and see it sitting in the world."},

	# --- Playback framing (#394, off Camera handling) ---
	#
	# It was filed among the camera knobs and is not one of them: handling is what the PLAYER'S hand
	# may do, and this is where a fight OPENS FROM -- authored direction, which is #520's business.
	# Its own group rather than joining "Camera travel" one table over. That used to be forced -- a
	# group shared across KNOBS and CLASS_KNOBS drew its heading twice -- and since #1074 builds the
	# panel group-major it is a choice: this is where a fight OPENS, not how the camera travels.
	#
	# UNTAGGED by profile on purpose, so it shows whichever column the Playback page is filtered to --
	# it is applied ONCE as playback starts, not per beat, so no one profile owns it.
	{"group": "Playback framing", "node": "CameraRig", "prop": "playback_distance", "label": "Playback zoom distance", "min": 4.0, "max": 30.0, "step": 0.5,
		"tip": "How far out the camera sits when a pass or an AI turn takes it (#520). Applied ONCE as playback starts and then the wheel is yours again -- so this is where a fight opens from, not a leash."},

	# --- World (#380, from the Objects tab's Globals; most of it left again in #902) ---
	# What is left here is world construction NO TILE OWNS. The seven rows that a tile could be
	# picked to look at -- prop block height, the two tuft dials, the four lamp defaults -- moved to
	# ObjectKnobs.GLOBALS and are drawn on the Tiles page beside the per-tile fields that fall back
	# to them (dev, 2026-09-12: the look values for objects belong on their individual pages). They
	# are the SAME KIND of value still, kept the same way -- this table and that one are both
	# node:property rows saved into their @export declaration, and only the page differs.
	#
	# A hole's walls stay, and the line is worth drawing: a lip is geometry a hole's NEIGHBOURS grow
	# into the shaft, not the `hole` tile's own art, so there is no one tile to put it on.
	# (#876). Depth is world units, not levels -- a chasm is not measured in the steps
	# you could have walked down it. Both re-cut every standing lip through BoardMirror's own sweep.
	{"group": "World", "node": "BoardMirror", "prop": "lip_shaft_depth", "label": "Hole wall depth", "min": 0.5, "max": 12.0, "step": 0.1,
		"tip": "How far the walls of a hole fall before the shaft is pure black. It is a LOOK, not a distance anything falls -- what a shove into a hole actually drops is Void fall depth, under Motion. Deep enough to read as bottomless at the zoom you play at is the whole target."},
	{"group": "World", "node": "BoardMirror", "prop": "lip_shaft_color", "label": "Hole wall colour",
		"tip": "The colour a hole's wall starts at where it meets the ground, fading to black at the bottom. Reads best a little darker and a little cooler than the ground it hangs off, so the eye takes it for shadow rather than for a different material."},

	# --- Fire (#324's knobs; out of Look in #272, here from Objects in #380) ---
	# A terrain STATE rather than an authored object, but the same KIND of value: how the world's
	# own furniture is drawn, matched once and constant after. flame_count is the one INT-backed
	# knob and its range is load-bearing -- the write-back law nudges by a tenth of the range, so
	# anything narrower than 10 rounds back to where it started and reads as a dead slider.
	{"group": "Fire: the flames", "node": "BoardMirror", "prop": "flame_lift", "label": "Flame lift", "min": 0.0, "max": 2.0, "step": 0.01,
		"tip": "How high the fire billboard's centre sits above a burning tile. Raising it makes fire read as standing up off the ground rather than lying on it."},
	{"group": "Fire: the flames", "node": "BoardMirror", "prop": "flame_size:x", "label": "Flame width", "min": 0.1, "max": 2.0, "step": 0.01,
		"tip": "Width of the fire billboard in world units, where 1.0 is exactly one cell across. Width and height share one declaration, so saving either writes both."},
	{"group": "Fire: the flames", "node": "BoardMirror", "prop": "flame_size:y", "label": "Flame height", "min": 0.1, "max": 2.0, "step": 0.01,
		"tip": "Height of the fire billboard in world units. Taller than wide reads as a flame; square reads as a scorch. Width and height share one declaration, so saving either writes both."},
	# The only INT-backed knob here, and its range is load-bearing: a slider write is nudged by a
	# tenth of the range, so anything narrower than 10 rounds back to where it started.
	{"group": "Fire: the flames", "node": "BoardMirror", "prop": "flame_count", "label": "Flame count", "min": 1.0, "max": 12.0, "step": 1.0,
		"tip": "How many separate flames a burning cell stands up. One is a sprite standing on a tile; three or more spread across the square is a tile that is on fire. Every flame is another quad and another draw, so this is the knob that costs something on a board with a lot of fire."},
	{"group": "Fire: the flames", "node": "BoardMirror", "prop": "flame_spread", "label": "Flame spread", "min": 0.0, "max": 0.6, "step": 0.01,
		"tip": "How far off the cell's centre the smaller flames sit, in cells -- 0.5 reaches the tile's edge. At zero they stack in the middle and the fire reads as one clump again."},
	{"group": "Fire: the flames", "node": "BoardMirror", "prop": "flame_fps", "label": "Flame fps", "min": 0.0, "max": 30.0, "step": 0.5,
		"tip": "How fast the flame's frames play. The art is eight looping frames, so this is the whole speed of the fire: low reads as a slow lick, high as a roar. Zero holds a frame without freezing the light."},
	{"group": "Fire: the flames", "node": "BoardMirror", "prop": "flame_flicker", "label": "Flame flicker", "min": 0.0, "max": 0.6, "step": 0.01,
		"tip": "How hard the fire's LIGHT breathes, as a fraction of its energy -- 0.2 swings it a fifth either way. This is what makes a burning tile feel lit by something alive rather than by a lamp; zero is a steady lamp."},
	{"group": "Fire: the flames", "node": "BoardMirror", "prop": "flame_camera_offset", "label": "Flame camera push", "min": 0.0, "max": 0.5, "step": 0.005,
		"tip": "How far each flame is pushed toward the camera, in cells. A flame and a unit sprite on one cell are the same camera-facing plane, so without this they speckle against each other wherever someone stands in fire; push too far and the fire visibly leaves its own tile. A clearance rather than a taste call -- it defends against a geometric coincidence."},
	{"group": "Fire: the flames", "node": "BoardMirror", "prop": "flame_animated", "label": "Flame animated",
		"tip": "Off holds the fire on one frame at steady light -- a still flame, not a missing one. This is the authored game constant; the PLAYER's photosensitivity toggle (#217) ANDs on top of it in BoardMirror._flame_animating, the one composed reader."},
	{"group": "Fire: the flames", "node": "BoardMirror", "prop": "flame_ground_gap", "label": "Flame ground gap", "min": 0.0, "max": 0.5, "step": 0.005,
		"tip": "Gap between the base of the flame and the tile surface. A small gap stops the flame z-fighting the ground it stands on; too large and the fire floats."},
	{"group": "Fire: the flames", "node": "BoardMirror", "prop": "flame_writes_depth", "label": "Flame writes depth",
		"tip": "Whether the flame writes into the depth buffer. On, it occludes what is behind it correctly but can cut a hard edge against overlapping sprites; off, it always draws as a soft overlay and never clips."},
	{"group": "Fire: light and glow", "node": "BoardMirror", "prop": "flame_light_energy", "label": "Flame light energy", "min": 0.0, "max": 8.0, "step": 0.05,
		"tip": "Brightness of the real point light each fire casts. This is what makes fire LIGHT the board -- units, walls and neighbouring tiles -- rather than merely glow on its own tile."},
	{"group": "Fire: light and glow", "node": "BoardMirror", "prop": "flame_light_range", "label": "Flame light range", "min": 0.5, "max": 12.0, "step": 0.1,
		"tip": "How far a fire's light reaches, in world units (roughly cells). Range and energy together decide whether a burning tile lights a room or just its own corner."},
	{"group": "Fire: light and glow", "node": "BoardMirror", "prop": "flame_light_color", "label": "Flame light colour",
		"tip": "The colour a fire casts onto everything around it. Its twin one row down is what the flame itself gives off; this one is what the neighbours are lit BY, the way Prop light colour is for lamps."},
	# The per-source half of glow (#420). Scene-wide bloom is a Moods knob and always will be -- one
	# Environment per board -- so what belongs here is only how hard THIS source burns.
	{"group": "Fire: light and glow", "node": "BoardMirror", "prop": "flame_glow_color", "label": "Flame glow colour",
		"tip": "The colour the flame itself gives off -- its emission, the thing the bloom pass picks up. Push it past white and the fire reads as hotter than its own art. This is the flame's own light, not what it throws onto the board: that is Flame light colour above."},
	{"group": "Fire: light and glow", "node": "BoardMirror", "prop": "flame_glow_energy", "label": "Flame glow strength", "min": 0.0, "max": 8.0, "step": 0.05,
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
	# burying it made a feel value with no surface.
	#
	# How much lighter shallow water is than deep IS here since #578 -- it was the two tiles' authored
	# modulate, on the reading that it had to reach the flat view too. That reading held right up
	# until the boundary had to BLEND, which a per-tile bake structurally cannot do: by fragment()
	# the two tints are two texels in one atlas. So 3D takes a knob pair and the flat view keeps the
	# modulate, a divergence declared on #292 rather than discovered.
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
	{"group": "Water (deep)", "node": "BoardMirror", "prop": "water_deep_color", "label": "Colour",
		"tip": "What colour deep water IS. It was the tile's own modulate baked into the atlas until #578, which is why the shallow/deep boundary changed colour in a single texel while every other dial glided across it -- a shader cannot unbake a per-tile tint. 3D ONLY: the flat view still reads the tileset, so moving this makes the two views disagree until you edit the tile to match."},
	{"group": "Water (deep)", "node": "BoardMirror", "prop": "water_deep_shore_darken", "label": "Shore darken", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "How much light deep water loses as it gets further from land. The one depth cue that is DARK rather than bright, which is the direction your #552 sweep moved everything -- 0 turns it off and leaves a flat colour out to the horizon."},

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
	{"group": "Water (shallow)", "node": "BoardMirror", "prop": "water_shallow_color", "label": "Colour",
		"tip": "What colour shallow water IS -- the base the bed and the bands are composited over. Same #578 story as deep's, and the same 3D-only caveat: the flat view keeps reading the tileset's modulate."},
	{"group": "Water (shallow)", "node": "BoardMirror", "prop": "water_shallow_shore_darken", "label": "Shore darken", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "How much light shallow water loses with distance from land. Usually wants LESS than deep's -- shallow water that is far from any shore is a contradiction, so this mostly shows up on a wide shelf."},

	# SHARED, and the reason they are a third group rather than a pair: both describe the TRANSITION
	# between the two waters, so there is nothing for a per-type version to mean. The water laws know
	# this category by name (SHARED_GLOBALS), the same way they know the board-data one.
	{"group": "Water (shared)", "node": "BoardMirror", "prop": "water_depth_range", "label": "Depth ramp", "min": 0.5, "max": 8.0, "step": 0.1,
		"tip": "How many CELLS the shallow-to-deep transition takes. 0.5 is the old hard-ish step at the cell edge; wider spreads EVERY per-type dial across that distance -- colour, waves, the bed and its caustics -- which is what makes the two read as one body that deepens rather than two kinds of water meeting. On a small pond a wide ramp means neither tile's own colour is ever seen pure."},
	{"group": "Water (shared)", "node": "BoardMirror", "prop": "water_shore_fade_range", "label": "Shore fade", "min": 1.0, "max": 8.0, "step": 0.1,
		"tip": "How far from land, in cells, the two Shore darken dials take to reach full. Longer is a gentler gradient out to sea; it does nothing at all while both of those are 0."},

]

# Board-markup values that are NOT node properties (#212 slice 2, moved here whole by #373). A
# DECLARED second table rather than a widening of KNOBS: a layer's colour is an entry of the const
# LAYERS table and a reach colour is a static var, so neither can be addressed as node:property, and
# both are written back to a different kind of line.
#
# Which LAYERS entries appear here is measured, not chosen. `set_layer_modulate` REPLACES a layer's
# albedo, so any layer something already drives per frame would take a knob that silently reverts --
# the lying-slider class. Excluded for that reason: ATTACK's 3D side and AIM (OverlayMirror rewrites
# both from the 2D every poll) and HOVER (battle3d._sync_bracket_tint). ZONE_PATROL is excluded as
# authoring-only -- invisible during real play, and it READS OverlayManager's constant, so a knob
# would fork a value that is deliberately one (dev call). ZONE_HIGHLIGHT left that list at #710,
# when the leash reveal made it a play colour: it is a `static` row now, like the threat field beside it.
#
# `static` entries are the exception that proves it: ATTACK has no 3D-only colour to tune, because
# the 3D mirrors the 2D's modulate rather than holding an answer. Tuning it moves BOTH stacks.

# Where the class-level stores are declared -- above the table because a row may name its own
# script home. Named once, here, because the Save has to write these files and a second spelling
# of "which file holds LAYERS" would go stale the first time one moved. Checked by a law.
const OVERLAYS_SCRIPT := "res://Classes/presentation/BoardOverlays.gd"
const OVERLAY_MANAGER_SCRIPT := "res://Classes/board/OverlayManager.gd"
# Where a PLAYER SETTING's authored default lives (#394). The third thing CLASS_KNOBS can name, and
# the only one whose live value is not what Save writes -- see the "setting" rows below.
const SETTINGS_SCRIPT := "res://Classes/core/PlayerSettings.gd"
const MOVEMENT_SCRIPT := "res://Classes/units/MovementComponent.gd"
const ACTION_MENU_SCRIPT := "res://Classes/ui/ActionMenuController.gd"
const PACING_SCRIPT := "res://Classes/core/Pacing.gd"
const MISSION_STATUS_SCRIPT := "res://Classes/ui/MissionStatusPanel.gd"
const ELEMENT_PALETTE_SCRIPT := "res://Classes/ui/ElementPalette.gd"
const QUEUE_STYLE_SCRIPT := "res://Classes/ui/queue/QueueStyle.gd"
const BOARD_SPACE_SCRIPT := "res://Classes/presentation/BoardSpace.gd"
const SIGHT_TRACE_SCRIPT := "res://Classes/board/SightTrace2D.gd"
const THREAT_LINES_SCRIPT := "res://Classes/board/ThreatLines2D.gd"
const MOVE_GRID_SCRIPT := "res://Classes/board/MoveGrid.gd"
const SQUAD_LINES_SCRIPT := "res://Classes/board/SquadLines2D.gd"
const UNIT_VISUALS_SCRIPT := "res://Classes/units/UnitVisuals.gd"
const MUSIC_DIRECTOR_SCRIPT := "res://Classes/audio/MusicDirector.gd"
const STAGING_DUST_SCRIPT := "res://Classes/presentation/StagingDust.gd"
const ARC_LIGHTNING_SCRIPT := "res://Classes/presentation/ArcLightning.gd"
const SHOCK_SPARKS_SCRIPT := "res://Classes/presentation/ShockSparks.gd"

const CLASS_KNOBS: Array[Dictionary] = [
	# --- Player settings the dev authors the DEFAULT for (#394) ---
	#
	# A THIRD kind of class-level value, and the only one where the control and the Save write
	# different things: the control writes the REAL preference (one value, one store -- dev, 2026-08-28,
	# so this and the pause menu's Settings page can never disagree), while Save writes the "default"
	# in PlayerSettings.DEFS, i.e. what someone who never opens that page gets. Flipping it here really
	# does change your own preference; saving is a separate act that decides what SHIPS.
	{"group": "Player settings", "setting": PlayerSettings.Setting.UNHOVERED_BAR_NUMBERS,
		"label": "Unhovered bars show number",
		"tip": "Whether a readout that is up for any reason OTHER than hover -- a queued plan, or the always-show setting -- also carries the HP digits. Off by default: either one can put a bar over half the board or all of it, and pointing at any of them reveals its number anyway."},

	{"group": "Range readout", "label": "Move fill", "layer": BoardOverlays.Layer.MOVE,
		"tip": "The tiles one of YOUR units can reach, while you hover it or order a move. Blue since #1066, and it sorts above every other range tone, so the intersect with an enemy field reads as tinted blue rather than as purple. Alpha is the dial that matters most -- markup has to read as gameplay information without burying the terrain under it."},
	{"group": "Range readout", "label": "Out-of-range grid", "layer": BoardOverlays.Layer.INVALID_MOVE,
		"tip": "Tiles a unit could walk to that its SQUAD will not let it take -- a member's past its leader's cohesion range, or a leader's that would strand somebody. The move grid in grey (#1070): same lattice, switched off. Hovering one turns the tether it would break red, and clicking it shakes that tether."},
	{"group": "Squads & zones", "label": "Capture zone", "layer": BoardOverlays.Layer.ZONE_CAPTURE,
		"tip": "A painted objective zone that can be captured. Stays visible for the whole battle -- this is live objective information, not authoring scaffolding."},
	{"group": "Squads & zones", "label": "Extraction zone", "layer": BoardOverlays.Layer.ZONE_EXTRACTION,
		"tip": "A painted zone your units must reach to extract. Also visible all battle."},
	{"group": "Squads & zones", "label": "Deployment zone", "layer": BoardOverlays.Layer.ZONE_DEPLOYMENT,
		"tip": "Where the force you bring may be placed before the mission starts. Unlike the two above it is gone the moment turn 1 begins, so this colour only has to read against the map for as long as you are choosing."},
	{"group": "Aiming", "label": "Attack reach (2D+3D)", "static": "ATTACK_MODULATE",
		"tip": "The reach fill while aiming a damaging attack. Red reads as hostile, which is the whole reason a healing pick paints green instead."},
	{"group": "Aiming", "label": "Heal reach (2D+3D)", "static": "HEAL_ATTACK_MODULATE",
		"tip": "The same reach fill when the pick HEALS. Forked off the attack's own heals flag, so an attack cannot paint the wrong colour for what it does."},
	# The footprint the reach pair above is aimed THROUGH -- the cells the current pick would actually
	# hit. A const with no row until #422 made it a static var: it is the third channel a player's aim
	# palette repaints, and a value a palette can move has to be one the dev can author. Its pulsed low
	# point follows it (aim_pulse_color borrows the fill's RGB), so there is no second colour to chase.
	{"group": "Aiming", "label": "Aim footprint (2D+3D)", "static": "HOVER_MODULATE",
		"tip": "The cells your current pick would actually hit, drawn on top of the reach fill. Yellow-on-red out of the box, which is the contrast that makes an aim readable -- tune it against whichever reach colour it sits over, not on its own."},
	{"group": "Aiming", "label": "Blocked-reach dim (3D)", "static": "BLOCKED_REACH_DIM",
		"min": 0.1, "max": 1.0, "step": 0.01,
		"tip": "How much darker a reach cell past the attack's vertical tolerance draws in 3D, relative to the live reach colour. The 2D says the same thing with a hatched tile instead."},

	# The three tones of the range readout (#1066): your blue above (Move fill), your red, and the
	# enemy's one field under both. Tune them as a STACK, never one at a time -- what the player
	# actually reads is what they composite to where they cross, and there is no fourth colour
	# authored for that intersect anywhere.
	{"group": "Range readout", "label": "Your attack reach (2D+3D)", "static": "REACH_MODULATE",
		"tip": "Every cell your hovered or selected unit could hit from anywhere in its blue move range. Drawn UNDER the blue, so what shows is the halo past where you may stand -- an alpha set too low leaves the halo invisible against an enemy field."},
	{"group": "Range readout", "label": "Enemy threat field (2D+3D)", "static": "THREAT_MODULATE",
		"tip": "Where an enemy could go AND what it could hit, as one unbroken field. Under both of your tones, so where it crosses your blue the composite IS the intersect colour -- tune it there as well as over bare ground. Its risky neighbour is the violet deployment zone."},

	# THE GRID YOUR MOVEMENT RANGE IS DRAWN WITH (#1074). Four placement values in pixels of the
	# 32-pixel tile, generated into one texture both views draw -- no colour here, because the line and
	# the inner square wear Move fill above. Defaults are the dev's own, picked off a slider mockup.
	{"group": "Movement grid", "label": "Grid line inset (2D+3D)", "static": "GRID_LINE_INSET",
		"script": MOVE_GRID_SCRIPT, "min": 0.0, "max": 12.0, "step": 1.0,
		"tip": "How far in from the tile's edge the line starts, in pixels of the 32-pixel tile. At 0 two neighbouring tiles' lines touch and read as one continuous lattice; above it every tile is its own framed square again, with a gap between neighbours."},
	{"group": "Movement grid", "label": "Grid line width (2D+3D)", "static": "GRID_LINE_WIDTH",
		"script": MOVE_GRID_SCRIPT, "min": 0.0, "max": 16.0, "step": 1.0,
		"tip": "How thick the line is on each tile. Where two tiles meet their lines sit side by side, so a line BETWEEN tiles draws twice this and the rim of the range once. At 1 the rim is a single pixel, which can shimmer at the farthest zoom. 0 is no line at all."},
	{"group": "Movement grid", "label": "Grid inner gap (2D+3D)", "static": "GRID_FILL_GAP",
		"script": MOVE_GRID_SCRIPT, "min": 0.0, "max": 12.0, "step": 1.0,
		"tip": "Clear space between the line's inner edge and the inner square, in the same pixels."},
	{"group": "Movement grid", "label": "Grid inner fill (2D+3D)", "static": "GRID_FILL_ALPHA",
		"script": MOVE_GRID_SCRIPT, "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "The inner square's strength as a fraction of the line's. It wears the same colour as the line (Move fill), so this is only how faint. 0 is the pure-gridline look, with nothing inside the tiles."},
	# The exact tier (#710 slice 2): what the AI WILL do, as opposed to what it COULD. It has to
	# read as a promise rather than a possibility, so tune it AGAINST the threat line above.
	# The PIN flash (#1066, re-cut by #1069). Its own two rows because a cue that says "you asked for
	# this one" has to be findable at a glance and was tunable nowhere at all -- PIN_PULSE_MODULATE
	# has been a static var with no row since the day it was written.
	{"group": "Enemy focus", "label": "Pinned enemy flash", "static": "PIN_PULSE_MODULATE",
		"script": UNIT_VISUALS_SCRIPT,
		"tip": "What a shift+clicked enemy's sprite brightens TO. Above 1.0 on each channel washes the art toward white, which is what the dev asked for after the first version read as the unit going dark between beats. It may be brighter than the aim pulse: the two no longer differ by depth, they differ by cadence -- an aim breathes, a pin snaps and sits."},
	{"group": "Enemy focus", "label": "Pinned enemy flash hold", "static": "PIN_PULSE_HOLD",
		"script": UNIT_VISUALS_SCRIPT, "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "How long it stays at that peak before easing back, in seconds. Zero is the old symmetric breathe, which spends half its cycle returning to normal and reads as a DIP rather than a flash. The ramp either side is half a second, so this is roughly how much of the cycle the cue actually occupies."},
	{"group": "Enemy focus", "label": "Enemy focus outline (2D+3D)", "static": "FOCUS_OUTLINE_COLOR",
		"tip": "The stroke round the whole field of the enemy under the pointer. Since #1066 it is the ONLY thing separating that enemy from every other one whose ranges are up -- nothing dims any more -- so it has to read against the threat field, your own two tones and the terrain alike."},
	{"group": "Reach lines: the arc", "label": "Reach mark (2D+3D)", "static": "MARK_LINE_COLOR", "script": THREAT_LINES_SCRIPT,
		"tip": "The mark from an enemy to the cell you are hovering a move onto -- one per enemy that could hit you there. Pink because nothing else on the board owns that hue: the aim footprint is yellow and the sight bead white, which is what the old amber read as. The cone at the far end shares it."},
	{"group": "Reach lines: the arc", "label": "Reach mark height", "static": "MARK_HEIGHT", "script": THREAT_LINES_SCRIPT,
		"min": 0.0, "max": 2.0, "step": 0.025,
		"tip": "How high above a unit's own footing the mark hangs, in rule height units (two to a level). 0.625 is the middle of a body: a map sprite's ink stands 1.25 of these tall. Deliberately NOT the sight beam's height, which is a RULE about what a wall is and cannot move for a look."},
	{"group": "Reach lines: the arc", "label": "Reach mark bow", "static": "MARK_BOW_PER_CELL", "script": THREAT_LINES_SCRIPT,
		"min": 0.0, "max": 1.0, "step": 0.025,
		"tip": "How far the mark arcs above the straight line between the two units, per CELL of its own length -- so a short mark and a long one bow by the same amount relative to their run. Zero draws a straight line."},
	{"group": "Reach lines: the arc", "label": "Reach mark inset", "static": "MARK_INSET", "script": THREAT_LINES_SCRIPT,
		"min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "How far short of the victim the mark stops, in cells. Pure taste -- the crown hangs well above the mark, so nothing is being cleared. Too large and it points at open air."},
	{"group": "Reach lines: the cone", "label": "Reach cone length", "static": "CONE_LENGTH", "script": THREAT_LINES_SCRIPT,
		"min": 0.0, "max": 1.5, "step": 0.05,
		"tip": "How much of the mark's far end tapers to a point, in cells, measured along the arc so a deeper bow does not shrink it. Zero leaves a bare line with nothing saying which way the blow runs but the bead."},
	{"group": "Reach lines: the cone", "label": "Reach cone width", "static": "CONE_WIDTH_SCALE", "script": THREAT_LINES_SCRIPT,
		"min": 1.0, "max": 6.0, "step": 0.1,
		"tip": "How wide the cone's base is as a MULTIPLE of the mark's own width, so widening the mark widens its cone with it. It wants to be subtle -- barely more than the shaft, converging to nothing at the victim."},
	{"group": "Squads & zones", "label": "Leash reveal (2D+3D)", "static": "ZONE_HIGHLIGHT_MODULATE",
		"tip": "A sentry's patrol zone while you hover it or hold the threat view -- and the Tile Brush's picked zone, which is the same layer and the same colour."},

	# THE SQUAD'S LINES (#1070): a tether from each member to its leader, and the dashed stroke round
	# where the squad may stand -- one system, so one colour and one dash for both. Class values on
	# SquadLines2D because both views draw them.
	{"group": "Squad lines", "label": "Tether and range (2D+3D)", "static": "TETHER_COLOR", "script": SQUAD_LINES_SCRIPT,
		"tip": "The tether from each member to its leader AND the dashed stroke round the squad's range -- one colour, because they are one system. Orange, the hue the cohesion fill always wore."},
	{"group": "Squad lines", "label": "Ghost tether (2D+3D)", "static": "TETHER_GHOST_COLOR", "script": SQUAD_LINES_SCRIPT,
		"tip": "A tether that MIGHT be: every unit Squad Up could recruit, or every squad Join Squad could join. Dim the colour itself, not only its alpha -- the 3D arrowhead is solid and ignores alpha, so a ghost there reads as darker rather than see-through."},
	{"group": "Squad lines", "label": "Strained tether (2D+3D)", "static": "TETHER_STRAIN_COLOR", "script": SQUAD_LINES_SCRIPT,
		"tip": "The tether a hovered move would break -- a member past its leader's range, or a member the leader would strand. It is also the one that shakes when you click that tile anyway."},
	{"group": "Squad lines", "label": "Dashes per tile", "static": "DASHES_PER_TILE", "script": SQUAD_LINES_SCRIPT,
		"min": 1, "max": 8, "step": 1,
		"tip": "How many dashes fit one tile's length. A count rather than a length so the range's stroke, which is one piece per tile edge, meets itself in step at every corner."},
	{"group": "Squad lines", "label": "Dash fill", "static": "DASH_FILL", "script": SQUAD_LINES_SCRIPT,
		"min": 0.05, "max": 1.0, "step": 0.05,
		"tip": "How much of each dash period is ink. 1.0 is a solid line."},
	{"group": "Squad lines", "label": "Dash speed", "static": "DASH_SPEED", "script": SQUAD_LINES_SCRIPT,
		"min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "How fast the dashes march, in tiles per second -- toward the leader along a tether, clockwise round the range. Slow is the brief. The photosensitivity setting stops them."},
	{"group": "Squad lines", "label": "Tether inset", "static": "TETHER_INSET", "script": SQUAD_LINES_SCRIPT,
		"min": 0.0, "max": 0.6, "step": 0.05,
		"tip": "How far short of the leader's centre the arrowhead's tip stops, in tiles, so it meets the leader's body rather than disappearing behind it."},
	{"group": "Squad lines", "label": "Shake size", "static": "SHAKE_AMPLITUDE", "script": SQUAD_LINES_SCRIPT,
		"min": 0.0, "max": 0.5, "step": 0.01,
		"tip": "How far the middle of a strained tether swings when you click a tile the squad will not let you take, in tiles. Both ends stay pinned, like a plucked string."},
	{"group": "Squad lines", "label": "Shake length", "static": "SHAKE_SECONDS", "script": SQUAD_LINES_SCRIPT,
		"min": 0.05, "max": 2.0, "step": 0.05,
		"tip": "How long the pluck rings before it settles, in seconds."},
	{"group": "Squad lines", "label": "Shake swings", "static": "SHAKE_SWINGS", "script": SQUAD_LINES_SCRIPT,
		"min": 0.5, "max": 8.0, "step": 0.5,
		"tip": "How many times it swings back and forth in that time."},

	# The watched footprint (#413). It has to read as a THREAT while every range overlay is off, and
	# it is on screen for both sides at once, so its loudness is the one dial that decides whether
	# the board is legible or a christmas tree. Tune it against the reach fills, not away from white:
	# red already means a damaging reach, and a watch is a promise of exactly that.
	{"group": "Watch", "label": "Watch footprint (2D+3D)", "static": "WATCH_MARK_COLOR",
		"tip": "The mark on every cell a standing Overwatch covers, yours and the enemy's alike. Always on screen while a watch is live, so this is the dial between 'unmissable' and 'noise'."},
	{"group": "Watch", "label": "Watch mark size", "static": "WATCH_MARK_SCALE",
		"min": 0.25, "max": 2.0, "step": 0.05,
		"tip": "How big the watch mark draws relative to its cell. 1.0 is one cell exactly, which is what the art is authored at; smaller reads as a tick in the middle of the tile."},

	# AIMING a watch (#591), which is a different job from the mark above: these are on screen only
	# while the player is declaring, and what they have to say is "this is not an ordinary shot".
	# Tune them as a PAIR and against the reach fills -- the wash carries the glance and the footprint
	# has to stay legible on top of it, which is what the yellow-on-red pair does for a shot.
	{"group": "Watch", "label": "Watch aim reach (2D+3D)", "static": "WATCH_REACH_MODULATE",
		"tip": "The reach fill while DECLARING an overwatch rather than firing. It replaces the red/green heal fork outright, on the grounds that you already know what you picked and cannot otherwise tell you are aiming a watch."},
	{"group": "Watch", "label": "Watch aim footprint (2D+3D)", "static": "WATCH_HOVER_MODULATE",
		"tip": "The cells a watch aim would actually cover, drawn over the reach fill above -- the watch's answer to the yellow an ordinary aim uses. Its pulsed low point is derived from this, so there is no third colour to chase."},

	# The shove trail (2026-08-21). A predicted shove and an authored move drew identically -- both
	# plain white -- so this is what separates "what is about to be done to this unit" from "what it
	# chose". Tune it AGAINST the arrow palette, not just away from white: red already means a
	# refused order and green a member falling behind.
	{"group": "Arrows & trails", "label": "Shove trail (2D+3D)", "static": "KNOCKBACK_MODULATE",
		"tip": "The knockback trail a predicted shove draws, and the drop pointer that hangs off it in 3D. Distinct from a planned move's arrow, which is an order the player authored -- a shove is a consequence. Takes effect on a preview already up."},

	# The three planned-move tints. They were hardcoded literals inside _arrow_modulate until the
	# trail art was desaturated (2026-08-21) -- while the art was cyan it carried most of the hue
	# and these only shaded it, so tuning them was near-pointless. On greyscale art they ARE the
	# colour, which is what makes them knobs.
	{"group": "Arrows & trails", "label": "Move arrow", "static": "MOVE_ARROW_MODULATE",
		"tip": "A queued move's path arrow. Pre-set to the cyan the old art baked in, so this is what moves have always looked like -- now as a value you can move rather than a colour hidden in a PNG."},
	{"group": "Arrows & trails", "label": "Refused-move arrow", "static": "INVALID_ARROW_MODULATE",
		"tip": "A queued move the plan has since refused -- out of the leader's cohesion range, or its destination taken. Reads brighter than before the art was desaturated, because the cyan used to multiply it down."},
	{"group": "Arrows & trails", "label": "Trailing-move arrow", "static": "TRAILING_ARROW_MODULATE",
		"tip": "A Group Move member that stays in range but ends FURTHER from its leader than it started (Case 1) -- legal, but worth seeing. Same brightening as the refused colour above."},

	# The armed-Guard pair (#414 shield, #450 arrow). The statics existed from #414 and their own
	# comment called them the loudness knobs, but neither had ever had a row in any panel -- so the
	# one knob the dev asked for brought its two siblings with it rather than leaving a mark half
	# tunable. The arrow ships WHITE deliberately: see GUARD_LINK_MODULATE's declaration.
	{"group": "Guard", "label": "Guard link arrow", "static": "GUARD_LINK_MODULATE",
		"tip": "The arrow running from a bodyguard to the unit it is covering. Starts neutral white, so this picker is the whole colour rather than a shade over one baked into the art. Tune it against the arrow palette -- cyan already means a queued move, red a refused one, green a member falling behind. Takes effect on links already on the board."},
	{"group": "Guard", "label": "Guard link head inset", "static": "GUARD_LINK_HEAD_INSET",
		"min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "How far back from the ward's cell centre the link's arrowhead stops, in cells. 0 puts it on the shield, which is what the dev reported as unreadable; 0.5 parks it on the edge the pair shares and leaves three columns of overlap; about 0.7 clears the shield outright. Redraws links already on the board."},
	{"group": "Guard", "label": "Guard ward shield", "static": "GUARD_RING_COLOR",
		"tip": "The shield decal under the unit a Guard is protecting -- the other half of the mark the arrow above points at. Neutral white by default now the art is real."},

	# The tile-pick flash (#116). A PERIOD and a peak ALPHA rather than a colour: the pick borrows
	# the reach layer, whose hue is already the two knobs above, so a flash that set its own colour
	# would be a second answer to what that layer looks like.
	{"group": "Tile pick", "label": "Tile-pick flash alpha", "static": "PICK_FLASH_ALPHA",
		"min": 0.1, "max": 1.0, "step": 0.01,
		"tip": "How opaque the candidate tiles go at the top of their flash while a rescue is asking which bank to pull a body onto. It breathes between the layer's own alpha and this one, so the hue never changes. Takes effect on the next pick."},
	{"group": "Tile pick", "label": "Tile-pick flash period", "static": "PICK_FLASH_PERIOD",
		"min": 0.05, "max": 2.0, "step": 0.05,
		"tip": "Seconds for HALF a flash cycle -- the time from the layer's own alpha up to the peak, then the same back down. Smaller is a faster blink. Takes effect on the next pick."},

	# The sight trace's two VERDICT colours (#506). They live on SightTrace2D because that is who
	# draws the flat view, and the diorama's beam copies them -- one answer, so the two views can
	# never disagree about what a blocked shot looks like. Statics rather than LAYERS entries for
	# the same reason: BoardOverlays' SIGHT_TRACE colour is only the no-mirror fallback, so a knob
	# pointed at it would be a slider nothing reads. HOW BRIGHT the 3D beam burns is a separate row
	# in the same section (a node property, one table over), since a colour row tops out at white.
	{"group": "Sight beam", "label": "Sight beam, clear", "static": "CLEAR_COLOR", "script": SIGHT_TRACE_SCRIPT,
		"tip": "The aim's sight beam when the shot has a clear line. Reads on top of the terrain rather than as part of it, so it wants to be a colour nothing on the board is -- the default is plain white and lets the glow knob do the work. Takes effect on a beam already up. Unlike the reach and footprint rows, the player's Aim colours palette does NOT repaint this -- the beam is outside #422's vocabulary, so what you tune here is what every player sees."},
	{"group": "Sight beam", "label": "Sight beam, blocked", "static": "BLOCKED_COLOR", "script": SIGHT_TRACE_SCRIPT,
		"tip": "The same beam when terrain stops the shot -- it is drawn only as far as the block, so this colour and the length are together the whole verdict. Wants to be unmistakable against the clear colour at a glance, since the two are never on screen at the same time to compare. Takes effect on a beam already up. Not palette-driven either, so this colour stands whatever Aim colours is set to."},

	# The #325 rings. A float rather than a colour, and the reason this table is named for WHERE a
	# value lives rather than for what type it is: ring alpha is a static on OverlayManager, exactly
	# like the two reach colours above, and both stacks read it.
	{"group": "Squads & zones", "label": "Ring opacity", "static": "SQUAD_RING_ALPHA",
		"min": 0.1, "max": 1.0, "step": 0.01,
		"tip": "Alpha of the per-squad membership rings under each member (the leader's crown, over the head, stays opaque). Takes effect on markers already up."},
	{"group": "Squads & zones", "label": "Ring pulse brightness", "static": "SQUAD_RING_PULSE_GAIN",
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

	# --- ELEMENT COLOURS (#685) ---------------------------------------------------------------
	#
	# What an element LOOKS like in 2D UI -- the action queue's rail, its state chips and its fired-
	# reaction words all read these. On the Elemental tab beside the fire block because that tab is
	# already where "what does this element look like" is answered; a class row rather than a node
	# property because the store is a static on ElementPalette, which KNOBS cannot reach.
	#
	# TUNE THEM AS A SET, against the queue panel's slate ground AND against each other -- the whole
	# job of these eight is that a glance at a row says which element without reading a word.
	{"group": "Element colours", "label": "Fire", "static": "ELEMENT_FIRE", "script": ELEMENT_PALETTE_SCRIPT,
		"tip": "Fire's colour wherever the UI names an element. The loudest of the set by default, since a burn is usually the consequence a player most wants to spot in a queued plan."},
	{"group": "Element colours", "label": "Water", "static": "ELEMENT_WATER", "script": ELEMENT_PALETTE_SCRIPT,
		"tip": "Water's colour -- and, since a state borrows the colour of the element that deposits it, what a WET chip wears. Tune it against Ice, which is the one it can be confused with."},
	{"group": "Element colours", "label": "Shock", "static": "ELEMENT_SHOCK", "script": ELEMENT_PALETTE_SCRIPT,
		"tip": "Shock's colour. It is the payoff half of the wet/shock combo, so it wants to read as clearly DIFFERENT from Water rather than as a neighbour of it."},
	{"group": "Element colours", "label": "Ice", "static": "ELEMENT_ICE", "script": ELEMENT_PALETTE_SCRIPT,
		"tip": "Ice's colour, and what a CHILLED chip wears. Its near-neighbour is Water; if a chilled row and a wet row read the same at a glance, this is the dial."},
	{"group": "Element colours", "label": "Earth", "static": "ELEMENT_EARTH", "script": ELEMENT_PALETTE_SCRIPT,
		"tip": "Earth's colour. No authored reaction carries it yet, so this one is set for when content does -- it still has to read against the slate panel today."},
	{"group": "Element colours", "label": "Air", "static": "ELEMENT_AIR", "script": ELEMENT_PALETTE_SCRIPT,
		"tip": "Air's colour. Carried by damageless utility carvings like Gust, which means it is often the only mark a row has that anything elemental happened at all."},
	{"group": "Element colours", "label": "Aether", "static": "ELEMENT_AETHER", "script": ELEMENT_PALETTE_SCRIPT,
		"tip": "Aether's colour. The rarest of the sigils, so it can afford to be the most distinctive -- nothing else on screen should be near it."},
	{"group": "Element colours", "label": "Corrosion", "static": "ELEMENT_CORROSION", "script": ELEMENT_PALETTE_SCRIPT,
		"tip": "Corrosion's colour -- the Chemical Spitter's element (#97). Not a sigil and not aura-bearing, so it never appears on a carving; where you WILL see it is a Spray's rail and a Vitriol vial. Its near-neighbours are Earth and Air, which is the pair to tune it against."},

	# --- THE SHOCK ARC (#887) -------------------------------------------------------------------
	#
	# What a shock LOOKS like when it lands: a bolt out of the sky onto the aim, and the current
	# arcing over every conductor the flood reached. Its own group on the Elemental tab because it
	# is an EVENT rather than a standing state -- fire above is what a burning tile looks like while
	# it burns, this is half a second of an attack.
	#
	# EVERY ROW IS LIVE THE INSTANT IT MOVES, with no re-apply hook of its own: the effect rebuilds
	# both of its meshes from these values on every frame a bolt is in the air, so there is no built
	# geometry to go stale. The other half of that is that a slider moved while nothing is flashing
	# shows nothing, which is the same deal PICK_FLASH_ALPHA gets.
	#
	# The one value NOT here is the corona's HUE -- it reads Shock's row above, because the colour of
	# the element is one decision (#422) and this effect is not entitled to a second opinion.
	#
	# SIX GROUPS, ALL ON THE ELEMENTAL TAB (#900). Thirty-five rows under one heading was already
	# past the ~15 where Water took its own sub-tab, and the split costs six GROUP_TABS lines and no
	# reordering -- each run of rows was already contiguous and in this order. It also hands the
	# Attack Editor its own sub-headings from this one store: a per-attack look draws the rows of
	# these groups, so the panel that tunes the default and the panel that overrides it cannot
	# disagree about how the values are arranged, and neither holds a second table.
	{"group": "Shock: the strike", "label": "Sky strike", "static": "sky_strike", "script": ARC_LIGHTNING_SCRIPT,
		"tip": "Whether the bolt comes down out of the sky onto the aimed cell at all. It is drawn down the attack.s OWN trajectory, so a rune authored to clear any height falls almost vertically and one authored flat draws a horizontal rod instead -- there is nothing to tune about the angle because the content already decided it."},
	{"group": "Shock: the strike", "label": "Strike height", "static": "strike_height", "script": ARC_LIGHTNING_SCRIPT,
		"min": 0.0, "max": 40.0, "step": 0.5,
		"tip": "How much of that trajectory is drawn, in cells above the tile it lands on. Zap.s authored clearance puts the apex some fifty cells up, so this is really 'how tall is the strike' -- past about twelve it leaves the top of any framing the camera holds."},
	{"group": "Shock: the strike", "label": "Strike lifetime", "static": "strike_life", "script": ARC_LIGHTNING_SCRIPT,
		"min": 0.05, "max": 2.0, "step": 0.05,
		"tip": "How long the sky bolt lasts. Judge it against the volley.s own beat rather than on its own: a strike shorter than the camera.s push-in is over before anyone has looked at it."},
	{"group": "Shock: the current", "label": "Arc over the water", "static": "arcs", "script": ARC_LIGHTNING_SCRIPT,
		"tip": "Whether the current itself is drawn -- a bolt over every conducting cell the flood reached, occupied or not. This is the half that shows which tiles are LIVE, so switching it off leaves the rule invisible again even though it still fires."},
	{"group": "Shock: the current", "label": "Bolt lift", "static": "bolt_lift", "script": ARC_LIGHTNING_SCRIPT,
		"min": 0.0, "max": 2.0, "step": 0.01,
		"tip": "How far above the surface the arcing bolts hang, in cells. At 0 they lie on the water and read as markup; the whole point of the effect is that the current is ABOVE the water, so this wants to be clearly off the surface without floating free of it."},
	{"group": "Shock: the current", "label": "Bolt lifetime", "static": "bolt_life", "script": ARC_LIGHTNING_SCRIPT,
		"min": 0.05, "max": 2.0, "step": 0.05,
		"tip": "How long one hop of the current lasts. Each hop lights on its own schedule, so a long life plus a long step delay leaves the whole network standing at once, and a short life plus a long delay draws a travelling pulse."},
	{"group": "Shock: the current", "label": "Strike-to-current gap", "static": "strike_delay", "script": ARC_LIGHTNING_SCRIPT,
		"min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "How long the current waits after the sky bolt before it starts travelling. Small values read as one event; larger ones read as a strike and then a consequence."},
	{"group": "Shock: the current", "label": "Step delay", "static": "arc_step_delay", "script": ARC_LIGHTNING_SCRIPT,
		"min": 0.0, "max": 0.5, "step": 0.01,
		"tip": "How long each ring of the flood waits behind the one before it. THIS IS THE DIAL THAT MAKES THE CURRENT TRAVEL -- at 0 the whole network lights at once and reads as a shape rather than a spread. The rule.s own reach is three cells, so the far edge is three of these behind the blast."},
	{"group": "Shock: one bolt", "label": "Bolt segments", "static": "bolt_segments", "script": ARC_LIGHTNING_SCRIPT,
		"min": 1.0, "max": 24.0, "step": 1.0,
		"tip": "How many straight pieces one bolt is made of. At 1 it is a clean line with no kink at all; high counts turn the kinks into noise the eye reads as a blur rather than as lightning. Costs two vertices each."},
	{"group": "Shock: one bolt", "label": "Bolt jag", "static": "bolt_jag", "script": ARC_LIGHTNING_SCRIPT,
		"min": 0.0, "max": 0.6, "step": 0.01,
		"tip": "How far the kinks throw the bolt off its straight line, as a fraction of that bolt.s own length -- so a one-cell hop and a tall strike bend the same amount relative to themselves. At 0 every bolt is a rod."},
	{"group": "Shock: one bolt", "label": "Flicker rate", "static": "flicker_rate", "script": ARC_LIGHTNING_SCRIPT,
		"min": 0.0, "max": 60.0, "step": 1.0,
		"tip": "How many times a second a bolt re-rolls its kinks. This is the only channel that strobes, so it is the one the photosensitivity setting freezes -- with that setting on the bolt still draws, holds and fades, it simply holds ONE shape."},
	{"group": "Shock: one bolt", "label": "Afterimage", "static": "afterimage", "script": ARC_LIGHTNING_SCRIPT,
		"min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "How much of the flash the tail hangs on to. At 0 the bolt is a hard pop that is gone a third of the way through its life; at 1 it fades evenly over the whole life, which is what keeps the network readable long enough to see who got caught."},
	{"group": "Shock: one bolt", "label": "Core colour", "static": "core_color", "script": ARC_LIGHTNING_SCRIPT,
		"tip": "The hot line down the middle of every bolt. Near-white on purpose: the violet is the corona.s job, and a core tinted toward the element loses the hot look that reads as electricity. Its ALPHA is the whole effect.s master strength."},
	{"group": "Shock: one bolt", "label": "Bolt width", "static": "bolt_width", "script": ARC_LIGHTNING_SCRIPT,
		"min": 0.01, "max": 0.5, "step": 0.005,
		"tip": "How wide the core is, in cells. A cell is 1.0 and the tile art is 32 pixels to a cell, so 0.03 is about one art pixel -- this is the dial that decides whether a bolt reads as a thread or as a beam."},
	{"group": "Shock: one bolt", "label": "Corona width scale", "static": "corona_scale", "script": ARC_LIGHTNING_SCRIPT,
		"min": 1.0, "max": 10.0, "step": 0.1,
		"tip": "How much wider the violet corona is than the core it wraps. Below about 2 the two read as one thick bolt; high values make a haze the core sits inside."},
	{"group": "Shock: one bolt", "label": "Core brightness", "static": "core_intensity", "script": ARC_LIGHTNING_SCRIPT,
		"min": 0.5, "max": 12.0, "step": 0.1,
		"tip": "How far past white the core is pushed. The diorama.s glow threshold is 1.2, so anything above that BLOOMS -- which is where the HD look comes from, not from more geometry. Below 1.2 the bolt is flat colour."},
	{"group": "Shock: one bolt", "label": "Corona brightness", "static": "corona_intensity", "script": ARC_LIGHTNING_SCRIPT,
		"min": 0.5, "max": 12.0, "step": 0.1,
		"tip": "The same push for the violet wrap. Keep it under the core.s or the corona blooms out the very thing it is supposed to be framing."},
	{"group": "Shock: one bolt", "label": "Edge softness", "static": "bolt_softness", "script": ARC_LIGHTNING_SCRIPT,
		"min": 0.2, "max": 6.0, "step": 0.1,
		"tip": "How the bolt fades across its own width. 1 is a straight fade to the rim; higher concentrates a bright thread down the middle and lets the rest fall away. The rim always reaches zero, so a bolt never has a visible edge to read as geometry."},
	{"group": "Shock: the screen flash", "label": "Screen flash", "static": "flash", "script": ARC_LIGHTNING_SCRIPT,
		"tip": "Whether the screen goes white for a moment when the blow lands. It drives the tear-out.s OWN white-out rather than a second rect, so the photosensitivity setting.s muted tint and its cap already apply -- and a shock struck during a tear-out is the louder of the two rather than the sum."},
	{"group": "Shock: the screen flash", "label": "Flash strength", "static": "flash_peak", "script": ARC_LIGHTNING_SCRIPT,
		"min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "How white the screen goes at the peak. 1 is a full white-out, which the tear-out uses to hide a cut and a blow almost certainly should not -- what this wants is enough to feel the hit without losing the board."},
	{"group": "Shock: the screen flash", "label": "Flash length", "static": "flash_life", "script": ARC_LIGHTNING_SCRIPT,
		"min": 0.02, "max": 1.0, "step": 0.01,
		"tip": "How long the flash takes to fade. It is a hard pop with no tail on purpose -- the afterimage above is the bolts. staying readable, and a screen flash that lingers is the thing photosensitive players are protected from."},
	{"group": "Shock: sparks", "label": "Sparks", "static": "sparks", "script": SHOCK_SPARKS_SCRIPT,
		"tip": "Whether each body the current catches throws a burst. This is the half that says WHO was caught -- the bolts say which TILES are live -- so switching it off leaves a shock that reads as terrain rather than as an attack on someone."},
	{"group": "Shock: sparks", "label": "Sparks per body", "static": "sparks_per_victim", "script": SHOCK_SPARKS_SCRIPT,
		"min": 0.0, "max": 60.0, "step": 1.0,
		"tip": "How many motes one body throws. Costs nothing per spark -- the whole board.s sparks are one emitter and one draw -- so this is a look dial rather than a budget."},
	{"group": "Shock: sparks", "label": "Spark speed", "static": "spark_speed", "script": SHOCK_SPARKS_SCRIPT,
		"min": 0.0, "max": 12.0, "step": 0.1,
		"tip": "How hard the sparks are thrown outward. High reads as a discharge blowing off the body; low as something smouldering on it."},
	{"group": "Shock: sparks", "label": "Spark spread", "static": "spark_spread", "script": SHOCK_SPARKS_SCRIPT,
		"min": 0.0, "max": 1.5, "step": 0.01,
		"tip": "How far across the cell the sparks START, in cells. Well under half a cell keeps the burst reading as coming off the BODY rather than off the tile it stands on."},
	{"group": "Shock: sparks", "label": "Spark rise", "static": "spark_upward", "script": SHOCK_SPARKS_SCRIPT,
		"min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "How much of the throw goes UP rather than out. Above 1 the burst fountains, which is what separates sparks from the slam dust rolling off a landing."},
	{"group": "Shock: sparks", "label": "Spark lifetime", "static": "spark_lifetime", "script": SHOCK_SPARKS_SCRIPT,
		"min": 0.05, "max": 3.0, "step": 0.05,
		"tip": "How long one spark lasts. Judge it against the bolt lifetime above: sparks outliving the bolt that threw them is what makes the moment read as an aftermath rather than as one event."},
	{"group": "Shock: sparks", "label": "Spark size", "static": "spark_size", "script": SHOCK_SPARKS_SCRIPT,
		"min": 0.005, "max": 0.5, "step": 0.005,
		"tip": "How big one spark is, in cells. The tile art is 32 pixels to a cell, so 0.03 is about one art pixel -- mixing densities is the loudest amateur tell in HD-2D, so keep it near the slam dust.s grains."},
	{"group": "Shock: sparks", "label": "Spark colour", "static": "spark_color", "script": SHOCK_SPARKS_SCRIPT,
		"tip": "What the sparks are made of. They draw ADDITIVELY, so overlapping ones get brighter rather than merely more opaque and the alpha reads as strength -- which also means a dark colour barely shows however much of it there is."},
	{"group": "Shock: sparks", "label": "Spark gravity", "static": "spark_gravity", "script": SHOCK_SPARKS_SCRIPT,
		"min": 0.0, "max": 30.0, "step": 0.5,
		"tip": "How fast the sparks fall. At 0 they hang where the burst put them, which reads as a glow rather than as debris."},
	{"group": "Shock: sparks", "label": "Spark drag", "static": "spark_drag", "script": SHOCK_SPARKS_SCRIPT,
		"min": 0.0, "max": 12.0, "step": 0.1,
		"tip": "How quickly a spark loses the speed it was thrown with. High drag makes the burst bloom and stop; zero lets every mote carry to the end of its life."},
	{"group": "Shock: sparks", "label": "Spark height", "static": "spark_lift", "script": ARC_LIGHTNING_SCRIPT,
		"min": 0.0, "max": 2.0, "step": 0.05,
		"tip": "How far up the body the burst starts, in cells. At 0 it comes off the feet; the default is roughly the torso, which is what makes it read as the UNIT sparking rather than the ground under it."},
	{"group": "Shock: the crawl", "label": "Crawl through the water", "static": "crawl", "script": ARC_LIGHTNING_SCRIPT,
		"tip": "Whether the current also shows IN the water, as filaments spreading over the surface with the same ring delay the bolts use. Ranked below the arcing above the water and built to be judged against it -- it is drawn by the water shader itself, so it only appears on water and never on a wet body standing on dry land."},
	{"group": "Shock: the crawl", "label": "Crawl lifetime", "static": "crawl_life", "script": ARC_LIGHTNING_SCRIPT,
		"min": 0.05, "max": 4.0, "step": 0.05,
		"tip": "How long one cell.s filaments last. Longer than the bolts by default: the water holding the charge after the air has cleared is what makes it read as a current passing through rather than as a second set of bolts."},
	{"group": "Shock: the crawl", "label": "Crawl strength", "static": "crawl_strength", "script": ARC_LIGHTNING_SCRIPT,
		"min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "How much of the water.s own colour the filaments replace at their brightest. Its HUE is not here -- it is Shock.s row under Element colours, because what colour electricity is should be one decision and not two."},

	# --- THE ACTION QUEUE.S OWN COLOURS (#685 round 4) -----------------------------------------
	#
	# Not an element: what the WORLD did to a unit. Its own group because the element rows above are about
	# elements wherever they are drawn, while this one is a value this panel invents.
	{"group": "Action queue", "label": "World event text", "static": "EVENT_TINT", "script": QUEUE_STYLE_SCRIPT,
		"tip": "The pill an action-queue row wears for a consequence the WORLD caused rather than an element -- Fell, Drowning, Into the void, Insulated. It shipped as the rail.s structural grey once and was unreadable against the row, so the one thing it must not be is another grey. Keep it OFF the element wheel: every element colour is saturated, so a near-neutral reads as 'not elemental' at a glance."},

	# ...and the two values that turn those element colours into INK on the PARCHMENT palette
	# (round 5). A player picks the palette in Settings; these are what the dev authors inside one.
	#
	# INERT WHILE SLATE IS LIVE, which is #422's cost pointed the other way -- the alternative is
	# authored in source, exactly as OverlayManager's aim palettes are. Tune them with Parchment
	# picked, where the panel repaints under the slider. The element rows above are inert under
	# NEITHER palette, which is the whole reason parchment adapts them rather than re-authoring them.
	{"group": "Action queue", "label": "Parchment ink depth", "static": "PARCHMENT_INK_DEPTH",
		"script": QUEUE_STYLE_SCRIPT, "min": 0.2, "max": 0.9, "step": 0.01,
		"tip": "How dark an element reads as ink on the parchment palette's cream rows. Its HUE never moves -- fire is orange in both palettes -- so this is the whole of how heavily they sit on the page. Too high and they wash out against the paper; too low and they all read as one dark smudge."},
	{"group": "Action queue", "label": "Parchment ink saturation", "static": "PARCHMENT_INK_SATURATION",
		"script": QUEUE_STYLE_SCRIPT, "min": 1.0, "max": 3.0, "step": 0.05,
		"tip": "How far the element colours are pushed toward pure hue before being inked onto parchment. The slate set is tuned to GLOW on a dark ground, so the palest of them (Ice, Air) go to mud at ink depth without this. A gain rather than a floor, so your relative choices stay in order -- it clamps at fully saturated, which is the one place they can flatten."},

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
		"tip": "Extra time for spinning a chainsword up. Ships short, beside the reload. PLAYER PASSES ONLY since #931 -- an AI's rev takes no beat at all."},
	{"group": "Actions", "label": "Linger: a rev", "static": "LINGER_REV",
		"action": BaseAction.ActionType.REV,
		"script": PACING_SCRIPT, "min": 0.0, "max": 4.0, "step": 0.05,
		"tip": "How long the camera stays on a chainsword that has just spun up. PLAYER PASSES ONLY since #931 -- an AI's rev takes no beat at all."},

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
	{"group": "Flourish: jolt", "label": "Jolt: a hit lands", "static": "SHAKE_HIT",
		"script": PACING_SCRIPT, "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "How hard the camera is knocked when a blow takes health off someone, in cells. Fires on the health-cube burst itself, so the jolt and the cubes always agree about when the hit landed. Applies in BOTH profiles -- it is matched to an animation, not to the drama. Zero is no shake."},
	{"group": "Flourish: jolt", "label": "Jolt: a unit goes down", "static": "SHAKE_DOWN",
		"script": PACING_SCRIPT, "min": 0.0, "max": 2.0, "step": 0.01,
		"tip": "How hard the camera is knocked when a unit is killed or removed, in cells. A killing hit fires ONLY this one, never the hit jolt above -- so this is the whole of what a death feels like, not an extra on top."},
	{"group": "Flourish: jolt", "label": "Jolt: how fast it dies", "static": "SHAKE_DECAY",
		"script": PACING_SCRIPT, "min": 1.0, "max": 40.0, "step": 0.5,
		"tip": "How quickly a jolt fades out. Higher is snappier -- a sharp rap rather than a wobble. Shared by both jolts above, so they read as one camera with one weight."},
	{"group": "Flourish: jolt", "label": "Jolt: how fast it shakes", "static": "SHAKE_FREQUENCY",
		"script": PACING_SCRIPT, "min": 4.0, "max": 90.0, "step": 1.0,
		"tip": "How fast the jolt oscillates. Low reads as a heave, high as a rattle. With the decay above, these two are the whole character of an impact."},
	{"group": "Flourish: sway", "label": "Sway: how far", "static": "SWAY_AMPLITUDE",
		"script": PACING_SCRIPT, "min": 0.0, "max": 0.5, "step": 0.01,
		"tip": "How far the camera drifts while it is resting on a shot, in cells -- the hand-held breath that keeps a held frame from reading as a screenshot. Zero is a locked-off camera."},
	{"group": "Flourish: sway", "label": "Sway: how fast", "static": "SWAY_SPEED",
		"script": PACING_SCRIPT, "min": 0.1, "max": 5.0, "step": 0.05,
		"tip": "How fast that drift breathes. It is two waves at an irrational ratio rather than one, so the bob never quite repeats -- this sets the slower of them."},
	{"group": "Flourish: sway", "label": "Sway strength (zoom off)", "static": "BOARD_SWAY",
		"profile": "board", "script": PACING_SCRIPT, "min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "How much of the sway applies on the plain board. Ships at 0 -- the board is as still as it has always been -- so wanting some breath down here later is this one number rather than a restructure."},
	{"group": "Flourish: sway", "label": "Sway strength (zoom on)", "static": "CINEMATIC_SWAY",
		"profile": "cinematic", "script": PACING_SCRIPT, "min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "How much of the sway applies with the battle zoom on."},
	# Lethality-aware direction (#520 diff 2c). The push-in leans on the player's own zoom rather
	# than replacing it, so these move how far the director may lean -- never where the wheel sits.
	{"group": "Flourish: shots", "label": "Shot: push-in on the loudest beat", "static": "DOLLY_IN",
		"profile": "cinematic", "script": PACING_SCRIPT, "min": 0.0, "max": 10.0, "step": 0.1,
		"tip": "How much closer the camera sits on a killing blow, in world units, at full emphasis. SUBTRACTED from wherever you have left the zoom, so the wheel keeps working underneath and the push-in comes off when the beat ends. Scaled by the directed-shot strength, so it is dead on the plain board."},
	{"group": "Flourish: shots", "label": "Shot: how close the push-in may get", "static": "DOLLY_FLOOR",
		"script": PACING_SCRIPT, "min": 0.5, "max": 20.0, "step": 0.5,
		"tip": "The nearest the push-in may bring the directed shot. During playback the camera is fully directed -- your own zoom is stashed and handed back after -- so this floors the director against flying through a unit. It caps the push-in's contribution, never the total: a shot already sitting closer just gets no push-in rather than being shoved back out. No floor on the wheel outside playback, by design."},
	{"group": "Flourish: shots", "label": "Shot: trained on a unit", "static": "TRAINED_DISTANCE",
		"script": PACING_SCRIPT, "min": 2.0, "max": 20.0, "step": 0.25,
		"tip": "How far out the camera sits while the shot is following one unit -- a beat's subject, a body mid-tumble. The close-up of the pair: the wide establishing shot fits the whole stage, and this is what it cuts in to. The push-in still leans in from here on a killing blow, so keep it a little above its floor."},
	{"group": "Flourish: emphasis", "label": "Emphasis: a unit goes down", "static": "EMPHASIS_DOWN",
		"script": PACING_SCRIPT, "min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "How big a moment a death is, 0 to 1 -- the weight that drives the push-in. Loudest rung wins, so this is the top of the ladder. An ordinary hit earns 0 and is the baseline the rest are read against."},
	{"group": "Flourish: emphasis", "label": "Emphasis: someone stands up surged", "static": "EMPHASIS_CRISIS",
		"script": PACING_SCRIPT, "min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "How big a Crisis is. Its own number rather than a share of the death rung: the two rankings may legitimately disagree, since a hold and a kill want different shots."},
	{"group": "Flourish: emphasis", "label": "Emphasis: that should have killed them", "static": "EMPHASIS_IRON_WILL",
		"script": PACING_SCRIPT, "min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "How big a capped hit is -- the blow that should have been lethal and was not. It earns a long PAUSE from the holds table already; this is separately how much of a push-in it earns."},
	{"group": "Flourish: freeze", "label": "Freeze: a killing blow", "static": "HITSTOP_DOWN",
		"profile": "cinematic", "script": PACING_SCRIPT, "min": 0.0, "max": 0.5, "step": 0.01,
		"tip": "How long EVERYTHING stops when a unit is killed, in real seconds -- the whole world, not just the camera. Zero is no freeze. The health cubes stop with it and resume with it, so the pause after a death still covers the burst exactly."},
	{"group": "Flourish: freeze", "label": "Freeze strength (zoom off)", "static": "BOARD_HITSTOP",
		"profile": "board", "script": PACING_SCRIPT, "min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "How much of that freeze the plain board gets. Ships at 0 -- a freeze CREATES time rather than matching an animation, so unlike the jolt it is drama and dials out with everything else down here."},
	{"group": "Flourish: freeze", "label": "Freeze strength (zoom on)", "static": "CINEMATIC_HITSTOP",
		"profile": "cinematic", "script": PACING_SCRIPT, "min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "How much of that freeze applies with the battle zoom on."},
	{"group": "Flourish: shots", "label": "Shot: how far the camera stoops", "static": "PITCH_DIVE",
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

	# --- ...and the dust it throws (#656) ---
	#
	# Its OWN group rather than nine more rows under the tear-out, on the precedent that split
	# "Water (deep)" from "Water (shallow)": a group is what draws a heading, so this reads as one
	# labelled block on the SAME Playback tab as the rest of the battle zoom (dev, 2026-09-04 --
	# every part of the zoom findable in one tab section), instead of a nineteen-row scroll.
	#
	# Game constants rather than mood, and that is the dev's call over the three-homes fork: nobody
	# has yet authored a board that wants its own dust, and putting the colour on the Moods tab
	# would split the zoom across two tabs to serve a disagreement that does not exist. If a mission
	# ever needs one, eligibility MOVES the value's home (#422) -- the ask is the trigger, not a
	# guess made here.
	{"group": "The tear-out: dust", "label": "Grains per tile", "static": "grains_per_tile",
		"profile": "cinematic", "script": STAGING_DUST_SCRIPT, "min": 0.0, "max": 60.0, "step": 1.0,
		"tip": "How many motes one landing throws. At 0 the tile lands silently. Costs nothing per grain -- the whole board's dust is one emitter and one draw -- so this is a look dial, not a budget."},
	{"group": "The tear-out: dust", "label": "Burst speed", "static": "burst_speed",
		"profile": "cinematic", "script": STAGING_DUST_SCRIPT, "min": 0.0, "max": 8.0, "step": 0.05,
		"tip": "How hard the dust is thrown outward from the tile. Low reads as settling, high as a shockwave."},
	{"group": "The tear-out: dust", "label": "Spread radius", "static": "burst_spread",
		"profile": "cinematic", "script": STAGING_DUST_SCRIPT, "min": 0.0, "max": 1.5, "step": 0.01,
		"tip": "How far across the tile the grains START, in cells. Half a cell fills the tile; above 1 the puff spills onto its neighbours."},
	{"group": "The tear-out: dust", "label": "Upward bias", "static": "upward_bias",
		"profile": "cinematic", "script": STAGING_DUST_SCRIPT, "min": 0.0, "max": 2.0, "step": 0.05,
		"tip": "How much of the burst speed goes UP rather than out. At 0 the dust rolls flat off the landing; at 1 it fountains."},
	{"group": "The tear-out: dust", "label": "Grain lifetime", "static": "grain_lifetime",
		"profile": "cinematic", "script": STAGING_DUST_SCRIPT, "min": 0.05, "max": 4.0, "step": 0.05,
		"tip": "How long one mote lasts before it has faded out completely. The dev's transition timings run long, so a puff tuned to read in isolation can vanish against them -- judge it against the flight above, not on its own."},
	{"group": "The tear-out: dust", "label": "Grain size", "static": "grain_size",
		"profile": "cinematic", "script": STAGING_DUST_SCRIPT, "min": 0.01, "max": 1.0, "step": 0.01,
		"tip": "How big one mote is, in cells. The tile art is 32 pixels to a cell, so 0.03 is roughly one art pixel -- mixing densities is the loudest amateur tell in HD-2D."},
	{"group": "The tear-out: dust", "label": "Grain colour", "static": "grain_color",
		"profile": "cinematic", "script": STAGING_DUST_SCRIPT,
		"tip": "What the dust is made of. Alpha is its strength, the way the water foam's is -- a hue and how much of it there is are one decision, not two."},
	{"group": "The tear-out: dust", "label": "Gravity", "static": "grain_gravity",
		"profile": "cinematic", "script": STAGING_DUST_SCRIPT, "min": 0.0, "max": 20.0, "step": 0.1,
		"tip": "How fast the dust falls back down. At 0 it hangs where the burst put it, which reads as smoke rather than grit."},
	{"group": "The tear-out: dust", "label": "Drag", "static": "grain_damping",
		"profile": "cinematic", "script": STAGING_DUST_SCRIPT, "min": 0.0, "max": 12.0, "step": 0.1,
		"tip": "How quickly a mote loses the speed it was thrown with. High drag makes the puff bloom and stop; zero lets every grain carry to the end of its life."},

	# The tear-out is its own section because it is CINEMATIC-ONLY by construction: _stage_the_fight
	# returns early on BOARD, so this slider is dead in the other column rather than merely unused.
	{"group": "The tear-out", "label": "How high the fight lifts off the board", "static": "STAGE_LIFT",
		"profile": "cinematic", "script": BOARD_SPACE_SCRIPT, "min": 0.0, "max": 60.0, "step": 0.5,
		"tip": "How far above the board the torn-out diorama sits, in cells. The fight plays up there and the tiles thud back into their sockets when it ends. At 0 the diorama sits inside the board it came from. Nothing stages at all with the battle zoom off."},

	# The cliff follow (#602). NO profile tag on any of these, and that is the section's own rule: a
	# fall is an animation running in real time in both profiles, so it is flat like the linger and
	# the impact jolt rather than forked like the sway. Since round 4 the trained shot rides every
	# fall to its end by ruling -- the only dial here is how far a DEATH fall is followed, because
	# only a death fall has no end to ride to.
	{"group": "The cliff follow", "label": "How far down a death fall is followed", "static": "CLIFF_FOLLOW_MAX",
		"script": PACING_SCRIPT, "min": 0.0, "max": 16.0, "step": 0.25,
		"tip": "How far below the lip the camera rides a body falling into a void, in cells, before it stops and lets the body drop on out of frame. This is the toggle on how long the ride lasts. Only a void fall meets it -- a drop onto ground is followed all the way down regardless."},
	{"group": "The cliff follow", "label": "How fast it climbs back", "static": "CLIFF_RECOVER",
		"script": PACING_SCRIPT, "min": 0.2, "max": 8.0, "step": 0.1,
		"tip": "How quickly the camera comes back up once the fall's show is over, in e-folds per second -- HIGHER IS FASTER. Going down is always instant, because the camera is chasing a body in free fall. The climb never races the death cubes at any setting here: the shot holds until they land, and this only paces the ride home afterwards."},
	{"group": "The cliff follow", "label": "Hold: the bottom of a void fall", "static": "PLUMMET_HOLD",
		"script": PACING_SCRIPT, "min": 0.0, "max": 6.0, "step": 0.05,
		"tip": "A beat down in the dark after a body stops falling, before it is removed -- which is the moment its health bricks burst up from under the frame, so this is also the wait before that show. The bricks themselves always land in shot; there is no slider that can lose them."},
	{"group": "The cliff follow", "label": "Shot sits above the units' feet", "static": "STAGE_AIM_LIFT",
		"script": PACING_SCRIPT, "min": -2.0, "max": 4.0, "step": 0.05,
		"tip": "How high above their feet the shot frames the people it is about, in cells -- the fighters on the torn-out diorama, and equally the one unit a trained shot is following. At 0 the shot is level with their feet, which leaves the sprites sitting high; raise it to bring them to the middle of the screen."},

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
	{"group": "Ring: shape", "label": "Centre gap", "static": "RING_INNER_RADIUS",
		"script": ACTION_MENU_SCRIPT, "min": 30.0, "max": 200.0, "step": 1.0,
		"tip": "Radius from the unit's sprite out to the first ring of options. Wide enough that the sprite in the middle reads as the subject rather than as decoration."},
	{"group": "Ring: shape", "label": "Ring thickness", "static": "RING_THICKNESS",
		"script": ACTION_MENU_SCRIPT, "min": 12.0, "max": 90.0, "step": 1.0,
		"tip": "How deep each ring of options is. Thin reads as a menu; thick starts reading as a pie chart, which is the thing this menu is trying not to be."},
	{"group": "Ring: shape", "label": "Ring gap", "static": "RING_GAP",
		"script": ACTION_MENU_SCRIPT, "min": 0.0, "max": 40.0, "step": 1.0,
		"tip": "Empty space between one ring and the next one out. Enough to read as two rings, not so much that a submenu looks unrelated to what opened it."},
	{"group": "Ring: shape", "label": "Dead zone", "static": "DEAD_ZONE_RADIUS",
		"script": ACTION_MENU_SCRIPT, "min": 10.0, "max": 200.0, "step": 1.0,
		"tip": "Radius around the centre that selects NOTHING -- the only place a click cancels, since every other point on the screen belongs to some slice. Keep it inside the centre gap."},
	# The name under the sprite (#560) and the lift that makes room for it. Two knobs because both are
	# taste: the dev asked to bump the sprite "slightly", which is not a number anyone can derive. The
	# name's WIDTH is not here on purpose -- it is the disc's own chord at the baseline, so it follows
	# Dead zone rather than being a third value to keep in sync.
	{"group": "Ring: shape", "label": "Sprite lift", "static": "CENTRE_SPRITE_LIFT",
		"script": ACTION_MENU_SCRIPT, "min": 0.0, "max": 60.0, "step": 1.0,
		"tip": "How far the unit's sprite rises off centre to make room for its name. Every unit's art sits on the bottom of its own texture, so one lift moves every unit's feet together."},
	{"group": "Ring: shape", "label": "Name baseline", "static": "CENTRE_NAME_BASELINE",
		"script": ACTION_MENU_SCRIPT, "min": 0.0, "max": 80.0, "step": 1.0,
		"tip": "How far below centre the unit's name sits. Lower is roomier under the sprite but NARROWER, since the disc is round -- push it far enough down and long names start shrinking to fit."},
	{"group": "Ring: slices", "label": "Wedge fill", "static": "PAINT_FRACTION",
		"script": ACTION_MENU_SCRIPT, "min": 0.15, "max": 1.0, "step": 0.01,
		"tip": "How much of its own slice a wedge actually paints, on the first ring. Below 1.0 leaves air between wedges. Purely a look: the slice you are pointing at does not change, only how much of it is drawn."},
	{"group": "Ring: readout", "label": "Readout panel", "static": "READOUT_BACKGROUND",
		"script": ACTION_MENU_SCRIPT,
		"tip": "The block behind the hovered slice's name and explanation, under the ring. It sits over a live board, so opacity here is legibility -- the first version had none and was painful to read."},
	{"group": "Ring: readout", "label": "Readout border", "static": "READOUT_BORDER",
		"script": ACTION_MENU_SCRIPT,
		"tip": "The outline around that block. Enough to separate it from whatever is behind it."},
	{"group": "Ring: readout", "label": "Readout border width", "static": "READOUT_BORDER_WIDTH",
		"script": ACTION_MENU_SCRIPT, "min": 0.0, "max": 8.0, "step": 0.5,
		"tip": "How thick that outline is drawn. Zero removes it."},
	{"group": "Ring: readout", "label": "Readout name", "static": "READOUT_TITLE_COLOR",
		"script": ACTION_MENU_SCRIPT,
		"tip": "The hovered slice's NAME, and every wedge label too. Kept fully opaque on purpose: the hierarchy against the explanation below is brightness, never transparency."},
	{"group": "Ring: readout", "label": "Readout detail", "static": "READOUT_DETAIL_COLOR",
		"script": ACTION_MENU_SCRIPT,
		"tip": "The explanation under that name -- what the option does, and why it is greyed when it is. Dimmer than the name, but still solid."},
	{"group": "Ring: shape", "label": "Widest wedge", "static": "MAX_WEDGE_DEGREES",
		"script": ACTION_MENU_SCRIPT, "min": 20.0, "max": 360.0, "step": 1.0,
		"tip": "Ceiling on how many degrees any one wedge PAINTS. Without it a submenu holding a single option balloons into a whole donut. It never moves a hit boundary -- the sectors still tile the circle, so the leftover angle belongs to the nearest wedge and the highlight says which."},
	{"group": "Ring: centre", "label": "Centre disc", "static": "CENTRE_COLOR",
		"script": ACTION_MENU_SCRIPT,
		"tip": "The disc the unit's sprite sits on. It is exactly the DEAD ZONE drawn, so its edge is a promise about where clicking selects nothing -- opaque enough to lift the sprite off the board behind it."},
	{"group": "Ring: centre", "label": "Centre rim", "static": "CENTRE_RIM_COLOR",
		"script": ACTION_MENU_SCRIPT,
		"tip": "The ring around that disc. Reads as the boundary between the unit and its options."},
	{"group": "Ring: centre", "label": "Centre rim width", "static": "CENTRE_RIM_WIDTH",
		"script": ACTION_MENU_SCRIPT, "min": 0.0, "max": 12.0, "step": 0.5,
		"tip": "How thick that rim is drawn. Zero removes it and leaves the bare disc."},
	{"group": "Ring: slices", "label": "Wedge fill falloff", "static": "PAINT_FRACTION_FALLOFF",
		"script": ACTION_MENU_SCRIPT, "min": 0.0, "max": 0.4, "step": 0.01,
		"tip": "How much less each ring further out paints than the one inside it, so a submenu builds out lighter instead of stacking full circles. Zero paints every ring the same."},
	{"group": "Ring: slices", "label": "Preview opacity", "static": "GHOST_ALPHA",
		"script": ACTION_MENU_SCRIPT, "min": 0.05, "max": 1.0, "step": 0.01,
		"tip": "Opacity of the ring PREVIEWED under the category you are hovering -- what you would open if you clicked. Faint enough to read as not-open-yet, solid enough to read at all."},
	{"group": "Ring: slices", "label": "Slice", "static": "SLICE_COLOR",
		"script": ACTION_MENU_SCRIPT,
		"tip": "An ordinary option's wedge. It sits over the board, so its alpha is what decides whether you can still see what you are acting on."},
	{"group": "Ring: slices", "label": "Slice (pointed at)", "static": "SLICE_SELECTED_COLOR",
		"script": ACTION_MENU_SCRIPT,
		"tip": "The one slice your angle currently picks. The pointer is routinely nowhere near the ring, so this highlight is the only feedback saying what a click would do."},
	{"group": "Ring: slices", "label": "Slice (unavailable)", "static": "SLICE_DISABLED_COLOR",
		"script": ACTION_MENU_SCRIPT,
		"tip": "An option the unit owns but cannot use right now -- a dry magazine, a carving it cannot pay for. It stays listed and says why, so this must read as present-but-dead, not as absent."},

	# How one track replaces another (#136 slice 3). A static on MusicDirector, which is a game
	# collaborator rather than a node of the Battle3D world -- the MissionStatusPanel case again, so a
	# class row is the only form available rather than a preference.
	{"group": "Music", "label": "Crossfade", "static": "CROSSFADE_SECONDS",
		"script": MUSIC_DIRECTOR_SCRIPT, "min": 0.0, "max": 4.0, "step": 0.05,
		"tip": "Seconds for one track to replace another. The swap fires twice a round, so judge this against a whole mission rather than against one hand-off: short enough and it reads as a cut every turn, long enough and the two tracks are audibly playing over each other. Zero is a hard cut. Takes effect on the next swap."},
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
# The group whose three aim rows a player's palette can override (#422). Named for the same reason
# ACTION_GROUP is: the table rows spell the string, and the PANEL needs one place to recognise it.
# It was "Board markup colours" until #1074 cut that group by subject -- the notice now sits under
# the section holding exactly the rows it talks about.
const AIM_GROUP := "Aiming"
# The group whose rows a player's camera steps SCALE (#394). Named for the panel's benefit, exactly
# as the two above are: the table rows spell the string, this is what recognises it.
const CAMERA_GROUP := "Camera handling"
# Which player settings scale something in that group, in the order their notice reads. A DECLARED
# list rather than "every Scale row", so a fourth one joins by decision -- MAIN_ACTION_NEVER's shape.
const CAMERA_SCALE_SETTINGS: Array[PlayerSettings.Setting] = [
	PlayerSettings.Setting.CAMERA_PAN_SPEED,
	PlayerSettings.Setting.MOUSE_SENSITIVITY,
	PlayerSettings.Setting.CAMERA_SMOOTHING,
]


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


# DECLARATION ORDER IS BOTH ORDERS since #1074: a tab appears where its first group does, and the
# sections inside a tab run in the order their groups are listed here. GameTool builds GROUP-major --
# each section's KNOBS rows then its CLASS_KNOBS rows -- so a section is a SUBJECT and may hold rows
# from either table. Before that the builder was table-major, which is why the Markup and Colours
# tabs were split by how a value is STORED (a node property vs a class value) and the reach mark's
# controls lived on two tabs at once; the dev: "the dev tools need more headers in the Game area.
# Those sets of controls are a bit dense right now."
const GROUP_TABS: Dictionary[String, String] = {
	# THE READOUT -- what the board says while you plan. The three range tones first, since they are
	# tuned as a stack, then the grid your own tones are drawn with.
	"Range readout": "Markup",
	"Movement grid": "Markup",
	"Enemy focus": "Markup",
	"Reach lines: the arc": "Markup",
	"Reach lines: the cone": "Markup",
	"Aiming": "Markup",
	"Sight beam": "Markup",
	"Watch": "Markup",
	# EVERYTHING ELSE LAID ON THE BOARD -- was "Colours", which named how the values were stored.
	"Arrows & trails": "Markers",
	"Guard": "Markers",
	"Squads & zones": "Markers",
	"Squad lines": "Markers",
	"Tile pick": "Markers",
	"Lift, brackets & icons": "Markers",
	"Dev chrome": "Markers",
	"HP cubes": "Unit HUD",
	"HP number": "Unit HUD",
	"Predicted change": "Unit HUD",
	"State icons": "Unit HUD",
	"Cube burst": "Unit HUD",
	"Heal pop": "Unit HUD",
	# Its OWN heading on the Unit HUD tab rather than joining the knobs above it (#394): these rows
	# write a player's real preference and their Save writes a different value again, which is worth
	# a line of separation from the knobs that simply are what they say.
	"Player settings": "Unit HUD",
	"Mission HUD": "Mission",
	# Its own tab with one row in it, which is thin today and is where the lethality stings and any
	# ducking land next -- a crossfade length has nothing to do with any other tab's subject.
	"Music": "Audio",
	"Camera handling": "Camera",
	"Playback framing": "Playback",
	"World": "World",
	# Water took its OWN sub-tab once every dial went per type (#552): twenty-one rows under the prop
	# lamps on World is a scroll rather than a panel. Two groups into one tab, and since a group draws
	# its own heading inside a tab it reads as Water (deep) / Water (shallow) -- which is also why the
	# split needs no third table, only a second group name.
	"Water (deep)": "Water",
	"Water (shallow)": "Water",
	"Water (shared)": "Water",
	# Elemental VFX, not just fire (#420). Ice draws as a flat Layer.TERRAIN icon with no 3D effect
	# and so has nothing to put here yet; Cover arrives with fire because #326 ruled it the same
	# kind of thing -- a terrain STATE whose art draws objects. A new element is one line.
	"Fire: the flames": "Elemental",
	"Fire: light and glow": "Elemental",
	"Cover": "Elemental",
	# ...and what an element looks like in 2D UI (#685), beside what it looks like on the board.
	"Element colours": "Elemental",
	# ...and what a shock looks like when it LANDS (#887). Beside fire rather than in it: fire is
	# what a burning tile looks like while it stands, this is half a second of an attack. SIX groups
	# since #900 -- see the table's own note where they are declared.
	"Shock: the strike": "Elemental",
	"Shock: the current": "Elemental",
	"Shock: one bolt": "Elemental",
	"Shock: the screen flash": "Elemental",
	"Shock: sparks": "Elemental",
	"Shock: the crawl": "Elemental",
	# The queue.s own invented colour, beside the element chips it has to read against (#685).
	"Action queue": "Elemental",
	# Playback is SIX groups on one tab (dev, 2026-08-27) -- thirty flat rows was unreadable, and a
	# group is what draws a heading. Same two-groups-one-tab shape Water uses, three sections further.
	"The profile": "Playback",
	"Actions": "Playback",
	"Outcomes": "Playback",
	"Camera travel": "Playback",
	# ...and a SEVENTH since #520 diff 2b. Its own group rather than more rows under the travel one
	# because they answer different questions: that section is how long the camera takes to GET
	# somewhere, this is what it does once it is there. Cut five ways by #1074, one per kind of move.
	"Flourish: jolt": "Playback",
	"Flourish: sway": "Playback",
	"Flourish: shots": "Playback",
	"Flourish: emphasis": "Playback",
	"Flourish: freeze": "Playback",
	"The tear-out": "Playback",
	# ...and its dust (#656), beside it rather than in it -- the Water split's shape, one tab along.
	"The tear-out: dust": "Playback",
	# ...and an EIGHTH since #602. Beside the tear-out rather than in it: both take the camera off the
	# board plane, but one is the fight being lifted OUT and the other is one body dropping out of it,
	# and only the first is cinematic-only.
	"The cliff follow": "Playback",
	"Motion": "Playback",
	"Ring: shape": "Action ring",
	"Ring: slices": "Action ring",
	"Ring: centre": "Action ring",
	"Ring: readout": "Action ring",
}


# --- What an ATTACK may override (#900) ----------------------------------------------------------
#
# Which groups of CLASS_KNOBS describe an element's attack-scoped effect, so an authored EffectLook
# can offer exactly those rows. A PROJECTION of the table above rather than a second one: every
# label, tooltip and range is already there, and a parallel list would be Law #4 with the ink still
# wet on the first.
#
# FIRE IS DELIBERATELY ABSENT. Its group is what a BURNING TILE looks like while it stands, and a
# tile's fire outlives the attack that lit it (#890) -- the ground owns that clock, so an attack has
# no standing to author it. A future element with an attack-scoped effect is one line here.
#
# It stays on the DEV side, and that is what keeps the arrangement free: shipping code never asks
# this. An effect reads the look's dictionary with its own static as the fallback, so GameKnobs is
# read by dev tools alone, exactly as ObjectKnobs is.
const LOOK_GROUPS: Dictionary[Elemental.Element, Array] = {
	Elemental.Element.SHOCK: [
		"Shock: the strike", "Shock: the current", "Shock: one bolt",
		"Shock: the screen flash", "Shock: sparks", "Shock: the crawl",
	],
}


# Every CLASS_KNOBS row an attack may override for this element, in the table's own order, so the
# attack editor's sections read in the same sequence the Game tab's do.
static func look_rows(element: Elemental.Element) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var groups: Array = LOOK_GROUPS.get(element, [])
	if groups.is_empty():
		return rows
	for knob: Dictionary in CLASS_KNOBS:
		if groups.has(knob.get("group", "")):
			rows.append(knob)
	return rows


# Keys in this look that name no live row for its own element -- what a knob RENAME leaves behind,
# and the one failure this storage shape has that the panel cannot show you (an orphaned key draws
# no row, so the file quietly carries an override nothing reads). Swept per FILE rather than per
# attack: a shared look would otherwise be counted once per wearer and an unworn one never at all.
static func stale_look_keys(look: EffectLook) -> PackedStringArray:
	var stale: PackedStringArray = []
	if look == null:
		return stale
	var live: PackedStringArray = []
	for knob: Dictionary in look_rows(look.element):
		live.append(knob["static"])
	for key: String in look.overrides:
		if not live.has(key):
			stale.append(key)
	return stale


# Which table an edit came from, carried through the save report. The two tables share an index
# space, so a saved row's number alone cannot say whose baseline to move.
const KNOB_SOURCE := "knobs"
const CLASS_SOURCE := "class"


# --- Reading and writing a CLASS knob ------------------------------------------------------------
#
# KNOBS rows route through LookKnobs.read/write like everything else. These do not: there is no node
# property to address, so each store gets its answer here and nowhere else.

static func read_class(host: Node3D, knob: Dictionary) -> Variant:
	if knob.has("setting"):
		return PlayerSettings.value_of(knob["setting"])
	if knob.has("static"):
		return read_static(knob["static"])
	var overlays := overlays_of(host)
	if overlays == null:
		return null
	return overlays.layer_modulate(knob["layer"])


static func write_class(host: Node3D, knob: Dictionary, value: Variant) -> void:
	if knob.has("setting"):
		# The REAL preference, not a panel-local copy -- no re-apply, because the one reader
		# (UnitMirror) is a per-frame reconcile and reads the store itself.
		PlayerSettings.set_value(knob["setting"], value)
		return
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
		"HOVER_MODULATE": return OverlayManager.HOVER_MODULATE
		"BLOCKED_REACH_DIM": return OverlayManager.BLOCKED_REACH_DIM
		"REACH_MODULATE": return OverlayManager.REACH_MODULATE
		"THREAT_MODULATE": return OverlayManager.THREAT_MODULATE
		"FOCUS_OUTLINE_COLOR": return OverlayManager.FOCUS_OUTLINE_COLOR
		"ZONE_HIGHLIGHT_MODULATE": return OverlayManager.ZONE_HIGHLIGHT_MODULATE
		"MARK_LINE_COLOR": return ThreatLines2D.MARK_LINE_COLOR
		"MARK_HEIGHT": return ThreatLines2D.MARK_HEIGHT
		"MARK_BOW_PER_CELL": return ThreatLines2D.MARK_BOW_PER_CELL
		"MARK_INSET": return ThreatLines2D.MARK_INSET
		"CONE_LENGTH": return ThreatLines2D.CONE_LENGTH
		"CONE_WIDTH_SCALE": return ThreatLines2D.CONE_WIDTH_SCALE
		"GRID_LINE_INSET": return MoveGrid.GRID_LINE_INSET
		"GRID_LINE_WIDTH": return MoveGrid.GRID_LINE_WIDTH
		"GRID_FILL_GAP": return MoveGrid.GRID_FILL_GAP
		"GRID_FILL_ALPHA": return MoveGrid.GRID_FILL_ALPHA
		"TETHER_COLOR": return SquadLines2D.TETHER_COLOR
		"TETHER_GHOST_COLOR": return SquadLines2D.TETHER_GHOST_COLOR
		"TETHER_STRAIN_COLOR": return SquadLines2D.TETHER_STRAIN_COLOR
		"DASHES_PER_TILE": return SquadLines2D.DASHES_PER_TILE
		"DASH_FILL": return SquadLines2D.DASH_FILL
		"DASH_SPEED": return SquadLines2D.DASH_SPEED
		"TETHER_INSET": return SquadLines2D.TETHER_INSET
		"SHAKE_AMPLITUDE": return SquadLines2D.SHAKE_AMPLITUDE
		"SHAKE_SECONDS": return SquadLines2D.SHAKE_SECONDS
		"SHAKE_SWINGS": return SquadLines2D.SHAKE_SWINGS
		"PIN_PULSE_MODULATE": return UnitVisuals.PIN_PULSE_MODULATE
		"PIN_PULSE_HOLD": return UnitVisuals.PIN_PULSE_HOLD
		"SQUAD_RING_ALPHA": return OverlayManager.SQUAD_RING_ALPHA
		"SQUAD_RING_PULSE_GAIN": return OverlayManager.SQUAD_RING_PULSE_GAIN
		"KNOCKBACK_MODULATE": return OverlayManager.KNOCKBACK_MODULATE
		"WATCH_MARK_COLOR": return OverlayManager.WATCH_MARK_COLOR
		# On SightTrace2D, not OverlayManager -- the flat renderer owns the verdict hue and the
		# diorama's beam copies it. The names match the vars, as every row in this table does.
		"CLEAR_COLOR": return SightTrace2D.CLEAR_COLOR
		"BLOCKED_COLOR": return SightTrace2D.BLOCKED_COLOR
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
		# The slam dust (#656). A GPU particle's state cannot be read back, so every one of these
		# names the CPU-side value the burst is built from -- which is also what makes the scatter
		# assertable rather than merely deterministic.
		"grains_per_tile": return StagingDust.grains_per_tile
		"burst_speed": return StagingDust.burst_speed
		"burst_spread": return StagingDust.burst_spread
		"upward_bias": return StagingDust.upward_bias
		"grain_lifetime": return StagingDust.grain_lifetime
		"grain_size": return StagingDust.grain_size
		"grain_color": return StagingDust.grain_color
		"grain_gravity": return StagingDust.grain_gravity
		"grain_damping": return StagingDust.grain_damping
		# The shock arc (#887). Read straight off the effect's statics, which is also what it draws
		# from every frame -- there is no built copy for these to fall out of step with.
		"sky_strike": return ArcLightning.sky_strike
		"strike_height": return ArcLightning.strike_height
		"strike_life": return ArcLightning.strike_life
		"arcs": return ArcLightning.arcs
		"bolt_lift": return ArcLightning.bolt_lift
		"bolt_life": return ArcLightning.bolt_life
		"strike_delay": return ArcLightning.strike_delay
		"arc_step_delay": return ArcLightning.arc_step_delay
		"bolt_segments": return ArcLightning.bolt_segments
		"bolt_jag": return ArcLightning.bolt_jag
		"flicker_rate": return ArcLightning.flicker_rate
		"afterimage": return ArcLightning.afterimage
		"core_color": return ArcLightning.core_color
		"bolt_width": return ArcLightning.bolt_width
		"corona_scale": return ArcLightning.corona_scale
		"core_intensity": return ArcLightning.core_intensity
		"corona_intensity": return ArcLightning.corona_intensity
		"bolt_softness": return ArcLightning.bolt_softness
		"flash": return ArcLightning.flash
		"flash_peak": return ArcLightning.flash_peak
		"flash_life": return ArcLightning.flash_life
		"spark_lift": return ArcLightning.spark_lift
		"crawl": return ArcLightning.crawl
		"crawl_life": return ArcLightning.crawl_life
		"crawl_strength": return ArcLightning.crawl_strength
		# ...and the sparks, whose own node holds them (#887 slice 2). A GPU particle's state cannot
		# be read back, so each of these names the CPU-side value a burst is built from.
		"sparks": return ShockSparks.sparks
		"sparks_per_victim": return ShockSparks.sparks_per_victim
		"spark_speed": return ShockSparks.spark_speed
		"spark_spread": return ShockSparks.spark_spread
		"spark_upward": return ShockSparks.spark_upward
		"spark_lifetime": return ShockSparks.spark_lifetime
		"spark_size": return ShockSparks.spark_size
		"spark_color": return ShockSparks.spark_color
		"spark_gravity": return ShockSparks.spark_gravity
		"spark_drag": return ShockSparks.spark_drag
		"PLAYBACK_PAN": return Pacing.PLAYBACK_PAN
		"TEAR_OUT_BRACE": return Pacing.TEAR_OUT_BRACE
		"TEAR_OUT_EMPTY_SKY": return Pacing.TEAR_OUT_EMPTY_SKY
		"TEAR_OUT_SETTLE": return Pacing.TEAR_OUT_SETTLE
		"TEAR_OUT_AFTERMATH": return Pacing.TEAR_OUT_AFTERMATH
		"CLIFF_FOLLOW_MAX": return Pacing.CLIFF_FOLLOW_MAX
		"CLIFF_RECOVER": return Pacing.CLIFF_RECOVER
		"PLUMMET_HOLD": return Pacing.PLUMMET_HOLD
		"STAGE_AIM_LIFT": return Pacing.STAGE_AIM_LIFT
		"TRAINED_DISTANCE": return Pacing.TRAINED_DISTANCE
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
		"CENTRE_SPRITE_LIFT": return ActionMenuController.CENTRE_SPRITE_LIFT
		"CENTRE_NAME_BASELINE": return ActionMenuController.CENTRE_NAME_BASELINE
		"PAINT_FRACTION": return ActionMenuController.PAINT_FRACTION
		"PAINT_FRACTION_FALLOFF": return ActionMenuController.PAINT_FRACTION_FALLOFF
		"GHOST_ALPHA": return ActionMenuController.GHOST_ALPHA
		"SLICE_COLOR": return ActionMenuController.SLICE_COLOR
		"SLICE_SELECTED_COLOR": return ActionMenuController.SLICE_SELECTED_COLOR
		"SLICE_DISABLED_COLOR": return ActionMenuController.SLICE_DISABLED_COLOR
		"CROSSFADE_SECONDS": return MusicDirector.CROSSFADE_SECONDS
		"URGENT_ROUNDS": return MissionStatusPanel.URGENT_ROUNDS
		"URGENT_COLOR": return MissionStatusPanel.URGENT_COLOR
		"ELEMENT_FIRE": return ElementPalette.ELEMENT_FIRE
		"ELEMENT_WATER": return ElementPalette.ELEMENT_WATER
		"ELEMENT_SHOCK": return ElementPalette.ELEMENT_SHOCK
		"ELEMENT_ICE": return ElementPalette.ELEMENT_ICE
		"ELEMENT_EARTH": return ElementPalette.ELEMENT_EARTH
		"ELEMENT_AIR": return ElementPalette.ELEMENT_AIR
		"ELEMENT_AETHER": return ElementPalette.ELEMENT_AETHER
		"ELEMENT_CORROSION": return ElementPalette.ELEMENT_CORROSION
		"EVENT_TINT": return QueueStyle.EVENT_TINT
		"PARCHMENT_INK_DEPTH": return QueueStyle.PARCHMENT_INK_DEPTH
		"PARCHMENT_INK_SATURATION": return QueueStyle.PARCHMENT_INK_SATURATION
	push_error("GameKnobs: unknown static '%s'" % name)
	return null


# The static IS the authority; what is already drawn is re-derived from it in the same breath, or a
# tuned value would not show until the next aim or the next squad change. #324's lesson: a knob on
# something RECONCILED rather than redrawn moves nothing until someone re-applies it.
static func write_static(host: Node3D, name: String, value: Variant) -> void:
	match name:
		"ATTACK_MODULATE": OverlayManager.ATTACK_MODULATE = value
		"HEAL_ATTACK_MODULATE": OverlayManager.HEAL_ATTACK_MODULATE = value
		"HOVER_MODULATE": OverlayManager.HOVER_MODULATE = value
		"BLOCKED_REACH_DIM": OverlayManager.BLOCKED_REACH_DIM = value   # mirror reads it per frame; the refresh below is harmless
		"REACH_MODULATE": OverlayManager.REACH_MODULATE = value
		"THREAT_MODULATE": OverlayManager.THREAT_MODULATE = value
		"FOCUS_OUTLINE_COLOR": OverlayManager.FOCUS_OUTLINE_COLOR = value
		"ZONE_HIGHLIGHT_MODULATE": OverlayManager.ZONE_HIGHLIGHT_MODULATE = value
		"MARK_LINE_COLOR": ThreatLines2D.MARK_LINE_COLOR = value
		"MARK_HEIGHT": ThreatLines2D.MARK_HEIGHT = value
		"MARK_BOW_PER_CELL": ThreatLines2D.MARK_BOW_PER_CELL = value
		"MARK_INSET": ThreatLines2D.MARK_INSET = value
		"CONE_LENGTH": ThreatLines2D.CONE_LENGTH = value
		"CONE_WIDTH_SCALE": ThreatLines2D.CONE_WIDTH_SCALE = value
		# Both need a REBUILD rather than a re-push: a running Tween holds the endpoints it was
		# STARTED with, so a turned value reaches a standing flash only by the flash being rebuilt.
		# That is #591's lesson from the aim pulse, which breathed back to its old colour twice a
		# second after a knob moved -- right in a screenshot and wrong in motion.
		"PIN_PULSE_MODULATE":
			UnitVisuals.PIN_PULSE_MODULATE = value
			_restyle_pin_flashes(host)
			return
		"PIN_PULSE_HOLD":
			UnitVisuals.PIN_PULSE_HOLD = value
			_restyle_pin_flashes(host)
			return
		# The movement grid (#1074). All four regenerate the one texture each view already holds.
		"GRID_LINE_INSET":
			MoveGrid.GRID_LINE_INSET = value
			_restyle_move_grid(host)
			return
		"GRID_LINE_WIDTH":
			MoveGrid.GRID_LINE_WIDTH = value
			_restyle_move_grid(host)
			return
		"GRID_FILL_GAP":
			MoveGrid.GRID_FILL_GAP = value
			_restyle_move_grid(host)
			return
		"GRID_FILL_ALPHA":
			MoveGrid.GRID_FILL_ALPHA = value
			_restyle_move_grid(host)
			return
		# The squad's lines (#1070). Every one re-applies to BOTH views through one door: the 3D beam
		# params (the dashes are shader uniforms) and the store, which re-derives the tethers -- the
		# inset is geometry -- and repaints the flat line.
		"TETHER_COLOR", "TETHER_GHOST_COLOR", "TETHER_STRAIN_COLOR", "DASHES_PER_TILE", "DASH_FILL", \
				"DASH_SPEED", "TETHER_INSET", "SHAKE_AMPLITUDE", "SHAKE_SECONDS", "SHAKE_SWINGS":
			_write_squad_line(name, value)
			_restyle_squad_lines(host)
			return
		"SQUAD_RING_ALPHA": OverlayManager.SQUAD_RING_ALPHA = value
		"SQUAD_RING_PULSE_GAIN": OverlayManager.SQUAD_RING_PULSE_GAIN = value
		"KNOCKBACK_MODULATE": OverlayManager.KNOCKBACK_MODULATE = value
		"WATCH_MARK_COLOR": OverlayManager.WATCH_MARK_COLOR = value
		# Both fall through to the re-apply match below rather than returning: a beam that is
		# already up does not repaint until the hovered aim changes, which is precisely not what
		# happens while the dev drags a slider (WATCH_MARK_COLOR's born-dead-slider reasoning).
		"CLEAR_COLOR": SightTrace2D.CLEAR_COLOR = value
		"BLOCKED_COLOR": SightTrace2D.BLOCKED_COLOR = value
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
		# The slam dust (#656). Every arm re-applies, because two of these nine (lifetime, and the
		# buffer `amount` that grains-per-tile sizes) are node state rather than values a burst
		# reads as it goes -- and one sweep for all nine beats nine that have to agree about which
		# ones need it. Costs nothing: the node's own apply() is a handful of assignments.
		"grains_per_tile":
			StagingDust.grains_per_tile = int(value)
			_reapply_staging_dust(host)
			return
		"burst_speed":
			StagingDust.burst_speed = value
			_reapply_staging_dust(host)
			return
		"burst_spread":
			StagingDust.burst_spread = value
			_reapply_staging_dust(host)
			return
		"upward_bias":
			StagingDust.upward_bias = value
			_reapply_staging_dust(host)
			return
		"grain_lifetime":
			StagingDust.grain_lifetime = value
			_reapply_staging_dust(host)
			return
		"grain_size":
			StagingDust.grain_size = value
			_reapply_staging_dust(host)
			return
		"grain_color":
			StagingDust.grain_color = value
			_reapply_staging_dust(host)
			return
		"grain_gravity":
			StagingDust.grain_gravity = value
			_reapply_staging_dust(host)
			return
		"grain_damping":
			StagingDust.grain_damping = value
			_reapply_staging_dust(host)
			return
		# The shock arc (#887). Every one takes SHOVE_SLIDE_SPEED's early return, and for a stronger
		# version of its reason: the effect rebuilds both of its meshes from these values on every
		# frame a bolt is alive, so there is nothing built for a knob to be stale against. The two
		# ints are cast at the door the way grains_per_tile is -- a slider hands out floats.
		"sky_strike":
			ArcLightning.sky_strike = value
			return
		"strike_height":
			ArcLightning.strike_height = value
			return
		"strike_life":
			ArcLightning.strike_life = value
			return
		"arcs":
			ArcLightning.arcs = value
			return
		"bolt_lift":
			ArcLightning.bolt_lift = value
			return
		"bolt_life":
			ArcLightning.bolt_life = value
			return
		"strike_delay":
			ArcLightning.strike_delay = value
			return
		"arc_step_delay":
			ArcLightning.arc_step_delay = value
			return
		"bolt_segments":
			ArcLightning.bolt_segments = int(value)
			return
		"bolt_jag":
			ArcLightning.bolt_jag = value
			return
		"flicker_rate":
			ArcLightning.flicker_rate = value
			return
		"afterimage":
			ArcLightning.afterimage = value
			return
		"core_color":
			ArcLightning.core_color = value
			return
		"bolt_width":
			ArcLightning.bolt_width = value
			return
		"corona_scale":
			ArcLightning.corona_scale = value
			return
		"core_intensity":
			ArcLightning.core_intensity = value
			return
		"corona_intensity":
			ArcLightning.corona_intensity = value
			return
		"bolt_softness":
			ArcLightning.bolt_softness = value
			return
		"flash":
			ArcLightning.flash = value
			return
		"flash_peak":
			ArcLightning.flash_peak = value
			return
		"flash_life":
			ArcLightning.flash_life = value
			return
		"spark_lift":
			ArcLightning.spark_lift = value
			return
		"crawl":
			ArcLightning.crawl = value
			return
		"crawl_life":
			ArcLightning.crawl_life = value
			return
		"crawl_strength":
			ArcLightning.crawl_strength = value
			return
		# The sparks. Every arm RE-APPLIES, because the emission buffer `sparks_per_victim` sizes
		# and the material's own fields are node state rather than values a burst reads as it goes
		# -- the slam dust's rule, and one sweep for all ten beats ten that have to agree about
		# which of them needs it.
		"sparks":
			ShockSparks.sparks = value
			_reapply_sparks(host)
			return
		"sparks_per_victim":
			ShockSparks.sparks_per_victim = int(value)
			_reapply_sparks(host)
			return
		"spark_speed":
			ShockSparks.spark_speed = value
			_reapply_sparks(host)
			return
		"spark_spread":
			ShockSparks.spark_spread = value
			_reapply_sparks(host)
			return
		"spark_upward":
			ShockSparks.spark_upward = value
			_reapply_sparks(host)
			return
		"spark_lifetime":
			ShockSparks.spark_lifetime = value
			_reapply_sparks(host)
			return
		"spark_size":
			ShockSparks.spark_size = value
			_reapply_sparks(host)
			return
		"spark_color":
			ShockSparks.spark_color = value
			_reapply_sparks(host)
			return
		"spark_gravity":
			ShockSparks.spark_gravity = value
			_reapply_sparks(host)
			return
		"spark_drag":
			ShockSparks.spark_drag = value
			_reapply_sparks(host)
			return
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
		"CLIFF_FOLLOW_MAX":
			Pacing.CLIFF_FOLLOW_MAX = value
		"CLIFF_RECOVER":
			Pacing.CLIFF_RECOVER = value
		"PLUMMET_HOLD":
			Pacing.PLUMMET_HOLD = value
		"STAGE_AIM_LIFT":
			Pacing.STAGE_AIM_LIFT = value
		"TRAINED_DISTANCE":
			Pacing.TRAINED_DISTANCE = value
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
		"CENTRE_SPRITE_LIFT":
			ActionMenuController.CENTRE_SPRITE_LIFT = value
			return
		"CENTRE_NAME_BASELINE":
			ActionMenuController.CENTRE_NAME_BASELINE = value
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
		# Needs NO re-apply, unlike the clock below: the director lerps toward its target every frame
		# and reads this value each time, so a drag mid-swap is honoured on the next frame by itself.
		"CROSSFADE_SECONDS":
			MusicDirector.CROSSFADE_SECONDS = value
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
		# The queue's rows read the palette when they are BUILT, so a dragged colour needs them
		# rebuilt -- and through the panel's own UI-only re-render, never game.refresh_action_queue,
		# which re-resolves the whole plan and would do so once per slider tick.
		"ELEMENT_FIRE":
			ElementPalette.ELEMENT_FIRE = value
			_restyle_action_queue(host)
			return
		"ELEMENT_WATER":
			ElementPalette.ELEMENT_WATER = value
			_restyle_action_queue(host)
			return
		"ELEMENT_SHOCK":
			ElementPalette.ELEMENT_SHOCK = value
			_restyle_action_queue(host)
			return
		"ELEMENT_ICE":
			ElementPalette.ELEMENT_ICE = value
			_restyle_action_queue(host)
			return
		"ELEMENT_EARTH":
			ElementPalette.ELEMENT_EARTH = value
			_restyle_action_queue(host)
			return
		"ELEMENT_AIR":
			ElementPalette.ELEMENT_AIR = value
			_restyle_action_queue(host)
			return
		"ELEMENT_AETHER":
			ElementPalette.ELEMENT_AETHER = value
			_restyle_action_queue(host)
			return
		"ELEMENT_CORROSION":
			ElementPalette.ELEMENT_CORROSION = value
			_restyle_action_queue(host)
			return
		"EVENT_TINT":
			QueueStyle.EVENT_TINT = value
			_restyle_action_queue(host)
			return
		"PARCHMENT_INK_DEPTH":
			QueueStyle.PARCHMENT_INK_DEPTH = value
			_restyle_action_queue(host)
			return
		"PARCHMENT_INK_SATURATION":
			QueueStyle.PARCHMENT_INK_SATURATION = value
			_restyle_action_queue(host)
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
		# Re-showing the standing trace is the re-apply: it repaints the flat line and bumps the
		# version the mirror gates on, which is exactly what a fresh hover does (#506).
		"CLEAR_COLOR", "BLOCKED_COLOR": manager.restyle_sight_trace()
		# The range readout's three (#710, #1066): the two fills re-tint their 2D layer, which the
		# mirror copies; the lines re-show the standing set, the sight trace's own re-apply. Nothing
		# is derived from either tone any more -- slice 4's dim twins went with the tier they served.
		"REACH_MODULATE": manager.restyle_reach()
		"THREAT_MODULATE": manager.restyle_threat()
		"FOCUS_OUTLINE_COLOR": manager.restyle_focus_outline()
		"ZONE_HIGHLIGHT_MODULATE": manager.restyle_leash()
		"MARK_LINE_COLOR", "MARK_HEIGHT", "MARK_BOW_PER_CELL", "MARK_INSET", "CONE_LENGTH", "CONE_WIDTH_SCALE":
			manager.restyle_reach_lines()
		# No bespoke sweep for the three planned-move tints: redraw_planned_paths already tears
		# every arrow down and rebuilds it through _arrow_modulate, so it IS the re-apply.
		"MOVE_ARROW_MODULATE", "INVALID_ARROW_MODULATE", "TRAILING_ARROW_MODULATE":
			manager.redraw_planned_paths()
		_: manager.refresh_aim_colors()


# Split out of write_static's match so the squad-line arm can list its names once. DASHES_PER_TILE is
# a COUNT and the slider hands over a float; the cast is what keeps the static an int, and so what
# Save writes back as one.
static func _write_squad_line(name: String, value: Variant) -> void:
	match name:
		"TETHER_COLOR": SquadLines2D.TETHER_COLOR = value
		"TETHER_GHOST_COLOR": SquadLines2D.TETHER_GHOST_COLOR = value
		"TETHER_STRAIN_COLOR": SquadLines2D.TETHER_STRAIN_COLOR = value
		"DASHES_PER_TILE": SquadLines2D.DASHES_PER_TILE = int(value)
		"DASH_FILL": SquadLines2D.DASH_FILL = value
		"DASH_SPEED": SquadLines2D.DASH_SPEED = value
		"TETHER_INSET": SquadLines2D.TETHER_INSET = value
		"SHAKE_AMPLITUDE": SquadLines2D.SHAKE_AMPLITUDE = value
		"SHAKE_SECONDS": SquadLines2D.SHAKE_SECONDS = value
		"SHAKE_SWINGS": SquadLines2D.SHAKE_SWINGS = value


# The squad lines' re-apply (#1070): the diorama's beam params and the store's derived tethers, the
# two halves #1074's grid taught -- missing either is a slider that moves one view only.
static func _restyle_squad_lines(host: Node3D) -> void:
	var overlays := overlays_of(host)
	if overlays != null:
		overlays.restyle_squad_lines()
	var manager := overlay_manager_of(host)
	if manager != null:
		manager.restyle_squad_lines()


# The movement grid's re-apply (#1074): BOTH views, because MoveGrid is one rule each of them
# rasterizes into a texture of its own. Missing either half is a slider that moves one view only.
static func _restyle_move_grid(host: Node3D) -> void:
	var overlays := overlays_of(host)
	if overlays != null:
		overlays.restyle_grid()
	var manager := overlay_manager_of(host)
	if manager != null:
		manager.restyle_move_grid()


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
# The action queue's re-apply (#685). Deliberately NOT game.refresh_action_queue, which is the
# mission-status precedent's shape: that door re-RESOLVES the plan, and an element colour is a UI
# fact the panel can repaint from its own cached entries.
static func _restyle_pin_flashes(host: Node3D) -> void:
	if host == null:
		return
	var game_2d: Node2D = host.game
	if game_2d != null:
		game_2d.restyle_pin_flashes()


static func _restyle_action_queue(host: Node3D) -> void:
	if host == null:
		return
	var game_2d: Node2D = host.game
	if game_2d == null:
		return
	var panel: SquadActionQueueControl = game_2d.squad_action_queue_control
	if panel != null:
		panel.restyle()


static func _refresh_guard_markers(host: Node3D) -> void:
	if host == null:
		return
	var game_2d: Node2D = host.game
	if game_2d == null:
		return
	game_2d.refresh_guard_markers()


# The slam dust's re-apply (#656). Its node is built in code by battle3d rather than authored into
# the scene, so it is reached the way every effect node here is -- through the host, by type, with a
# null answer meaning "no 3D host attached" rather than an error.
# The sparks live one node DOWN from the host -- ArcLightning owns them, because they fire on the
# current's own schedule and that schedule is the effect's. So this walks two levels rather than
# one, which is the whole difference from the dust's own sweep beside it.
#
# SINCE #900 IT GOES THROUGH THE ARC rather than reaching the emitter itself: the effect holds the
# look the last strike adopted, and a re-apply that pushed the bare statics would silently strip an
# authored look the moment any spark knob was dragged.
static func _reapply_sparks(host: Node3D) -> void:
	if host == null:
		return
	for child in host.get_children():
		var arc := child as ArcLightning
		if arc != null:
			arc.reapply_sparks()
			return


static func _reapply_staging_dust(host: Node3D) -> void:
	if host == null:
		return
	for child in host.get_children():
		var dust := child as StagingDust
		if dust != null:
			dust.apply()
			return


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
		if knob.has("setting"):
			# The live preference becomes the SHIPPED DEFAULT. Unlike the two kinds below, what is
			# written is not where the value was read from -- the store keeps owning the live one.
			#
			# WATCH THE LITERAL WHEN A CHOICE ROW JOINS. literal_for spells a bool as true/false,
			# which is what a DEFS default already looks like; an int would replace
			# `AimPalette.DEFAULT` with a bare `0` -- correct, lossy, and every test here would still
			# pass. A choice row wants its enum spelling written: a branch to add, not a default to
			# inherit.
			var setting_name: String = PlayerSettings.Setting.keys()[knob["setting"]]
			edits.append(KnobSource.edit(SETTINGS_SCRIPT, KnobSource.Kind.SETTING_DEFAULT,
				setting_name, literal, knob["label"], i, CLASS_SOURCE))
			continue
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


# The full tip for a row whose Save writes an authored DECLARATION -- the which-stack note above,
# plus the line saying what moving it costs. It lives here rather than on the Game tab because that
# tab stopped being its only reader in #902: ObjectKnobs.GLOBALS rows are drawn on the Tiles page and
# saved exactly the same way, and a second copy of the sentence would drift the first time either was
# reworded. The BUTTON is the parameter because only that differs between the two pages.
#
# A SETTING row is the exception and gets no game-wide line at all: it is not one value for every
# board, it is one value per PLAYER, and tip_for has already said so.
static func declaration_tip(knob: Dictionary, save_label := "Save to source") -> String:
	if knob.has("setting"):
		return tip_for(knob)
	return tip_for(knob) + "\n\n" + DevWidgets.wrap_tooltip(
		"GAME-WIDE -- one value for every board. %s writes it into the declaration that authors it; no mission can carry its own." % save_label)


# The which-stack note is appended per KIND rather than typed into each tip, so it cannot drift out
# of step with the table it describes.
static func tip_for(knob: Dictionary) -> String:
	var tip: String = knob.get("tip", "")
	if knob.has("layer"):
		tip += "\n\n3D ONLY -- the flat 2D board keeps its own colour. A declared divergence, and provisional: tune it, look at it, then decide whether 2D should follow."
	elif knob.has("static"):
		tip += "\n\nMOVES BOTH STACKS -- this is one value both the 2D and the 3D read, so the flat game changes with it."
	elif knob.has("setting"):
		tip += "\n\nTHE REAL PLAYER SETTING, not a preview -- the same one the pause menu's Settings page shows, so flipping it here changes your own preference. Save writes what a player who never opens that page gets."
	return DevWidgets.wrap_tooltip(tip)
