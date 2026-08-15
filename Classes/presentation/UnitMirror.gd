extends Node3D
class_name UnitMirror

# The Battle3D unit mirror (#215 / #176 stage 4a): a per-frame reconcile of the
# hidden game's $Units children into UnitSprite3Ds. Poll, don't wire: no spawn
# signal exists, clear_board frees without unit_died, and the 2D walk tween is
# already the one animation authority — position is unit.position / 16 (the
# map_to_local metric), so the 3D sprite glides exactly as the 2D one does.
# Keyed by instance id, never by object ref (#149: a freed Unit in a typed slot
# dies on the type-check before any null guard runs). Since #222 it also hosts the
# planning-ghost pool (set_ghosts) and copies each 2D sprite's own modulate per frame,
# so pulse/highlight/tint parity comes by copy rather than by reimplementation.
#
# Since #229 it also hosts the per-unit health readout: one UnitHealthBar per mirrored unit, shown
# only for whichever unit the pointer currently resolves to. Both facts it needs already have
# exactly one answer elsewhere — hovered_unit_source asks the question HoverPresenter._process asks,
# and HP comes off the Unit — so this adds a SURFACE, not a seam.

const PIXELS_PER_CELL := float(GridUtils.TILE_SIZE)  # 16 — grid.map_to_local's metric

# Unit-sprite pixel density, in texels per world unit — the inspector face of
# UnitSprite3D.texels_per_unit, which every sprite reads at construction (ghosts included, which
# is why the number lives on the class and not on each sprite). It sits here because this is the
# node that builds them, and its _ready runs before any reconcile can.
#
# A knob since #250 put the real 16px tile art on the ground: at 32 the ground's pixels are twice
# the size of a unit's, at 16 a 32px unit stands two cells tall — exactly its proportion in the 2D
# game. #176 calls mixed densities "the single loudest amateur HD-2D tell"; which way to fix it is
# an eye call, so it is a dial rather than a guess.
@export var texels_per_unit := 32.0

# --- The hover health readout (#229) -------------------------------------------------
# Eye-knobs, all of them read in _sync_bar and never written back, which is what makes them legal
# Look-tab entries. They live on this node rather than on UnitHealthBar because a knob may only
# name a property of a node that exists in Battle3D.tscn, and the bars are built at runtime.
@export var hud_lift := 1.35            # the readout's height above the unit's stand point
@export var bar_width_texels := 24.0
@export var bar_height_texels := 3.0
@export var bar_back_color := Color(0.05, 0.04, 0.07, 0.85)
# The fill lerps empty -> full by the HP fraction. One mechanism rather than a colour plus a
# "should it ramp" flag: a flat bar is just setting both of these the same.
@export var bar_full_color := Color(0.35, 0.85, 0.4, 1.0)
@export var bar_empty_color := Color(0.85, 0.2, 0.2, 1.0)
# Floats, though both are int properties on Label3D: every other numeric knob is a float slider,
# and writing 12.5 into an int would store 12 and read back changed — the "moves and silently
# reverts" failure test_look_tool.gd exists to catch. Cast at the point of use instead.
@export var number_font_size := 12.0
@export var number_outline_size := 2.0
@export var number_color := Color.WHITE
@export var number_gap := 0.05           # clear space between the bar's top edge and the glyphs
# Whether the number reads "12/20" or "12". A knob because it is a taste call about how much text
# belongs over a head, and the bar already carries the fraction either way.
@export var number_shows_max := true

# Which unit the pointer resolves to, injected by battle3d — the same idiom as pointer_source and
# board_source. A Callable rather than a game back-ref keeps this node testable and keeps the
# question single-sourced: it returns whatever HoverPresenter's own derivation returns.
var hovered_unit_source: Callable

var units_root: Node2D

# The elevation store (#273); pushed in by battle3d beside units_root. A unit stands on the
# SURFACE, and this is what tells it where that is — null on a board with no heights wired, which
# BoardSpace.surface_point reads as flat.
var heights: BoardHeights

var _mirrored: Dictionary[int, UnitSprite3D] = {}
var _bars: Dictionary[int, UnitHealthBar] = {}   # #229; keyed like _mirrored, never by object ref
var _ghosts: Array[UnitSprite3D] = []
var _camera_right := Vector3.ZERO   # last camera basis facing was judged against


func _ready() -> void:
	UnitSprite3D.texels_per_unit = texels_per_unit


func _process(_delta: float) -> void:
	if units_root != null:
		reconcile()
	_refresh_facing_on_camera_turn()


# Facing is judged against the LIVE camera, but _sync only re-judges a sprite that MOVED
# — so rotating the camera used to leave every standing unit mirrored the wrong way until
# it next walked. Free orbit (#176 4d) made that continuous instead of occasional. One
# viewport read per frame; per-sprite work only on the frames the camera actually turned.
func _refresh_facing_on_camera_turn() -> void:
	if not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var right := camera.global_transform.basis.x
	if right.is_equal_approx(_camera_right):
		return
	_camera_right = right
	for sprite: UnitSprite3D in _mirrored.values():
		if sprite.last_step != Vector3.ZERO:
			sprite.flip_h = sprite.facing_flip_for(sprite.last_step)


func reconcile() -> void:
	# Asked ONCE per frame, not once per unit: it is a board-wide question, and calling it per unit
	# would re-derive every other unit's projected cell for each unit on the board.
	var hovered := _hovered_unit()
	var live: Dictionary[int, bool] = {}
	for child in units_root.get_children():
		var unit := child as Unit
		if unit == null or unit.is_queued_for_deletion():
			continue
		var id := unit.get_instance_id()
		live[id] = true
		if not _mirrored.has(id):
			var sprite := UnitSprite3D.for_unit_data(unit.unit_data)
			add_child(sprite)
			_mirrored[id] = sprite
		if not _bars.has(id):
			var bar := UnitHealthBar.new()
			add_child(bar)
			_bars[id] = bar
		_sync(unit, _mirrored[id])
		_sync_bar(unit, _mirrored[id], _bars[id], unit == hovered)
	for id: int in _mirrored.keys():
		if not live.has(id):
			_mirrored[id].queue_free()
			_mirrored.erase(id)
			if _bars.has(id):
				_bars[id].queue_free()
				_bars.erase(id)


