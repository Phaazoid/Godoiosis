extends Node
class_name OverlayManager

# All 2D board visuals: the tile-layer fills (move/attack/hover/squad/zones), path
# arrows, selection icons, projected-unit ghosts, knockback + terrain previews, and
# the target-pulse channel. Every draw is RETAINED — the layers hold their cells and
# the dicts below hold their sprites — which is what lets the 3D OverlayMirror poll
# full parity off this manager with zero trigger hooks (#222).

@onready var move_overlay = $MoveOverlay
@onready var attack_overlay = $AttackOverlay
@onready var hover_overlay = $HoverOverlay
@onready var squad_overlay = $SquadOverlay
@onready var icon_overlay = $IconOverlay
@onready var arrow_icon_overlay: Node2D = $ArrowIconOverlay
@onready var projected_unit_overlay: Node2D = $ProjectedUnitOverlay
@onready var squadrange_overlay = $SquadRangeOverlay
@onready var invalidmove_overlay = $InvalidMoveOverlay
@onready var board_tilemap = $"../Grid"
@onready var zone_overlay = $ZoneOverlay
@onready var capture_overlay = $CaptureOverlay
@onready var extraction_overlay = $ExtractionOverlay

const PATH_ERROR := preload("res://Art/Icons/ArrowIcons/ERROR.png")
const PATH_HORIZONTAL := preload("res://Art/Icons/ArrowIcons/horizontal.png")
const PATH_VERTICAL := preload("res://Art/Icons/ArrowIcons/vertical.png")

const PATH_UP_RIGHT := preload("res://Art/Icons/ArrowIcons/topright.png")
const PATH_UP_LEFT := preload("res://Art/Icons/ArrowIcons/topleft.png")
const PATH_DOWN_RIGHT := preload("res://Art/Icons/ArrowIcons/bottomright.png")
const PATH_DOWN_LEFT := preload("res://Art/Icons/ArrowIcons/bottomleft.png")

const PATH_START_RIGHT := preload("res://Art/Icons/ArrowIcons/startright.png")
const PATH_START_LEFT := preload("res://Art/Icons/ArrowIcons/startleft.png")
const PATH_START_UP := preload("res://Art/Icons/ArrowIcons/starttop.png")
const PATH_START_DOWN := preload("res://Art/Icons/ArrowIcons/startbottom.png")

const PATH_ARROW_RIGHT := preload("res://Art/Icons/ArrowIcons/endfromleft.png")
const PATH_ARROW_LEFT := preload("res://Art/Icons/ArrowIcons/endfromright.png")
const PATH_ARROW_UP := preload("res://Art/Icons/ArrowIcons/endfrombottom.png")
const PATH_ARROW_DOWN := preload("res://Art/Icons/ArrowIcons/endfromtop.png")

const TERRAIN_STATE_ICONS: Dictionary = {
	Terrain.TileState.BURNING: preload("res://Art/Icons/TerrainIcons/Fire.png"),
	Terrain.TileState.FROZEN: preload("res://Art/Icons/TerrainIcons/Ice.png"),
	Terrain.TileState.COVER: preload("res://Art/Icons/TerrainIcons/Cover.png"),
	Terrain.TileState.BLAZE: preload("res://Art/Icons/TerrainIcons/Fire.png"),   # #174: same art as BURNING -- permanence is the only difference
}

const TERRAIN_Z_INDEX := 1                                # above the board, below unit sprites — tweak by eye
const TERRAIN_PREVIEW_MODULATE := Color(1, 1, 1, 0.5)     # ghost the pending-ignite marker (Part B)

const ICON_SCENE = preload("res://Scenes/OverlayIcon.tscn")
const SOURCE_ID = 0
# The overlay tileset's atlas coordinates, and the single home for them: game.gd used to keep a
# duplicate `OVERLAY_DEFAULT_ATLAS = Vector2i(0,0)` plus five more that were never referenced.
const ATLAS_COORDS = Vector2i(0,0)          # plain fill — what every overlay layer draws with
# (1,0) is the marker tile on the AttackOverlay's sheet — #316: this read (3,0) since before the
# reorg, a coord the one-tile sheet never had, so the highlight drew in NEITHER view.
const TARGET_ATLAS_COORDS = Vector2i(1, 0)  # the "pick this unit" marker (PICKING_TARGET)
# (2,0): the hatched fill for a reach cell a point aim can never legally target — in range but past
# the attack's vertical tolerance (#258). Same layer, same modulate (so the heal-green fork follows
# for free); distinctness is the tile art, the TARGET_ATLAS_COORDS precedent for per-cell states.
const BLOCKED_ATLAS_COORDS = Vector2i(2, 0)

const PROJECTED_MODULATE := Color(0.7, 0.9, 1, 0.75)        # the planning-ghost tint
const PROJECTED_HIGHLIGHT := Color(1.4, 1.4, 1.0, 1.0)      # brightened + opaque on hover
const HOVER_MODULATE := Color(1, 1, 0)                  # the aim-footprint fill
const HOVER_PULSE_MODULATE := Color(1, 1, 0, 0.3)       # its pulsed low point

# The reach layer's fill (#123 follow-up): red reads as hostile, so a healing pick paints green
# instead. Decided from the attack's own `heals` flag -- the one question, one answer this already
# is (resolution-pipeline.md) -- not a new axis. Only the constant reach fill is heal-aware; the
# MAP-footprint hover-pulse channel below is untouched since no heal in the game targets MAP yet.
# static var, not const, so the Moods tab can tune them live (#212 slice 2). attack_reach_color is
# itself static and reads them, so this is the only form that works. Unlike the 3D-only layer
# colours, tuning these moves BOTH stacks -- the 3D mirrors this modulate rather than holding an
# answer of its own, so there is no 3D-only value here to tune (dev call: acceptable).
static var ATTACK_MODULATE := Color(1, 0, 0, .5)
static var HEAL_ATTACK_MODULATE := Color(0, 1, 0, .5)
# How much darker a vertically-BLOCKED reach cell (#258) draws than the reach fill. The 2D says
# "blocked" with the hatched tile under the same modulate; the 3D has no per-cell art, so its
# ATTACK_BLOCKED layer derives its colour as the live reach modulate scaled by this. One factor,
# never a second colour -- deriving keeps the heal-green fork and any tuned reach colour for free.
static var BLOCKED_REACH_DIM := 0.45

# The tile pick FLASHES its candidates (#116, dev 2026-08-26: "I would like all of the valid tiles to
# flash"). Alpha rather than hue, so a pick that borrows the reach layer keeps whatever colour that
# layer is wearing and only breathes; and a PERIOD rather than a rate, matching Pulse's own unit.
static var PICK_FLASH_ALPHA := 0.9
static var PICK_FLASH_PERIOD := 0.45
# The two authoring-zone tints. Named because the 3D mirrors them (#231) and the parallel
# stacks' rule is that a mirrored color is COPIED from here, never restated — a literal on
# each side is two answers to "what colour is a patrol zone".
const ZONE_PATROL_MODULATE := Color(1, 0.5, 0, 0.35)
const ZONE_HIGHLIGHT_MODULATE := Color(1, 1, 1, 0.45)


enum OverlayType {
	MOVE,
	ATTACK,
	HOVER,
	SQUAD,
	ARROW,
	SQUADRANGE,
	INVALIDMOVE
}

