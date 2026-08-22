extends Node3D
class_name UnitHealthBar

# The health readout (#229, rebuilt as blocks by #314): a grid of small cubes in the volume above a
# unit, one cube per point of HP. That volume opened up mechanically when 4c moved the selection
# icons off the cell and onto billboards; this is the first thing to occupy it DELIBERATELY.
#
# WHY BLOCKS RATHER THAN A BAR (#314). A continuous bar communicates *roughly how hurt*, which is
# the right readout for a game where the next hit's damage is a distribution. Law #1 says no
# randomness: damage here is exact and previewable, so the player wants *exactly how many points
# stand between this unit and the next rung*, and a cube per point answers that at a glance. Ten to
# a row is what makes it a glance rather than a count -- one full row plus four reads as 14 without
# counting anything.
#
# A cube is `_block` texels including a black frame `_border` texels thick, and cubes are pitched
# `_block - _border` apart so neighbours SHARE that frame. At the shipped 5/1 that is a 3-texel
# coloured core in a 1-texel black cage, and a 20 HP unit's grid is 41 x 9 texels -- barely wider
# than the 26 x 5 bar it replaces. Width is the axis to spend: the crown hangs above at
# BoardOverlays.billboard_lift and the state row stacks above the grid, so vertical growth is the
# only growth that collides with anything.
#
# THE BLACK CAGE IS WHY A CUBE READS AS A CUBE (dev, 2026-08-21: "each edge of the cube should be
# black, corner to corner. I'm thinking little green squares, with black outlines"). It is a
# generated texture -- black frame, white centre -- on all six faces, tinted per role through
# albedo_color. Black survives the tint and white takes it, so ONE texture serves green, red and
# amber alike; that is #325's ring-outline trick, not a new idea. It matters because this display
# may not be lit: see the paragraph below.
#
# GAMEPLAY DESCRIPTOR, NOT SCENERY (dev feel-check, 2026-08-15). The first pass set `shaded = false`
# and called that unlit; it is not. Unshaded only skips direct lighting, while volumetric fog, glow,
# filmic tonemap and DoF all still ran over it, which is what read as "transparent". So every
# surface here carries `disable_fog` and `disable_ambient_light`. That is also what rules out
# earning the 3D read from lighting -- a lit gauge would change with the time-of-day preset, and fog
# would wash it exactly as it did in that first pass. The cage does the job instead, and it holds
# while a knocked-off cube tumbles through every orientation.
# What remains outside our reach is whole-frame post (glow, tonemap, DoF): there is no per-object
# exemption for those, and true immunity means drawing the HUD in its own pass.
#
# THE CUBES ARE OPAQUE, and that is a change from the bar (#314). The bar's five quads were coplanar
# with no depth to separate them, so they were TRANSPARENCY_ALPHA purely to buy render_priority
# ordering -- "no transparency" was about the alpha value, not the queue. Cubes have real depth and
# sit at real distances, so they sort by DEPTH like the solid objects they are, and the priority
# ladder they needed is gone. The plate behind them and the text in front of them keep theirs.
#
# LOST HEALTH IS A RECESSED RED CUBE (dev, 2026-08-21). The grid is always a full rectangle, so max
# HP is readable from its shape; a lost cube sinks into the plate rather than vanishing, so the
# readout carries a DENT as well as a colour. That second cue is what makes it survive distance,
# peripheral vision, and the green/red confusion this palette otherwise invites.
#
# World-scaled, not screen-constant (dev, 2026-08-15): it shrinks with distance like the icons
# beside it, because it belongs to the scene rather than to the glass.
#
# Since #313 the grid also carries the PREDICTION: the exact cubes the queued plan will take wear a
# third colour -- doomed if the plan is taking HP, a heal colour on the sockets it will refill.
# #313's NOTCH is deleted, because colouring the specific cubes that go states it more precisely
# than a marker beside them, and keeping both would say one fact twice (Law #4).
#
# Since #357 it also carries the ELEMENT-STATE row: one icon per state the unit holds, sitting just
# above the grid and flush with its left edge. That is the first deliberate occupant of the channel
# #346 freed -- above the head is what this unit IS -- and it is a CHILD of this group rather than a
# display of its own precisely so it cannot grow a second visibility rule: a hidden readout hides it
# by construction, which is what #350's one-gate ruling asks for.
#
# Since #322 that row also carries the DOWNED glyph and the rescue clock beside it. The HP number
# cannot separate a body from a living unit clinging on -- a downed unit sits at exactly 1 HP
# because _go_downed puts it there, so `1/20` is two completely different board states -- and the
# fix is the row saying what the number cannot, in the same icon-then-count shape the hover card
# already uses. It rides the readout's own visibility for the same structural reason the state icons
# do; the fact that a unit is down is carried unconditionally by its downed ART, so this
# disambiguates the readout rather than being the only thing that marks the body.
#
# A dumb idempotent sink: it is TOLD a style, an HP pair and a prediction, and draws them. It never
# reads a Unit, the plan, the board or the pointer -- UnitMirror owns all of that, and owns the
# knobs too, since the Look panel can only address nodes that exist in the scene. The ONE piece of
# history it keeps is the heal pop, which is an animation and cannot be a pure function of current
# HP; it follows the same ownership discipline as the alarm.

