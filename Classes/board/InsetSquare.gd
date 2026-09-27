extends Object
class_name InsetSquare

# What a PAYLOAD's tile looks like in the aim preview (#1058 D2b, rulings 37/41): the aim's own yellow,
# a size smaller -- a solid square with a clear margin round it, so a tile an attack only reaches by
# what it DROPS reads apart from one it strikes itself. MoveGrid's shape: the one rule both views
# rasterize, the flat view at its tile size and the diorama at 32 texels, so the Game-tab knob moves
# both and neither holds a baked PNG.
#
# The COLOUR is not here. Every texel is white or clear and the layer tints it, which is what keeps a
# watch aim or a player's aim palette on the insets by construction.

# The margin on each side, as a share of the tile. Game-tab knob (GameKnobs.CLASS_KNOBS, Aiming).
static var PAYLOAD_INSET := 0.2


# One tile at `size` texels a side: opaque white inside the margin, clear outside it.
static func image(size: int) -> Image:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var margin := margin_texels(size)
	for y in size:
		for x in size:
			var inside := x >= margin and x < size - margin and y >= margin and y < size - margin
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 if inside else 0.0))
	return img


# The clear margin in whole texels. Held under half the tile, so a knob at its top still leaves a
# square to see rather than nothing at all.
static func margin_texels(size: int) -> int:
	return clampi(roundi(PAYLOAD_INSET * size), 0, floori((size - 1) / 2.0))


# The inset square of `cell` in the flat view's pixels -- what AimFlash2D whitens there.
static func rect(cell: Vector2i) -> Rect2:
	var tile := float(GridUtils.TILE_SIZE)
	var margin := float(margin_texels(GridUtils.TILE_SIZE))
	return Rect2(Vector2(cell) * tile + Vector2.ONE * margin, Vector2.ONE * (tile - 2.0 * margin))
