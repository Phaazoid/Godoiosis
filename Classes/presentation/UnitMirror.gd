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
# #322 puts the DOWNED glyph and its rescue clock in that same row. It is deliberately NOT a fourth
# reason to be up: the fact that a unit is down is already carried unconditionally by its downed
# ART, so this exists to stop the BAR contradicting it — `1/20` over a body and over a living unit
# at 1 HP are the same readout for two completely different board states.
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
# The CROWN hangs at BoardOverlays.billboard_lift, measured from the CELL, and the dev's stacking is
# it on top with the readout tucked under. Nothing enforces that: a test would be pinning one tuning
# value against another, which the tuning razor forbids, so if the crown moves this moves by hand.
# (It is the head channel's only tenant since #325's verdict -- TARGET went to the ground with #346,
# squad membership followed it as a ring.)
@export var hud_lift := 0.24
# --- The health grid (#314) -------------------------------------------------------------
# One cube per point of HP. A cube is this many texels INCLUDING its black cage, and cubes are
# pitched (block - border) apart so neighbours share that cage -- at 5/1 that is a 3-texel coloured
# core in a 1-texel frame, which is the smallest that still reads as a bordered square.
#
# TEN to a row is the whole reason the readout is countable: one full row plus four reads as 14
# without counting. Rows grow upward and the BOTTOM row fills first, so losses show along the top
# where a knocked-off cube has clearance to leave.
@export var hp_block_texels := 4.0
@export var hp_block_border_texels := 1.0
@export var hp_blocks_per_row := 10
# How far back a LOST cube sits. The dent is a second cue beside the colour, which is what makes the
# readout survive distance and the green/red confusion this palette invites.
@export var hp_block_recess_texels := 0.0
# Depth ALONE did not read as a dent (dev, 2026-08-22) — head-on, a cube pushed back is still a
# same-sized square, because there is no socket wall to see. Shrinking it pulls it away from its
# neighbours' cages, and dimming it puts it in shadow; together they are the dent.
@export var hp_block_recess_shrink := 0.65
@export var hp_block_recess_shade := 0.55
# How far the TOP face of every cube is darkened. The one thing that tells the top apart from the
# front; taking the black cage off it instead left "a green mass with black painted on" (dev).
@export var hp_block_top_shade := 0.15
# Whether the grid turns to face the camera. OFF by default (dev: "The health bars are 3D, they
# should not billboard towards the camera") — held in place it sits on the board's own axes like the
# voxel props, and goes edge-on at some yaws, which is what keeping it in place means.
@export var hp_grid_faces_camera := true
# Two FLAT colours, not a ramp (dev feel-check, 2026-08-15): the fill is what the unit HAS, and the
# missing colour what it has LOST — a cube in both cases, since the readout draws no backing for one
# to show through. Both fully opaque on purpose — this is a gameplay descriptor, meant to sit on top
# of the scene rather than blend into it.
@export var bar_fill_color := Color(0.0, 1.0, 0.2353, 1.0)
@export var bar_missing_color := Color(0.9, 0.05, 0.05, 1.0)
# The number's WORLD height in cells, NOT a font size: the glyph atlas is held at a fixed high
# resolution and this scales the quad instead, so small text stays crisp. Sizing by font_size would
# have meant a 4px font to reach the size asked for, which renders to mush.
@export var number_height_cells := 0.125
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
# #313's NOTCH is gone with #314's grid: with one cube per point, colouring the exact cubes the
# plan takes says it more precisely than a marker beside them, and both would be one fact twice.
# What the doomed cubes pulse TO when the plan predicts a named rung — a down, a kill, or Crisis.
# Only the peak is a knob: the resting colour is bar_doomed_color, so the alarm cannot drift away
# from the thing it is alarming about.
@export var alarm_peak_color := Color(1.0, 1.0, 1.0, 1.0)