# Not knobs: an outline exists to separate a shape from whatever is behind it, and over a board that
# can be any colour, black is the only value that does the job.
const OUTLINE_COLOR := Color.BLACK
# Glyph resolution, held high and fixed while the DISPLAYED size rides pixel_size instead. Sizing
# text by font_size would have meant a 4px font to hit the size the dev asked for, which renders to
# mush; sizing by pixel_size keeps the atlas crisp and shrinks the quad.
const FONT_RESOLUTION := 32
# Which entry of the face list in _build_cube_mesh is +Y. Named because two places read it and a
# bare 4 in either is a magic number nobody could check.
const TOP_FACE := 4

# The cube and its cage, built ONCE and shared by every block of every readout on the board. Static
# because they are a pure function of knobs pushed identically to every readout -- a mesh and a
# texture per unit would be N copies of one answer. Rebuilt only when those knobs change, which is a
# knob drag, not a frame.
static var _cube_mesh: ArrayMesh
static var _cage_texture: ImageTexture
static var _cube_key := Vector4i(-1, -1, -1, -1)

var _plate: MeshInstance3D                       # what the cubes sit on and recess into
var _blocks: Array[MeshInstance3D] = []          # one per point of MAX hp; pooled, hidden not freed
# One material per ROLE rather than one per cube: every cube of a role is the same colour, so three
# materials answer what N would. Per READOUT rather than static, because the alarm pulses the doomed
# one and a shared material would pulse it over every unit on the board, alarmed or not.
var _mat_fill: StandardMaterial3D
var _mat_missing: StandardMaterial3D
# The two directions of a prediction are two MATERIALS rather than one that swaps colour, because
# they say opposite things about the cube wearing them: a doomed cube is STANDING and about to go,
# a heal-marked one is an empty socket about to be refilled. One material could not tell the two
# apart, and every rendered count below would then have to guess the direction — or read depth,
# which the recess knob is allowed to set to zero.
var _mat_doomed: StandardMaterial3D
var _mat_heal: StandardMaterial3D
var _label: Label3D
# #357: the element-state row above the grid. A POOL, grown on demand and hidden rather than freed --
# the same contract UnitMirror.set_ghosts and BoardOverlays use, for the same reason: the count
# changes every time a state lands or expires.
var _state_icons: Array[MeshInstance3D] = []
# #322: the rescue clock's digits, sitting after the last icon in that row. Its own Label3D rather
# than more text on _label -- that one reads the HP and sits ON the grid, this one belongs to the row
# above it, so they are placed by different rules even though they are drawn at one size.
var _count: Label3D

var _block := 5.0
var _border := 1.0
var _per_row := 10
var _recess := 2.0
var _recess_shrink := 0.7
var _recess_shade := 0.55
var _top_shade := 0.7
var _outline_texels := 1.0
var _fill_color := Color(0.15, 1.0, 0.2, 1.0)
var _missing_color := Color(0.9, 0.05, 0.05, 1.0)
var _number_height := 0.13
var _number_outline := 6.0
var _number_color := Color.WHITE
var _gap := 0.04
var _shows_max := true
var _current := 0
var _maximum := 1

var _doomed_color := Color(1.0, 0.75, 0.1, 1.0)
var _heal_color := Color(0.4, 0.9, 1.0, 1.0)
var _alarm_peak_color := Color(1.0, 1.0, 1.0, 1.0)
var _predicted := 0
var _has_prediction := false
var _number_shown := true
var _state_textures: Array[Texture2D] = []
var _state_icon_texels := 8.0
var _state_gap_texels := 2.0
var _state_spacing_texels := 1.0
var _downed_turns := -1          # #322; -1 = not downed, which is a different answer from 0
var _count_gap_texels := 1.0

var _alarm: Tween
var _alarm_peak_live := Color(1.0, 1.0, 1.0, 1.0)   # the peak the RUNNING tween was started with
# Every input the drawing reads, snapshotted (#313). UnitMirror pushes style, HP and prediction
# every frame for every SHOWN readout, and a redraw re-places the whole grid and measures the
# label's AABB -- fine for the single hovered readout #229 shipped, N times a frame once a plan puts
# one over everybody. It is also what lets the alarm own the doomed colour: an unguarded redraw
# repainted over the tween sixty times a second. Same value-diff-before-push idiom OverlayMirror
# uses.
var _drawn: Array = []

# The heal pop (#314). Restored cubes rise out of the dent they were sitting in rather than
# appearing already proud -- the socket is their natural origin, so nothing has to be invented for
# them to arrive from. _pop_from is the first index of the run that is rising; _pop_phase is driven
# by a tween, and a redraw writes the TARGET only and never the phase, which is the same ownership
# rule alarm_color follows so the redraw cannot stomp the animation.
var _pop_from := -1
var _pop_tween: Tween
var _pop_time := 0.18
var _pop_lift := 3.0
var _pop_phase := 1.0:
	set(value):
		_pop_phase = value
		_place_blocks()


# The pulsing colour of the doomed cubes (#313). Written by the alarm TWEEN rather than by the tween
# writing a material directly, so one place owns albedo and the pulse never becomes a second owner
# of it -- the rule a live pulse already follows for sprite.modulate.
var alarm_color := Color.WHITE:
	set(value):
		alarm_color = value
		if _mat_doomed != null:
			_mat_doomed.albedo_color = value


func _init() -> void:
	# The plate stays a coplanar alpha quad on the old priority ladder: it has no depth of its own,
	# and the cubes standing in front of it do the sorting.
	_plate = _make_quad(BoardOverlays.UNIT_HUD_RENDER_PRIORITY)
	_mat_fill = _make_block_material()
	_mat_missing = _make_block_material()
	_mat_doomed = _make_block_material()
	_mat_heal = _make_block_material()
	# Text draws in FRONT of cubes that now stand proud of the plate, so its priority sits above the
	# whole grid and _text_z pushes it clear in Z as well.
	_label = _make_label(BoardOverlays.UNIT_HUD_RENDER_PRIORITY + 6)
	_count = _make_label(BoardOverlays.UNIT_HUD_RENDER_PRIORITY + 6)
	add_child(_plate)
	add_child(_label)
	add_child(_count)
	visible = false
	_rebuild()


