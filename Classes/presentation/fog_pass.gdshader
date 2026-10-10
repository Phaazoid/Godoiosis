// The fog's body (#1285): a full-screen quad that marches each view ray from the eye to the surface the
// depth buffer holds, through fog_field's density, and builds up opacity -- so fog lies thicker where the
// ray crosses more of it, pools in the low ground and banks up, and stops at the ground rather than
// painting it. Only the slab fog can stand in is marched (slab_low..slab_high, world y), in STEPS jittered
// samples. PIXEL steps snap each sample's x and z to the ground's art grid (never y: that stairs every
// wall) and band the opacity, so the edges read as pixel art.
//
// It sorts under every piece of markup (BoardOverlays.FOG_RENDER_PRIORITY), and units draw after it: the
// pass veils the ground, and only the cards cross a unit.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

#include "res://Classes/presentation/fog_field.gdshaderinc"
#include "res://Classes/presentation/screen_ground.gdshaderinc"

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 tint : source_color = vec4(0.86, 0.89, 0.93, 1.0);
uniform float strength = 1.2;
uniform float slab_low = 0.0;
uniform float slab_high = 5.0;
uniform float pixel_steps = 0.0;
uniform float art_pixels = 16.0;   // the ground's art pixels a cell

const int STEPS = 24;
const float BANDS = 6.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	vec3 end = screen_world(max(d, SCREEN_SKY), SCREEN_UV, INV_VIEW_MATRIX, INV_PROJECTION_MATRIX);
	vec3 eye = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 ray = end - eye;
	float len = length(ray);
	vec3 dir = ray / max(len, 0.0001);
	float t0 = 0.0;
	float t1 = len;
	if (abs(dir.y) > 0.0001) {
		float ta = (slab_high - eye.y) / dir.y;
		float tb = (slab_low - eye.y) / dir.y;
		t0 = max(0.0, min(ta, tb));
		t1 = min(len, max(ta, tb));
	}
	float tau = 0.0;
	if (t1 > t0) {
		float dt = (t1 - t0) / float(STEPS);
		float jitter = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		for (int i = 0; i < STEPS; i++) {
			vec3 p = eye + dir * (t0 + (float(i) + jitter) * dt);
			if (pixel_steps > 0.5) {
				p.xz = screen_art_snap(p.xz, art_pixels, cell_size);
			}
			tau += fog_amount(p) * strength * dt;
		}
	}
	float a = 1.0 - exp(-tau);
	if (pixel_steps > 0.5) {
		a = screen_steps(a, BANDS);
	}
	ALBEDO = tint.rgb;
	ALPHA = a * tint.a;
}