# The ONE answer to what each marker type looks like, applied once by create_unit_icon's setup --
# so _style_icon below never touches a texture, and there is no second place a marker's art can come
# from. Membership is a per-squad ring underfoot, leadership the crown over the head (#325, settled
# 2026-08-19); the legacy green square lost, and SquadHighlightIcon.png is now unreferenced.
const ICON_TEXTURES = {
	OverlayIcon.IconType.CROWN: preload("res://Art/Icons/BoardIcons/CrownIcon.png"),
	OverlayIcon.IconType.SQUADMEMBER: preload("res://Art/Icons/BoardIcons/SquadRingIcon.png"),
	# ProjectUtumno_full row 38 col 35 (dev pick, 2026-08-21), downscaled 32 -> 16.
	#
	# 16px is not a style choice, it is the CELL SIZE: BoardOverlays sizes a 3D ground quad as
	# texture pixels / ART_PIXELS_PER_CELL (16), so 32px art is a FOUR-CELL decal sprawling over its
	# neighbours -- which is exactly how this shipped once and read as "the marker isn't showing up".
	# Pinned by test_every_board_icon_is_authored_at_one_cell.
	#
	# LANCZOS here where the queue-row icon uses NEAREST, and the difference is the ART, not a rule:
	# that one's features are 2px+ and survive pixel-dropping, this one's are 1px planks that only a
	# smooth filter keeps legible. Look at the result before picking either.
	OverlayIcon.IconType.GUARD_WARD: preload("res://Art/Icons/BoardIcons/GuardWardIcon.png")
}

# The armed-Guard pair's ground mark (#414). Neutral by default now the art is real -- these stay as
# the tuning knobs for how loud the mark is, not as a way of faking a distinct sprite.
static var GUARD_RING_COLOR := Color.WHITE
# NO Game-tab row, deliberately, where GUARD_RING_COLOR has one (#450): OverlayMirror._marker copies
# a marker's texture and tint and NOT its scale, and 3D sizes a ground quad from its texture's own
# pixels, so this moves the flat board and leaves the one the game boots into alone. A knob that
# lies is worse than a missing one -- give the mirror a scale before giving this a slider.
static var GUARD_RING_SCALE := 1.0
# The blocker->ward arrow (#450). WHITE on purpose: the shared arrow art is desaturated, so the
# tint IS the colour (the three planned-move knobs' own reasoning) and starting neutral leaves the
# Game tab's picker its full range rather than multiplying against a baked-in hue.
static var GUARD_LINK_MODULATE := Color.WHITE
# How far back from the ward's cell CENTRE the link's arrowhead sits, in cells (#450 round 2, dev
# found it in play: "the shield just isn't as readable as I'd like it to be under the arrowhead").
#
# Measured rather than guessed. The arrowhead tile's ink runs x=0..11 of 16 with the chevron tip at
# 11, and GuardWardIcon's runs x=1..13 -- so drawn on the ward's own cell the arrow covers ELEVEN of
# the shield's thirteen columns. At half a cell that is three, and they are the shield's thinnest.
# 0.5 is the geometric rule (the head stops at the edge the pair shares) rather than an art-derived
# number; ~0.7 clears the shield entirely, which is what the range above 0.5 is for.
static var GUARD_LINK_HEAD_INSET := 0.5

# --- Squad markers (#325, settled 2026-08-19) ----------------------------------------------
# The dev played both styles and took a MIX: membership is a per-squad coloured RING underfoot,
# leadership is the ORIGINAL crown over the head. The legacy green squares lost and are deleted --
# no toggle, no second style. SQUAD_RING_ALPHA stays a live Look-tab value; it tunes a shipped
# feature rather than picking between two.
static var SQUAD_RING_ALPHA := 0.9
# How much brighter a ring goes at the top of its "you may click this" pulse (#442). A GAIN on the
# ring's own hue rather than a second colour, so a pulsing ring stays recognisably its squad's --
# the pulse says LOOK HERE, the hue still says WHICH SQUAD.
static var SQUAD_RING_PULSE_GAIN := 1.8

# --- Arrow tints (2026-08-21) --------------------------------------------------------------
# The trail ART is GREYSCALE, so every colour below is exactly what the board shows. It was cyan
# until now, and modulate MULTIPLIES: dialling yellow zeroed the blue channel and drew green, and
# a "white" planned move had always rendered cyan. Desaturating the 14 segments is what makes these
# four values mean what they say. (ERROR.png keeps its red -- GridUtils.ERROR_ICON draws it
# untinted as the unknown-terrain marker.)
#
# A shove and a planned move are opposite kinds of fact -- one is what a unit CHOSE, the other is
# what is about to be done to it -- and they drew identically until now.
static var KNOCKBACK_MODULATE := Color(1.0, 1.0, 0.0, 0.9)
# Pre-tuned to the art's own brightest pixel (136,248,248), so a planned move looks exactly as it
# did before the desaturation rather than turning white by accident (dev, 2026-08-21).
static var MOVE_ARROW_MODULATE := Color(0.4118, 1.0, 1.0, 1.0)
# These two keep the numbers they always had, so both now read BRIGHTER than before -- the cyan art
# used to multiply them down. Knobs, not guesses: tune against the shove colour on the Game tab.
static var INVALID_ARROW_MODULATE := Color(1, 0.25, 0.25, 0.85)
static var TRAILING_ARROW_MODULATE := Color(0.4, 1, 0.45, 0.9)
# Per-squad hues, dealt lazily by SquadManager when a squad first gains a squadmate: cool for
# friendly squads, warm for enemy ones, so "which squad" and "whose side" read from one glance.
# Plain consts, one per line -- edit freely; WHITE is reserved as the not-yet-dealt sentinel.
const SQUAD_HUES_FRIENDLY: Array[Color] = [
	Color(0.3, 0.6, 1.0),    # blue
	Color(0.2, 0.9, 0.8),    # teal
	Color(0.65, 0.5, 1.0),   # violet
	Color(0.35, 0.9, 0.5),   # green
	Color(0.6, 0.85, 1.0),   # sky
	Color(0.3, 0.4, 0.95),   # indigo
]
const SQUAD_HUES_ENEMY: Array[Color] = [
	Color(1.0, 0.35, 0.3),   # red
	Color(1.0, 0.65, 0.2),   # orange
	Color(1.0, 0.4, 0.75),   # magenta
	Color(1.0, 0.85, 0.3),   # amber
	Color(0.8, 0.2, 0.45),   # wine
	Color(1.0, 0.95, 0.5),   # yellow
]
const RING_Z_INDEX := 2       # underfoot: above terrain state (1), below arrows (3) and units (4)
const HEAD_ICON_Z_INDEX := 8  # the legacy squares' z; code re-asserts it so the toggle round-trips

var overlay_map = {}
var icons_by_unit := {} # { Unit : { IconType : OverlayIcon } }

