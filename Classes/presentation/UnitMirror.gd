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
#
# Since #313 a readout has a SECOND reason to be up: the queued plan is about to change this unit's
# HP. That number is the resolver's, threaded across the whole pass and read through
# PlanResolver.projected_hp — never recomputed here, and never the per-hit target_hp_after, which
# answers a different question for a unit struck twice. This node computes no damage; if it ever
# needs to, that is the bug.
#
# #354 split that second reason in two. WHO wears one is PlanResolver.plan_changes, asked of the
# plan's own hypothetical; WHAT it draws is the live HP under a frozen prediction. Only the fill
# tracks the board, so a bar drains down to its notch as the hit lands instead of vanishing at the
# moment of impact — and the readout leaves when the PASS does, because the plan does.
#
# #350 adds the THIRD and last reason: a player who has asked for every bar, always. That one is a
# PREFERENCE rather than a derivation, so it comes off PlayerSettings rather than off anything on
# the board — one more disjunct in the same expression, no new per-unit state, nothing to compute.
# The expression is now THE gate for this volume, and #357's state-icon row rides it: the icons are
# CHILDREN of the bar, so a hidden bar hides them with nothing to keep in step. A second visibility
# rule in this file would be the bug.
#
# It reads the MODEL for that, not the 2D — the departure from OverlayMirror's "the 2D stays the one
# authority" that #229 already made, and for the same reason: the flat view draws no HP over units
# at all, so there is no retained 2D state to mirror.
#
# Since #321 it also mirrors UnitVisuals' effect OFFSET (the attack lunge, the invalid-order shake),
# which is expressed on the Unit's child sprite rather than on the Unit — the one fact of that class
# the position read above cannot see. The rule the ticket settled: anything a 2D effect writes on the
# Unit node mirrors for free, anything it writes as a child offset arrives through animation_offset().

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
# CLEARANCE above the art's topmost opaque pixel — not a height above the feet. It was the latter
# for two rounds and read as floating both times, because a map sprite's visible head is wherever
# its transparent padding ends and no single number is right for every piece of art.
#
# The selection icons (crown, squad member, target) hang at BoardOverlays.billboard_lift, measured
# from the CELL, and the dev's stacking is icons on top with the readout tucked under them. Nothing
# enforces that: a test would be pinning one tuning value against another, which the tuning razor
# forbids, so if the icons move this moves by hand.
@export var hud_lift := 0.06
@export var bar_width_texels := 26.0
@export var bar_height_texels := 5.0
@export var bar_outline_texels := 1.0   # black border thickness; the colour itself is not a knob
# Two FLAT colours, not a ramp (dev feel-check, 2026-08-15): the fill is what the unit HAS, and the
# missing colour is the backing showing through behind it. Both fully opaque on purpose — this is a
# gameplay descriptor, meant to sit on top of the scene rather than blend into it.
@export var bar_fill_color := Color(0.15, 1.0, 0.2, 1.0)
@export var bar_missing_color := Color(0.9, 0.05, 0.05, 1.0)
# The number's WORLD height in cells, NOT a font size: the glyph atlas is held at a fixed high
# resolution and this scales the quad instead, so small text stays crisp. Sizing by font_size would
# have meant a 4px font to reach the size asked for, which renders to mush.
@export var number_height_cells := 0.13
# Glyph-atlas units, so what reaches the screen is this times pixel_size. That indirection is why
# the first two values were far too thin to read: at 5 against FONT_RESOLUTION 32 and a 0.13-cell
# glyph, the outline came out 0.020 world units — under ONE art texel (0.031), i.e. thinner than a
# single pixel of the game's own art. Roughly 8 buys one texel, 16 buys two.
#
# The ratio to FONT_RESOLUTION is what decides thickness RELATIVE to the glyphs, and at this display
# size a readable outline is a large fraction of the letter height, so pushed far enough the digits
# will start to bleed into one another. If that runs out before it reads, the answer is not more
# outline — it is a dark backing plate behind the number, or inverting to black digits.
@export var number_outline_size := 10.0
@export var number_color := Color.WHITE
@export var number_gap := 0.01           # inset from the bar's left edge; the number sits ON the bar
# Whether the number reads "12/20" or "12". A knob because it is a taste call about how much text
# belongs over a head, and the bar already carries the fraction either way.
@export var number_shows_max := true

# --- The predicted readout (#313) ------------------------------------------------------
# The span between what a unit HAS and what the plan leaves it with. Two colours because the span
# means opposite things in the two directions and the geometry cannot say which.
@export var bar_doomed_color := Color(1.0, 0.75, 0.1, 1.0)
@export var bar_heal_color := Color(0.4, 0.9, 1.0, 1.0)
@export var notch_color := Color.WHITE
@export var notch_texels := 1.0
# What the doomed span pulses TO when the plan predicts a named rung — a down, a kill, or Crisis.
# Only the peak is a knob: the resting colour is bar_doomed_color, so the alarm cannot drift away
# from the thing it is alarming about.
@export var alarm_peak_color := Color(1.0, 1.0, 1.0, 1.0)