# --- The cubes a unit LOSES (#314) ------------------------------------------------------
# Losing HP knocks the cubes that were standing out of the grid: they pop up and away, tumble,
# bounce once off the board and fade. Every value here is feel, so every one is a Game-tab row.
@export var block_burst_speed := 2.3
@export var block_burst_spread := 0.6      # how wide the fan is; 0 sends every cube straight up
@export var block_spin_speed := 8.5
@export var block_gravity := 7.0
@export var block_bounce := 0.45           # how much of the fall a cube keeps on the way back up
@export var block_lifetime := 2.35
# How long each cube waits before its own launch, so a multi-cube burst MARCHES through the grid
# rather than leaving all at once (dev, 2026-08-22). A waiting cube sits in its socket rather than
# hiding, so the grid breaks apart in sequence with no gap running ahead of it.
@export var block_burst_stagger := 0.04
# A DEATH detonates the whole remaining grid, harder than an ordinary hit -- the loudest thing the
# readout ever does, for the loudest thing that happens on the board.
@export var block_death_power := 1.8
# How long a healed cube takes to rise back out of its dent, and HOW FAR it travels while doing it.
# The distance is its OWN value rather than the recess depth: round 1 borrowed the dent, which made
# the pop a couple of screen pixels and exactly nothing once the dent was dialled to 0.
@export var block_pop_time := 0.54
@export var hp_pop_lift_texels := 5.0
# How long each restored cube waits before its own rise, so a heal FILLS IN rather than popping as one
# block (dev, 2026-08-22). The run rises ASCENDING -- the burst leaves descending, so a cube comes back
# the way it left, backwards. Its own value rather than block_burst_stagger's: that one races a cube's
# whole flight, this one races block_pop_time, so the same number does not mean the same thing.
@export var hp_pop_stagger := 0.08

# --- Crowding, shared by every non-hover reason (#313, widened by #350) ----------------
# Whether a bar that is up for a reason OTHER than hover also carries its number. Off by default,
# and the reason generalises past the ticket that found it: a plan can put a readout over half the
# board at once, and #350's toggle puts one over ALL of it. So the digits stay a hover reward
# either way. ONE knob rather than one per reason -- the question is how crowded this volume may
# get, and that question does not change with why a bar happens to be up.
@export var unhovered_shows_number := false

# --- The element-state row (#357) ------------------------------------------------------
# One icon per state the unit holds, just above the bar. In TEXELS, at the same pixel density as
# the bar and every sprite. Not a multiple of the bar's height: nothing ties a status icon to how
# thick the gauge happens to be.
#
# 8 is half a cell, and deliberate rather than arbitrary: both source icons are powers of two (the
# wet drop 32px, the frozen-tile placeholder 16px), so both land on exact 4:1 and 2:1 reductions.
@export var state_icon_texels := 9.0
@export var state_icon_gap_texels := 1.0        # clearance above the bar's outline
@export var state_icon_spacing_texels := 2.0    # between neighbouring icons

# --- The rescue clock beside the downed glyph (#322) ------------------------------------
# Turns left before a downed body is lost, written after the last icon in that row. WHERE it sits is
# the only knob: its size, colour and outline are all the HP digits', because the dev's legibility
# floor makes size the same kind of fact those two already were — "any number needs to be at least
# as big as the numbers in the healthbar to be readable. Smaller than that is just impossible."
# (2026-08-21). A dial whose lower half is unreadable is worse than no dial, so there isn't one; if
# this number ever wants to be BIGGER than the HP digits, that is a knob to add deliberately.
@export var downed_count_gap_texels := 1.0      # between the last icon and the digits

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

# Who the end-of-turn effect pass is about, injected the same way beside it (#534). A ResolvedPlan
# cannot answer this -- the burn phase has no plan -- so it is its own source rather than a faked
# one. Unset reads as "no pass running", the same graceful absence plan_source has.
var effect_subjects_source: Callable

var units_root: Node2D

# The elevation store (#273); pushed in by battle3d beside units_root. A unit stands on the
# SURFACE, and this is what tells it where that is — null on a board with no heights wired, which
# BoardSpace.surface_point reads as flat.
var heights: BoardHeights

var _mirrored: Dictionary[int, UnitSprite3D] = {}
var _bars: Dictionary[int, UnitHealthBar] = {}   # #229; keyed like _mirrored, never by object ref
var _ghosts: Array[UnitSprite3D] = []
var _camera_right := Vector3.ZERO   # last camera basis facing was judged against
# What each unit's HP was last frame (#314), keyed like _mirrored. Updated for EVERY live unit,
# BEFORE the readout's own visibility gate -- a baseline only refreshed while a readout is up goes
# stale the moment one hides, and the next time it appears the whole hidden loss reads as damage
# taken this frame and bursts.
var _last_hp: Dictionary[int, int] = {}
var _debris: HealthBlockDebris


