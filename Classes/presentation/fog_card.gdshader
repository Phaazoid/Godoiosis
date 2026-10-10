// The fog's cards (#1285): pixel wisps that carry the fog's look (the dev's pick, "cards lead"). Born on
// the ground anywhere on the board (the box WeatherMirror hands it) at up to `lift` above it,
// but only where fog_field says there is fog on the ground below. They drift with the wind, ride the
// surface DOWN as they go but never up (a card meeting higher ground holds its height and dissolves
// against the face), die over the void, and re-read the fog every frame: CUSTOM.x is how present the
// fog is on the ground under the card, so one drifting out of it fades. CUSTOM.y is its age (0..1),
// CUSTOM.z its frame, CUSTOM.w its own height over the ground; COLOR.a is how much of it has not yet
// dissolved.
shader_type particles;

#include "res://Classes/presentation/fog_field.gdshaderinc"

uniform vec3 box_min = vec3(0.0);
uniform vec3 box_max = vec3(1.0);
uniform float keep : hint_range(0.0, 1.0) = 1.0;
uniform vec3 velocity = vec3(0.3, 0.0, 0.1);
uniform float lift = 0.55;
uniform float frames = 3.0;

// How much fog a card needs on the ground under it to be born, and how much reads as fully present.
// Asked at the ground, not the card's own height: a card says WHERE there is fog, not how thick.
const float BORN_ABOVE = 0.05;
const float FULL = 0.2;
const float AT_GROUND = 0.05;
// How far the ground under a card may rise before it counts as climbing (floating noise on flat ground
// never trips it), and how long a card takes to dissolve once it has.
const float RISE_TOLERANCE = 0.05;
const float DISSOLVE_SECONDS = 0.5;

void start() {
	uint seed = weather_hash(NUMBER + uint(41) + RANDOM_SEED);
	if (RESTART_CUSTOM) {
		CUSTOM = vec4(0.0);
	}
	if (RESTART_COLOR) {
		COLOR = vec4(1.0);
	}
	if (RESTART_POSITION) {
		vec2 p = mix(box_min.xz, box_max.xz, vec2(weather_rand(seed), weather_rand(seed)));
		float s = weather_surface(p);
		float h = lift * (0.5 + 0.5 * weather_rand(seed));
		CUSTOM.z = floor(weather_rand(seed) * frames);
		CUSTOM.w = h;
		TRANSFORM = mat4(1.0);
		TRANSFORM[3].xyz = vec3(p.x, s + h, p.y);
		if (s < WEATHER_VOID * 0.5 || weather_rand(seed) > keep || fog_amount(vec3(p.x, s + AT_GROUND, p.y)) < BORN_ABOVE) {
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
		float rides = s + CUSTOM.w;
		if (COLOR.a < 1.0 || rides > at.y + RISE_TOLERANCE) {
			// Fog never climbs (dev): the ground rose under it, so it holds its height and dissolves
			// against the face, and once begun it finishes.
			COLOR.a = max(COLOR.a - DELTA / DISSOLVE_SECONDS, 0.0);
			if (COLOR.a <= 0.0) {
				ACTIVE = false;
			}
		} else {
			// Eased down onto lower ground, so a card rolls off a ledge rather than dropping.
			TRANSFORM[3].y = mix(at.y, rides, 1.0 - exp(-4.0 * DELTA));
		}
		CUSTOM.x = smoothstep(0.0, FULL, fog_amount(vec3(at.x, s + AT_GROUND, at.z)));
	}
}