# The knob values, pushed by UnitMirror. Explicit parameters rather than public fields because this
# is one call site and a signature is what keeps it typed end to end. The PREDICTION's own knobs sit
# in their own setter below rather than growing this one past the point a call site can be read.
func set_style(block: float, border: float, per_row: int, recess: float, outline: float,
		fill: Color, missing: Color, number_height: float, number_outline: float,
		number_color: Color, gap: float, shows_max: bool) -> void:
	_block = block
	_border = border
	_per_row = per_row
	_recess = recess
	_outline_texels = outline
	_fill_color = fill
	_missing_color = missing
	_number_height = number_height
	_number_outline = number_outline
	_number_color = number_color
	_gap = gap
	_shows_max = shows_max
	_rebuild()


func set_prediction_style(doomed: Color, heal: Color, alarm_peak: Color) -> void:
	_doomed_color = doomed
	_heal_color = heal
	_alarm_peak_color = alarm_peak
	_rebuild()


# How long a restored cube takes to rise out of its socket, and HOW FAR it travels. The distance is
# the round-2 addition and it is not optional: borrowing the recess made the pop vanish whenever the
# recess was dialled to 0. See _z_for.
func set_pop(seconds: float, lift_texels: float) -> void:
	_pop_time = seconds
	_pop_lift = lift_texels


# What a cube looks like beyond its colour: how far a SUNK one shrinks and dims, and how far the
# TOP face of any of them is darkened.
func set_cube_style(recess_shrink: float, recess_shade: float, top_shade: float) -> void:
	_recess_shrink = recess_shrink
	_recess_shade = recess_shade
	_top_shade = top_shade
	_rebuild()


func _shaded(color: Color) -> Color:
	var shade: float = maxf(_recess_shade, 0.0)
	return Color(color.r * shade, color.g * shade, color.b * shade, color.a)


func set_hp(current: int, maximum: int) -> void:
	_current = current
	_maximum = maximum
	_rebuild()


# HP going UP, with the pop played (#314). Separate from set_hp because a readout can arrive at a
# higher number for reasons that are not a heal -- coming back on screen, a max-HP change, a
# scenario load -- and only UnitMirror can tell those apart. It owns the diff; this owns the
# animation.
func play_heal_from(previous: int) -> void:
	if previous >= _current:
		return
	_pop_from = previous
	if _pop_tween != null:
		_pop_tween.kill()
	_pop_phase = 0.0
	_pop_tween = create_tween()
	_pop_tween.tween_property(self, ^"_pop_phase", 1.0, maxf(_pop_time, 0.001))


# What the queued plan leaves this unit at (#313), already run through the display clamp -- this node
# never sees a raw resolver number. `alarm` raises the pulse for a predicted DOWN or KILL.
func set_prediction(predicted: int, alarm: bool) -> void:
	_predicted = predicted
	_has_prediction = true
	_rebuild()
	set_alarm(alarm)


func clear_prediction() -> void:
	if not _has_prediction:
		return
	_has_prediction = false
	_rebuild()
	set_alarm(false)


# Crowding, not styling: an unhovered ghost is grid-only by default, and hovering it reveals the
# number. Two reasons to be up (#313), so the number follows the reason rather than the readout.
func set_number_shown(shown: bool) -> void:
	_number_shown = shown
	_rebuild()


# The element-state row (#357). Textures only: StateIcons stays the one answer to which art means
# which state, and this node keeps reading no game state at all.
#
# The array is DUPLICATED on the way in because it joins the _drawn signature. That signature holds
# a reference, so a caller reusing one buffer across frames would mutate the very thing the redraw
# gate compares against and the row would freeze on whatever it drew first.
func set_state_icons(textures: Array[Texture2D], size_texels: float, gap_texels: float,
		spacing_texels: float) -> void:
	_state_textures = textures.duplicate()
	_state_icon_texels = size_texels
	_state_gap_texels = gap_texels
	_state_spacing_texels = spacing_texels
	_rebuild()


# The rescue clock (#322): turns left before this body is lost, or -1 for a unit that is not down.
# The GLYPH beside it arrives through set_state_icons like any other status art -- one row, one
# layout -- so this setter carries only the number and where it sits. How BIG it is comes off the HP
# digits and is not tunable apart from them; see _draw_downed_count.
func set_downed_turns(turns: int, gap_texels: float) -> void:
	_downed_turns = turns
	_count_gap_texels = gap_texels
	_rebuild()


func set_shown(shown: bool) -> void:
	visible = shown
	if not shown:
		set_alarm(false)   # a tween on a hidden readout is invisible work, and outlives what raised it


# Idempotent because it is TOLD every frame: start once, stop once. Pulse.stop writes the base value
# back through alarm_color's setter, so the cubes land on their resting colour with no extra paint.
# A tween carries the peak it STARTED with, so a peak retuned mid-pulse restarts it -- a Look knob
# that only lands at the next alarm reads as a dead slider.
func set_alarm(on: bool) -> void:
	if on and _alarm != null and _alarm_peak_live != _alarm_peak_color:
		_stop_alarm()
	if on == (_alarm != null):
		return
	if on:
		# The RESTING colour is always the doomed one: an alarm is raised for a predicted down, kill
		# or Crisis, and none of those is something a heal can predict.
		alarm_color = _doomed_color
		_alarm_peak_live = _alarm_peak_color
		_alarm = Pulse.start(self, self, &"alarm_color", _doomed_color, _alarm_peak_color)
	else:
		_stop_alarm()


