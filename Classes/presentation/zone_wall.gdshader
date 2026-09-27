// Look C of the zone experiment (#955): a wall of light standing on a zone's perimeter, strongest at
// its foot and fading to nothing at the top, with a slow shimmer rising through it. The kind's colour
// rides the vertex colour, so every zone on the board is one mesh and one draw (ZoneWalls).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform float strength = 0.8;
uniform float shimmer_speed = 0.45;

void fragment() {
	float rise = UV.y;
	float shimmer = 0.72 + 0.28 * sin(6.2831853 * (rise * 1.3 - TIME * shimmer_speed));
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * strength * pow(1.0 - rise, 1.2) * shimmer;
}
