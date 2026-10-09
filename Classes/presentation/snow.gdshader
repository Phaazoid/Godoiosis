// The snow's flakes (#1269): born in rain's box over the view, falling slowly, wandering as they go,
// and LYING where they land for a moment before they melt -- over the void they fall on until the
// floor below the frame. WeatherMirror owns the box, the fall and the wander.
//
// The wander is two motions: a per-flake SWAY, a slow side-to-side drift, and a shared SWIRL, a
// divergence-free field of eddies that loops the flakes when it outruns the fall -- what keeps a
// blizzard from reading as rain (dev, 2026-10-09).
//
// CUSTOM: x and w a flake's two phases, y how far it has melted (0..1), z 1 for a big flake.
shader_type particles;

#include "res://Classes/presentation/weather_mask.gdshaderinc"

uniform vec3 box_min = vec3(0.0);
uniform vec3 box_max = vec3(1.0);
uniform vec3 velocity = vec3(0.0, -2.0, 0.0);
uniform float floor_y = -50.0;
uniform float keep : hint_range(0.0, 1.0) = 1.0;
uniform float sway = 0.3;
uniform float swirl = 0.0;
uniform float swirl_scale = 1.5;
uniform float settle = 0.8;          // seconds a landed flake lies before it is gone
uniform float big : hint_range(0.0, 1.0) = 0.15;
uniform float lift = 0.02;           // how far above the surface a landed flake's centre sits

// The eddies' velocity at `p`: the curl of two stream functions, one turning in the ground plane and
// one in the upright plane across the wind, drifting with time so the field is never still.
vec3 eddies(vec3 p, float t) {
	vec3 q = p / max(swirl_scale, 0.05);
	float a = q.x * 1.3 + t * 0.35;
	float b = q.z * 1.1 - t * 0.27;
	float c = q.y * 1.2 + t * 0.31;
	// psi1(x, z) = sin(a) * cos(b): (dpsi/dz, -dpsi/dx) in the ground plane.
	vec2 level = vec2(-sin(a) * sin(b) * 1.1, -cos(a) * cos(b) * 1.3);
	// psi2(x, y) = cos(a * 0.8 + 1.7) * sin(c): (dpsi/dy, -dpsi/dx) across the upright plane.
	vec2 upright = vec2(cos(a * 0.8 + 1.7) * cos(c) * 1.2, sin(a * 0.8 + 1.7) * sin(c) * 1.04);
	return vec3(level.x + upright.x, upright.y, level.y);
}

void start() {
	uint seed = weather_hash(NUMBER + uint(11) + RANDOM_SEED);
	if (RESTART_POSITION) {
		vec3 r = vec3(weather_rand(seed), weather_rand(seed), weather_rand(seed));
		TRANSFORM = mat4(1.0);
		TRANSFORM[3].xyz = mix(box_min, box_max, r);
		if (weather_rand(seed) > keep) {
			ACTIVE = false;
		}
	}
	if (RESTART_VELOCITY) {
		VELOCITY = velocity;
	}
	if (RESTART_CUSTOM) {
		CUSTOM = vec4(weather_rand(seed) * 6.2832, 0.0, weather_rand(seed) < big ? 1.0 : 0.0,
				weather_rand(seed) * 6.2832);
	}
}

// A particles processor may not `return`, so the three states are one chain: lying (melting away),
// landing this frame, falling.
void process() {
	vec3 at = TRANSFORM[3].xyz;
	float ground = weather_surface(at.xz);
	if (CUSTOM.y > 0.0) {
		VELOCITY = vec3(0.0);
		CUSTOM.y += DELTA / max(settle, 0.001);
	} else if (ground > WEATHER_VOID * 0.5 && at.y <= ground + lift) {
		TRANSFORM[3].y = ground + lift;
		VELOCITY = vec3(0.0);
		CUSTOM.y = settle > 0.0 ? 0.0001 : 1.0;
	} else if (at.y < floor_y) {
		CUSTOM.y = 1.0;
	} else {
		float t = TIME;
		vec3 wander = vec3(sin(t * 0.9 + CUSTOM.x), 0.0, cos(t * 0.7 + CUSTOM.w)) * sway;
		VELOCITY = velocity + wander + eddies(at, t) * swirl;
	}
	if (CUSTOM.y >= 1.0) {
		ACTIVE = false;
	}
}
