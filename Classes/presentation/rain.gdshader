// The rain's drops (#1260): born in a box over the view, falling at one velocity, gone the instant
// they reach the surface under them (WeatherMask) or the floor below the frame. The project's first
// particles shader; WeatherMirror owns the box, the velocity and the floor.
shader_type particles;

#include "res://Classes/presentation/weather_mask.gdshaderinc"

uniform vec3 box_min = vec3(0.0);
uniform vec3 box_max = vec3(1.0);
uniform vec3 velocity = vec3(0.0, -14.0, 0.0);
uniform float floor_y = -50.0;
// The share of births kept: the box shrinks and grows with the camera while the system's amount stays
// put, so a smaller box drops the births it has no room for and the density stays the authored one.
uniform float keep : hint_range(0.0, 1.0) = 1.0;

void start() {
	uint seed = weather_hash(NUMBER + uint(1) + RANDOM_SEED);
	if (RESTART_POSITION) {
		vec3 r = vec3(weather_rand(seed), weather_rand(seed), weather_rand(seed));
		TRANSFORM = mat4(1.0);
		// The streak's own axis rides the basis: Y points back along the fall.
		vec3 y = -normalize(velocity);
		vec3 x = normalize(cross(y, vec3(0.0, 0.0, 1.0)));
		TRANSFORM[0].xyz = x;
		TRANSFORM[1].xyz = y;
		TRANSFORM[2].xyz = cross(x, y);
		TRANSFORM[3].xyz = mix(box_min, box_max, r);
		if (weather_rand(seed) > keep) {
			ACTIVE = false;
		}
	}
	if (RESTART_VELOCITY) {
		VELOCITY = velocity;
	}
}

void process() {
	vec3 at = TRANSFORM[3].xyz;
	if (at.y < max(weather_surface(at.xz), floor_y)) {
		ACTIVE = false;
	}
}