func _ready() -> void:
	UnitSprite3D.texels_per_unit = texels_per_unit
	# The knocked-off cubes live HERE rather than under a readout, because they must outlive the one
	# they fell off: a readout hides the instant the pointer moves or the plan settles.
	_debris = HealthBlockDebris.new()
	add_child(_debris)


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
	# ...and who the end-of-turn effect pass is about, asked once for the same reason (#534). Empty
	# whenever no pass is running, which is nearly always.
	var marked: Dictionary[int, bool] = _effect_subjects()
	# The player's standing preference (#350), asked once for the same reason: it cannot change
	# mid-frame, and a static read per unit would be N reads answering one question.
	var always_on := PlayerSettings.is_on(PlayerSettings.Setting.ALWAYS_SHOW_HEALTH)
	_push_debris_knobs()
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
			# THE ONE SIGNAL THIS NODE LISTENS TO (#314), and the exception is structural rather
			# than a preference: die() emits and queue_free()s in the same frame, and the loop
			# above skips a unit already queued for deletion, so the poll NEVER observes HP at 0.
			# Noticing the unit vanish instead would fire on clear_board, which frees without
			# dying. Nothing else here needs a wire; this cannot be answered without one.
			unit.unit_died.connect(_on_unit_died.bind(id))
		_sync(unit, _mirrored[id])
		_sync_bar(unit, _mirrored[id], _bars[id], unit == hovered, plan, marked.has(id), always_on)
		_settle_health_change(unit, id, _bars[id])
	for id: int in _mirrored.keys():
		if not live.has(id):
			_mirrored[id].queue_free()
			_mirrored.erase(id)
			_last_hp.erase(id)
			if _bars.has(id):
				_bars[id].queue_free()
				_bars.erase(id)


func mirrored_count() -> int:
	return _mirrored.size()


func sprite_for(unit: Unit) -> UnitSprite3D:
	return _mirrored.get(unit.get_instance_id())


func bar_for(unit: Unit) -> UnitHealthBar:
	return _bars.get(unit.get_instance_id())


# The cubes currently in the air (#314). Board-wide rather than per unit, and deliberately so: a
# thrown cube has left the readout it came from and does not belong to a unit any more.
func debris() -> HealthBlockDebris:
	return _debris


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
	var stand_y := BoardSpace.surface_point(over, heights).y
	# The airborne shove (#259 rework; the fall became a BEAT of the slide in #472). While sliding,
	# height is SLAVED to the horizontal motion, never rate-limited -- the slide runs many cells a
	# second, so an eased height cannot track a ramp and reads as floating (measured, dev report).
	# Airborne holds the launch height; ground contact follows the surface plane directly under the
	# sprite (surface_height_at -- ramp-aware and continuous, so a tumble STICKS to the slope).
	#
	# There is no ramp/flat LANDING fork here any more, and its absence is the #472 fix. This used
	# to begin ground contact on any ramp landing, on the theory that a ramp's high edge meets the
	# flight level -- true only at a drop of ONE down a matching slope, which is the sole case the
	# resolver calls a slide-on. Every other ramp landing therefore snapped by the difference, in
	# one frame, halfway through the final flight segment. MovementComponent now ends the flight at
	# the edge and FALLS there, so by the time `airborne` goes false the sprite is already on the
	# surface and there is nothing left to reconcile.
	#
	# Both falls are checked BEFORE the slide: each owns the height outright while it runs, and the
	# slide branch below would otherwise haul the sprite back to the lip it is dropping past.
	if unit.movement.plummeting:
		stand_y -= unit.movement.plummet_depth * BoardSpace.CELL_SIZE
	elif unit.movement.landing_falling:
		stand_y = unit.movement.landing_fall_top \
				- unit.movement.landing_fall_depth * BoardSpace.CELL_SIZE
	elif unit.movement.sliding:
		var m := unit.movement
		if m.airborne:
			stand_y = BoardSpace.surface_point(m.slide_origin, heights).y
		else:
			stand_y = BoardSpace.surface_height_at(over, unit.position.x / PIXELS_PER_CELL,
					unit.position.y / PIXELS_PER_CELL, heights)
	var stand := Vector3(unit.position.x / PIXELS_PER_CELL,
			stand_y, unit.position.y / PIXELS_PER_CELL)
	# Half a ROW down, not half a cell (#427 slice 2): the standing point sits exactly on a row
	# boundary, and the cell wanted is the one BELOW it — dropping a whole row would name the one
	# under that.
	#
	# Taken BEFORE the tear-out offset (#521): a sprite's CELL is a board fact, and the diorama is
	# the same board somewhere else. Reading it off the displaced point would name a cell in the sky.
	sprite.cell = BoardSpace.cell_of(stand - Vector3(0.0, BoardSpace.ROW_HEIGHT * 0.5, 0.0))
	# ...and the sprite goes wherever the ground it is standing on went. The horizontal half comes
	# from PIXELS above rather than from BoardSpace, which is why the offset is added to the whole
	# placement here instead of hiding inside surface_point.
	stand += BoardSpace.staged_offset(over)
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
	# A SHOVED unit keeps the facing it had when it was hit (dev, #259 rework) -- being moved is
	# not moving, so the slide neither flips the sprite nor pollutes its facing memory.
	if not unit.movement.sliding and Vector2(step.x, step.z).length_squared() > 0.000001:
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