# Puts the STANDING markers back after this manager clears the channel whole, injected by game (the
# squad_manager.board_source idiom). A Callable that DRAWS rather than one that returns a squad
# list, so "what does the standing set look like" has exactly one implementation instead of one
# here and one in game. Does nothing while ALWAYS_SHOW_SQUAD_RINGS is off.
var standing_rings_drawer: Callable = func() -> void: pass
var planned_move_by_unit := {} #{Unit : MoveAction}
var terrain_live_sprites: Array[Sprite2D] = []       # live terrain icons (persist across selection)
var terrain_preview_sprites: Array[Sprite2D] = []    # ephemeral plan-time ghosts (Part B)
# The blocker->ward arrows of every armed Guard (#450). Owned and cleared by redraw_guard_wards
# alongside the ward shields, because the two are one marker with two halves -- see it there.
var guard_link_sprites: Array[Sprite2D] = []
# The same pair GHOSTED, for a Guard that is only QUEUED (#450 part 2). Two stores rather than one
# because the halves reach 3D through different mirror branches, exactly as the armed pair does --
# and separate from the armed stores because the LIFETIMES differ: these are plan-time and die with
# the next re-plan, while an armed ward outlives the whole enemy phase.
var guard_preview_icons: Array[Sprite2D] = []
var guard_preview_links: Array[Sprite2D] = []
var hover_move_preview: MoveAction = null
var hover_move_previews: Array[MoveAction] = []
var projected_unit_sprites := {} # { Unit : Sprite2D }
var knockback_preview_sprites: Array[Node2D] = []
# The knockback ghosts, keyed so "which sprite stands for this unit?" has an answer for them too.
# A DECLARED second store rather than an entry in projected_unit_sprites: the two have different
# lifetimes (a move ghost dies with clear_projected_unit, a shove's with clear_knockback_preview),
# so they stay apart and _ghost_for is the one place that answers across both.
var knockback_ghost_by_unit := {} # { Unit : Sprite2D }
# ZoneManager.Kind -> the TileMapLayer that draws it. A layer per kind rather than a method per
# kind: colour is `modulate`, which is per-LAYER, so a kind that needs its own colour needs its
# own layer. Adding a kind is one line here.
var zone_layer_map := {}
var zone_highlight_overlay: TileMapLayer = null   # the Tile Brush's picked zone; built in _ready
# The two inputs to whether authoring zones draw -- see set_zone_visibility. The INTENT is what
# a 3D mirror asks; `.visible` is the product and answers only "does the 2D draw this".
var zones_authoring_visible := false
var board_rendering := true
# Knockback preview (#84): a ghosted arrow (target cell -> landing cell) plus a planning-ghost of
# the shoved unit where it lands. Same "resolve the plan, show it pending" rail as the terrain
# preview; its own sprite list so a plan change clears and redraws it cleanly.
var knockback_hidden_units: Array[Unit] = []   # shoved units whose real sprite we hid behind a ghost
var _pulsing_units: Array[Unit] = []

# Which units currently wear a PULSING ring (#442). Separate from _pulsing_units above: that one is
# the aim's "about to be hit" channel on the unit SPRITE, this one is the ground ring saying "you
# may click this". Different channel, different meaning, deliberately not merged.
var _pulsing_rings: Array[Unit] = []
var _tile_pulse: Tween = null
var _pick_flash: Tween = null
var _pick_flash_base: Color = ATTACK_MODULATE   # replaced by the live value when a flash starts
# What the reach fill was last painted for, so refresh_attack_reach_color can re-derive it.
var _reach_attack: AttackData = null

# The hovered aim's sight trace (#258): computed ONCE by HoverPresenter via Reach.sight_trace and
# stored here as DATA -- SightTrace2D draws it flat, OverlayMirror lifts the same points into the
# diorama. `sight_trace_version` is the monotonic, non-consuming change signal the mirror gates on
# (the #308 rule: never a copied key).
var sight_trace: Reach.SightTrace = null
var sight_trace_version := 0
var _sight_trace_2d: SightTrace2D



# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	overlay_map = {
		OverlayType.MOVE: move_overlay,
		OverlayType.ATTACK: attack_overlay,
		OverlayType.HOVER: hover_overlay,
		OverlayType.SQUAD: squad_overlay,
		OverlayType.ARROW: arrow_icon_overlay,
		OverlayType.SQUADRANGE: squadrange_overlay,
		OverlayType.INVALIDMOVE: invalidmove_overlay
	}
	
	move_overlay.modulate = Color(1, 1, 0, .5)
	attack_overlay.modulate = ATTACK_MODULATE
	hover_overlay.modulate = HOVER_MODULATE
	squad_overlay.modulate = Color(1, 0.5, 0, 0.5)
	squadrange_overlay.modulate = Color(1, 0.5, 0, 0.5)
	invalidmove_overlay.modulate = Color(0.5, 0.36, 0.4, .5)
	zone_overlay.modulate = ZONE_PATROL_MODULATE
	zone_overlay.visible = false   # authoring-only visual; DevOverlay shows it with the Tile Brush tab
	capture_overlay.modulate = Color(0.3, 0.9, 1, 0.5)
	extraction_overlay.modulate = Color(0.4, 1, 0.5, 0.5)
	# PATROL is an authoring aid (DevOverlay shows it with the Tile Brush tab); CAPTURE is live
	# objective information and stays visible for the whole battle.
	zone_layer_map = {
		ZoneManager.Kind.PATROL: zone_overlay,
		ZoneManager.Kind.CAPTURE: capture_overlay,
		ZoneManager.Kind.EXTRACTION: extraction_overlay,
	}
	# The Tile Brush's picked-zone highlight: a white lift drawn over the kind layers so the picked
	# zone reads against its neighbours. Code-built as a duplicate of zone_overlay (same tileset and
	# transform, no .tscn edit) and appended LAST, so tree order draws it above every zone layer.
	# Authoring-only like PATROL -- set_zone_visibility owns both. Headless Play boards
	# (play/board_builder) supply the overlays as bare Node2Ds: no layer to duplicate, no brush to
	# serve -- the highlight stays null there and redraw_zone_highlight tolerates it.
	if zone_overlay is TileMapLayer:
		zone_highlight_overlay = zone_overlay.duplicate() as TileMapLayer
		zone_highlight_overlay.name = "ZoneHighlightOverlay"
		zone_highlight_overlay.modulate = ZONE_HIGHLIGHT_MODULATE
		zone_highlight_overlay.visible = false
		add_child(zone_highlight_overlay)
	# The bead-path renderer (#258). Code-built (no .tscn edit), above the tile overlays and below
	# unit sprites, the standing rule for board markup.
	_sight_trace_2d = SightTrace2D.new()
	_sight_trace_2d.name = "SightTrace2D"
	_sight_trace_2d.z_index = TERRAIN_Z_INDEX
	add_child(_sight_trace_2d)


func show_sight_trace(trace: Reach.SightTrace) -> void:
	sight_trace = trace
	sight_trace_version += 1
	_sight_trace_2d.trace = trace
	_sight_trace_2d.queue_redraw()


func clear_sight_trace() -> void:
	if sight_trace == null:
		return   # idempotent -- exit paths spam this; the version only moves on real change
	sight_trace = null
	sight_trace_version += 1
	_sight_trace_2d.trace = null
	_sight_trace_2d.queue_redraw()

# What color the reach layer should paint with for this attack -- red for damage, green for a
# heal. A null attack (bare fists) reads as the default/damage color.
static func attack_reach_color(attack: AttackData) -> Color:
	return HEAL_ATTACK_MODULATE if attack != null and attack.heals else ATTACK_MODULATE

func set_attack_reach_color(attack: AttackData) -> void:
	_reach_attack = attack
	attack_overlay.modulate = attack_reach_color(attack)


# Re-derive the reach fill from the attack it was last given. The Moods tab calls this after tuning
# ATTACK_MODULATE: the 3D mirrors `attack_overlay.modulate` every frame rather than the constant,
# so without this a tuned colour would not show until the player next entered targeting.
func refresh_attack_reach_color() -> void:
	set_attack_reach_color(_reach_attack)

# The one door for the attack-reach draw (#258). Membership = the full union, drawn once on
# entering the mode (the inviolable rule); `blocked` cells re-tile to the hatched fill in the same
# pass, so a cell the aim gate would refuse says so up front. Never called during aiming.
func show_attack_reach(cells: Array[Vector2i], blocked: Array[Vector2i]) -> void:
	show_overlay(OverlayType.ATTACK, cells, ATLAS_COORDS)
	draw_cells(attack_overlay, blocked, BLOCKED_ATLAS_COORDS)

