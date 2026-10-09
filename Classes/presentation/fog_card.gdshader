// The fog's cards (#1285): pixel wisps that carry the fog's look (the dev's pick, "cards lead"). Born on
// the ground anywhere in the view (splash.gdshader's way, through WeatherMask) at up to `lift` above it,
// but only where fog_field says there is fog at that height. They drift with the wind, ride the surface
// as they go, die over the void, and re-read the fog every frame: CUSTOM.x is how present the fog is
// where the card now floats, so one drifting out of it fades. CUSTOM.y is its age (0..1), CUSTOM.z its
// frame, CUSTOM.w its own height over the ground.
shader_type particles;

#include "res://Classes/presentation/fog_field.gdshaderinc"

uniform vec3 box_min = vec3(0.0);
uniform vec3 box_max = vec3(1.0);
uniform float keep : hint_range(0.0, 1.0) = 1.0;
uniform vec3 velocity = vec3(0.3, 0.0, 0.1);
uniform float lift = 0.55;
uniform float frames = 3.0;

// How much fog a card needs under it to be born, and how much reads as fully present.
const float BORN_ABOVE = 0.05;
const float FULL = 0.35;

void start() {
	uint seed = weather_hash(NUMBER + uint(41) + RANDOM_SEED);
	if (RESTART_CUSTOM) {
		CUSTOM = vec4(0.0);
	}
	if (RESTART_POSITION) {
		vec2 p = mix(box_min.xz, box_max.xz, vec2(weather_rand(seed), weather_rand(seed)));
		float s = weather_surface(p);
		float h = lift * (0.5 + 0.5 * weather_rand(seed));
		CUSTOM.z = floor(weather_rand(seed) * frames);
		CUSTOM.w = h;
		TRANSFORM = mat4(1.0);
		TRANSFORM[3].xyz = vec3(p.x, s + h, p.y);
		if (s < WEATHER_VOID * 0.5 || weather_rand(seed) > keep || fog_amount(TRANSFORM[3].xyz) < BORN_ABOVE) {
			ACTIVE = false;
		}
	}
	if (RESTART_VELOCITY) {
		VELOCITY = velocity * (0.8 + 0.4 * weather_rand(seed));
	}
}

void process() {
	CUSTOM.y += DELTA / LIFETIME;
	vec3 at = TRANSFORM[3].xyz;
	float s = weather_surface(at.xz);
	if (s < WEATHER_VOID * 0.5) {
		ACTIVE = false;
	} else {
		// Eased onto the surface, so a card drifting up a terrace climbs rather than jumps.
		TRANSFORM[3].y = mix(at.y, s + CUSTOM.w, 1.0 - exp(-4.0 * DELTA));
		CUSTOM.x = smoothstep(0.0, FULL, fog_amount(TRANSFORM[3].xyz));
	}
}