# The instance ids the running effect pass is about, empty when none is (#534). Typed local rather
# than a cast, because a typed Dictionary is not a cast target.
func _effect_subjects() -> Dictionary[int, bool]:
	if not effect_subjects_source.is_valid():
		return {}
	var subjects: Dictionary[int, bool] = effect_subjects_source.call()
	return subjects


# What the plan leaves this unit at, ALREADY CLAMPED for display — the raw threaded number goes
# negative on a fatal hit, and LethalityRules.displayed_hp is the one answer to what a preview shows
# for it, shared with the queue panel's own "before -> after" (#313). Drawn ONLY; the clamp flattens
# a felled unit's prediction onto the HP it already has, so it can never be asked who gets a bar
# (#354) — that question goes to the hypo, which still knows the difference.
func _predicted_hp(unit: Unit, plan: ResolvedPlan) -> int:
	return LethalityRules.displayed_hp(PlanResolver.projected_hp(unit, plan.hypo),
			PlanResolver.projected_lifecycle(unit, plan.hypo))


func _sync_bar(unit: Unit, sprite: UnitSprite3D, bar: UnitHealthBar, hovered: bool,
		plan: ResolvedPlan, marked: bool, always_on: bool) -> void:
	# Two reasons to be up (#313), and the SECOND is the whole ticket: a readout stays over a unit
	# because a plan is about to happen to it. That reaches everyone the plan touches, enemies your
	# own attack will hit included, and nobody it doesn't.
	#
	# WHO is a question about the plan and is asked of the plan (#354). It used to be "predicted
	# differs from current", which made membership a function of LIVE HP — so every bar switched
	# itself off at the instant its own hit landed, mid-pass, one at a time.
	var foretold := plan != null and PlanResolver.plan_changes(unit, plan.hypo)
	# THE gate: FOUR reasons now, ONE expression (#350). #357's state-icon row rides it structurally —
	# the icons hang off the bar — so a second visibility rule anywhere in this file is the bug.
	#
	# `marked` is the second reason again, from the other direction (#534): the end-of-turn effect
	# pass is also a thing about to happen to a unit, but it has no plan to be read out of. Without
	# it the pass panned to a unit, damaged it, and showed nothing at all for anyone who had not
	# turned "always show health bars" on — _settle_health_change skips a hidden bar, so even the
	# cubes stayed put.
	var shown := hovered or foretold or marked or always_on
	bar.set_shown(shown)
	if not shown:
		return
	bar.set_style(hp_block_texels, hp_block_border_texels, hp_blocks_per_row,
			hp_block_recess_texels, bar_fill_color,
			bar_missing_color, number_height_cells, number_outline_size, number_color,
			number_gap, number_shows_max)
	bar.set_prediction_style(bar_doomed_color, bar_heal_color, alarm_peak_color)
	bar.set_cube_style(hp_block_recess_shrink, hp_block_recess_shade, hp_block_top_shade)
	bar.set_pop(block_pop_time, hp_pop_lift_texels, hp_pop_stagger)
	bar.set_hp(unit.get_current_hp(), unit.get_max_hp())
	bar.set_number_shown(hovered or unhovered_shows_number)
	# #357: what this unit IS, in the channel #346 freed. Below the early return above, so the row
	# rides THE gate rather than growing one — and the art comes from StateIcons, which stays the
	# one answer to which icon means which state for all three surfaces that draw them.
	#
	# #322 appends the DOWNED glyph to that same row, in the same order the hover card puts it —
	# element states first, lifecycle after — because the HP the bar draws cannot tell a body from a
	# unit clinging on at 1. ONE derived value drives the glyph and the count, or the two could
	# disagree for a frame; the `> 0` clause is the hover card's own, since the clock emits 0 in the
	# instant before the body is lost.
	var downed_turns: int = unit.downed_turns_remaining if unit.is_downed() else -1
	var row: Array[Texture2D] = StateIcons.textures_for(unit.element_states)
	if downed_turns > 0:
		row.append(StateIcons.DOWNED)
	else:
		downed_turns = -1
	bar.set_state_icons(row, state_icon_texels, state_icon_gap_texels, state_icon_spacing_texels)
	bar.set_downed_turns(downed_turns, downed_count_gap_texels)
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
			bar.face(camera.global_transform.basis, hp_grid_faces_camera)


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
	# The ghost's cell, so the readout rides the diorama with the ground it is over (#521). The
	# branch above needs no offset: sprite.position already carries it.
	var ghost_cell := unit.get_projected_destination()
	return BoardSpace.surface_point(ghost_cell, heights) + BoardSpace.staged_offset(ghost_cell) + lift


