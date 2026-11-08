extends Object
class_name VeinLook

# What a materia vein LOOKS like on the board (#696): the crystals VeinMirror grows along a vein and the
# stain it lays under one. Every value is a `static var` with a Game-tab row (the "Veins" groups on the
# Elemental page): nobody should disagree about a vein's look between boards, so these are game
# constants rather than a look preset.
#
# THE HUES ARE A DECLARED SECOND REPRESENTATION. ElementPalette is what an element looks like in the UI
# and on a unit; a vein's crystals wear their own colours here, because the dev asked for vein colours
# the palette does not hold (rusty earth, silver air, purple aether -- 2026-11-07, #696). Unifying the
# two is its own decision, with its own mock; until then a vein reads these and nothing else does.
#
# VeinMirror's poll compares key() every frame, so a row takes effect without a sweep.

static var vein_fire_color := Color(0.96, 0.15, 0.11)
static var vein_water_color := Color(0.16, 0.42, 1.0)
static var vein_earth_color := Color(0.72, 0.37, 0.15)
static var vein_air_color := Color(0.88, 0.91, 0.96)
static var vein_aether_color := Color(0.62, 0.27, 1.0)
static var vein_lightning_color := Color(1.0, 0.84, 0.12)
static var vein_alkahest_stain := Color(0.4, 0.3, 0.5)   # alkahest's crystals wear each habit's own

static var vein_size := 1.45          # every crystal's scale
static var vein_density := 14         # the most crystals one cell grows
static var vein_clear := 0.2          # the radius kept clear at a cell's middle, where a unit stands
static var vein_glow := 1.0           # how strongly the crystals glow in their colour
static var vein_stain := 0.55         # how dark the stain under a vein is at its heart
static var vein_stain_reach := 0.2    # how far, in cells, the stain bleeds past a vein's edge
static var vein_stain_dark := 0.45    # how far the stain's colour is darkened from the vein's
static var vein_stain_slope := 0.25   # how steep ground must be before the stain fades from it (0: cliff sides too)


# The crystal colour of a vein of this kind; alkahest's, which only its stain uses.
static func color_of(kind: Vein.Kind) -> Color:
	match kind:
		Vein.Kind.FIRE: return vein_fire_color
		Vein.Kind.WATER: return vein_water_color
		Vein.Kind.EARTH: return vein_earth_color
		Vein.Kind.AIR: return vein_air_color
		Vein.Kind.AETHER: return vein_aether_color
		Vein.Kind.LIGHTNING: return vein_lightning_color
		Vein.Kind.ALKAHEST: return vein_alkahest_stain
	return Color.TRANSPARENT


# Every value above, for the mirror's poll: a row moved is a rebuild.
static func key() -> Array:
	return [vein_fire_color, vein_water_color, vein_earth_color, vein_air_color, vein_aether_color,
		vein_lightning_color, vein_alkahest_stain, vein_size, vein_density, vein_clear, vein_glow,
		vein_stain, vein_stain_reach, vein_stain_dark, vein_stain_slope]