# --- Crowding, shared by every non-hover reason (#313, widened by #350) ----------------
# Whether a bar that is up for a reason OTHER than hover also carries its number. Off by default,
# and the reason generalises past the ticket that found it: a plan can put a readout over half the
# board at once, and #350's toggle puts one over ALL of it. So the digits stay a hover reward
# either way. ONE knob rather than one per reason -- the question is how crowded this volume may
# get, and that question does not change with why a bar happens to be up.
@export var unhovered_shows_number := false
# #325: the leader's crown badge beside the bar, as a multiple of the bar's own height.
@export var crown_badge_scale := 1.0

# --- The element-state row (#357) ------------------------------------------------------
# One icon per state the unit holds, just above the bar. In TEXELS, at the same pixel density as
# the bar and every sprite — the crown is measured against the bar's height because the dev asked
# for it at bar height, and nothing ties these to how thick the gauge is.
#
# 8 is half a cell, and deliberate rather than arbitrary: both source icons are powers of two (the
# wet drop 32px, the frozen-tile placeholder 16px), so both land on exact 4:1 and 2:1 reductions.
@export var state_icon_texels := 8.0
@export var state_icon_gap_texels := 2.0        # clearance above the bar's outline
@export var state_icon_spacing_texels := 1.0    # between neighbouring icons

# Which unit the pointer resolves to, injected by battle3d — the same idiom as pointer_source and
# board_source. A Callable rather than a game back-ref keeps this node testable and keeps the
# question single-sourced: it returns whatever HoverPresenter's own derivation returns.
var hovered_unit_source: Callable

# The plan whose consequences are being previewed, injected by battle3d beside the hover source
# (#313). Returns SquadManager's last resolve for the active squad — the same object the queue rows
# and the board's knockback/terrain preview are drawn from, so all three can only agree. Unset on a
# bare Main.tscn launch or a headless fixture, which reads as "no plan": the prediction is simply
# absent rather than wrong.
var plan_source: Callable

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
	var plan := _plan()   # board-wide for the same reason, and a dictionary read per unit after
	# The player's standing preference (#350), asked once for the same reason: it cannot change
	# mid-frame, and a static read per unit would be N reads answering one question.
	var always_on := PlayerSettings.is_on(PlayerSettings.Setting.ALWAYS_SHOW_HEALTH)
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
		_sync_bar(unit, _mirrored[id], _bars[id], unit == hovered, plan, always_on)
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
		# ...and it sorts by PRIORITY, not by depth (#317). OPAQUE_PREPASS writes depth only where
		# alpha clears the prepass threshold, and a ghost's tint is 0.75 — so a ghost wrote none,
		# and what holds markup behind a REAL sprite is that depth, never UNIT_RENDER_PRIORITY.
		ghost.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
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
	# The BOARD point, which is what every derivation below reads — never the written position,
	# which since #321 also carries the effect offset.
	var previous := sprite.position - sprite.art_offset
	# The height comes from the cell the sprite is OVER, not from unit.movement.cell: mid-walk the
	# pixel position is between cells, and reading the destination would pop the sprite to the new
	# level before it arrives. Derived from the same pixels that place X and Z, so it steps up as
	# the sprite crosses the edge.
	var over := Vector2i(floori(unit.position.x / PIXELS_PER_CELL),
			floori(unit.position.y / PIXELS_PER_CELL))
	var stand := Vector3(unit.position.x / PIXELS_PER_CELL,
			BoardSpace.surface_point(over, heights).y, unit.position.y / PIXELS_PER_CELL)
	sprite.cell = BoardSpace.cell_of(stand + Vector3(0, -0.5, 0))
	# The attack lunge and the invalid-order shake (#321) tween $MapSprite's LOCAL position, which
	# unit.position never sees — the one fact UnitVisuals expresses that the reads above cannot
	# reach. Mapped through the same metric and the same axes as the stand point: a 2D y is board
	# DEPTH, never height. Added last, so a lunge is not a step and does not change the cell.
	var art := unit.visuals.animation_offset() / PIXELS_PER_CELL
	sprite.art_offset = Vector3(art.x, 0.0, art.y)
	sprite.position = stand + sprite.art_offset

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

	var step := stand - previous
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


func _plan() -> ResolvedPlan:
	if not plan_source.is_valid():
		return null
	return plan_source.call() as ResolvedPlan


