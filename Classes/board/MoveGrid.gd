extends Object
class_name MoveGrid

# What the player's movement range LOOKS like, tile by tile (#1074): a line round every reachable
# tile plus a faint square of the same tint inside it. The one rule both views rasterize -- the
# diorama at 32 texels a tile (BoardOverlays), the flat view at 16 (OverlayManager) -- so a knob
# dragged on the Game tab moves both, and neither holds a baked PNG that could drift from the other.
# ThreatLines2D's shape: a board/ class whose statics both stacks read and GameKnobs.CLASS_KNOBS tunes.
#
# It replaced #1069's hollow PNG, whose outermost texel ring was deliberately SOFTENED (alpha 0.7
# against the 1.0 rings inside it). Two neighbours put two soft rings side by side, and the dev read
# that seam as the tiles being disconnected: "that space between tiles should be highlighted too, so
# the range doesn't look as disconnected." So nothing here is softened -- at an inset of 0 a tile's
# line runs to its edge at full strength and meets its neighbour's.
#
# The COLOUR is not here. Every texel is white with an alpha, and the layer tints it (Move fill on
# the Game tab), which is what makes the inner square the same blue as the line by construction.

# The metric the four values below are authored in: pixels of the diorama's 32-texel tile.
const ART_TEXELS := 32

# How far in from the tile's edge the line starts. At 0 neighbouring tiles' lines touch and read as
# one continuous lattice, which is the dev's ask; above it every tile is its own framed square again.
static var GRID_LINE_INSET := 0.0
# The line's thickness per tile. Where two tiles meet their lines sit side by side, so a line BETWEEN
# tiles draws twice this and the rim of the range once. Zero is no line at all.
static var GRID_LINE_WIDTH := 2.0
# Clear space between the line's inner edge and the inner square.
static var GRID_FILL_GAP := 0.0
# The inner square's strength as a fraction of the line's -- the dev's "same shade, much fainter
# alpha". Zero is #1069's pure-gridline look.
static var GRID_FILL_ALPHA := 0.57


# One tile of the grid at `size` texels a side, as white-with-alpha for a layer to tint.
#
# A texel is judged by the SPAN of distance it covers, never by its centre: its ring index `e` is how
# many texels in from the nearest edge it sits, so it covers [e, e+1) texels of distance -- in
# 32nds, [e, e+1) / scale. A texel touching the line band at all is line. At 32 texels that is
# exactly centre sampling for whole-pixel knobs; at the flat view's 16 it is what keeps a 1-pixel
# line from vanishing, since a centre sample would land every texel outside a band that narrow.
static func image(size: int) -> Image:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var scale := float(size) / float(ART_TEXELS)
	var line_end := GRID_LINE_INSET + GRID_LINE_WIDTH
	var gap_end := line_end + GRID_FILL_GAP
	for y in size:
		for x in size:
			var ring := mini(mini(x, size - 1 - x), mini(y, size - 1 - y))
			var near := float(ring) / scale
			var far := float(ring + 1) / scale
			var alpha := 0.0
			if far <= GRID_LINE_INSET:
				alpha = 0.0
			elif GRID_LINE_WIDTH > 0.0 and near < line_end:
				alpha = 1.0
			elif near < gap_end:
				alpha = 0.0
			else:
				alpha = GRID_FILL_ALPHA
			img.set_pixel(x, y, Color(1, 1, 1, alpha))
	return img