func _stop_alarm() -> void:
	Pulse.stop(_alarm, self, &"alarm_color", _doomed_color)
	_alarm = null


# Turn the WHOLE readout to face the camera, once, instead of letting each part billboard itself.
# Per-object billboarding is what pulled this display apart: each element rebuilds its own basis
# about its own origin, so any displacement written in world space shears as the camera orbits, and
# the only displacement that does not -- an in-plane offset -- is not honoured identically by every
# element (Label3D moves its glyphs and its outline by different amounts). Rotating the parent makes
# every child's ordinary local position correct by construction, at any angle. With #314's cubes it
# does more than that: a real Z offset is only meaningful because one rotation owns the whole group,
# and proud-versus-recessed IS a Z offset.
#
# Yaw only, and it must MATCH BILLBOARD_FIXED_Y rather than merely resemble it (#325 follow-up).
# FIXED_Y aligns a sprite to the VIEW PLANE, one yaw board-wide; pointing each readout at the camera
# POSITION instead gives a slightly different angle per unit, agreeing only at screen centre --
# which read as the crown and the readout sitting on visibly different axes. Every sprite in this
# stack is FIXED_Y, UnitSprite3D included, so the READOUT is what moves: the unit art is the anchor
# anything hung on it must agree with. Camera basis +Z is the direction FIXED_Y faces.
#
# FACING THE CAMERA IS NOW OPTIONAL (dev, 2026-08-22: "The health bars are 3D, they should not
# billboard towards the camera. Let's add an option to keep them in place."). Held in place, the grid
# sits on the board's own axes like the voxel props do, and orbiting past it edge-on turns it into a
# thin line -- that is what keeping it in place MEANS, not a bug. Everything above still applies to
# the facing mode; nothing here billboards per element either way.
func face(camera_basis: Basis, faces_camera: bool) -> void:
	if not faces_camera:
		global_rotation = Vector3.ZERO
		return
	var facing := camera_basis.z
	if absf(facing.x) < 0.0001 and absf(facing.z) < 0.0001:
		return   # camera straight overhead: any yaw is as good as another, so keep the last one
	global_rotation = Vector3(0.0, atan2(facing.x, facing.z), 0.0)


# ==============================================================================
#  Rendered facts
#
#  Every accessor below reads what is DRAWN, never the value it was told, so a test can catch a
#  readout that agrees with itself and not with the unit.
# ==============================================================================

# How many sockets exist, which is max HP.
func block_count() -> int:
	var count := 0
	for block: MeshInstance3D in _blocks:
		if block.visible:
			count += 1
	return count


# How many cubes the readout is claiming, which is current HP. Read off the MATERIAL rather than off
# the depth: a doomed cube is still one the unit has, and the recess knob may legitimately be zero,
# which would leave a depth reading unable to answer at all.
func filled_block_count() -> int:
	var count := 0
	for block: MeshInstance3D in _blocks:
		if block.visible and (block.material_override == _mat_fill
				or block.material_override == _mat_doomed):
			count += 1
	return count


# The prediction's span, in either direction — cubes the plan takes plus sockets it refills.
func doomed_block_count() -> int:
	var count := 0
	for block: MeshInstance3D in _blocks:
		if block.visible and (block.material_override == _mat_doomed
				or block.material_override == _mat_heal):
			count += 1
	return count


# Whether this socket is OCCUPIED, read off the material. The knob-independent twin of
# block_is_proud, which asks the DEPTH question and cannot answer at all once the recess is dialled
# to 0 — its two depths become one. Anything about which sockets are full wants this one.
func block_is_filled(index: int) -> bool:
	if index < 0 or index >= _blocks.size():
		return false
	var material := _blocks[index].material_override
	return material == _mat_fill or material == _mat_doomed


func block_is_proud(index: int) -> bool:
	if index < 0 or index >= _blocks.size():
		return false
	return _blocks[index].position.z > _proud_z() - _texel() * 0.5


# Where a socket sits in WORLD space -- what the debris pool needs to spawn a cube exactly where the
# one that left had been standing.
func block_world_position(index: int) -> Vector3:
	if index < 0 or index >= _blocks.size():
		return global_position
	return _blocks[index].global_position


# A socket's depth in the readout's own space, and the plate's. Both local, so they can be compared
# without the group's yaw entering into it.
func block_depth(index: int) -> float:
	if index < 0 or index >= _blocks.size():
		return 0.0
	return _blocks[index].position.z


func plate_depth() -> float:
	return _plate.position.z


func block_size_texels() -> float:
	return maxf(roundf(_block), 1.0)


# The grid's own extent in texels, which is what the state row and the plate lay out against.
func stack_size_texels() -> Vector2:
	var block := block_size_texels()
	var pitch := _pitch_texels()
	var safe_max := maxi(1, _maximum)
	var per_row: int = maxi(1, _per_row)
	var cols: int = mini(safe_max, per_row)
	var rows: int = ceili(float(safe_max) / float(per_row))
	return Vector2(float(cols - 1) * pitch + block, float(rows - 1) * pitch + block)


# What fraction of the grid is still standing. Derived from the cube counts rather than kept
# alongside them, so it cannot disagree with what block_count and filled_block_count report.
func fill_fraction() -> float:
	var total := block_count()
	if total <= 0:
		return 0.0
	return float(filled_block_count()) / float(total)


