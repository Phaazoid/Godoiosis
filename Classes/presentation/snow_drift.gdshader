// A blizzard's ground drift (#1269): loose snow streaming along the wind just above the surface,
// born on the ground anywhere in the view (splash.gdshader's way, through WeatherMask) and riding the
// surface's height as it goes. It dies over the void, and where the ground steps away under it or
// rises in front of it -- a wall stops loose snow. Drawn by rain_drop.gdshader as a streak laid along
// its own velocity, fading in and out over its life (CUSTOM.y).
shader_type particles;

#include "res://Classes/presentation/weather_mask.gdshaderinc"

uniform vec3 box_min = vec3(0.0);
uniform vec3 box_max = vec3(1.0);
uniform float floor_y = -50.0;
uniform float keep : hint_range(0.0, 1.0) = 1.0;
uniform vec3 velocity = vec3(5.0, 0.0, 0.0);   // along the ground
uniform float hover = 0.05;                     // how far above the surface it skims
// The height change over one frame's travel past which the ground is a step, not a slope.
uniform float step_height = 0.3;

void start() {
	uint seed = weather_hash(NUMBER + uint(23) + RANDOM_SEED);
	if (RESTART_POSITION) {
		vec2 p = mix(box_min.xz, box_max.xz, vec2(weather_rand(seed), weather_rand(seed)));
		float s = weather_surface(p);
		vec3 along = length(velocity) > 0.001 ? normalize(velocity) : vec3(1.0, 0.0, 0.0);
		// The streak's own axis rides the basis, as a raindrop's does: Y points back along the travel.
		vec3 y = -along;
		vec3 x = normalize(cross(y, vec3(0.0, 1.0, 0.0)));
		TRANSFORM = mat4(1.0);
		TRANSFORM[0].xyz = x;
		TRANSFORM[1].xyz = y;
		TRANSFORM[2].xyz = cross(x, y);
		TRANSFORM[3].xyz = vec3(p.x, s + hover, p.y);
		if (s < floor_y || weather_rand(seed) > keep) {
			ACTIVE = false;
		}
	}
	if (RESTART_VELOCITY) {
		VELOCITY = velocity * (0.7 + 0.6 * weather_rand(seed));
	}
	CUSTOM = vec4(0.0);
}

void process() {
	CUSTOM.y += DELTA / LIFETIME;
	vec3 at = TRANSFORM[3].xyz;
	float s = weather_surface(at.xz);
	if (s < WEATHER_VOID * 0.5 || abs(s + hover - at.y) > step_height) {
		ACTIVE = false;
	} else {
		TRANSFORM[3].y = s + hover;
	}
}