func show_overlay(type: int, cells: Array, atlas_coord: Vector2i):
	var layer = overlay_map[type]
	layer.clear()
	draw_cells(layer, cells, atlas_coord)

	# Move overlay always wins tiles it shares with squad tint (avoids alpha-stacked orange+yellow
	# bleed where a unit's move range overlaps its squad's leader range).
	if type == OverlayType.MOVE:
		for cell in cells:
			squad_overlay.erase_cell(cell)
			squadrange_overlay.erase_cell(cell)

# PATROL only -- capture zones are objective info, not an authoring overlay. The picked-zone
# highlight is authoring scaffolding too, so it follows the same switch.
#
# TWO inputs, one answer (#231). `.visible` on these layers used to BE the authoring intent,
# and that stopped being true once the 3D mirrored them: Battle3D hides the whole 2D board in
# the 3D view, so the same flag also had to mean "the 2D is rendering at all". Two writers,
# two meanings, one field -- #232's shape exactly. So the intent gets its own name, `.visible`
# becomes the computed render fact, and the 3D mirror reads the INTENT.
func set_zone_visibility(shown: bool) -> void:
	zones_authoring_visible = shown
	_apply_zone_visibility()


# Battle3D's half: whether the 2D board draws at all. Default true, so the flat game and every
# headless fixture are untouched -- only a 3D host ever calls this.
func set_board_rendering(shown: bool) -> void:
	board_rendering = shown
	_apply_zone_visibility()


func _apply_zone_visibility() -> void:
	var shown: bool = zones_authoring_visible and board_rendering
	zone_overlay.visible = shown
	if zone_highlight_overlay != null:
		zone_highlight_overlay.visible = shown

# The Tile Brush's picked zone, drawn as a lift over whatever kind layers hold the same cells.
# Empty = no pick (clears the layer).
func redraw_zone_highlight(cells: Array[Vector2i]) -> void:
	if zone_highlight_overlay == null:
		return
	zone_highlight_overlay.clear()
	draw_cells(zone_highlight_overlay, cells, ATLAS_COORDS)

# One method for every zone kind: each zone draws into the layer registered for its kind, and a
# kind with no layer simply isn't drawn. `hidden` drops zones that are done with (a captured
# point stops glowing) without needing a second redraw entry point.
func redraw_zones(zones: ZoneManager, hidden: Array[String] = []) -> void:
	for layer in zone_layer_map.values():
		layer.clear()
	for name in zones.zone_names():
		if hidden.has(name):
			continue
		var layer = zone_layer_map.get(zones.kind_of(name))
		if layer == null:
			continue
		draw_cells(layer, zones.cells_in(name), ATLAS_COORDS)

# The aim's live feedback: what the CURRENT aim would affect pulses, while the red reach layer never
# changes. WHICH channel pulses is the attack's own `targets` -- units, tiles or both -- so the kind
# of attack being aimed reads at a glance. Diffed against the previous set, not restarted: this runs
# on every hover change, and killing a tween per mouse-move strobes.
func set_target_pulse(units: Array[Unit], pulse_tiles: bool) -> void:
	for unit in _pulsing_units:
		if is_instance_valid(unit) and not units.has(unit):
			unit.visuals.stop_pulse()
	for unit in units:
		if is_instance_valid(unit) and not _pulsing_units.has(unit):
			unit.visuals.start_pulse()
	_pulsing_units = units.duplicate()

	if pulse_tiles and _tile_pulse == null:
		_tile_pulse = Pulse.start(self, hover_overlay, &"modulate", HOVER_MODULATE, HOVER_PULSE_MODULATE)
	elif not pulse_tiles and _tile_pulse != null:
		Pulse.stop(_tile_pulse, hover_overlay, &"modulate", HOVER_MODULATE)
		_tile_pulse = null

# Flash the cells a CELL pick is offering (#116). It pulses the pick layer's own modulate rather than
# adding a channel of its own: the 3D mirror reads that modulate every frame, so one tween moves both
# stacks -- the same reason set_attack_reach_color needs no 3D twin.
#
# The base is CAPTURED at start rather than read off ATTACK_MODULATE, and that is load-bearing: this
# layer's colour is DERIVED from the aimed attack (set_attack_reach_color forks heal-green), so
# restoring a constant would repaint the reach the next time targeting opened. Idempotent, because
# game.exit_current_mode clears every pulse unconditionally and a pick may end without one running.
func set_pick_flash(on: bool) -> void:
	if on == (_pick_flash != null):
		return
	if on:
		_pick_flash_base = attack_overlay.modulate
		var peak := Color(_pick_flash_base.r, _pick_flash_base.g, _pick_flash_base.b, PICK_FLASH_ALPHA)
		_pick_flash = Pulse.start(self, attack_overlay, &"modulate", _pick_flash_base, peak,
			PICK_FLASH_PERIOD)
	else:
		Pulse.stop(_pick_flash, attack_overlay, &"modulate", _pick_flash_base)
		_pick_flash = null

# The typed local is load-bearing: a bare [] literal passed to an Array[Unit] parameter fails at
# RUNTIME, not parse time (CLAUDE.md "Sharp edges").
func clear_target_pulse() -> void:
	var none: Array[Unit] = []
	set_target_pulse(none, false)

func show_hover_move_path(move: MoveAction):
	clear_hover_move_path()
	hover_move_preview = move
	draw_path_arrows(hover_move_preview)
	hover_move_preview.set_preview_z_index(MoveAction.HOVERED_ARROW_Z_INDEX)
	
func clear_hover_move_path():
	if hover_move_preview != null:
		hover_move_preview.clear_preview_sprites()
		hover_move_preview = null
	for m in hover_move_previews:
		m.clear_preview_sprites()
	hover_move_previews.clear()

# Plan-time preview of pending deposits (Law #2 — the board shows the ignite/entrenchment BEFORE
# you execute). Takes {"cell": Vector2i, "state": Terrain.TileState} entries (mirrors
# show_knockback_preview's shape) so each deposit draws its OWN icon — was BURNING-only until
# Burrow (#84) made a second previewable state real. Ephemeral: redrawn on plan change.
func show_terrain_preview(deposits: Array) -> void:
	clear_terrain_preview()
	for deposit in deposits:
		var state: Terrain.TileState = deposit["state"]
		if not TERRAIN_STATE_ICONS.has(state):
			continue
		var cell: Vector2i = deposit["cell"]
		var sprite := Sprite2D.new()
		sprite.texture = TERRAIN_STATE_ICONS[state]
		sprite.global_position = GridUtils.cell_world(board_tilemap, cell)
		sprite.z_index = TERRAIN_Z_INDEX
		sprite.modulate = TERRAIN_PREVIEW_MODULATE
		icon_overlay.add_child(sprite)
		terrain_preview_sprites.append(sprite)

func clear_terrain_preview() -> void:
	for sprite in terrain_preview_sprites:
		if is_instance_valid(sprite):
			sprite.queue_free()
	terrain_preview_sprites.clear()

