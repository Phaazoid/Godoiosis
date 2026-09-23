extends Object
class_name StatusLook

# What an element state LOOKS like worn on a unit's sprite (#358): every value the status shader is
# told, as a `static var` with a Game-tab row on the Elemental page. Nobody should disagree about a
# status read between boards, so these are game constants rather than a look preset.
#
# The HUES are deliberately absent. `ElementPalette.color_for_state` is already the answer to what
# colour a state is, so tuning Water or Ice under Element colours moves this too.
#
# `push` is the one door from these values to a material. UnitMirror calls it every frame for every
# sprite wearing a state, which is why no knob here needs a sweep: there is no stale copy to reach.
# The world half's values (slice 2) are read the same way, by StatusWorld and StatusParticles.

static var status_fade_time := 0.5        # seconds a state takes to fade in or out
static var icicle_grow_time := 1.0        # seconds an icicle takes to grow to full length
static var icicle_min_texels := 2.0
static var icicle_max_texels := 4.0

static var wet_tint := 0.35               # how far the body takes the water hue
static var wet_streak_speed := 0.7        # rows per second a drip streak runs down, over 8-row runs
static var wet_streak_density := 0.5      # the share of the art's columns that carry a streak
static var wet_streak_glow := 0.6

static var chill_tint := 0.55             # how far the body takes the ice hue, desaturated
static var chill_sheen_period := 3.3      # seconds between one sheen pass and the next
static var chill_sheen_width := 0.045     # band thickness, as a fraction of the body's height
static var chill_sheen_glow := 0.6
static var chill_rime_glow := 0.5
static var chill_glint_rate := 0.1        # the share of body texels that ever twinkle
static var chill_glint_glow := 1.0

# The world half (slice 2): what a worn state throws off the body, and the damp patch a Wet unit
# leaves under it (a ground-only Decal; UnitMirror spreads and dries it). Read by StatusWorld and
# StatusParticles every frame, so these need no sweep either.
static var wet_drip_rate := 1.2           # drips a second from a fully Wet unit
static var wet_drip_fall_time := 0.35     # seconds from the overhang to the ground
static var wet_drip_length := 2.0         # texels
static var wet_drip_alpha := 0.9
static var wet_drip_whiten := 0.45        # how far a drip is lifted from the Water hue toward white
static var wet_splash_count := 4
static var wet_splash_speed := 0.5
static var wet_splash_rise := 1.2         # how much of the splash's speed goes up rather than out
static var wet_splash_gravity := 6.0
static var wet_splash_time := 0.25
static var wet_blot_size := 0.6           # the damp patch across, as a share of a cell, fully spread
static var wet_blot_darkness := 0.45      # how much of the ground's own colour the patch replaces
static var wet_blot_tint := 0.9           # how far the patch leans from black to the Water hue
static var wet_blot_spread_time := 0.8    # seconds to spread once the unit is wet
static var wet_blot_dry_time := 4.0       # seconds to dry once it is not
static var wet_ripple_time := 0.6         # seconds a ring takes to spread through the patch from a landed drip
static var wet_ripple_reach := 3.0        # the ring's widest radius, in the patch's own texels
static var wet_ripple_light := 0.8        # how far a new ring is lifted from the patch's colour toward white

static var chill_mist_rate := 4.0         # puffs a second from a fully Chilled unit
static var chill_mist_life := 1.6         # seconds a puff takes to sink from the body to the ground
static var chill_mist_drift := 0.18       # world units a puff wanders out from the body as it sinks
static var chill_mist_size := 3.0         # texels
static var chill_mist_alpha := 0.35
static var chill_whiten := 0.6            # how far mist and breath are lifted from the Ice hue
static var chill_breath_period := 2.6
static var chill_breath_count := 4
static var chill_breath_speed := 0.35
static var chill_breath_life := 1.0
static var chill_breath_size := 2.0       # texels
static var chill_breath_alpha := 0.6
static var chill_breath_x := 0.7          # the anchor, as a share of the ink box across the UNFLIPPED art
static var chill_breath_y := 0.2          # ...and down from the top of the ink


static func push(material: ShaderMaterial, wet: float, chill: float, icicles: float, clock: float,
		seed: float) -> void:
	material.set_shader_parameter("wet", wet)
	material.set_shader_parameter("chill", chill)
	material.set_shader_parameter("icicles", icicles)
	material.set_shader_parameter("status_time", clock)
	material.set_shader_parameter("status_seed", seed)
	material.set_shader_parameter("wet_hue", ElementPalette.color_for_state(Elemental.State.WET))
	material.set_shader_parameter("chill_hue", ElementPalette.color_for_state(Elemental.State.CHILLED))
	material.set_shader_parameter("wet_tint", wet_tint)
	material.set_shader_parameter("wet_streak_speed", wet_streak_speed)
	material.set_shader_parameter("wet_streak_density", wet_streak_density)
	material.set_shader_parameter("wet_streak_glow", wet_streak_glow)
	material.set_shader_parameter("chill_tint", chill_tint)
	material.set_shader_parameter("chill_sheen_period", chill_sheen_period)
	material.set_shader_parameter("chill_sheen_width", chill_sheen_width)
	material.set_shader_parameter("chill_sheen_glow", chill_sheen_glow)
	material.set_shader_parameter("chill_rime_glow", chill_rime_glow)
	material.set_shader_parameter("chill_glint_rate", chill_glint_rate)
	material.set_shader_parameter("chill_glint_glow", chill_glint_glow)
	material.set_shader_parameter("icicle_min_texels", icicle_min_texels)
	material.set_shader_parameter("icicle_max_texels", icicle_max_texels)
