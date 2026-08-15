extends Node3D
class_name UnitHealthBar

# The hover health readout (#229): a track quad, a fill quad and a Label3D standing in the volume
# above a unit. That volume opened up mechanically when 4c moved the selection icons off the cell
# and onto billboards; this is the first thing to occupy it DELIBERATELY. Nothing showed HP on the
# board before it, in either view — the hover card was the only answer, and reading it costs a
# glance away from the diorama.
#
# World-scaled, not screen-constant (dev, 2026-08-15): it shrinks with distance like the icons
# beside it, because it belongs to the scene rather than to the glass.
#
# A dumb idempotent sink, on BoardOverlays' contract: it is TOLD a style and an HP pair and draws
# them. It never reads a Unit, the board or the pointer — UnitMirror owns all of that, and owns
# the knobs too, since the Look panel can only address nodes that exist in the scene.
#
# Width comes from region_rect, NEVER from node scale: a billboarded quad's local axes are rebuilt
# in the vertex shader, so scaling one is a bet on shader internals, while a region is plain texel
# arithmetic that also lands pixel-snapped — which is what pixel art wants anyway.

# The white source both quads region into. Also the ceiling on bar width, which is why the knob's
# max matches it.
const TEXTURE_SIZE := 128
# Not a knob: an outline exists to separate the glyphs from whatever is behind them, and over a
# board that can be any colour, black is the only value that does the job.
const OUTLINE_COLOR := Color.BLACK

static var _white: ImageTexture

var _track: Sprite3D
var _fill: Sprite3D
var _label: Label3D

var _width := 24.0
var _height := 3.0
var _back_color := Color(0.05, 0.04, 0.07, 0.85)
var _full_color := Color(0.35, 0.85, 0.4, 1.0)
var _empty_color := Color(0.85, 0.2, 0.2, 1.0)
var _font_size := 12
var _outline := 2
var _number_color := Color.WHITE
var _gap := 0.05
var _shows_max := true
var _current := 0
var _maximum := 1


func _init() -> void:
	_track = _make_quad(BoardOverlays.UNIT_HUD_RENDER_PRIORITY)
	# One band above the track. Both are transparent and exactly coplanar, so priority is the ONLY
	# thing separating them — there is no depth write to fall back on, and nudging one along local
	# Z is meaningless under a billboard.
	_fill = _make_quad(BoardOverlays.UNIT_HUD_RENDER_PRIORITY + 1)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_label.shaded = false
	_label.pixel_size = _texel()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.outline_modulate = OUTLINE_COLOR
	_label.render_priority = BoardOverlays.UNIT_HUD_RENDER_PRIORITY + 2
	_label.outline_render_priority = BoardOverlays.UNIT_HUD_RENDER_PRIORITY + 1
	_label.layers = BoardOverlays.UNIT_RENDER_LAYER
	_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_track)
	add_child(_fill)
	add_child(_label)
	visible = false
	_rebuild()


# The knob values, pushed by UnitMirror. Ten parameters rather than ten public fields because this
# is one call site and an explicit signature is what keeps it typed end to end.
func set_style(width: float, height: float, back: Color, full: Color, empty: Color,
		font_size: int, outline: int, number_color: Color, gap: float, shows_max: bool) -> void:
	_width = width
	_height = height
	_back_color = back
	_full_color = full
	_empty_color = empty
	_font_size = font_size
	_outline = outline
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


# What fraction of the track the fill actually covers — the RENDERED fact, read off the regions
# rather than recomputed from the HP that produced them, so a test can catch a bar that agrees
# with itself and not with the unit.
func fill_fraction() -> float:
	if not _fill.visible:
		return 0.0
	return _fill.region_rect.size.x / maxf(_track.region_rect.size.x, 1.0)


func track_texels() -> float:
	return _track.region_rect.size.x


func number_text() -> String:
	return _label.text


func _rebuild() -> void:
	var track_w: float = clampf(roundf(_width), 1.0, float(TEXTURE_SIZE))
	var bar_h: float = clampf(roundf(_height), 1.0, float(TEXTURE_SIZE))
	var safe_max := maxi(1, _maximum)
	var shown := clampi(_current, 0, safe_max)
	var fraction := float(shown) / float(safe_max)
	var fill_w := roundf(track_w * fraction)

	_track.region_rect = Rect2(0.0, 0.0, track_w, bar_h)
	_track.modulate = _back_color

	# A region is never zero-wide (Godot draws nothing sensible from one), so empty is expressed by
	# hiding the node — which is also what fill_fraction() keys off.
	_fill.visible = fill_w > 0.0
	_fill.region_rect = Rect2(0.0, 0.0, maxf(fill_w, 1.0), bar_h)
	_fill.modulate = _empty_color.lerp(_full_color, fraction)
	# Both quads are centred, so left-aligning the fill inside the track is a texel offset rather
	# than an anchor mode — which corner `centered = false` pins is exactly the sort of engine
	# detail that reads fine and ships wrong.
	_fill.offset = Vector2(-(track_w - fill_w) * 0.5, 0.0)

	if _shows_max:
		_label.text = "%d/%d" % [shown, safe_max]
	else:
		_label.text = str(shown)
	_label.font_size = _font_size
	_label.outline_size = _outline
	_label.modulate = _number_color
	# Above the bar, by a real gap: Label3D centres on its own origin, so half the glyph height
	# has to be cleared before `gap` means what its name says.
	var texel := _texel()
	_label.position = Vector3(0.0, bar_h * 0.5 * texel + _gap + float(_font_size) * texel * 0.5, 0.0)


func _make_quad(priority: int) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.texture = _white_texture()
	sprite.region_enabled = true
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded = false
	sprite.pixel_size = _texel()
	sprite.render_priority = priority
	sprite.layers = BoardOverlays.UNIT_RENDER_LAYER
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return sprite


# The one pixel density, same as every sprite in this stack — #176's "one pixel density,
# everywhere". A HUD drawn at its own density is the mixed-density tell in miniature.
func _texel() -> float:
	return 1.0 / UnitSprite3D.texels_per_unit


static func _white_texture() -> ImageTexture:
	if _white == null:
		var image := Image.create_empty(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(image)
	return _white