# One entry per SHOVE ({"target", "path", "to", "removed"}), in resolve order. A unit can be shoved
# more than once in a plan (#105 — two maces, or a mace plus a counter), so this draws an arrow PER
# HIT but at most ONE ghost per target, at the cell the chain ends on. The trail draws the
# resolver's own `knockback_path` (#259) — a landing tumble can bend a shove once, so the old
# endpoints-plus-direction reconstruction can no longer describe it (and its `while cursor != to`
# was an infinite loop for any bent pair). A REMOVED target (shoved into a void) gets a trail and
# neither ghost nor hide: its sprite stays where it stands, matching the unpublished projection.
func show_knockback_preview(shoves: Array) -> void:
	clear_knockback_preview()

	var final_cell := {}   # Unit -> Vector2i; entries arrive in resolve order, so the last one wins
	var removed := {}      # Unit -> bool, same last-one-wins
	for shove in shoves:
		final_cell[shove["target"]] = shove["to"]
		removed[shove["target"]] = shove.get("removed", false)

	for shove in shoves:
		# The WHOLE trail, cell by cell, through the same texture pick a planned move uses (#126).
		var path: Array[Vector2i] = shove["path"]
		var landing: int = shove.get("landing_index", path.size() - 1)
		var trail := _draw_arrow_trail(path, KNOCKBACK_MODULATE)
		for i in trail.size():
			# The AIRBORNE geometry, riding each sprite for the 3D mirror (#259 rework) — the
			# flat canvas can't draw height, but the trail must not pretend the flight hugs the
			# ground: cells before the landing are flown at the launch cell's level, and the
			# landing cell is where the flight meets the world again.
			if i < landing:
				trail[i].set_meta("kb_air_from", path[0])
			elif i == landing:
				trail[i].set_meta("kb_drop_from", path[0])
				if shove.get("removed", false):
					trail[i].set_meta("kb_removed", true)
					# No flat arrowhead on a hole: the pointer alone says where it went. The
					# sprite keeps its meta so the 3D mirror still hangs the pointer off it.
					trail[i].texture = null
			# The 3D drop pointer's clothes and hanger (#431): every step past the first carries
			# the trail's own straight rail texture -- turned vertical, a rail has no cardinal
			# identity, so the EW cut serves every direction -- and the step INTO this cell, which
			# names the EDGE the mirror measures the two surfaces across. Every cell, not just the
			# landing: a tumble that bottoms out at a lip drops a second time, and only the edge
			# each cell was entered by can say so.
			if i > 0:
				trail[i].set_meta("kb_rail_texture",
						_get_path_segment_atlas(Vector2i.LEFT, Vector2i.RIGHT))
				trail[i].set_meta("kb_dir", path[i] - path[i - 1])
			knockback_preview_sprites.append(trail[i])

	# Hide each real sprite while its ghost stands in at the FINAL landing cell — the same pairing
	# redraw_projected_units uses for moves (set_projected hides, show_projected_unit draws).
	for target in final_cell:
		if removed.get(target, false):
			continue   # nothing stands in a hole — the trail and the KILL row say where it went
		var unit: Unit = target
		unit.visuals.set_projected(true)
		knockback_hidden_units.append(unit)
		var ghost := Sprite2D.new()
		ghost.texture = unit.get_move_texture()
		ghost.global_position = GridUtils.cell_world(board_tilemap, final_cell[target])
		ghost.z_index = Unit.BASE_SPRITE_INDEX
		ghost.modulate = PROJECTED_MODULATE
		ghost.offset = Vector2i(0, -8)
		projected_unit_overlay.add_child(ghost)
		knockback_preview_sprites.append(ghost)
		knockback_ghost_by_unit[unit] = ghost

func clear_knockback_preview() -> void:
	for unit in knockback_hidden_units:
		if is_instance_valid(unit):
			unit.visuals.set_projected(false)   # restore the real sprite
	knockback_hidden_units.clear()
	for sprite in knockback_preview_sprites:
		if is_instance_valid(sprite):
			sprite.queue_free()
	knockback_preview_sprites.clear()
	knockback_ghost_by_unit.clear()

# Re-tint a preview that is already up, so the Game-tab knob is not a slider that moves nothing
# until the next shove (#324's lesson). TRAIL sprites only -- the same parent test OverlayMirror
# forks on -- because the ghosts in that array wear PROJECTED_MODULATE and are not part of the
# trail. A sprite whose texture was nulled (a void removal) is re-tinted too: the 3D drop pointer
# copies its modulate, so it still carries the colour even with nothing to draw flat.
func restyle_knockback_trail() -> void:
	for node in knockback_preview_sprites:
		if not is_instance_valid(node):
			continue
		if node.get_parent() == arrow_icon_overlay:
			node.modulate = KNOCKBACK_MODULATE

func show_planned_path(unit: Unit, move: MoveAction):
	if planned_move_by_unit.has(unit):
		var old_move: MoveAction = planned_move_by_unit[unit]
		old_move.clear_preview_sprites()
		
	planned_move_by_unit[unit] = move
	redraw_planned_paths()

func clear_planned_path(unit: Unit):
	if planned_move_by_unit.has(unit):
		var move: MoveAction = planned_move_by_unit[unit]
		move.clear_preview_sprites()
	
	planned_move_by_unit.erase(unit)
	redraw_planned_paths()

# A move's markup -- its path ARROW and its destination GHOST -- ends at one moment, and this is it
# (#558). Two doors reach that moment: the move was CANCELLED (game._on_unit_action_cancelled) or it
# was CARRIED OUT (OrderExecutor, as each unit arrives). One lifetime with two routes in, rather than
# two markers whose clears drift apart -- which is what left a ghost sitting on top of its own unit
# for the rest of the squad's pass while the arrow went at the first step.
#
# planned_move_by_unit is the DURABLE half: both redraw_* rebuild from it, so freeing the sprites
# alone is undone by the next redraw.
func clear_move_markup(unit: Unit) -> void:
	clear_planned_path(unit)
	clear_projected_unit(unit)

func clear_all_planned_paths():
	clear_hover_move_path()
	
	for move: MoveAction in planned_move_by_unit.values():
		move.clear_preview_sprites()
	planned_move_by_unit.clear()

func redraw_planned_paths():
	for action: MoveAction in planned_move_by_unit.values():
		action.clear_preview_sprites()
		
	for action in planned_move_by_unit.values():
		draw_path_arrows(action)

func create_unit_icon(unit: Unit, type: OverlayIcon.IconType) -> OverlayIcon:
	if unit == null:
		return null
		
	if not icons_by_unit.has(unit):
		icons_by_unit[unit] = {}
		
	if icons_by_unit[unit].has(type):
		return icons_by_unit[unit][type]
		
	var icon := ICON_SCENE.instantiate()
	icon_overlay.add_child(icon)
	icon.setup(ICON_TEXTURES[type], unit, board_tilemap, type)
	icon.position = board_tilemap.map_to_local(icon.current_cell())
	_style_icon(icon, unit)

	icons_by_unit[unit][type] = icon
	return icon

# Presentation only: the TINT and Z a marker wears. Never the texture -- ICON_TEXTURES above is that
# one answer and setup applies it, so this cannot become a second place a marker's art comes from.
# What genuinely varies per UNIT is the squad hue, and only membership rings carry one; the crown
# keeps its authored gold over the head so it never fights the palette.
func _style_icon(icon: OverlayIcon, unit: Unit) -> void:
	# A live pulse OWNS modulate (#442), the same yield UnitVisuals.set_highlighted makes for the
	# target pulse. Z is not animated, so it is still safe to set.
	if icon.icon_type == OverlayIcon.IconType.SQUADMEMBER:
		icon.sprite.z_index = RING_Z_INDEX
		if not icon.is_pulsing():
			icon.sprite.modulate = _ring_base(unit)
	elif icon.icon_type == OverlayIcon.IconType.GUARD_WARD:
		icon.sprite.z_index = RING_Z_INDEX + 1   # underfoot with the squad ring, and above it
		icon.sprite.scale = Vector2.ONE * GUARD_RING_SCALE
		# Yields to a live pulse for #442's reason, even though nothing pulses this channel yet:
		# the rule is "a pulse owns modulate", and a branch that ignores it is the one that breaks
		# the day someone pulses a ward mark.
		if not icon.is_pulsing():
			icon.sprite.modulate = GUARD_RING_COLOR
	else:
		icon.sprite.z_index = HEAD_ICON_Z_INDEX
		if not icon.is_pulsing():
			icon.sprite.modulate = Color.WHITE

