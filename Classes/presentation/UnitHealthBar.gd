extends Node3D
class_name UnitHealthBar

# The health readout (#229): a black-outlined bar with the number snapped to its left, in the
# volume above a unit. That volume opened up mechanically when 4c moved the selection icons off the
# cell and onto billboards; this is the first thing to occupy it DELIBERATELY. Nothing showed HP on
# the board before it, in either view — the hover card was the only answer, and reading it costs a
# glance away from the diorama.
#
# Since #313 the same bar also carries the PREDICTION: a notch at the HP the queued plan leaves the
# unit at, with the span between there and now filled in a third colour — doomed if the plan is
# taking HP, a heal colour if it is giving it back. One bar rather than a second ghost beside it:
# current and predicted are one fact about one unit, and stacking a twin over every unit the plan
# touches crowds a volume the selection icons already share.
#
# GAMEPLAY DESCRIPTOR, NOT SCENERY (dev feel-check, 2026-08-15). The first pass set `shaded = false`
# and called that unlit; it is not. Unshaded only skips direct lighting, while volumetric fog, glow,
# filmic tonemap and DoF all still ran over it, which is what read as "transparent". So the bar is
# built from explicit StandardMaterial3Ds carrying `disable_fog` and `disable_ambient_light`, not
# from Sprite3Ds — SpriteBase3D exposes no fog control at all. Flat opaque colours, no texture.
# What remains outside our reach is whole-frame post (glow, tonemap, DoF): there is no per-object
# exemption for those, and true immunity means drawing the HUD in its own pass.
#
# World-scaled, not screen-constant (dev, 2026-08-15): it shrinks with distance like the icons
# beside it, because it belongs to the scene rather than to the glass.
#
# Since #357 it also carries the ELEMENT-STATE row: one icon per state the unit holds, sitting just
# above the bar and flush with its left edge. That is the first deliberate occupant of the channel
# #346 freed — above the head is what this unit IS — and it is a CHILD of this group rather than a
# display of its own precisely so it cannot grow a second visibility rule: a hidden bar hides it by
# construction, which is what #350's one-gate ruling asks for.
#
# A dumb idempotent sink: it is TOLD a style, an HP pair and a prediction, and draws them. It never
# reads a Unit, the plan, the board or the pointer — UnitMirror owns all of that, and owns the knobs
# too, since the Look panel can only address nodes that exist in the scene.
#
# Width comes from the quad MESH plus center_offset, never from node scale: a billboarded quad's
# local axes are rebuilt in the vertex shader, so scaling one is a bet on shader internals, while
# center_offset is applied to the vertices before that and rides the billboard correctly.

# Not knobs: an outline exists to separate a shape from whatever is behind it, and over a board that
# can be any colour, black is the only value that does the job.
const OUTLINE_COLOR := Color.BLACK
# Glyph resolution, held high and fixed while the DISPLAYED size rides pixel_size instead. Sizing
# text by font_size would have meant a 4px font to hit the size the dev asked for, which renders to
# mush; sizing by pixel_size keeps the atlas crisp and shrinks the quad.
const FONT_RESOLUTION := 32

var _outline: MeshInstance3D
var _missing: MeshInstance3D
var _fill: MeshInstance3D
var _doomed: MeshInstance3D    # #313: the span between current HP and what the plan predicts
var _notch: MeshInstance3D     # #313: the marker AT the predicted level
var _label: Label3D
# #357: the element-state row above the bar. A POOL, grown on demand and hidden rather than freed —
# the same contract UnitMirror.set_ghosts and BoardOverlays use, for the same reason: the count
# changes every time a state lands or expires.
var _state_icons: Array[MeshInstance3D] = []

var _width := 32.0
var _height := 6.0
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
var _notch_color := Color.WHITE
var _notch_texels := 1.0
var _alarm_peak_color := Color(1.0, 1.0, 1.0, 1.0)
var _predicted := 0
var _has_prediction := false
var _number_shown := true
var _state_textures: Array[Texture2D] = []
var _state_icon_texels := 8.0
var _state_gap_texels := 2.0
var _state_spacing_texels := 1.0

