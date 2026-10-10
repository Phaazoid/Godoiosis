// The wind's cloud shadows (#1286): a full-screen quad that finds the surface each pixel shows (the
// depth buffer, as fog_pass.gdshader does), samples WeatherArt's seamless noise there at a cloud's size,
// drifting with the wind, and darkens what lies under a cloud. The sky past the board is skipped, so
// the void stays untouched. Optional pixel steps snap the sample to the ground's art grid and step the
// edge, so it reads as pixel art.
//
// It sorts under every piece of markup and under the fog (BoardOverlays.CLOUD_RENDER_PRIORITY), and
// units draw after it: a passing cloud shades the ground and the props, never a move tile or a unit.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D cloud_noise : filter_linear, repeat_enable;
uniform vec2 drift = vec2(0.0);         // world units the clouds have travelled
uniform float cover : hint_range(0.0, 1.0) = 0.35;
uniform float darkness : hint_range(0.0, 1.0) = 0.22;
uniform float cloud_size = 10.0;        // world units across one cloud
uniform float softness = 0.12;
uniform float pixel_steps = 1.0;
uniform float art_pixels = 16.0;        // the ground's art pixels a cell
uniform float cell_size = 1.0;

// The noise tile holds about this many clouds across, at its own frequency.
const float CLOUDS_PER_TILE = 4.0;
// With pixel steps, a shadow's edge darkens in this many steps rather than smoothly.
const float BANDS = 3.0;
// Past this, a ray has hit nothing but sky.
const float FAR = 0.00001;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	float shade = 0.0;
	if (d > FAR) {
		vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
		vec2 p = world.xz / world.w;
		if (pixel_steps > 0.5) {
			p = (floor(p * art_pixels / cell_size) + 0.5) * cell_size / art_pixels;
		}
		float n = texture(cloud_noise, (p - drift) / max(cloud_size * CLOUDS_PER_TILE, 0.01)).r;
		float edge = mix(0.72, 0.28, cover);
		shade = smoothstep(edge - softness, edge + softness, n);
		if (pixel_steps > 0.5) {
			shade = floor(shade * BANDS + 0.5) / BANDS;
		}
	}
	ALBEDO = vec3(0.0);
	ALPHA = shade * darkness;
}
