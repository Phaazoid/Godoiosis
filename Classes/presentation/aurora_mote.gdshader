// The aurora's rising motes (#1298): born anywhere in the view, on the ground under them (WeatherMask,
// as a speck is) and up to `height` over it, rising at their own share of `rise` and wandering a little
// sideways, and drifting with the board's wind -- straight up on a calm board. They die over the void.
// CUSTOM.x is a mote's own phase, CUSTOM.y its age (0..1), CUSTOM.zw its own sideways wander on x / z;
// aurora_mote_draw.gdshader draws it.
shader_type particles;

#include "res://Classes/presentation/weather_mask.gdshaderinc"

uniform vec3 box_min = vec3(0.0);
uniform vec3 box_max = vec3(1.0);
uniform float keep : hint_range(0.0, 1.0) = 1.0;
uniform float rise = 0.3;               // world units a second, on average
uniform float wander = 0.3;             // a mote's sideways speed, as a share of its rise
uniform vec2 wind = vec2(0.0);          // world units a second on x / z: the mote's share of the wind
uniform float height = 0.6;             // world units over the ground a mote is born, at most

// How far over the ground a mote is held at its birth, so one born on a slope never starts inside it.
const float SKIM = 0.06;

void start() {
	uint seed = weather_hash(NUMBER + uint(83) + RANDOM_SEED);
	if (RESTART_CUSTOM) {
		CUSTOM = vec4(0.0);
	}
	if (RESTART_POSITION) {
		vec2 p = mix(box_min.xz, box_max.xz, vec2(weather_rand(seed), weather_rand(seed)));
		float s = weather_surface(p);
		TRANSFORM = mat4(1.0);
		TRANSFORM[3].xyz = vec3(p.x, s + SKIM + height * weather_rand(seed), p.y);
		CUSTOM.x = weather_rand(seed) * 6.2831853;
		if (s < WEATHER_VOID * 0.5 || weather_rand(seed) > keep) {
			ACTIVE = false;
		}
	}
	if (RESTART_VELOCITY) {
		float speed = rise * (0.6 + 0.8 * weather_rand(seed));
		float turn = weather_rand(seed) * 6.2831853;
		CUSTOM.zw = vec2(cos(turn), sin(turn)) * speed * wander;
		VELOCITY = vec3(CUSTOM.z + wind.x, speed, CUSTOM.w + wind.y);
	}
}

void process() {
	CUSTOM.y += DELTA / LIFETIME;
	vec3 at = TRANSFORM[3].xyz;
	if (weather_surface(at.xz) < WEATHER_VOID * 0.5) {
		ACTIVE = false;
	} else {
		VELOCITY.xz = CUSTOM.zw + wind;
	}
}
