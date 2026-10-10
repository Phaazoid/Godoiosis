// The wind's blown specks (#1286): leaves and dust carried across the board, born anywhere in the view
// at up to `height` over the ground under them (WeatherMask, as a splash is) and flying with the wind,
// tumbling side to side across it as they go. They die over the void and against ground that rises past
// them. CUSTOM.x is a speck's own phase, CUSTOM.y its age (0..1), CUSTOM.z its art frame and CUSTOM.w
// 1 for a leaf, 0 for a mote; wind_speck_draw.gdshader draws it.
shader_type particles;

#include "res://Classes/presentation/weather_mask.gdshaderinc"

uniform vec3 box_min = vec3(0.0);
uniform vec3 box_max = vec3(1.0);
uniform float keep : hint_range(0.0, 1.0) = 1.0;
uniform vec2 wind = vec2(1.5, 0.0);     // world units a second on x / z, the gust included
uniform float flutter = 0.6;            // world units a second of tumble across the wind
uniform float height = 1.2;             // world units over the ground a speck flies, at most
uniform float leaves : hint_range(0.0, 1.0) = 0.5;
uniform float leaf_frames = 4.0;
uniform float dust_frames = 2.0;

// How far over the ground a speck is held, so one skimming a slope never sinks into it.
const float SKIM = 0.06;

void start() {
	uint seed = weather_hash(NUMBER + uint(61) + RANDOM_SEED);
	if (RESTART_CUSTOM) {
		CUSTOM = vec4(0.0);
	}
	if (RESTART_POSITION) {
		vec2 p = mix(box_min.xz, box_max.xz, vec2(weather_rand(seed), weather_rand(seed)));
		float s = weather_surface(p);
		TRANSFORM = mat4(1.0);
		TRANSFORM[3].xyz = vec3(p.x, s + SKIM + height * weather_rand(seed), p.y);
		bool leaf = weather_rand(seed) < leaves;
		CUSTOM.w = leaf ? 1.0 : 0.0;
		CUSTOM.z = leaf ? floor(weather_rand(seed) * leaf_frames) : leaf_frames + floor(weather_rand(seed) * dust_frames);
		CUSTOM.x = weather_rand(seed) * 6.2831853;
		if (s < WEATHER_VOID * 0.5 || weather_rand(seed) > keep) {
			ACTIVE = false;
		}
	}
	if (RESTART_VELOCITY) {
		VELOCITY = vec3(wind.x, 0.0, wind.y);
	}
}

void process() {
	CUSTOM.y += DELTA / LIFETIME;
	vec3 at = TRANSFORM[3].xyz;
	float s = weather_surface(at.xz);
	if (s < WEATHER_VOID * 0.5 || s > at.y + 0.3) {
		ACTIVE = false;
	} else {
		// Each speck rides its own share of the wind, and tumbles across it and up and down.
		float t = CUSTOM.y * LIFETIME;
		vec2 across = length(wind) > 0.001 ? normalize(vec2(-wind.y, wind.x)) : vec2(0.0, 1.0);
		float share = 0.7 + 0.6 * fract(CUSTOM.x * 0.1591549);
		VELOCITY.xz = wind * share + across * sin(t * 3.1 + CUSTOM.x) * flutter;
		VELOCITY.y = cos(t * 2.3 + CUSTOM.x) * flutter * 0.5;
		TRANSFORM[3].y = max(at.y, s + SKIM);
	}
}
