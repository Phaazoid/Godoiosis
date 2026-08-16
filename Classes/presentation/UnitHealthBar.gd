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
	_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_label.shaded = false
	# The back face of a billboarded label is coplanar with its front and blends over it, which is
	# the other way text on a billboard ghosts itself. Nothing ever sees the reverse of a sprite
	# that always faces the camera, so there is nothing to lose by dropping it.
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
	_label.outline_size = int(_number_outline)
	_label.modulate = _number_color
	# ONE display, locked at every camera angle (dev feel-check, 2026-08-15: the number "kinda floats
	# apart depending on the angle"). Every element billboards INDEPENDENTLY, so a displacement
	# written to node `position` is a WORLD offset: the bar spins in place under orbit while the
	# number stays put, and the two shear apart. Label3D.offset is applied in the label's own plane
	# BEFORE the billboard rebuilds the basis — the same space QuadMesh.center_offset lives in — so
	# it turns with the bar instead. Nothing here may ever move a child by `position`.
	#
	# Sits ON the bar, inset from its left edge. get_aabb() is read for the text's WIDTH, which is
	# offset-independent, so this cannot feed back on itself frame to frame; the digit count changes
	# with the HP, which is why it is measured rather than assumed.
	var half_text: float = _label.get_aabb().size.x * 0.5
	var inside_left := -track_w * 0.5 * texel + _gap + half_text
	_label.offset = Vector2(inside_left / _label.pixel_size, 0.0)


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
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
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
