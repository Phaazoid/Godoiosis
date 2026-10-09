// Where the rain lands (#1260): a ring born on the ground somewhere in the view, lying on the
// surface's own slope, aging into splash_draw's flipbook. Not tied to a particular drop -- born at the
// drops' rate over the same box, it reads the same and needs no sub-emitter.
shader_type particles;

#include "res://Classes/presentation/weather_mask.gdshaderinc"

uniform vec3 box_min = vec3(0.0);
uniform vec3 box_max = vec3(1.0);
uniform float floor_y = -50.0;
uniform float lift = 0.01;
uniform float keep : hint_range(0.0, 1.0) = 1.0;

void start() {
	uint seed = weather_hash(NUMBER + uint(7) + RANDOM_SEED);
	if (RESTART_POSITION) {
		vec2 p = mix(box_min.xz, box_max.xz, vec2(weather_rand(seed), weather_rand(seed)));
		float s = weather_surface(p);
		// The slope, from two nearby samples: a ring on a ramp lies on the ramp.
		float e = 0.04;
		vec3 tx = vec3(e, weather_surface(p + vec2(e, 0.0)) - s, 0.0);
		vec3 tz = vec3(0.0, weather_surface(p + vec2(0.0, e)) - s, e);
		vec3 up = normalize(cross(tz, tx));
		if (abs(tx.y) > 1.0 || abs(tz.y) > 1.0) {
			up = vec3(0.0, 1.0, 0.0);   // a sample crossed a cliff edge; lie flat
		}
		vec3 x = normalize(cross(up, vec3(0.0, 0.0, 1.0)));
		TRANSFORM = mat4(1.0);
		TRANSFORM[0].xyz = x;
		TRANSFORM[1].xyz = up;
		TRANSFORM[2].xyz = cross(x, up);
		TRANSFORM[3].xyz = vec3(p.x, s + lift, p.y);
		if (s < floor_y || weather_rand(seed) > keep) {
			ACTIVE = false;
		}
	}
	VELOCITY = vec3(0.0);
	CUSTOM = vec4(0.0);
}

void process() {
	CUSTOM.y += DELTA / LIFETIME;
}
