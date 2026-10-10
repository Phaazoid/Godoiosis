// A rising aurora mote (#1298), drawn as glow (additive) in `tint`, at the sprites' art density: a DOT is
// a 2x2-pixel square facing the camera, a STREAK a 1x6-pixel thread standing upright and turning to face
// the camera about its own axis, its pixels stepping from dim at the top to bright at the bottom. Faded
// in and out over its life, and near the lens, rain_drop's rule. The shape is generated here, so a mote
// needs no art.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0);   // its alpha fades the motes with the weather
uniform float texel = 0.03125;                  // one art pixel, in world units
uniform float shape = 0.0;                      // 0 dots, 1 streaks: WeatherLook.MoteShape
uniform vec2 near_fade = vec2(3.0, 9.0);

const float DOT_PIXELS = 2.0;
const float STREAK_PIXELS = 6.0;

varying float seen_from;
varying float age;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	seen_from = distance(CAMERA_POSITION_WORLD, origin);
	age = INSTANCE_CUSTOM.y;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec2 size = vec2(DOT_PIXELS) * texel;
	if (shape > 0.5) {
		vec3 to_eye = CAMERA_POSITION_WORLD - origin;
		to_eye.y = 0.0;
		if (length(to_eye) > 0.0001) {
			right = normalize(vec3(to_eye.z, 0.0, -to_eye.x));
		}
		up = vec3(0.0, 1.0, 0.0);
		size = vec2(1.0, STREAK_PIXELS) * texel;
	}
	vec3 world = origin + right * VERTEX.x * size.x + up * VERTEX.y * size.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

// In fast, holding, out slowly: 0 at birth, full by a fifth of its life, 0.9 by two thirds, then gone.
float life_fade(float t) {
	if (t < 0.2) {
		return t / 0.2;
	}
	if (t < 0.65) {
		return mix(1.0, 0.9, (t - 0.2) / 0.45);
	}
	return 0.9 * clamp(1.0 - (t - 0.65) / 0.35, 0.0, 1.0);
}

void fragment() {
	float pixel = 1.0;
	if (shape > 0.5) {
		float row = min(floor(UV.y * STREAK_PIXELS), STREAK_PIXELS - 1.0);
		pixel = 0.25 + 0.75 * row / (STREAK_PIXELS - 1.0);
	}
	ALBEDO = tint.rgb;
	ALPHA = pixel * tint.a * life_fade(clamp(age, 0.0, 1.0)) * smoothstep(near_fade.x, near_fade.y, seen_from);
}