var _alarm: Tween
var _alarm_peak_live := Color(1.0, 1.0, 1.0, 1.0)   # the peak the RUNNING tween was started with
# Every input the drawing reads, snapshotted (#313). UnitMirror pushes style, HP and prediction
# every frame for every SHOWN bar, and a redraw resizes five meshes and measures the label's AABB —
# fine for the single hovered bar #229 shipped, N times a frame once a plan puts one over everybody.
# It is also what lets the alarm own the doomed colour: an unguarded redraw repainted over the tween
# sixty times a second. Same value-diff-before-push idiom OverlayMirror uses.
var _drawn: Array = []


# The pulsing colour of the doomed segment (#313). Written by the alarm TWEEN rather than by the
# tween writing a material directly, so _paint stays the single writer of albedo and the pulse never
# becomes a second owner of it — the rule a live pulse already follows for sprite.modulate.
var alarm_color := Color.WHITE:
	set(value):
		alarm_color = value
		if _doomed != null:
			_paint(_doomed, value)


func _init() -> void:
	# Priority ascends outline -> missing -> fill -> doomed -> notch. All are coplanar and there is
	# no depth write to separate them, so priority IS the relationship. They are TRANSPARENCY_ALPHA
	# despite being fully opaque colours: an opaque material sorts by depth, which coplanar quads
	# cannot do, while the alpha queue honours render_priority. "No transparency" is about the alpha
	# value.
	_outline = _make_quad(BoardOverlays.UNIT_HUD_RENDER_PRIORITY)
	_missing = _make_quad(BoardOverlays.UNIT_HUD_RENDER_PRIORITY + 1)
	_fill = _make_quad(BoardOverlays.UNIT_HUD_RENDER_PRIORITY + 2)
	_doomed = _make_quad(BoardOverlays.UNIT_HUD_RENDER_PRIORITY + 3)
	_notch = _make_quad(BoardOverlays.UNIT_HUD_RENDER_PRIORITY + 4)
	_label = Label3D.new()
	# NOT billboarded, like everything else here — face() turns the whole group instead. Label3D
	# draws its glyphs and its outline as two surfaces, and displacing it with Label3D.offset (the
	# only in-plane displacement a per-object billboard permits) moved them by different amounts,
	# which is what the dev saw as the number "appearing double and overlapping" (2026-08-15).
	_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_label.shaded = false
	_label.double_sided = false
	_label.font_size = FONT_RESOLUTION
	_label.outline_modulate = OUTLINE_COLOR
	_label.render_priority = BoardOverlays.UNIT_HUD_RENDER_PRIORITY + 6
	_label.outline_render_priority = BoardOverlays.UNIT_HUD_RENDER_PRIORITY + 5
	_label.layers = BoardOverlays.UNIT_RENDER_LAYER
	_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_outline)
	add_child(_missing)
	add_child(_fill)
	add_child(_doomed)
	add_child(_notch)
	add_child(_label)
	visible = false
	_rebuild()


# The knob values, pushed by UnitMirror. Explicit parameters rather than public fields because this
# is one call site and a signature is what keeps it typed end to end. The PREDICTION's own knobs sit
# in their own setter below rather than growing this one past the point a call site can be read.
func set_style(width: float, height: float, outline: float, fill: Color, missing: Color,
		number_height: float, number_outline: float, number_color: Color, gap: float,
		shows_max: bool) -> void:
	_width = width
	_height = height
	_outline_texels = outline
	_fill_color = fill
	_missing_color = missing
	_number_height = number_height
	_number_outline = number_outline
	_number_color = number_color
	_gap = gap
	_shows_max = shows_max
	_rebuild()


func set_prediction_style(doomed: Color, heal: Color, notch: Color, notch_texels: float,
		alarm_peak: Color) -> void:
	_doomed_color = doomed
	_heal_color = heal
	_notch_color = notch
	_notch_texels = notch_texels
	_alarm_peak_color = alarm_peak
	_rebuild()


func set_hp(current: int, maximum: int) -> void:
	_current = current
	_maximum = maximum
	_rebuild()


# What the queued plan leaves this unit at (#313), already run through the display clamp — this node
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


# Crowding, not styling: an unhovered ghost is bar-only by default, and hovering it reveals the
# number. Two reasons to be up (#313), so the number follows the reason rather than the bar.
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