# What the plan leaves this unit at, ALREADY CLAMPED for display — the raw threaded number goes
# negative on a fatal hit, and LethalityRules.displayed_hp is the one answer to what a preview shows
# for it, shared with the queue panel's own "before -> after" (#313). Drawn ONLY; the clamp flattens
# a felled unit's prediction onto the HP it already has, so it can never be asked who gets a bar
# (#354) — that question goes to the hypo, which still knows the difference.
func _predicted_hp(unit: Unit, plan: ResolvedPlan) -> int:
	return LethalityRules.displayed_hp(PlanResolver.projected_hp(unit, plan.hypo),
			PlanResolver.projected_lifecycle(unit, plan.hypo))


func _sync_bar(unit: Unit, sprite: UnitSprite3D, bar: UnitHealthBar, hovered: bool,
		plan: ResolvedPlan, always_on: bool) -> void:
	# Two reasons to be up (#313), and the SECOND is the whole ticket: a readout stays over a unit
	# because a plan is about to happen to it. That reaches everyone the plan touches, enemies your
	# own attack will hit included, and nobody it doesn't.
	#
	# WHO is a question about the plan and is asked of the plan (#354). It used to be "predicted
	# differs from current", which made membership a function of LIVE HP — so every bar switched
	# itself off at the instant its own hit landed, mid-pass, one at a time.
	var foretold := plan != null and PlanResolver.plan_changes(unit, plan.hypo)
	# THE gate: three reasons, ONE expression (#350). #357's state-icon row rides it structurally —
	# the icons hang off the bar — so a second visibility rule anywhere in this file is the bug.
	var shown := hovered or foretold or always_on
	bar.set_shown(shown)
	if not shown:
		return
	bar.set_style(bar_width_texels, bar_height_texels, bar_outline_texels, bar_fill_color,
			bar_missing_color, number_height_cells, number_outline_size, number_color,
			number_gap, number_shows_max)
	bar.set_prediction_style(bar_doomed_color, bar_heal_color, notch_color, notch_texels,
			alarm_peak_color)
	bar.set_hp(unit.get_current_hp(), unit.get_max_hp())
	bar.set_number_shown(hovered or unhovered_shows_number)
	# #325: in ring mode leadership reads beside health; the squares arm keeps its billboard.
	var leads: bool = OverlayManager.SQUAD_MARKER_RINGS and unit.squad != null \
			and unit.squad.get_leader() == unit and unit.has_squad()
	var crown: Texture2D = OverlayManager.ICON_TEXTURES[OverlayIcon.IconType.CROWN] if leads else null
	bar.set_leader_badge(crown, crown_badge_scale)
	# #357: what this unit IS, in the channel #346 freed. Below the early return above, so the row
	# rides THE gate rather than growing one — and the art comes from StateIcons, which stays the
	# one answer to which icon means which state for all three surfaces that draw them.
	bar.set_state_icons(StateIcons.textures_for(unit.element_states), state_icon_texels,
			state_icon_gap_texels, state_icon_spacing_texels)
	if foretold:
		bar.set_prediction(_predicted_hp(unit, plan), PlanResolver.plan_fells(unit, plan.hypo))
	else:
		bar.clear_prediction()
	bar.position = _bar_anchor(unit, sprite)
	# The readout turns as ONE object rather than five that each billboard themselves — see
	# UnitHealthBar.face(). One camera read for the whole frame; the rotation is per SHOWN bar, which
	# is the hovered one plus whoever the plan is about to change.
	if is_inside_tree():
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			bar.face(camera.global_position)


# The readout rides whatever is ON SCREEN. That is the same fork _sync makes when it hides a
# sprite behind a planning ghost, asked again rather than re-decided: hovering resolves at the
# PROJECTED cell (game.unit_at_pointer), so a unit with a queued move is picked while its own
# sprite is hidden — and a bar parented to that sprite would vanish exactly when a hovered unit
# most needs one. Reading the projected cell also covers the knockback ghost, whose 2D preview
# sprites carry no unit identity to hang anything off.
func _bar_anchor(unit: Unit, sprite: UnitSprite3D) -> Vector3:
	# Measured, not assumed: hud_lift is clearance above the ART's topmost opaque pixel, so units
	# whose sprites carry different amounts of transparent padding still wear the readout at the
	# same apparent height. Anchoring it a fixed distance off the FEET is what left it looking too
	# high twice over (dev, 2026-08-15), because the head is not one cell up — #279's lamp float
	# was this same padding.
	var lift := Vector3(0.0, sprite.art_top_height() + hud_lift, 0.0)
	if not unit.visuals.projected:
		return sprite.position + lift
	return BoardSpace.surface_point(unit.get_projected_destination(), heights) + lift
