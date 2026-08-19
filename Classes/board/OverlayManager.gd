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

const PROJECTED_MODULATE := Color(0.7, 0.9, 1, 0.75)        # the planning-ghost tint
const PROJECTED_HIGHLIGHT := Color(1.4, 1.4, 1.0, 1.0)      # brightened + opaque on hover
const HOVER_MODULATE := Color(1, 1, 0)                  # the aim-footprint fill
const HOVER_PULSE_MODULATE := Color(1, 1, 0, 0.3)       # its pulsed low point

# The reach layer's fill (#123 follow-up): red reads as hostile, so a healing pick paints green
# instead. Decided from the attack's own `heals` flag -- the one question, one answer this already
# is (resolution-pipeline.md) -- not a new axis. Only the constant reach fill is heal-aware; the
# MAP-footprint hover-pulse channel below is untouched since no heal in the game targets MAP yet.
# static var, not const, so the Look tab can tune them live (#212 slice 2). attack_reach_color is
# itself static and reads them, so this is the only form that works. Unlike the 3D-only layer
# colours, tuning these moves BOTH stacks -- the 3D mirrors this modulate rather than holding an
# answer of its own, so there is no 3D-only value here to tune (dev call: acceptable).
static var ATTACK_MODULATE := Color(1, 0, 0, .5)
static var HEAL_ATTACK_MODULATE := Color(0, 1, 0, .5)
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

const ICON_TEXTURES = {
	OverlayIcon.IconType.CROWN: preload("res://Art/Icons/BoardIcons/CrownIcon.png"),
	OverlayIcon.IconType.SQUADMEMBER: preload("res://Art/Icons/BoardIcons/SquadHighlightIcon.png")
}

# --- Squad marker style (#325 experiment) --------------------------------------------------
# Rings underfoot vs the legacy over-the-head squares. static, the ATTACK_MODULATE pattern, so
# the Look tab's toggle reaches it without a node ref; read by _style_icon here and by
# OverlayMirror._icons, so flipping it moves BOTH stacks. Style only -- icon LIFECYCLE (when a
# marker exists) is untouched either way. The losing style gets deleted when the experiment ends.
static var SQUAD_MARKER_RINGS := true
static var SQUAD_RING_ALPHA := 0.9
const SQUAD_RING_TEXTURE := preload("res://Art/Icons/BoardIcons/SquadRingIcon.png")
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
var planned_move_by_unit := {} #{Unit : MoveAction}
var terrain_live_sprites: Array[Sprite2D] = []       # live terrain icons (persist across selection)
var terrain_preview_sprites: Array[Sprite2D] = []    # ephemeral plan-time ghosts (Part B)
var hover_move_preview: MoveAction = null
var hover_move_previews: Array[MoveAction] = []
var projected_unit_sprites := {} # { Unit : Sprite2D }
var knockback_preview_sprites: Array[Node2D] = []
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
var _tile_pulse: Tween = null
# What the reach fill was last painted for, so refresh_attack_reach_color can re-derive it.
var _reach_attack: AttackData = null



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

# What color the reach layer should paint with for this attack -- red for damage, green for a
# heal. A null attack (bare fists) reads as the default/damage color.
static func attack_reach_color(attack: AttackData) -> Color:
	return HEAL_ATTACK_MODULATE if attack != null and attack.heals else ATTACK_MODULATE

func set_attack_reach_color(attack: AttackData) -> void:
	_reach_attack = attack
	attack_overlay.modulate = attack_reach_color(attack)


# Re-derive the reach fill from the attack it was last given. The Look tab calls this after tuning
# ATTACK_MODULATE: the 3D mirrors `attack_overlay.modulate` every frame rather than the constant,
# so without this a tuned colour would not show until the player next entered targeting.
func refresh_attack_reach_color() -> void:
	set_attack_reach_color(_reach_attack)

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