# How much of the grid the plan is about to take (or give back), rendered.
func doomed_fraction() -> float:
	var total := block_count()
	if total <= 0:
		return 0.0
	return float(doomed_block_count()) / float(total)


func alarm_running() -> bool:
	return _alarm != null


# The state row's rendered facts (#357), read off the meshes like every accessor above. The count is
# of SHOWN slots, not pooled ones: the pool only ever grows, so its size answers a different
# question than "how many states is this unit wearing".
func state_icon_count() -> int:
	var count := 0
	for quad: MeshInstance3D in _state_icons:
		if quad.visible:
			count += 1
	return count


func state_icon_size() -> Vector2:
	if _state_icons.is_empty():
		return Vector2.ZERO
	return (_state_icons[0].mesh as QuadMesh).size


func state_icon_offset(index: int) -> Vector3:
	return (_state_icons[index].mesh as QuadMesh).center_offset


# The rescue clock's rendered facts (#322), same contract as the accessors above. Shown-ness is its
# own question because a readout can be up over a unit that is not down.
func downed_count_text() -> String:
	return _count.text


func downed_count_shown() -> bool:
	return _count.visible


func downed_count_offset() -> Vector3:
	return _count.position


# Rendered glyph height, in world units, for each of the two texts -- pixel_size times the atlas
# resolution, which is what actually reaches the screen. They exist so a law can hold the dev's own
# floor (#322 round 2: a number smaller than the HP digits is unreadable) as a RELATIONSHIP, without
# any test naming a value that retuning could move.
func number_glyph_height() -> float:
	return _label.pixel_size * float(FONT_RESOLUTION)


func downed_count_glyph_height() -> float:
	return _count.pixel_size * float(FONT_RESOLUTION)


func track_texels() -> float:
	return stack_size_texels().x


func number_text() -> String:
	return _label.text


# Whether the digits are up, as opposed to what they SAY. A separate question since #350: a readout
# can be up for three reasons now and only one of them earns the number.
func number_shown() -> bool:
	return _label.visible


# ==============================================================================
#  Drawing
# ==============================================================================

func _rebuild() -> void:
	var signature: Array = [_block, _border, _per_row, _recess, _recess_shrink, _recess_shade, _top_shade,
			_outline_texels, _fill_color, _missing_color,
			_number_height, _number_outline, _number_color, _gap, _shows_max, _number_shown,
			_doomed_color, _heal_color,
			_current, _maximum, _predicted, _has_prediction,
			_state_textures, _state_icon_texels, _state_gap_texels, _state_spacing_texels,
			_downed_turns, _count_gap_texels]
	if signature == _drawn:
		return
	_drawn = signature
	_draw()


func _draw() -> void:
	var texel := _texel()
	var block := block_size_texels()
	var edge: float = maxf(roundf(_outline_texels), 0.0)
	var stack := stack_size_texels()
	var safe_max := maxi(1, _maximum)

	_ensure_cube(int(block), int(maxf(roundf(_border), 0.0)), texel, _top_shade)
	_paint_materials()

	# The plate the cubes sit on and sink into. Full bounding box of the grid, so a unit whose top
	# row is partial still wears a rectangle rather than an L.
	_size_quad(_plate, (stack.x + edge * 2.0) * texel, (stack.y + edge * 2.0) * texel, 0.0)
	(_plate.material_override as StandardMaterial3D).albedo_color = OUTLINE_COLOR
	# BEHIND the deepest face any cube can present, never at z 0 — the plate sat exactly on the back
	# faces of the cubes at a recess of 0, and coplanar black against green is what the dev saw
	# z-fighting from behind (2026-08-22). Derived from the cube depth so it cannot drift with the
	# size knob.
	_plate.position.z = _recessed_z() - (block * 0.5 + 1.0) * texel

	while _blocks.size() < safe_max:
		var cube := MeshInstance3D.new()
		cube.layers = BoardOverlays.UNIT_RENDER_LAYER
		cube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cube)
		_blocks.append(cube)
	# Occupancy, NOT visibility: extras are parked rather than freed, and the readout's own visible
	# flag is what decides whether any of this is seen.
	for i in _blocks.size():
		var cube: MeshInstance3D = _blocks[i]
		cube.visible = i < safe_max
		if not cube.visible:
			continue
		cube.mesh = _cube_mesh
		cube.material_override = _material_for(i)
	_place_blocks()

	_label.visible = _number_shown
	if _shows_max:
		_label.text = "%d/%d" % [clampi(_current, 0, safe_max), safe_max]
	else:
		_label.text = str(clampi(_current, 0, safe_max))
	_label.pixel_size = maxf(_number_height, 0.001) / float(FONT_RESOLUTION)
	_label.outline_size = roundi(_number_outline)
	_label.modulate = _number_color
	# Sits ON the grid, inset from its left edge, in the parent's local space. get_aabb() is read for
	# the text's WIDTH only, which does not depend on where the label sits, so this cannot feed back
	# on itself frame to frame; the digit count changes with the HP, which is why it is measured
	# rather than assumed. Z clears the PROUD face of a cube rather than the plate, because the cubes
	# now stand in front of it.
	var half_text: float = _label.get_aabb().size.x * 0.5
	_label.position = Vector3(-stack.x * 0.5 * texel + _gap + half_text, 0.0, _text_z())

	_draw_state_row(texel, stack, edge)