# What a ring RESTS at -- one expression, so the pulse's base, its restore-on-stop and the ordinary
# style all read the same answer.
func _ring_base(unit: Unit) -> Color:
	var hue: Color = unit.squad.ring_hue if unit.squad != null else Color.WHITE
	return Color(hue.r, hue.g, hue.b, SQUAD_RING_ALPHA)

# The rings that say "you may click this" (#442's join-squad flow). A SET rather than a per-unit
# call, and diffed rather than restarted, for the reason set_target_pulse is: restarting a live
# pulse every time the caller re-runs strobes it, and drops it out of phase with its neighbours.
func set_ring_pulse(units: Array[Unit]) -> void:
	for unit in _pulsing_rings:
		if is_instance_valid(unit) and not units.has(unit):
			_stop_ring_pulse(unit)
	for unit in units:
		if not is_instance_valid(unit):
			continue
		var icon := _ring_icon(unit)
		if icon != null:
			var base := _ring_base(unit)
			icon.start_pulse(Color(minf(base.r * SQUAD_RING_PULSE_GAIN, 1.0),
					minf(base.g * SQUAD_RING_PULSE_GAIN, 1.0),
					minf(base.b * SQUAD_RING_PULSE_GAIN, 1.0), 1.0))
	_pulsing_rings = units.duplicate()

# The typed local is load-bearing: a bare [] literal passed to an Array[Unit] parameter fails at
# RUNTIME, not parse time (CLAUDE.md "Sharp edges") -- clear_target_pulse's own note.
func clear_ring_pulse() -> void:
	var none: Array[Unit] = []
	set_ring_pulse(none)

func _stop_ring_pulse(unit: Unit) -> void:
	var icon := _ring_icon(unit)
	if icon != null:
		icon.stop_pulse(_ring_base(unit))

func _ring_icon(unit: Unit) -> OverlayIcon:
	if not icons_by_unit.has(unit):
		return null
	var icon := icons_by_unit[unit].get(OverlayIcon.IconType.SQUADMEMBER) as OverlayIcon
	return icon if is_instance_valid(icon) else null

# The Moods tab's ring-opacity slider restyles markers already on screen; walking the store here
# keeps the panel ignorant of icon lifecycle.
func restyle_squad_markers() -> void:
	for unit in icons_by_unit.keys().duplicate():
		if not is_instance_valid(unit):
			_purge_unit_entry(unit)
			continue
		for icon: OverlayIcon in icons_by_unit[unit].values():
			if is_instance_valid(icon):
				_style_icon(icon, unit)

func clear_unit_icon(unit: Unit, type: OverlayIcon.IconType):
	if not icons_by_unit.has(unit):
		return
		
	if not icons_by_unit[unit].has(type):
		return
		
	var icon: OverlayIcon = icons_by_unit[unit][type]
	if is_instance_valid(icon):
		icon.hide()
		icon.queue_free()
	
	icons_by_unit[unit].erase(type)
	if icons_by_unit[unit].is_empty():
		icons_by_unit.erase(unit)

func clear_unit_icons(unit: Unit):
	if not icons_by_unit.has(unit):
		return
		
	for type in icons_by_unit[unit].keys().duplicate():
		clear_unit_icon(unit, type)
	
func clear_unit_icon_types(types: Array[OverlayIcon.IconType]):
	for unit in icons_by_unit.keys().duplicate():
		if not is_instance_valid(unit):
			_purge_unit_entry(unit)
			continue
		for type in types:
			clear_unit_icon(unit, type)

# Every armed, unspent Guard on the board: a shield under the WARD, and an arrow from the blocker
# pointing at it (#450). #414 shipped the same shield at both ends, which said the pair was linked
# but never which way round -- and the direction was readable only off the queue row, i.e. exactly
# not during the enemy phase, when a standing reaction is the thing you need to read.
#
# One redraw owns both halves because they are one marker: same source (live ward state), same
# lifetime, so there is no moment either can be right while the other is stale. Its own redraw
# rather than a clause in redraw_squad_unit_icons: a Guard is not selection markup and must stay on
# screen through the enemy phase -- that is the whole point of a standing reaction being telegraphed.
# Called from the moments the state can move: a pass settling, a faction's turn starting, a board
# load, and a plan change (the arrows are static sprites where the shield is an OverlayIcon that
# re-reads its own cell every frame, so a queued move would walk one and leave the other behind).
# Both views get it free -- OverlayMirror routes every non-CROWN type to GROUND_ICONS.
#
# Deliberately NOT routed through #435's standing_rings_drawer, though the two are adjacent: that
# Callable exists because redraw_squad_unit_icons clears the CROWN/SQUADMEMBER channel WHOLE and has
# to put back squads other than the one being drawn. This channel is nobody else's to clear, and its
# contents are derived from live ward state rather than from a player setting. Two questions, and
# the day a third marker wants to stand is the day to generalise -- not before (Law #4 cuts both ways).
func redraw_guard_wards(units: Array[Unit]) -> void:
	clear_unit_icon_types([OverlayIcon.IconType.GUARD_WARD])
	_clear_guard_links()
	for unit in units:
		if not is_instance_valid(unit) or unit.guard == null:
			continue
		if unit.guard.spent or not unit.guard.is_intact():
			continue   # a used Guard protects nobody; drawing it would promise cover that is gone
		create_unit_icon(unit.guard.ward, OverlayIcon.IconType.GUARD_WARD)
		_draw_guard_link(unit, unit.guard.ward)

# The blocker's half of the mark: the shared path-arrow trail, one step long, aimed at the ward.
# The SAME arrows a move draws (dev call) rather than a bespoke connector -- the tail under the
# blocker is what says "this one is doing the covering", so the blocker needs no icon of its own.
#
# PROJECTED cells, the same expression OverlayIcon.current_cell() reads, so the shield and the arrow
# structurally cannot point at different cells (#308 -- derived, never copied).
#
# Drawn only across ONE ORTHOGONAL STEP, which is the arrow atlas's limit rather than a rule about
# Guard: _path_arrow_texture has no tile for a diagonal or a gap and falls to PATH_ERROR. Manhattan
# range 1 (Abilities.GUARD_BASE_RANGE) always satisfies it, but guard_range is authored per-content
# and a shove can already drag a live pair apart -- and a pair with no drawable link still keeps its
# shield, so nothing goes silent. A longer link needs an interpolated path or a drawn line; that is
# the day to build one, not before.
func _draw_guard_link(blocker: Unit, ward: Unit) -> void:
	guard_link_sprites.append_array(_guard_link_trail(blocker, ward, GUARD_LINK_MODULATE))

# The trail itself, shared by the armed pair and the queued ghost so the two can never disagree
# about where a link runs or when there is one to run.
func _guard_link_trail(blocker: Unit, ward: Unit, tint: Color) -> Array[Sprite2D]:
	var none: Array[Sprite2D] = []
	var from := blocker.get_projected_destination()
	var to := ward.get_projected_destination()
	if GridUtils.manhattan_distance(from, to) != 1:
		return none
	var trail := _draw_arrow_trail([from, to], tint)
	# The head STOPS SHORT, so the ward's cell is the shield's (#450 round 2). The trail is exactly
	# two sprites here -- a start tile on the blocker and the head on the ward -- and only the head
	# moves; the tail stays put, so the link still visibly crosses between the pair.
	#
	# A sub-cell position is honest in BOTH views, which is the whole reason this is available:
	# OverlayMirror._anchor_px keeps the sprite's true pixels through BoardSpace.of_pixels and snaps
	# only the cell it looks the surface tilt up by. Contrast SCALE and OFFSET, which _marker does
	# not carry at all -- nudging either would move the flat board and leave 3D behind (#414's art
	# fix, and the reason GUARD_RING_SCALE has no knob).
	if trail.size() == 2:
		var back := Vector2(from - to) * GridUtils.TILE_SIZE * GUARD_LINK_HEAD_INSET
		trail[1].global_position += back
	return trail

