// A unit sprite wearing an element state (#358). Included by unit_status.gdshader (real sprites) and
// unit_status_ghost.gdshader (planning ghosts), which differ only in render_mode.
//
// THE FIRST HALF IS A HAND COPY OF THE ENGINE'S OWN Sprite3D MATERIAL: BaseMaterial3D's code for a
// shaded, double-sided, FIXED_Y-billboarded sprite whose albedo comes from the vertex colour. Measured
// pixel-identical to the engine sprite on 4.7.1 (tools/sprite_parity/), shadows and flip included. The
// engine stays authoritative; after an engine upgrade, re-run that probe before trusting this half.
// A sprite only carries this material while it wears a state, so everything else keeps the engine's.
//
// The second half draws the state from StatusArt's effect map. Tint goes to ALBEDO, so it is lit
// with the sprite; the bright marks go to EMISSION, so they still read on a dark board. Every mark
// sits on the art's own texel grid, and time is status_time, never TIME, so a hitstop freezes it.

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color, filter_nearest, repeat_enable;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float specular : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float metallic : hint_range(0.0, 1.0, 0.01) = 0.0;

uniform sampler2D status_map : filter_nearest, repeat_enable;
uniform float wet = 0.0;
uniform float chill = 0.0;
uniform float icicles = 0.0;
uniform float status_time = 0.0;
uniform float status_seed = 0.0;
uniform vec4 wet_hue : source_color = vec4(0.353, 0.682, 0.91, 1.0);
uniform vec4 chill_hue : source_color = vec4(0.557, 0.827, 0.918, 1.0);
uniform float wet_tint = 0.35;
uniform float wet_streak_speed = 0.7;
uniform float wet_streak_density = 0.5;
uniform float wet_streak_glow = 0.6;
uniform float chill_tint = 0.55;
uniform float chill_sheen_period = 3.3;
uniform float chill_sheen_width = 0.045;
uniform float chill_sheen_glow = 0.6;
uniform float chill_rime_glow = 0.5;
uniform float chill_glint_rate = 0.1;
uniform float chill_glint_glow = 1.0;
uniform float icicle_min_texels = 2.0;
uniform float icicle_max_texels = 4.0;

// StatusArt stores icicle depth as k / ICICLE_SCALE.
const float ICICLE_SCALE = 8.0;

float status_hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// The two TINTS are mixed in display space, as the approved mockup mixed them. The same formulas run
// on linear albedo come out far stronger on dark texels -- measured, they turned the art's black
// outline mid-blue -- and an outline is what makes the silhouette read.
vec3 status_to_display(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2));
}

vec3 status_to_linear(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(2.2));
}

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(normalize(cross(vec3(0.0, 1.0, 0.0), MAIN_CAM_INV_VIEW_MATRIX[2].xyz)), 0.0),
			vec4(0.0, 1.0, 0.0, 0.0),
			vec4(normalize(cross(MAIN_CAM_INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
			MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 tint = COLOR;
	if (!OUTPUT_IS_SRGB) {
		tint.rgb = mix(pow((tint.rgb + vec3(0.055)) * (1.0 / (1.0 + 0.055)), vec3(2.4)),
				tint.rgb * (1.0 / 12.92), lessThan(tint.rgb, vec3(0.04045)));
	}
	vec4 art = texture(texture_albedo, UV);
	vec4 albedo_tex = art * tint;
	vec3 rgb = albedo.rgb * albedo_tex.rgb;
	float alpha = albedo.a * albedo_tex.a;
	vec3 glow = vec3(0.0);

	vec2 size = vec2(textureSize(texture_albedo, 0));
	vec2 texel = floor(UV * size);
	vec4 fx = texture(status_map, (texel + 0.5) / size);
	bool body = art.a >= 0.5;
	float column = status_hash(vec2(texel.x, status_seed));

	if (body && wet > 0.0) {
		vec3 shown = status_to_display(rgb);
		vec3 hue = status_to_display(wet_hue.rgb);
		rgb = status_to_linear(mix(shown, (shown * 0.45 + hue * 0.55) * 0.9, wet_tint * wet));
		if (column < wet_streak_density) {
			float run = fract(texel.y / 8.0 - status_time * wet_streak_speed * (0.5 + 0.5 * column) + column * 7.0);
			if (run < 0.2) {
				glow += mix(wet_hue.rgb, vec3(1.0), 0.5) * (1.0 - run * 5.0) * wet_streak_glow * wet;
			}
		}
	}

	if (body && chill > 0.0) {
		vec3 frost = mix(chill_hue.rgb, vec3(1.0), 0.75);
		vec3 shown = status_to_display(rgb);
		float lum = dot(shown, vec3(0.3, 0.59, 0.11));
		rgb = status_to_linear(mix(shown, lum * status_to_display(chill_hue.rgb) * 1.28, chill_tint * chill));
		glow += frost * fx.r * chill_rime_glow * chill;
		float band = fract(status_time / max(chill_sheen_period, 0.01) + status_seed) * 1.7 - 0.35;
		if (abs(fx.b - band - fx.a * 0.3) < chill_sheen_width) {
			glow += frost * chill_sheen_glow * chill;
		}
		float glint = status_hash(texel + vec2(status_seed * 3.1, 0.0));
		if (glint < chill_glint_rate) {
			float phase = fract(status_time * 0.5 + glint * 170.0);
			if (phase < 0.08) {
				glow += vec3(1.0) * (1.0 - phase / 0.08) * chill_glint_glow * chill;
			}
		}
	}

	if (!body && icicles > 0.0 && fx.g > 0.0) {
		float k = floor(fx.g * ICICLE_SCALE + 0.5);
		float reach = floor(mix(icicle_min_texels, icicle_max_texels + 0.999, column) * icicles);
		if (k <= reach) {
			vec3 ice = mix(chill_hue.rgb, vec3(1.0), 0.55);
			rgb = ice;
			alpha = albedo.a * tint.a;
			glow += (k >= reach ? vec3(1.0) : ice) * 0.4 * icicles;
		}
	}

	ALBEDO = rgb;
	EMISSION = glow;
	METALLIC = metallic;
	SPECULAR = specular;
	ROUGHNESS = roughness;
	ALPHA *= alpha;
}