# HP moving, and what the readout does about it (#314). The BASELINE is written before anything
# else, hidden readouts included — see _last_hp. Everything after it is presentation, so it is
# gated on the readout actually being up: cubes are pieces of a thing you can see, and a burst over
# a unit wearing no readout would be cubes materialising out of empty air. Damage taken with no
# readout up is #188's gap, and it wants a shake on the SPRITE, which is visible either way.
func _settle_health_change(unit: Unit, id: int, bar: UnitHealthBar) -> void:
	var current := unit.get_current_hp()
	var previous: int = _last_hp.get(id, current)
	_last_hp[id] = current
	if previous == current or not bar.visible:
		return
	if current > previous:
		bar.play_heal_from(previous)   # the restored cubes rise out of the dents they were in
		return
	_burst_lost(bar, previous, current, 1.0)


# A death detonates the WHOLE grid — the red cubes go too (dev, 2026-08-22: "On a killing hit, even
# the red blocks should fly away"). Reached by signal because nothing else can reach it: see the
# connect site in reconcile. The standing/lost split comes off the RENDERED count, so each cube
# leaves wearing what it was showing rather than what an HP number says it should have been.
func _on_unit_died(_unit: Unit, id: int) -> void:
	var bar: UnitHealthBar = _bars.get(id)
	if bar == null or not is_instance_valid(bar) or not bar.visible:
		return
	var standing := bar.filled_block_count()
	var positions: Array[Vector3] = []
	var colors := PackedColorArray()
	for step in bar.block_count():
		var index := bar.block_count() - 1 - step   # see _burst_lost: the march starts at the top right
		positions.append(bar.block_world_position(index))
		colors.append(bar_fill_color if index < standing else bar_missing_color)
	_throw(bar, positions, colors, block_death_power)


# The cubes between two HP readings, thrown from the sockets they were standing in. They leave in the
# FILL colour rather than whatever those sockets are showing now: the readout has already redrawn, so
# they read as missing — which is what they BECAME, not what left.
func _burst_lost(bar: UnitHealthBar, from: int, to: int, power: float) -> void:
	var positions: Array[Vector3] = []
	var colors := PackedColorArray()
	# DESCENDING, because the stagger launches in array order and the march starts at the TOP RIGHT
	# (dev, 2026-08-22: "the top right is the start of the healthbar... when we hit the second row,
	# right side again"). The grid fills bottom-up and left-to-right, so walking the sockets backwards
	# IS that order — top row right-to-left, then the row below. No second rule to keep in step.
	for index in range(from - 1, maxi(to, 0) - 1, -1):
		positions.append(bar.block_world_position(index))
		colors.append(bar_fill_color)
	_throw(bar, positions, colors, power)


func _throw(bar: UnitHealthBar, positions: Array[Vector3], colors: PackedColorArray,
		power: float) -> void:
	if positions.is_empty():
		return
	_debris.burst(positions, colors, bar.global_transform.basis, power, block_burst_stagger)


# Pushed once a frame rather than at build time: these are Game-tab knobs, and a value read only at
# construction is a slider that moves and does nothing (#264's born-dead slider).
func _push_debris_knobs() -> void:
	_debris.heights = heights
	_debris.burst_speed = block_burst_speed
	_debris.burst_spread = block_burst_spread
	_debris.spin_speed = block_spin_speed
	_debris.gravity = block_gravity
	_debris.bounce = block_bounce
	_debris.lifetime = block_lifetime
