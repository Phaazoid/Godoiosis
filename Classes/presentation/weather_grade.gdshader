// The weather's own grade over the board (#1269): a full-screen rect on a canvas layer BELOW the 2D
// game's, reading the finished 3D frame -- so it grades the board after the board's own look and never
// touches the HUD (measured on 4.7.1 before it was built). Saturation, brightness and a tint pulled
// toward the frame's own brightness, then the whiteout: slow bands of noise drifting across the view.
// Time arrives as veil_offset, advanced by WeatherGrade, never TIME.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float saturation = 1.0;
uniform float brightness = 1.0;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.0);   // alpha is how much
uniform float veil = 0.0;
uniform vec2 veil_offset = vec2(0.0);
uniform vec4 veil_color : source_color = vec4(0.92, 0.94, 0.97, 1.0);
uniform vec2 veil_scale = vec2(2.5, 5.0);   // bands across and down the screen

// A lattice corner's value, from its INTEGER coordinates (#1278). A fract(sin()) hash made a last-bit
// rounding difference a different value, so neighbouring cells disagreed about a shared corner and
// the veil drew a checkerboard of hard edges.
float grade_hash(ivec2 p) {
	uint h = uint(p.x) * 1597334677u ^ uint(p.y) * 3812015801u;
	h = (h ^ (h >> 16u)) * 2246822519u;
	h ^= h >> 13u;
	return float(h & 65535u) / 65535.0;
}

float grade_noise(vec2 p) {
	ivec2 i = ivec2(floor(p));
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(grade_hash(i), grade_hash(i + ivec2(1, 0)), u.x),
			mix(grade_hash(i + ivec2(0, 1)), grade_hash(i + ivec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation) * brightness;
	c = mix(c, tint.rgb * l * 1.15, tint.a);
	if (veil > 0.0) {
		vec2 p = SCREEN_UV * veil_scale + veil_offset;
		float n = grade_noise(p) * 0.65 + grade_noise(p * 2.3 + vec2(5.2, 1.3)) * 0.35;
		c = mix(c, veil_color.rgb, smoothstep(0.35, 0.85, n) * veil);
	}
	COLOR = vec4(c, 1.0);
}