func mirrored_count() -> int:
	return _mirrored.size()


func sprite_for(unit: Unit) -> UnitSprite3D:
	return _mirrored.get(unit.get_instance_id())


func bar_for(unit: Unit) -> UnitHealthBar:
	return _bars.get(unit.get_instance_id())


# Planning ghosts (#222): the 2D projected/knockback stand-ins, mirrored as pooled
# UnitSprite3Ds. One entry per ghost: {"pos": Vector3, "texture": Texture2D,
# "modulate": Color} — texture and tint arrive by copy, the 2D stays the authority.
# Wholesale replace, same pool contract as BoardOverlays (extras hidden, not freed).
func set_ghosts(ghosts: Array[Dictionary]) -> void:
	while _ghosts.size() < ghosts.size():
		var ghost := UnitSprite3D.new()
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # a translucent stand-in casts no shadow
		add_child(ghost)
		_ghosts.append(ghost)
	for i in _ghosts.size():
		var ghost: UnitSprite3D = _ghosts[i]
		if i < ghosts.size():
			ghost.visible = true
			ghost.position = ghosts[i]["pos"]
			ghost.texture = ghosts[i]["texture"]
			ghost.modulate = ghosts[i]["modulate"]
		else:
			ghost.visible = false


func ghost_count() -> int:
	var visible_count := 0
	for ghost in _ghosts:
		if ghost.visible:
			visible_count += 1
	return visible_count


func _sync(unit: Unit, sprite: UnitSprite3D) -> void:
	var previous := sprite.position
	# The height comes from the cell the sprite is OVER, not from unit.movement.cell: mid-walk the
	# pixel position is between cells, and reading the destination would pop the sprite to the new
	# level before it arrives. Derived from the same pixels that place X and Z, so it steps up as
	# the sprite crosses the edge.
	var over := Vector2i(floori(unit.position.x / PIXELS_PER_CELL),
			floori(unit.position.y / PIXELS_PER_CELL))
	sprite.position = Vector3(unit.position.x / PIXELS_PER_CELL,
			BoardSpace.surface_point(over, heights).y, unit.position.y / PIXELS_PER_CELL)
	sprite.cell = BoardSpace.cell_of(sprite.position + Vector3(0, -0.5, 0))

	var downed := unit.lifecycle_state == Unit.LifecycleState.DOWNED
	if downed != sprite.is_downed():
		sprite.set_downed(downed)
	if not downed:
		sprite.set_walking_visual(unit.movement.moving)

	# Hidden ONLY when a planning ghost stands in (#232). Asking visuals.projected rather
	# than copying $MapSprite.visible: that flag has a second writer, _show_downed_sprite,
	# which hides it to swap in the separate downed art — so the copy hid every downed unit
	# one line after set_downed above had correctly mirrored it. Never is_visible_in_tree
	# either: 3D hosting hides the whole board subtree, which must not read as every unit
	# hidden.
	sprite.visible = not unit.visuals.projected
	# The PRODUCT, because 2D modulate multiplies down the tree and the faction tint lives
	# on the Unit node while the effects (pulse, highlight, flash) live on its sprite. The
	# child alone is what left enemies un-reddened in 3D.
	sprite.modulate = unit.modulate * unit.visuals.sprite.modulate

	var step := sprite.position - previous
	if Vector2(step.x, step.z).length_squared() > 0.000001:
		sprite.last_step = step
		sprite.flip_h = sprite.facing_flip_for(step)


# --- The hover health readout (#229) -------------------------------------------------

# Whichever unit the pointer is over, straight off HoverPresenter's own derivation. Unset on a
# host that never injects it (a bare Main.tscn launch, or a headless fixture), which reads as
# "nothing hovered" — so the readout is simply absent rather than wrong.
func _hovered_unit() -> Unit:
	if not hovered_unit_source.is_valid():
		return null
	return hovered_unit_source.call() as Unit


func _sync_bar(unit: Unit, sprite: UnitSprite3D, bar: UnitHealthBar, hovered: bool) -> void:
	bar.set_shown(hovered)
	if not hovered:
		return   # one bar is up at a time, so everything below is per-FRAME work, not per-unit
	bar.set_style(bar_width_texels, bar_height_texels, bar_back_color, bar_full_color,
			bar_empty_color, int(number_font_size), int(number_outline_size), number_color,
			number_gap, number_shows_max)
	bar.set_hp(unit.get_current_hp(), unit.get_max_hp())
	bar.position = _bar_anchor(unit, sprite)


# The readout rides whatever is ON SCREEN. That is the same fork _sync makes when it hides a
# sprite behind a planning ghost, asked again rather than re-decided: hovering resolves at the
# PROJECTED cell (game.unit_at_pointer), so a unit with a queued move is picked while its own
# sprite is hidden — and a bar parented to that sprite would vanish exactly when a hovered unit
# most needs one. Reading the projected cell also covers the knockback ghost, whose 2D preview
# sprites carry no unit identity to hang anything off.
func _bar_anchor(unit: Unit, sprite: UnitSprite3D) -> Vector3:
	var lift := Vector3(0.0, hud_lift, 0.0)
	if not unit.visuals.projected:
		return sprite.position + lift
	return BoardSpace.surface_point(unit.get_projected_destination(), heights) + lift