func _clear_guard_links() -> void:
	for sprite in guard_link_sprites:
		if is_instance_valid(sprite):
			sprite.queue_free()
	guard_link_sprites.clear()

# Plan-time preview of Guards that are QUEUED but not yet armed (#450 part 2). Every other queued
# verb previews -- a move gets arrows and a ghost, an ignite gets a ghosted icon -- and a Guard was
# the odd one out, visible only as a queue row until you pressed Execute.
#
# The SAME two marks the armed pair wears, at the ghost alpha the board already uses for "planned,
# not yet real" (TERRAIN_PREVIEW_MODULATE's). Drawing them identically would be the board telling
# the player they are covered when they are not yet, which is the question #450 left open; borrowing
# the existing alpha rather than inventing a second one is the rest of the answer.
#
# Takes {"blocker": Unit, "ward": Unit} entries, show_terrain_preview's shape -- the caller decides
# which Guards are still pending, since only a resolved plan knows.
func show_guard_preview(pairs: Array) -> void:
	clear_guard_preview()
	for pair in pairs:
		var blocker: Unit = pair["blocker"]
		var ward: Unit = pair["ward"]
		if not is_instance_valid(blocker) or not is_instance_valid(ward):
			continue
		var shield := Sprite2D.new()
		shield.texture = ICON_TEXTURES[OverlayIcon.IconType.GUARD_WARD]
		shield.global_position = GridUtils.cell_world(board_tilemap, ward.get_projected_destination())
		shield.z_index = RING_Z_INDEX + 1        # the armed shield's plane, so the two read as one mark
		shield.scale = Vector2.ONE * GUARD_RING_SCALE
		shield.modulate = _ghosted(GUARD_RING_COLOR)
		icon_overlay.add_child(shield)
		guard_preview_icons.append(shield)
		guard_preview_links.append_array(_guard_link_trail(blocker, ward, _ghosted(GUARD_LINK_MODULATE)))

func clear_guard_preview() -> void:
	for sprite in guard_preview_icons + guard_preview_links:
		if is_instance_valid(sprite):
			sprite.queue_free()
	guard_preview_icons.clear()
	guard_preview_links.clear()

# ONE answer to how ghosted a plan-time mark is, derived from the ignite preview's alpha rather than
# restated -- a second ghosting constant is a second answer to "does the board mean this yet".
# Multiplied into the live tint, so a tuned Guard colour carries into its own ghost.
func _ghosted(tint: Color) -> Color:
	return Color(tint.r, tint.g, tint.b, tint.a * TERRAIN_PREVIEW_MODULATE.a)

# The Game tab's colour knob re-applying to links already on screen (restyle_knockback_trail's
# shape). Re-tints rather than redrawing: this manager has no unit list to rebuild the pairs from.
func restyle_guard_link() -> void:
	for sprite in guard_link_sprites:
		if is_instance_valid(sprite):
			sprite.modulate = GUARD_LINK_MODULATE

# The channel is cleared whole, so everything that should be on it after this call has to be drawn
# by it: the STANDING set first, then the squad the caller is actually about (which may already be
# in that set -- create_unit_icon is idempotent, so the overlap costs nothing).
func redraw_squad_unit_icons(squad: Squad):
	clear_unit_icon_types([OverlayIcon.IconType.CROWN, OverlayIcon.IconType.SQUADMEMBER])
	standing_rings_drawer.call()
	draw_squad_unit_icons(squad)

# What ONE squad's markers ARE: a ring on every member, the crown on its leader. Split out of the
# redraw above so the standing-ring sweep (game.refresh_squad_rings) can draw many squads without
# each one wiping the last -- the alternative was a second copy of this pair, which is how the two
# would have drifted.
#
# The membership gate lives HERE rather than at the call sites (#441): a ring means "this unit is in
# a squad with somebody", so a solo squad has nothing to say on this channel -- and two of the three
# callers had no gate, which put a ring tinted with the UNDEALT ring_hue sentinel (Color.WHITE) under
# solo units between AI turns. A sentinel that can reach the screen is being read as a colour.
# The crown rides the same gate on purpose: a solo unit leads nobody, which is the rule
# _on_squad_became_active already applied to its own crown.
func draw_squad_unit_icons(squad: Squad) -> void:
	if squad == null or not squad.has_squadmates():
		return
	for member in squad.get_members():
		create_unit_icon(member, OverlayIcon.IconType.SQUADMEMBER)
		if member == squad.get_leader():
			create_unit_icon(member, OverlayIcon.IconType.CROWN)
				
func clear_selection_overlays():
	move_overlay.clear()
	attack_overlay.clear()
	hover_overlay.clear()
	squad_overlay.clear()
	invalidmove_overlay.clear()
	squadrange_overlay.clear()

# The live terrain state on the board (#50). Drawn from TerrainStateManager after execution,
# NOT cleared by clear_selection_overlays (or any selection change) — a burning tile stays burning regardless of what
# you click. Its own sprite dict, so the icon/overlay clears never touch it.
func redraw_terrain_live(states: TerrainStateManager) -> void:
	_clear_terrain_live()
	for state in TERRAIN_STATE_ICONS:
		var icon: Texture2D = TERRAIN_STATE_ICONS[state]
		for cell in states.cells_with(state):
			var sprite := Sprite2D.new()
			sprite.texture = icon
			sprite.global_position = GridUtils.cell_world(board_tilemap, cell)
			sprite.z_index = TERRAIN_Z_INDEX
			icon_overlay.add_child(sprite)
			terrain_live_sprites.append(sprite)

func _clear_terrain_live() -> void:
	for sprite in terrain_live_sprites:
		if is_instance_valid(sprite):
			sprite.queue_free()
	terrain_live_sprites.clear()

func clear_squad_range():
	squadrange_overlay.clear()
	
func draw_cells(layer: TileMapLayer, cells: Array, atlas_coord: Vector2i):
	for cell in cells:
		#if is_valid_cell(cell):
			layer.set_cell(cell, SOURCE_ID, atlas_coord)
		
func is_valid_cell(cell: Vector2i) -> bool:
	return move_overlay.get_used_rect().has_point(cell)

func draw_path_arrows(move: MoveAction):
	var tint := _arrow_modulate(move)

	# Hold-position is move-specific semantics, so it stays out of the shared trail: there is no
	# path to draw, only an error marker when the hold itself is refused.
	if move.is_hold_position:
		if not move.is_valid:
			move.add_preview_sprite(_create_arrow_sprite(move.destination, PATH_ERROR, tint))
		return

	for sprite in _draw_arrow_trail(move.get_move_path(), tint):
		move.add_preview_sprite(sprite)

# ONE arrow trail, drawn cell by cell -- the seam for ANY effect that walks a unit along a path
# (#126 follow-up; planned moves and knockback shoves are the two callers today). Returns the
# sprites rather than tracking them, because lifetime differs per caller -- a move's arrows die
# with its MoveAction, a shove's with clear_knockback_preview -- so ownership stays the caller's.
# An empty path draws nothing; a single-cell path draws PATH_ERROR (a trail that goes nowhere is
# a bug worth seeing, and the texture pick below needs a neighbour to aim at).
func _draw_arrow_trail(path: Array[Vector2i], tint: Color) -> Array[Sprite2D]:
	var sprites: Array[Sprite2D] = []
	if path.is_empty():
		return sprites
	if path.size() == 1:
		sprites.append(_create_arrow_sprite(path[0], PATH_ERROR, tint))
		return sprites
	for i in range(path.size()):
		sprites.append(_create_arrow_sprite(path[i], _path_arrow_texture(path, i), tint))
	return sprites

