extends Node3D
class_name UnitHealthBar

# The hover health readout (#229): a black-outlined bar with the number snapped to its left, in the
# volume above a unit. That volume opened up mechanically when 4c moved the selection icons off the
# cell and onto billboards; this is the first thing to occupy it DELIBERATELY. Nothing showed HP on
# the board before it, in either view — the hover card was the only answer, and reading it costs a
# glance away from the diorama.
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
# A dumb idempotent sink: it is TOLD a style and an HP pair and draws them. It never reads a Unit,
# the board or the pointer — UnitMirror owns all of that, and owns the knobs too, since the Look
# panel can only address nodes that exist in the scene.
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
var _label: Label3D

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


func _init() -> void:
	# Priority ascends outline -> missing -> fill. All three are coplanar and there is no depth
	# write to separate them, so priority IS the relationship. They are TRANSPARENCY_ALPHA despite
	# being fully opaque colours: an opaque material sorts by depth, which coplanar quads cannot do,
	# while the alpha queue honours render_priority. "No transparency" is about the alpha value.
	_outline = _make_quad(BoardOverlays.UNIT_HUD_RENDER_PRIORITY)
	_missing = _make_quad(BoardOverlays.UNIT_HUD_RENDER_PRIORITY + 1)
	_fill = _make_quad(BoardOverlays.UNIT_HUD_RENDER_PRIORITY + 2)
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
	_label.render_priority = BoardOverlays.UNIT_HUD_RENDER_PRIORITY + 4
	_label.outline_render_priority = BoardOverlays.UNIT_HUD_RENDER_PRIORITY + 3
	_label.layers = BoardOverlays.UNIT_RENDER_LAYER
	_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_outline)
	add_child(_missing)
	add_child(_fill)
	add_child(_label)
	visible = false
	_rebuild()


# The knob values, pushed by UnitMirror. Explicit parameters rather than public fields because this
# is one call site and a signature is what keeps it typed end to end.
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


func set_hp(current: int, maximum: int) -> void:
	_current = current
	_maximum = maximum
	_rebuild()


func set_shown(shown: bool) -> void:
	visible = shown


# Turn the WHOLE readout to face the camera, once, instead of letting each part billboard itself.
# Per-object billboarding is what pulled this display apart: each element rebuilds its own basis
# about its own origin, so any displacement written in world space shears as the camera orbits,
# and the only displacement that does not — an in-plane offset — is not honoured identically by
# every element (Label3D moves its glyphs and its outline by different amounts). Rotating the
# parent makes every child's ordinary local position correct by construction, at any angle.
#
# Yaw only, matching the BILLBOARD_FIXED_Y the icons beside it use: atan2(x, z) points local +Z,
# which is the face QuadMesh and Label3D present, at the camera.
func face(camera_position: Vector3) -> void:
	var to_camera := camera_position - global_position
	if absf(to_camera.x) < 0.0001 and absf(to_camera.z) < 0.0001:
		return   # camera directly overhead: any yaw is as good as another, so keep the last one
	global_rotation = Vector3(0.0, atan2(to_camera.x, to_camera.z), 0.0)


# What fraction of the bar the fill actually covers — the RENDERED fact, read off the mesh rather
# than recomputed from the HP that produced it, so a test can catch a bar that agrees with itself
# and not with the unit.
func fill_fraction() -> float:
	if not _fill.visible:
		return 0.0
	var full: float = (_missing.mesh as QuadMesh).size.x
	return (_fill.mesh as QuadMesh).size.x / maxf(full, 0.0001)


func track_texels() -> float:
	return roundf(_width)


func number_text() -> String:
	return _label.text


func _rebuild() -> void:
	var texel := _texel()
	var track_w: float = maxf(roundf(_width), 1.0)
	var bar_h: float = maxf(roundf(_height), 1.0)
	var edge: float = maxf(roundf(_outline_texels), 0.0)
	var safe_max := maxi(1, _maximum)
	var shown := clampi(_current, 0, safe_max)
	var fraction := float(shown) / float(safe_max)
	var fill_w := roundf(track_w * fraction)

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


func _size_quad(quad: MeshInstance3D, width: float, height: float, offset_x: float) -> void:
	var mesh := quad.mesh as QuadMesh
	mesh.size = Vector2(width, height)
	mesh.center_offset = Vector3(offset_x, 0.0, 0.0)


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
