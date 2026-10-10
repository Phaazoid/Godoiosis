// The aurora's curtains of light on the ground (#1298): a full-screen pass that finds the surface each
// pixel shows (screen_ground.gdshaderinc) and ADDS bands of coloured light there -- glow, never paint, so
// it only ever brightens. Each band swings along its line, its colour ramping from `color_low` at its
// heart to `color_high` at its edge, broken along its length by drifting rays. Light thins off steep
// faces, so a curtain never streaks down a cliff. Pixel steps snap the ground point to the art grid and
// step the glow; off draws it soft. The sky past the board is skipped, so the void stays untouched.
//
// It sorts under the clouds' slot, the fog and every piece of markup (BoardOverlays.AURORA_RENDER_PRIORITY),
// and units draw after it: a move tile or a ring reads over the light, and the light on a unit is the
// aurora's own DirectionalLight3D, not this pass.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

#include "res://Classes/presentation/screen_ground.gdshaderinc"

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform vec4 color_low : source_color = vec4(0.25, 1.0, 0.55, 1.0);
uniform vec4 color_high : source_color = vec4(1.0, 0.35, 0.7, 1.0);
uniform float strength = 0.7;           // the glow, faded in and out with the weather
uniform int bands = 3;
uniform float spacing = 6.0;            // world units between bands
uniform float band_width = 1.4;         // world units across one band
uniform float wave = 2.5;               // world units a band swings either side of its line
uniform float wave_length = 14.0;       // world units along one swing
uniform float time = 0.0;               // the ripple's clock: the mirror's, scaled by the drift speed
uniform float rays = 0.6;               // 0..1: how much the rays break a band up
uniform float ray_spacing = 0.6;        // world units between rays
uniform float pulse = 1.0;              // the slow swell the light shares
uniform float angle = 0.5;              // radians the bands lie at
uniform vec2 centre = vec2(0.0);        // the board's centre, x / z: the bands lie across it
uniform float pixel_steps = 1.0;
uniform float art_pixels = 16.0;        // the ground's art pixels a cell
uniform float cell_size = 1.0;

// No more bands than this are drawn, whatever `bands` asks.
const int MAX_BANDS = 6;
// With pixel steps, the glow brightens in this many steps.
const float LEVELS = 5.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	float glow = 0.0;
	vec3 tint = vec3(0.0);
	if (!screen_is_sky(d)) {
		vec3 wp = screen_world(d, SCREEN_UV, INV_VIEW_MATRIX, INV_PROJECTION_MATRIX);
		vec3 nrm = normalize(cross(dFdy(wp), dFdx(wp)));
		float flatness = smoothstep(0.55, 0.85, abs(nrm.y));
		vec2 p = wp.xz;
		if (pixel_steps > 0.5) {
			p = screen_art_snap(p, art_pixels, cell_size);
		}
		vec2 q = p - centre;
		float ca = cos(angle);
		float sa = sin(angle);
		float u = q.x * ca + q.y * sa;
		float v = -q.x * sa + q.y * ca;
		float k = 6.2831853 / max(wave_length, 0.1);
		for (int i = 0; i < MAX_BANDS; i++) {
			if (i >= bands) {
				break;
			}
			float fi = float(i);
			float off = (fi - float(bands - 1) * 0.5) * spacing;
			float line = off + wave * sin(u * k + time * 0.35 + fi * 2.1)
					+ wave * 0.45 * sin(u * k * 2.3 - time * 0.6 + fi * 4.7);
			float across = (v - line) / max(band_width, 0.01);
			float body = exp(-across * across * 1.6);
			float n = texture(noise_tex, vec2(u / max(ray_spacing * 4.0, 0.01) + time * 0.04 + fi * 0.37,
					fi * 0.21 + time * 0.05)).r;
			float ray = mix(1.0, 0.25 + 1.5 * n, rays);
			float fringe = smoothstep(0.0, 1.6, across);
			float a = body * ray;
			glow += a;
			tint += mix(color_low.rgb, color_high.rgb, fringe) * a;
		}
		glow *= flatness;
		tint *= flatness;
	}
	vec3 col = glow > 0.0001 ? tint / glow : vec3(0.0);
	float level = glow * pulse;
	if (pixel_steps > 0.5) {
		level = screen_steps(level, LEVELS);
	}
	ALBEDO = col * level * strength;
	ALPHA = 1.0;
}