# Which arrow tile belongs at path[i]: start / segment / arrowhead. Split from the trail drawer
# above only because the two answer different questions (texture vs sprites); every caller should
# go through _draw_arrow_trail. Corners are legal -- _get_path_segment_atlas knows them -- so the
# trail is not limited to straight lines; non-CARDINAL steps fall to PATH_ERROR (an atlas limit).
func _path_arrow_texture(path: Array[Vector2i], i: int) -> Texture2D:
	var current := path[i]
	if i == 0:
		return _get_start_atlas(path[i + 1] - current)
	if i == path.size() - 1:
		return _get_arrowhead_atlas(current - path[i - 1])
	return _get_path_segment_atlas(path[i - 1] - current, path[i + 1] - current)

func _get_arrowhead_atlas(dir: Vector2i) -> Texture2D:
	match dir:
		Vector2i.UP:
			return PATH_ARROW_UP
		Vector2i.RIGHT:
			return PATH_ARROW_RIGHT
		Vector2i.DOWN:
			return PATH_ARROW_DOWN
		Vector2i.LEFT:
			return PATH_ARROW_LEFT
		_:
			return PATH_ERROR
			
func _get_start_atlas(dir: Vector2i) -> Texture2D:
	match dir:
		Vector2i.UP:
			return PATH_START_UP
		Vector2i.DOWN:
			return PATH_START_DOWN
		Vector2i.LEFT:
			return PATH_START_LEFT
		Vector2i.RIGHT:
			return PATH_START_RIGHT
		_:
			return PATH_ERROR
			
func _get_path_segment_atlas(from_dir: Vector2i, to_dir: Vector2i) -> Texture2D:
	#Horizontal
	if _dirs_match(from_dir, to_dir, Vector2i.LEFT, Vector2i.RIGHT):
		return PATH_HORIZONTAL
	
	#Vertical
	if _dirs_match(from_dir, to_dir, Vector2i.UP, Vector2i.DOWN):
		return PATH_VERTICAL
		
	#Corners
	if _dirs_match(from_dir, to_dir, Vector2i.UP, Vector2i.RIGHT):
		return PATH_UP_RIGHT
	if _dirs_match(from_dir, to_dir, Vector2i.RIGHT, Vector2i.DOWN):
		return PATH_DOWN_RIGHT
	if _dirs_match(from_dir, to_dir, Vector2i.DOWN, Vector2i.LEFT):
		return PATH_DOWN_LEFT
	if _dirs_match(from_dir, to_dir, Vector2i.LEFT, Vector2i.UP):
		return PATH_UP_LEFT

	return PATH_ERROR

#Just to keep my cases tighter
func _dirs_match(a: Vector2i, b: Vector2i, dir1: Vector2i, dir2: Vector2i) -> bool:
	return (a == dir1 and b == dir2) or (a == dir2 and b == dir1)
	
# Arrow tint, worst-first: refused, following-but-falling-behind (Case 1), keeping formation.
# Separate from _create_arrow_sprite because the knockback preview draws the same arrows for a
# shove, which has no MoveAction to ask.
func _arrow_modulate(move: MoveAction) -> Color:
	if not move.is_valid:
		return INVALID_ARROW_MODULATE
	if move.is_trailing:
		return TRAILING_ARROW_MODULATE
	return MOVE_ARROW_MODULATE

func _create_arrow_sprite(cell: Vector2i, texture: Texture2D, tint: Color) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.z_index = MoveAction.ARROW_BASE_Z_INDEX
	sprite.global_position = GridUtils.cell_world(board_tilemap, cell)
	sprite.modulate = tint
	arrow_icon_overlay.add_child(sprite)
	return sprite
	
func on_hovered_unit_changed(previous_unit: Unit, new_unit: Unit):
	if previous_unit != null and is_instance_valid(previous_unit):
		set_unit_path_hovered(previous_unit, false)
	
	if new_unit != null and is_instance_valid(new_unit):
		set_unit_path_hovered(new_unit, true)
	
func set_unit_path_hovered(unit: Unit, hovered: bool):
	if not planned_move_by_unit.has(unit):
		return
		
	var move: MoveAction = planned_move_by_unit[unit]
	move.set_preview_z_index(MoveAction.HOVERED_ARROW_Z_INDEX if hovered else MoveAction.ARROW_BASE_Z_INDEX)
	
func show_projected_unit(unit: Unit, cell: Vector2i):
	clear_projected_unit(unit)
	
	var sprite := Sprite2D.new()
	sprite.texture = unit.get_move_texture()
	sprite.global_position = GridUtils.cell_world(board_tilemap, cell)
	sprite.z_index = Unit.BASE_SPRITE_INDEX
	
	#Planning sprite modulation
	sprite.modulate = PROJECTED_MODULATE
	var offset = Vector2i(0, -8)
	sprite.offset = offset
	projected_unit_overlay.add_child(sprite)
	projected_unit_sprites[unit] = sprite

# Whichever ghost is standing in for this unit, from EITHER store -- a queued move's or a predicted
# shove's. Both hide the real sprite (UnitVisuals.set_projected), so a caller that only knew about
# the move ghost wrote its highlight to a node nobody can see: hovering the queue row for an attack
# that knocks its target back lit nothing at all, in the flat view and the diorama alike.
func _ghost_for(unit: Unit) -> Sprite2D:
	var sprite: Sprite2D = projected_unit_sprites.get(unit)
	if sprite == null:
		sprite = knockback_ghost_by_unit.get(unit)
	return sprite if is_instance_valid(sprite) else null

func has_projected_unit(unit: Unit) -> bool:
	return _ghost_for(unit) != null

func set_projected_unit_highlighted(unit: Unit, value: bool) -> void:
	var sprite := _ghost_for(unit)
	if sprite == null:
		return
	sprite.modulate = PROJECTED_HIGHLIGHT if value else PROJECTED_MODULATE

func clear_projected_unit(unit: Unit):
	if not projected_unit_sprites.has(unit):
		return
	
	var sprite: Sprite2D = projected_unit_sprites[unit]
	
	if is_instance_valid(sprite):
		sprite.hide()
		sprite.queue_free()
		
	projected_unit_sprites.erase(unit)
	
func clear_all_projected_sprites():
	for unit in projected_unit_sprites.keys().duplicate():
		clear_projected_unit(unit)
		
func redraw_projected_units():
	clear_all_projected_sprites()

	for unit in planned_move_by_unit.keys().duplicate():
		var move: MoveAction = planned_move_by_unit[unit]
		if not is_instance_valid(unit):
			move.clear_preview_sprites()
			planned_move_by_unit.erase(unit)
			continue

		unit.visuals.set_projected(move.is_valid)
		if move.is_valid:
			show_projected_unit(unit, move.destination)
			
func handle_unit_death(unit: Unit):
	clear_unit_icons(unit)
	clear_planned_path(unit)
	clear_projected_unit(unit)
	if hover_move_preview != null and hover_move_preview.actor == unit:
		clear_hover_move_path()
		
#Untyped parameter on purpose: freed objects cannot pass a typed Unit parameter
func _purge_unit_entry(unit):
	if not icons_by_unit.has(unit):
		return
	for icon in icons_by_unit[unit].values():
		if is_instance_valid(icon):
			icon.queue_free()
	icons_by_unit.erase(unit)
	
func show_hover_move_paths(moves: Array[MoveAction]):
	clear_hover_move_path()
	hover_move_previews = moves
	for m in hover_move_previews:
		draw_path_arrows(m)
		m.set_preview_z_index(MoveAction.HOVERED_ARROW_Z_INDEX)
