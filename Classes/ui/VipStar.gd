extends Control
class_name VipStar

# THE VIP MARK's one star (#1456): a roster unit the mission is lost without. Every surface that marks a
# VIP draws this -- the card's portrait seal and name pill, the Deployed force portrait, and the Protect
# row the contract and the HUD share. Drawn rather than pixel art, so a pixel icon could replace it in
# this one place.
#
# Its colours are QueueStyle's VIP roles, handed in, since the frame and the paper want different ones.
# The OUTLINE is transparent on slate, so one drawing serves both palettes.
#
# It is also the home of the gold BAND's outline (draw_band_outline), for the boxed marks -- the card
# frame, the Required toggle, the pill, the force portrait -- whose gold is their own StyleBoxFlat
# border: a box with one border colour cannot draw black|gold|black, and keeping the gold IN the box is
# what lets everything that reads a box's border keep reading it.

const POINTS := 5
const INNER_RATIO := 0.45
const OUTLINE_WIDTH := 1.2

var ink := Color.WHITE
var outline := Color(0, 0, 0, 0)
# A seal: the star sits on a disc of `disc` ringed in `ink` and then `outline`, so it reads over a
# portrait's own colours. Transparent for a bare star.
var disc := Color(0, 0, 0, 0)


static func make(star_ink: Color, star_outline: Color, px: float, seal_disc := Color(0, 0, 0, 0)) -> VipStar:
	var star := VipStar.new()
	star.ink = star_ink
	star.outline = star_outline
	star.disc = seal_disc
	star.custom_minimum_size = Vector2(px, px)
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return star


func _draw() -> void:
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * 0.5
	if disc.a > 0.0:
		draw_circle(centre, radius, disc)
		draw_circle(centre, radius - 0.6, ink, false, OUTLINE_WIDTH, true)
		draw_circle(centre, radius - 0.6, outline, false, OUTLINE_WIDTH, true)
		radius *= 0.76
	draw_star(self, centre, radius, ink, outline)


static func draw_star(item: CanvasItem, centre: Vector2, radius: float, star_ink: Color,
		star_outline: Color) -> void:
	var points := PackedVector2Array()
	for i in POINTS * 2:
		var angle := -PI / 2.0 + i * PI / POINTS
		points.append(centre + Vector2(cos(angle), sin(angle)) * (radius if i % 2 == 0 else radius * INNER_RATIO))
	item.draw_colored_polygon(points, star_ink)
	if star_outline.a > 0.0:
		var loop := points.duplicate()
		loop.append(points[0])
		item.draw_polyline(loop, star_outline, OUTLINE_WIDTH, true)


# The one-pixel outline either side of a gold band `band` thick, drawn by a box onto `rect`: just
# outside it (unless `outer` is false -- the card, whose outside is the dark frame and is clipped), and
# just inside the gold. Nothing at all when the palette's outline is transparent.
static func draw_band_outline(item: CanvasItem, rect: Rect2, band: int, radius: int, outer := true) -> void:
	var outline_ink := QueueStyle.ink(QueueStyle.Role.VIP_OUTLINE)
	if outline_ink.a <= 0.0:
		return
	if outer:
		_line(item, rect.grow(1.0), radius + 1, outline_ink)
	_line(item, rect.grow(-band), maxi(radius - band, 0), outline_ink)


static func _line(item: CanvasItem, rect: Rect2, radius: int, colour: Color) -> void:
	var line := StyleBoxFlat.new()
	line.draw_center = false
	line.border_color = colour
	line.set_border_width_all(1)
	line.set_corner_radius_all(radius)
	line.anti_aliasing = true
	item.draw_style_box(line, rect)