# Which role a socket is wearing. ONE derivation, read by both the material assignment and the
# proud/recessed placement, so the colour and the depth can never disagree about a cube.
func _material_for(index: int) -> StandardMaterial3D:
	var safe_max := maxi(1, _maximum)
	var shown := clampi(_current, 0, safe_max)
	if _has_prediction:
		var predicted := clampi(_predicted, 0, safe_max)
		# The span between where the grid is now and where the plan leaves it -- the same two bounds
		# say "this much is coming off" and "this much is coming back", and the colour is what names
		# the direction, because the geometry cannot.
		if index >= mini(shown, predicted) and index < maxi(shown, predicted):
			return _mat_heal if predicted > shown else _mat_doomed
	return _mat_fill if index < shown else _mat_missing


# Where every cube stands. Split out of _draw because the heal pop drives it every frame while
# nothing else about the drawing changes -- and because a redraw must be able to re-place cubes
# without disturbing a running pop.
func _place_blocks() -> void:
	if _blocks.is_empty():
		return
	var texel := _texel()
	var block := block_size_texels()
	var pitch := _pitch_texels()
	var stack := stack_size_texels()
	var safe_max := maxi(1, _maximum)
	var shown := clampi(_current, 0, safe_max)
	var per_row: int = maxi(1, _per_row)
	var left: float = -stack.x * 0.5 + block * 0.5
	var bottom: float = -stack.y * 0.5 + block * 0.5
	for i in _blocks.size():
		var cube: MeshInstance3D = _blocks[i]
		if not cube.visible:
			continue
		# Row 0 is the BOTTOM row and fills first, so losses show in the top row -- which is where a
		# knocked-off cube has clearance to leave from.
		@warning_ignore("integer_division")
		var row: int = i / per_row
		var col: int = i % per_row
		cube.position = Vector3(
				(left + float(col) * pitch) * texel,
				(bottom + float(row) * pitch) * texel,
				_z_for(i, shown))
		# SHRINKING is what actually reads as a hole (dev, 2026-08-22). Depth alone did not: a cube
		# pushed back is still a same-sized square head-on, because there is no socket WALL to see --
		# shrunk, the plate shows around its edges and the dent is legible at play distance.
		cube.scale = Vector3.ONE * lerpf(1.0, maxf(_recess_shrink, 0.05), _sunk_fraction(i, shown))


# How far INTO the plate this socket is: 1 while empty, 0 while occupied, and easing between the two
# while a heal pop plays. Read by the scale; the depth has its own curve because it carries the pop's
# overshoot and the scale should not bulge.
func _sunk_fraction(index: int, shown: int) -> float:
	if index >= shown:
		return 1.0
	if _pop_from < 0 or index < _pop_from or _pop_phase >= 1.0:
		return 0.0
	return 1.0 - _pop_ease()


# Proud if the cube is there, recessed if the socket is empty -- and mid-rise while a heal pop is
# playing over the run that is arriving. The overshoot is what makes it read as popping rather than
# sliding; it is deliberately not a knob, because a pop with no overshoot is just the target value.
#
# THE POP HAS ITS OWN TRAVEL, and that is the round-2 fix. It borrowed the RECESS as its amplitude,
# which made it a couple of screen pixels at the shipped depth and EXACTLY ZERO once the depth was
# dialled to 0 -- so the dev saw an instant pop however he set the time (2026-08-22). A knob that may
# legitimately be zero must never be an animation's distance.
func _z_for(index: int, shown: int) -> float:
	if index >= shown:
		return _recessed_z()
	if _pop_from < 0 or index < _pop_from or _pop_phase >= 1.0:
		return _proud_z()
	var lift: float = maxf(_pop_lift, 0.0) * _texel()
	var overshoot: float = sin(clampf(_pop_phase, 0.0, 1.0) * PI) * 0.35
	return _proud_z() - lift * (1.0 - _pop_ease()) + lift * overshoot


func _pop_ease() -> float:
	return 1.0 - pow(1.0 - clampf(_pop_phase, 0.0, 1.0), 3.0)


# The cube's CENTRE, which is half a block short of the face you can see.
func _proud_z() -> float:
	return block_size_texels() * 0.5 * _texel()


func _recessed_z() -> float:
	return (block_size_texels() * 0.5 - maxf(_recess, 0.0)) * _texel()


# Clear of the cube's FRONT FACE, never its centre. _proud_z is where a cube's MIDDLE sits, so the
# solid reaches half a block further toward the camera -- and since the cubes are opaque and write
# depth, text placed at the centre is buried inside one and depth-rejected. That is exactly how the
# HP digits shipped invisible in round 1 (dev, 2026-08-22: "no matter what my settings are, I can't
# see the numbers"), and no knob could have rescued it.
func _text_z() -> float:
	return (block_size_texels() + 1.0) * _texel()


# Cubes SHARE their black frame: pitching them a full block apart would put two frames between
# neighbouring cores and read as a gap rather than as a grid.
func _pitch_texels() -> float:
	return maxf(block_size_texels() - maxf(roundf(_border), 0.0), 1.0)


func _paint_materials() -> void:
	_mat_fill.albedo_color = _fill_color
	# DARKENED as well as sunk (dev, 2026-08-22). A shade MULTIPLIER on the authored colour rather
	# than a second colour knob -- at 1.0 it is exactly bar_missing_color, so this modifies one answer
	# instead of becoming a rival to it. HEAL sockets are deliberately NOT shaded: they are marked to
	# be seen, and dimming them fights the only thing they are for.
	_mat_missing.albedo_color = _shaded(_missing_color)
	_mat_heal.albedo_color = _heal_color
	for material: StandardMaterial3D in [_mat_fill, _mat_missing, _mat_doomed, _mat_heal]:
		material.albedo_texture = _cage_texture
	# The alarm owns the doomed colour while it runs; otherwise the resting one. Reading alarm_color
	# here rather than skipping the paint keeps one writer either way.
	_mat_doomed.albedo_color = alarm_color if _alarm != null else _doomed_color