func set_shown(shown: bool) -> void:
	visible = shown
	if not shown:
		set_alarm(false)   # a tween on a hidden bar is invisible work, and outlives what raised it


# Idempotent because it is TOLD every frame: start once, stop once. Pulse.stop writes the base value
# back through alarm_color's setter, so the segment lands on its resting colour with no extra paint.
# A tween carries the peak it STARTED with, so a peak retuned mid-pulse restarts it -- a Look knob
# that only lands at the next alarm reads as a dead slider.
func set_alarm(on: bool) -> void:
	if on and _alarm != null and _alarm_peak_live != _alarm_peak_color:
		_stop_alarm()
	if on == (_alarm != null):
		return
	if on:
		alarm_color = _segment_color()
		_alarm_peak_live = _alarm_peak_color
		_alarm = Pulse.start(self, self, &"alarm_color", _segment_color(), _alarm_peak_color)
	else:
		_stop_alarm()


func _stop_alarm() -> void:
	Pulse.stop(_alarm, self, &"alarm_color", _segment_color())
	_alarm = null


# Turn the WHOLE readout to face the camera, once, instead of letting each part billboard itself.
# Per-object billboarding is what pulled this display apart: each element rebuilds its own basis
# about its own origin, so any displacement written in world space shears as the camera orbits,
# and the only displacement that does not — an in-plane offset — is not honoured identically by
# every element (Label3D moves its glyphs and its outline by different amounts). Rotating the
# parent makes every child's ordinary local position correct by construction, at any angle.
#
# Yaw only, and it must MATCH BILLBOARD_FIXED_Y rather than merely resemble it (#325 follow-up).
# FIXED_Y aligns a sprite to the VIEW PLANE, one yaw board-wide; pointing each readout at the
# camera POSITION instead gives a slightly different angle per unit, agreeing only at screen
# centre -- which read as the crown and the bar sitting on visibly different axes. Every sprite
# in this stack is FIXED_Y, UnitSprite3D included, so the READOUT is what moves: the unit art is
# the anchor anything hung on it must agree with. Camera basis +Z is the direction FIXED_Y faces.
func face(camera_basis: Basis) -> void:
	var facing := camera_basis.z
	if absf(facing.x) < 0.0001 and absf(facing.z) < 0.0001:
		return   # camera straight overhead: any yaw is as good as another, so keep the last one
	global_rotation = Vector3(0.0, atan2(facing.x, facing.z), 0.0)


# What fraction of the bar the fill actually covers — the RENDERED fact, read off the mesh rather
# than recomputed from the HP that produced it, so a test can catch a bar that agrees with itself
# and not with the unit.
func fill_fraction() -> float:
	if not _fill.visible:
		return 0.0
	return _quad_width(_fill) / maxf(_quad_width(_missing), 0.0001)


# Where the notch SITS, as a fraction of the track — read off the mesh for the same reason
# fill_fraction is. -1.0 when no prediction is up, which is a different answer from 0.0 (a kill).
func notch_fraction() -> float:
	if not _notch.visible:
		return -1.0
	var track := maxf(_quad_width(_missing), 0.0001)
	var centre: float = (_notch.mesh as QuadMesh).center_offset.x
	return clampf((centre + track * 0.5) / track, 0.0, 1.0)


# How much of the track the plan is about to take (or give back), rendered.
func doomed_fraction() -> float:
	if not _doomed.visible:
		return 0.0
	return _quad_width(_doomed) / maxf(_quad_width(_missing), 0.0001)


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


func track_texels() -> float:
	return roundf(_width)


func number_text() -> String:
	return _label.text


# Whether the digits are up, as opposed to what they SAY. A separate question since #350: a bar can
# be up for three reasons now and only one of them earns the number.
func number_shown() -> bool:
	return _label.visible


func _rebuild() -> void:
	var signature: Array = [_width, _height, _outline_texels, _fill_color, _missing_color,
			_number_height, _number_outline, _number_color, _gap, _shows_max, _number_shown,
			_doomed_color, _heal_color, _notch_color, _notch_texels,
			_current, _maximum, _predicted, _has_prediction,
			_state_textures, _state_icon_texels, _state_gap_texels, _state_spacing_texels]
	if signature == _drawn:
		return
	_drawn = signature
	_draw()


