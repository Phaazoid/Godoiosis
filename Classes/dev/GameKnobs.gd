extends Object
class_name GameKnobs

# WHAT the game's own presentation constants are -- board markup, the unit readout, camera handling,
# dev chrome -- and how a tuned one is KEPT (#373). Static and pure; ObjectKnobs' twin, one shelf
# along, and LookKnobs' opposite number.
#
# The split it exists to make. A LookPreset is a mission's MOOD: one board may look unlike another,
# so a board names a preset and wears it. Everything here is the same in every mission forever --
# how high an icon floats, how thick a health bar is, how fast the camera pans -- so there is
# nothing for a board to carry, and every one of these rows was already excluded from presets. What
# they had no door to was PERSISTENCE: the Look tab's only "keep this" button writes a preset, which
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

	# The #325 rings. A float rather than a colour, and the reason this table is named for WHERE a
	# value lives rather than for what type it is: ring alpha is a static on OverlayManager, exactly
	# like the two reach colours above, and both stacks read it.
	{"group": "Squad markers", "label": "Ring opacity", "static": "SQUAD_RING_ALPHA",
		"min": 0.1, "max": 1.0, "step": 0.01,
		"tip": "Alpha of the per-squad membership rings under each member (the leader's crown, over the head, stays opaque). Takes effect on markers already up."},
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
}

# Where the two class-level stores are declared. Named once, here, because the Save has to write
# these files and a second spelling of "which file holds LAYERS" would go stale the first time one
# moved. Both are checked by a law rather than trusted.
const OVERLAYS_SCRIPT := "res://Classes/presentation/BoardOverlays.gd"
const OVERLAY_MANAGER_SCRIPT := "res://Classes/board/OverlayManager.gd"

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
		"SQUAD_RING_ALPHA": return OverlayManager.SQUAD_RING_ALPHA
	push_error("GameKnobs: unknown static '%s'" % name)
	return null


# The static IS the authority; what is already drawn is re-derived from it in the same breath, or a
# tuned value would not show until the next aim or the next squad change. #324's lesson: a knob on
# something RECONCILED rather than redrawn moves nothing until someone re-applies it.
static func write_static(host: Node3D, name: String, value: Variant) -> void:
	match name:
		"ATTACK_MODULATE": OverlayManager.ATTACK_MODULATE = value
		"HEAL_ATTACK_MODULATE": OverlayManager.HEAL_ATTACK_MODULATE = value
		"SQUAD_RING_ALPHA": OverlayManager.SQUAD_RING_ALPHA = value
		_:
			push_error("GameKnobs: unknown static '%s'" % name)
			return
	var manager := overlay_manager_of(host)
	if manager == null:
		return
	match name:
		"SQUAD_RING_ALPHA": manager.restyle_squad_markers()
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
			edits.append(KnobSource.edit(OVERLAY_MANAGER_SCRIPT, KnobSource.Kind.DECLARATION,
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