# The element-state row (#357): square icons ABOVE the grid, the first one flush with the plate's
# left edge and the rest growing rightward. Sized in texels rather than as a multiple of the grid's
# height: nothing ties a status icon to how tall the gauge happens to be, and the two want to be
# tunable apart.
#
# Local space again, and that is the whole reason this lives inside the group: face() turns the
# parent, so an offset written here is a real offset at every camera angle.
func _draw_state_row(texel: float, stack: Vector2, edge: float) -> void:
	while _state_icons.size() < _state_textures.size():
		var quad := _make_quad(BoardOverlays.UNIT_HUD_RENDER_PRIORITY + 6)
		var fresh := quad.material_override as StandardMaterial3D
		fresh.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # pixel art, like every sprite in this stack
		add_child(quad)
		_state_icons.append(quad)
	var icon: float = maxf(roundf(_state_icon_texels), 1.0)
	var gap: float = maxf(roundf(_state_gap_texels), 0.0)
	var spacing: float = maxf(roundf(_state_spacing_texels), 0.0)
	# Clear of the plate's TOP edge, and flush with its LEFT one, so the row and the gauge share a
	# left margin rather than each finding its own.
	var row_y: float = (stack.y * 0.5 + edge + gap + icon * 0.5) * texel
	var left: float = -(stack.x * 0.5 + edge)
	for i in _state_icons.size():
		var quad: MeshInstance3D = _state_icons[i]
		quad.visible = i < _state_textures.size()
		if not quad.visible:
			continue
		_size_quad(quad, icon * texel, icon * texel,
				(left + icon * 0.5 + float(i) * (icon + spacing)) * texel, row_y)
		quad.position.z = _text_z()
		var material := quad.material_override as StandardMaterial3D
		material.albedo_texture = _state_textures[i]
		material.albedo_color = Color.WHITE
	_draw_downed_count(texel, left, icon, spacing, row_y)


# The rescue clock (#322): how many turns this body has before it is lost, written after the last
# icon in the row above. It reads as a COUNT ON the downed glyph rather than as a second readout,
# which is the whole reason it goes in this row instead of beside the HP digits -- the hover card
# already spells it exactly this way, icon then number.
#
# It carries no lifecycle logic. UnitMirror decides who is downed and hands the turns down; -1 here
# means only "no count", the same way _has_prediction means only "no prediction".
func _draw_downed_count(texel: float, left: float, icon: float, spacing: float, row_y: float) -> void:
	_count.visible = _downed_turns >= 0
	if not _count.visible:
		return
	_count.text = str(_downed_turns)
	# SIZE, outline and colour all come off the HP digits, and none of them is a knob of its own:
	# two texts on one display agree by construction rather than by a value somebody keeps in step.
	# Size joined them in round 2 (dev, 2026-08-21) -- "any number needs to be at least as big as the
	# numbers in the healthbar to be readable. Smaller than that is just impossible." A knob whose
	# whole lower half is unreadable is not a knob, so there is nothing here to drag.
	_count.pixel_size = maxf(_number_height, 0.001) / float(FONT_RESOLUTION)
	_count.outline_size = roundi(_number_outline)
	_count.modulate = _number_color
	# Where the icons END, in texels -- n icons and the n-1 gaps between them, measured off the same
	# left margin they lay out from. An empty row collapses to that margin, so the count still has a
	# home if this readout is ever told a clock with no glyph beside it.
	var shown := _state_textures.size()
	var row_right: float = left
	if shown > 0:
		row_right = left + float(shown) * icon + float(shown - 1) * spacing
	var gap: float = maxf(roundf(_count_gap_texels), 0.0)
	var half_text: float = _count.get_aabb().size.x * 0.5
	_count.position = Vector3((row_right + gap) * texel + half_text, row_y, _text_z())


# ==============================================================================
#  The cube and its cage
# ==============================================================================

# Rebuilt only when the knobs that shape it move. The KEY carries the world size too, because
# texels_per_unit is itself a dial (#250) and a mesh built at the old density would be silently the
# wrong size.
static func _ensure_cube(block: int, border: int, texel: float, top_shade: float) -> void:
	var key := Vector4i(block, border, roundi(texel * 100000.0), roundi(top_shade * 1000.0))
	if _cube_mesh != null and _cube_key == key:
		return
	_cube_key = key
	_cage_texture = _build_cage_texture(block, border)
	_cube_mesh = _build_cube_mesh(float(block) * texel, top_shade)


# Black frame, white centre. White takes the tint and black survives it, so this one image is the
# cage for every colour a cube can wear -- #325's ring-outline trick, one shelf along.
static func _build_cage_texture(block: int, border: int) -> ImageTexture:
	var side: int = maxi(block, 1)
	var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	var inner: int = side - maxi(border, 0) * 2
	if inner > 0:
		image.fill_rect(Rect2i(border, border, inner, inner), Color.WHITE)
	return ImageTexture.create_from_image(image)