func _draw() -> void:
	var texel := _texel()
	var track_w: float = maxf(roundf(_width), 1.0)
	var bar_h: float = maxf(roundf(_height), 1.0)
	var edge: float = maxf(roundf(_outline_texels), 0.0)
	var safe_max := maxi(1, _maximum)
	var shown := clampi(_current, 0, safe_max)
	var fill_w := roundf(track_w * (float(shown) / float(safe_max)))

	_size_quad(_outline, (track_w + edge * 2.0) * texel, (bar_h + edge * 2.0) * texel, 0.0)
	_paint(_outline, OUTLINE_COLOR)
	# Everything below lays out in ORDINARY local space. That is only safe because nothing here
	# billboards on its own — face() turns the parent — so a local offset is a real offset at every
	# camera angle rather than a world-space one that shears.
	# The MISSING health is the backing, drawn full width; the fill covers what remains. Two flat
	# colours rather than one lerping between them (dev, 2026-08-15) — a bar that changes hue as it
	# shortens says the same thing twice and reads muddy in the middle.
	_size_quad(_missing, track_w * texel, bar_h * texel, 0.0)
	_paint(_missing, _missing_color)

	_fill.visible = fill_w > 0.0
	# Left-anchored inside the bar: the quad shrinks from the right, so its centre walks left by
	# half of what it lost. center_offset rather than node position, so it rides the billboard.
	_size_quad(_fill, maxf(fill_w, 1.0) * texel, bar_h * texel, -(track_w - fill_w) * 0.5 * texel)
	_paint(_fill, _fill_color)

	_draw_prediction(texel, track_w, bar_h, safe_max, fill_w)

	_label.visible = _number_shown
	if _shows_max:
		_label.text = "%d/%d" % [shown, safe_max]
	else:
		_label.text = str(shown)
	_label.pixel_size = maxf(_number_height, 0.001) / float(FONT_RESOLUTION)
	_label.outline_size = roundi(_number_outline)
	_label.modulate = _number_color
	# Sits ON the bar, inset from its left edge, in the parent's local space. get_aabb() is read for
	# the text's WIDTH only, which does not depend on where the label sits, so this cannot feed back
	# on itself frame to frame; the digit count changes with the HP, which is why it is measured
	# rather than assumed. Z nudges the text a hair toward the viewer, which is now a meaningful
	# direction precisely because the group has one orientation.
	var half_text: float = _label.get_aabb().size.x * 0.5
	_label.position = Vector3(-track_w * 0.5 * texel + _gap + half_text, 0.0, texel)

	_draw_state_row(texel, track_w, bar_h, edge)


# The element-state row (#357): square icons ABOVE the bar, the first one flush with the outline's
# left edge and the rest growing rightward. Sized in texels rather than as a multiple of the bar's
# height: nothing ties a status icon to how thick the gauge happens to be, and the two want to be
# tunable apart.
#
# Local space again, and that is the whole reason this lives inside the group: face() turns the
# parent, so an offset written here is a real offset at every camera angle. Priority is the group's
# base — the row is coplanar with nothing, so it has no sibling to sort against.
func _draw_state_row(texel: float, track_w: float, bar_h: float, edge: float) -> void:
	while _state_icons.size() < _state_textures.size():
		var quad := _make_quad(BoardOverlays.UNIT_HUD_RENDER_PRIORITY)
		var fresh := quad.material_override as StandardMaterial3D
		fresh.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # pixel art, like every sprite in this stack
		add_child(quad)
		_state_icons.append(quad)
	var icon: float = maxf(roundf(_state_icon_texels), 1.0)
	var gap: float = maxf(roundf(_state_gap_texels), 0.0)
	var spacing: float = maxf(roundf(_state_spacing_texels), 0.0)
	# Clear of the outline's TOP edge, and flush with its LEFT one, so the row and the gauge share a
	# left margin rather than each finding its own.
	var row_y: float = (bar_h * 0.5 + edge + gap + icon * 0.5) * texel
	var left: float = -(track_w * 0.5 + edge)
	for i in _state_icons.size():
		var quad: MeshInstance3D = _state_icons[i]
		# Occupancy, NOT visibility: extras are parked rather than freed, and the bar's own
		# visible flag is what decides whether any of this is seen.
		quad.visible = i < _state_textures.size()
		if not quad.visible:
			continue
		_size_quad(quad, icon * texel, icon * texel,
				(left + icon * 0.5 + float(i) * (icon + spacing)) * texel, row_y)
		var material := quad.material_override as StandardMaterial3D
		material.albedo_texture = _state_textures[i]
		material.albedo_color = Color.WHITE


