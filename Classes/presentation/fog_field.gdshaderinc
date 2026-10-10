// How thick the fog is at a world point (#1285), 0..1: the ONE answer, read by the fog pass and the
// fog cards alike, so a card can never drift where the pass says there is none. The ground under the
// point is WeatherMask's; FogGround's field gives the edge fade (R), the pooled depth (G) and the share over water (B), sampled
// LINEAR so both ease from cell to cell. The noise drifts by `fog_drift`, which the mirror advances on
// its own (scaled) clock, so a hitstop holds the fog with the world.

#include "res://Classes/presentation/weather_mask.gdshaderinc"

uniform sampler2D fog_field : filter_linear, repeat_disable;
uniform sampler2D fog_noise : filter_linear, repeat_enable;
uniform float layer_amount = 1.0;
uniform float layer_depth = 0.8;
uniform float pool_amount = 1.0;
uniform float bank_amount = 0.0;
uniform float bank_height = 1.5;
uniform float bank_size = 7.0;
uniform float breakup = 0.6;
uniform vec2 fog_drift = vec2(0.0);

// Cells across one tile of the breakup noise; a bank's tile holds about four banks.
const float FOG_BREAKUP_CELLS = 12.5;
const float FOG_BANKS_PER_TILE = 4.0;

float fog_amount(vec3 p) {
	float ground = weather_surface(p.xz);
	float result = 0.0;
	if (ground > WEATHER_VOID * 0.5) {
		float above = p.y - ground;
		if (above > -0.1) {
			vec2 uv = (p.xz / cell_size - mask_origin) / vec2(textureSize(fog_field, 0));
			vec3 here = texture(fog_field, uv).rgb;
			float layer = layer_amount * (1.0 - smoothstep(0.0, layer_depth, above));
			float pool = pool_amount * min(here.g / 0.1, 1.0) * (1.0 - smoothstep(here.g * 0.4, here.g + 0.15, above));
			vec2 drifted = p.xz / cell_size - fog_drift;
			float low = texture(fog_noise, drifted / (bank_size * FOG_BANKS_PER_TILE)).r;
			float bank = bank_amount * smoothstep(0.48, 0.62, low) * (1.0 - smoothstep(0.0, bank_height, above));
			float n = texture(fog_noise, drifted / FOG_BREAKUP_CELLS).r;
			result = max(max(layer, pool), bank) * here.r * here.b * mix(1.0 - breakup, 1.0, n);
		}
	}
	return result;
}

// The share of the fog that stands over the ground at this point (FogGround's B, #1302): less than 1 over
// water, so a card drifting out over a river thins with it.
float fog_share(vec2 xz) {
	vec2 uv = (xz / cell_size - mask_origin) / vec2(textureSize(fog_field, 0));
	return texture(fog_field, uv).b;
}
