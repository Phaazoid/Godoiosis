// A sandstorm's blowing grit (#1302): the blizzard's ground drift (snow_drift.gdshader) lifted into the
// air. Each grain is born over the board on WeatherMask, flies along the wind at its own height over the
// ground -- most of them low -- rides the surface as it goes with a little bob, and dies over the void or
// where the ground rises into it: a wall stops blown sand. Drawn by rain_drop.gdshader as a streak laid
// along its own velocity, fading in and out over its life (CUSTOM.y).
shader_type particles;

#include "res://Classes/presentation/weather_mask.gdshaderinc"

uniform vec3 box_min = vec3(0.0);
uniform vec3 box_max = vec3(1.0);
uniform float keep : hint_range(0.0, 1.0) = 1.0;
uniform vec3 velocity = vec3(5.0, 0.0, 0.0);   // along the wind
uniform float hover = 0.05;                     // the lowest a grain flies over the surface
uniform float rise = 1.6;                       // how much higher one may fly
uniform float bob = 0.12;                       // world units it bobs up and down as it flies
// How far the ground may rise into a grain, over one frame's travel, before it is a wall.
uniform float step_height = 0.6;

void start() {
	uint seed = weather_hash(NUMBER + uint(41) + RANDOM_SEED);
	if (RESTART_POSITION) {
		vec2 p = mix(box_min.xz, box_max.xz, vec2(weather_rand(seed), weather_rand(seed)));
		float s = weather_surface(p);
		float h = hover + rise * pow(weather_rand(seed), 1.6);
		vec3 along = length(velocity) > 0.001 ? normalize(velocity) : vec3(1.0, 0.0, 0.0);
		// The streak's own axis rides the basis, as a raindrop's does: Y points back along the travel.
		vec3 y = -along;
		vec3 x = normalize(cross(y, vec3(0.0, 1.0, 0.0)));
		TRANSFORM = mat4(1.0);
		TRANSFORM[0].xyz = x;
		TRANSFORM[1].xyz = y;
		TRANSFORM[2].xyz = cross(x, y);
		TRANSFORM[3].xyz = vec3(p.x, s + h, p.y);
		CUSTOM = vec4(0.0, 0.0, h, weather_rand(seed) * 6.283);
		if (s < WEATHER_VOID * 0.5 || weather_rand(seed) > keep) {
			ACTIVE = false;
		}
	}
	if (RESTART_VELOCITY) {
		VELOCITY = velocity * (0.6 + 0.8 * weather_rand(seed));
	}
	CUSTOM.y = 0.0;
}

void process() {
	CUSTOM.y += DELTA / LIFETIME;
	vec3 at = TRANSFORM[3].xyz;
	float s = weather_surface(at.xz);
	float h = CUSTOM.z + bob * sin(CUSTOM.w + CUSTOM.y * 9.0);
	if (s < WEATHER_VOID * 0.5 || s + h - at.y > step_height) {
		ACTIVE = false;
	} else {
		TRANSFORM[3].y = mix(at.y, s + h, clamp(DELTA * 6.0, 0.0, 1.0));
	}
}