# The prediction (#313). The SPAN runs between where the bar is now and where the plan leaves it,
# so the same two quads say "this much is coming off" and "this much is coming back" — the colour is
# what names the direction, because the geometry cannot.
func _draw_prediction(texel: float, track_w: float, bar_h: float, safe_max: int, fill_w: float) -> void:
	if not _has_prediction:
		_doomed.visible = false
		_notch.visible = false
		return
	var predicted_w := roundf(track_w * (float(clampi(_predicted, 0, safe_max)) / float(safe_max)))
	var left: float = minf(fill_w, predicted_w)
	var right: float = maxf(fill_w, predicted_w)

	_doomed.visible = right - left > 0.0
	_size_quad(_doomed, maxf(right - left, 1.0) * texel, bar_h * texel,
			((left + right) * 0.5 - track_w * 0.5) * texel)
	# The alarm owns this colour while it runs; otherwise the resting one. Reading alarm_color here
	# rather than skipping the paint keeps _paint the only writer either way.
	_paint(_doomed, alarm_color if _alarm != null else _segment_color())

	# Kept wholly inside the track: at a predicted 0 or a predicted full, half the marker would
	# otherwise hang off the end and read as a shorter bar rather than as a mark on this one.
	var notch_w: float = maxf(roundf(_notch_texels), 1.0)
	var centre: float = clampf(predicted_w, notch_w * 0.5, track_w - notch_w * 0.5)
	_notch.visible = true
	_size_quad(_notch, notch_w * texel, bar_h * texel, (centre - track_w * 0.5) * texel)
	_paint(_notch, _notch_color)


# Losing HP or gaining it — the span is the same shape either way, and only this says which.
func _segment_color() -> Color:
	return _heal_color if _has_prediction and _predicted > _current else _doomed_color


# offset_y defaults to 0 because everything in the bar proper is vertically centred on it; the
# state row is the one thing that sits OFF the line, so it is the only caller that passes it.
func _size_quad(quad: MeshInstance3D, width: float, height: float, offset_x: float,
		offset_y := 0.0) -> void:
	var mesh := quad.mesh as QuadMesh
	mesh.size = Vector2(width, height)
	mesh.center_offset = Vector3(offset_x, offset_y, 0.0)


func _quad_width(quad: MeshInstance3D) -> float:
	return (quad.mesh as QuadMesh).size.x


func _paint(quad: MeshInstance3D, color: Color) -> void:
	var material := quad.material_override as StandardMaterial3D
	material.albedo_color = color


func _make_quad(priority: int) -> MeshInstance3D:
	var quad := MeshInstance3D.new()
	quad.mesh = QuadMesh.new()   # one mesh per node: each carries its own size and center_offset
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# No per-object billboard: face() turns the group. See the note there for why one rotation for
	# the whole display beats four that each rebuild their own basis.
	material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED   # the group only yaws, so it can be edge-on
	# The half of "not affected by lighting" that IS reachable per-object. Unshaded already skips
	# direct light; without these two the volumetric fog still washes the bar toward the fog albedo,
	# which is exactly what the first pass looked like.
	material.disable_fog = true
	material.disable_ambient_light = true
	material.disable_receive_shadows = true
	material.render_priority = priority
	quad.material_override = material
	quad.layers = BoardOverlays.UNIT_RENDER_LAYER
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return quad


# The one pixel density, same as every sprite in this stack — #176's "one pixel density,
# everywhere". The bar is measured in texels so it stays in proportion with the art; the NUMBER
# deliberately is not, because a font atlas is not the game's pixel art.
func _texel() -> float:
	return 1.0 / UnitSprite3D.texels_per_unit