# One entry per SHOVE ({"target", "from", "to"}), in resolve order. A unit can be shoved more than
# once in a plan (#105 — two maces, or a mace plus a counter), so this draws an arrow PER HIT but
# exactly ONE ghost per target, at the cell the chain ends on. Drawing a ghost per hit would leave a
# copy of the unit standing on every waypoint.
func show_knockback_preview(shoves: Array) -> void:
	clear_knockback_preview()

	var final_cell := {}   # Unit -> Vector2i; entries arrive in resolve order, so the last one wins
	for shove in shoves:
		final_cell[shove["target"]] = shove["to"]

	for shove in shoves:
		var from: Vector2i = shove["from"]
		var to: Vector2i = shove["to"]
		# The FACING, not the displacement: a shove of 2+ tiles (and, before #105, a mis-sourced
		# start cell) makes to - from a vector the arrow atlas has no texture for, so it fell
		# through to PATH_ERROR. Same helper the resolver picks the shove direction with.
		var dir := GridUtils.cardinal_direction_i_between(from, to)
		# The WHOLE trail, cell by cell, through the same texture pick a planned move uses (#126).
		# This used to draw two sprites -- start and arrowhead -- which is complete only when they are
		# adjacent, so Blowback (1 tile) looked right and every longer shove left its middle blank.
		# Stepping `dir` is not a second source for the cells: a shove is a straight cardinal line by
		# construction (_resolve_knockback walks one direction and stops at the first blocked cell),
		# so from + to + dir cannot describe a different path than the resolver walked.
		for sprite in _draw_arrow_trail(_shove_path(from, to, dir), Color.WHITE):
			knockback_preview_sprites.append(sprite)

	# Hide each real sprite while its ghost stands in at the FINAL landing cell — the same pairing
	# redraw_projected_units uses for moves (set_projected hides, show_projected_unit draws).
	for target in final_cell:
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

# Every cell a shove crosses, `from` and `to` inclusive. A zero/undecidable direction yields just the
# start, which _draw_arrow_trail renders as PATH_ERROR -- a malformed shove is visible, never a hang.
func _shove_path(from: Vector2i, to: Vector2i, dir: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [from]
	if dir == Vector2i.ZERO:
		return cells
	var cursor := from
	while cursor != to:
		cursor += dir
		cells.append(cursor)
	return cells

func clear_knockback_preview() -> void:
	for unit in knockback_hidden_units:
		if is_instance_valid(unit):
			unit.visuals.set_projected(false)   # restore the real sprite
	knockback_hidden_units.clear()
	for sprite in knockback_preview_sprites:
		if is_instance_valid(sprite):
			sprite.queue_free()
	knockback_preview_sprites.clear()

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
	var cell := unit.get_projected_destination()
	icon.setup(ICON_TEXTURES[type], cell, type)
	icon.position = board_tilemap.map_to_local(cell)
	_style_icon(icon, unit)

	icons_by_unit[unit][type] = icon
	return icon

# Presentation only (#325): which texture/tint/z an icon wears under the current marker style.
# Rings lie under the unit in the squad's dealt hue; the crown decal keeps its authored gold so
# it never fights the palette. Square mode is byte-for-byte the legacy look.
func _style_icon(icon: OverlayIcon, unit: Unit) -> void:
	if SQUAD_MARKER_RINGS and icon.icon_type == OverlayIcon.IconType.SQUADMEMBER:
		icon.sprite.z_index = RING_Z_INDEX
		icon.sprite.texture = SQUAD_RING_TEXTURE
		var hue: Color = unit.squad.ring_hue if unit.squad != null else Color.WHITE
		icon.sprite.modulate = Color(hue.r, hue.g, hue.b, SQUAD_RING_ALPHA)
	else:
		# CROWN keeps the legacy over-sprite form in BOTH styles: in ring mode the 3D never
		# mirrors it (the leader reads off the health bar's badge -- UnitMirror), but the flat
		# view has no bar to badge, so its head crown stays. The readout family's #292
		# asymmetry, one member wider.
		icon.sprite.texture = ICON_TEXTURES[icon.icon_type]
		icon.sprite.z_index = HEAD_ICON_Z_INDEX
		icon.sprite.modulate = Color.WHITE

# The Look-tab toggle restyles markers already on screen; walking the store here keeps the
# panel ignorant of icon lifecycle.
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

func redraw_squad_unit_icons(squad: Squad):
	clear_unit_icon_types([OverlayIcon.IconType.CROWN, OverlayIcon.IconType.SQUADMEMBER])
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
		return Color(1, .25, .25, .85)
	if move.is_trailing:
		return Color(.4, 1, .45, .9)
	return Color.WHITE

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

func has_projected_unit(unit: Unit) -> bool:
	return projected_unit_sprites.has(unit)

func set_projected_unit_highlighted(unit: Unit, value: bool) -> void:
	if not projected_unit_sprites.has(unit):
		return
	var sprite: Sprite2D = projected_unit_sprites[unit]
	if not is_instance_valid(sprite):
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