# Six quads with their own full-range UVs, rather than a BoxMesh: BoxMesh lays its faces out across
# one shared UV span, so a cage texture on it would stretch across the box instead of framing each
# face. Built the way BoardOverlays builds its bracket -- an ArrayMesh from explicit arrays.
#
# EVERY face wears the cage, and the TOP is darkened by a vertex COLOUR instead (dev, 2026-08-22:
# taking the cage off the other five left "a green mass with black painted on" -- the cage is what
# makes a cube read as a cube, and only the top needed telling apart). With
# vertex_color_use_as_albedo, albedo is `albedo_color x texture x vertex colour`, so the black frame
# stays black at any shade (zero times anything) and only the coloured core dims. It is the one way
# to get a per-face tint from ONE mesh and ONE material; a second surface would double the draw
# calls on every cube of every grid.
static func _build_cube_mesh(size: float, top_shade: float) -> ArrayMesh:
	var h := size * 0.5
	var faces: Array[Array] = [
		[Vector3(-h, -h, h), Vector3(h, -h, h), Vector3(h, h, h), Vector3(-h, h, h)],       # +Z
		[Vector3(h, -h, -h), Vector3(-h, -h, -h), Vector3(-h, h, -h), Vector3(h, h, -h)],   # -Z
		[Vector3(h, -h, h), Vector3(h, -h, -h), Vector3(h, h, -h), Vector3(h, h, h)],       # +X
		[Vector3(-h, -h, -h), Vector3(-h, -h, h), Vector3(-h, h, h), Vector3(-h, h, -h)],   # -X
		[Vector3(-h, h, h), Vector3(h, h, h), Vector3(h, h, -h), Vector3(-h, h, -h)],       # +Y
		[Vector3(-h, -h, -h), Vector3(h, -h, -h), Vector3(h, -h, h), Vector3(-h, -h, h)],   # -Y
	]
	var corners: Array[Vector2] = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var shade: float = maxf(top_shade, 0.0)
	for f in faces.size():
		var face: Array = faces[f]
		var base := vertices.size()
		# Face 4 is +Y, the top -- the one that was reading as a squashed extra row of cells. It is the
		# ONLY face that differs, and it differs by shade rather than by losing its frame.
		var tint := Color(shade, shade, shade) if f == TOP_FACE else Color.WHITE
		for c in 4:
			vertices.append(face[c] as Vector3)
			uvs.append(corners[c])
			colors.append(tint)
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# The cage and the cube, for anything that needs to draw one of its own -- the debris pool builds
# its own materials but must wear the same cage, or a knocked-off cube would stop matching the
# socket it came out of. Callers ask AFTER a readout has drawn; null means nothing has yet.
static func cage_texture() -> ImageTexture:
	return _cage_texture


static func cube_mesh() -> ArrayMesh:
	return _cube_mesh


# The shared cube's edge in WORLD units. Read off the key the mesh was BUILT from rather than off
# the live knob, so a caller sizing itself against a cube can never be a frame ahead of the mesh.
static func cube_world_size() -> float:
	if _cube_mesh == null:
		return 0.0
	return float(_cube_key.x) / UnitSprite3D.texels_per_unit


# OPAQUE, unlike everything else in this display: a cube has real depth, so it sorts by distance the
# way a solid object should and needs none of the priority ladder the coplanar quads live on.
static func _make_block_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED   # winding-proof; a solid cube hides its own back faces anyway
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# What lets the mesh darken the TOP face without a second material: albedo becomes
	# `albedo_color x texture x vertex colour`, so the cage's black survives any shade.
	material.vertex_color_use_as_albedo = true
	# The half of "not affected by lighting" that IS reachable per-object. Unshaded already skips
	# direct light; without these two the volumetric fog still washes the readout toward the fog
	# albedo, which is exactly what the 2026-08-15 first pass looked like.
	material.disable_fog = true
	material.disable_ambient_light = true
	material.disable_receive_shadows = true
	return material


func _size_quad(quad: MeshInstance3D, width: float, height: float, offset_x: float,
		offset_y := 0.0) -> void:
	var mesh := quad.mesh as QuadMesh
	mesh.size = Vector2(width, height)
	mesh.center_offset = Vector3(offset_x, offset_y, 0.0)


# Every text in this display, built one way. NOT billboarded, like everything else here -- face()
# turns the whole group instead. Label3D draws its glyphs and its outline as two surfaces, and
# displacing it with Label3D.offset (the only in-plane displacement a per-object billboard permits)
# moved them by different amounts, which is what the dev saw as the number "appearing double and
# overlapping" (2026-08-15). The OUTLINE draws one priority below the glyphs it backs.
func _make_label(priority: int) -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.shaded = false
	label.double_sided = false
	label.font_size = FONT_RESOLUTION
	label.outline_modulate = OUTLINE_COLOR
	label.render_priority = priority
	label.outline_render_priority = priority - 1
	label.layers = BoardOverlays.UNIT_RENDER_LAYER
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return label


func _make_quad(priority: int) -> MeshInstance3D:
	var quad := MeshInstance3D.new()
	quad.mesh = QuadMesh.new()   # one mesh per node: each carries its own size and center_offset
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED   # the group only yaws, so it can be edge-on
	material.disable_fog = true
	material.disable_ambient_light = true
	material.disable_receive_shadows = true
	material.render_priority = priority
	quad.material_override = material
	quad.layers = BoardOverlays.UNIT_RENDER_LAYER
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return quad


# The one pixel density, same as every sprite in this stack -- #176's "one pixel density,
# everywhere". The grid is measured in texels so it stays in proportion with the art; the NUMBER
# deliberately is not, because a font atlas is not the game's pixel art.
func _texel() -> float:
	return 1.0 / UnitSprite3D.texels_per_unit
