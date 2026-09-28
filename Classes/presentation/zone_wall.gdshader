// A zone's wall (#955): light standing just inside its perimeter, strongest at its foot and fading to
// nothing at the top, with a slow shimmer rising through it. The kind's colour rides the vertex colour
// and the strip's strength its alpha (a lit zone is stronger), so every zone is one mesh and one draw.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform float shimmer_speed = 0.45;

void fragment() {
	float rise = UV.y;
	float shimmer = 0.72 + 0.28 * sin(6.2831853 * (rise * 1.3 - TIME * shimmer_speed));
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * pow(1.0 - rise, 1.2) * shimmer;
}
