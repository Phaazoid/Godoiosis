// A drop's streak (#1260), and a blizzard's ground drift (#1269) laid along the ground: a quad standing on the particle's own Y axis (the fall, reversed) and
// turned about it to face the camera, so a wind-slanted drop slants and every drop faces you. The
// head sits on the particle's point; the tail trails back up the fall.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

uniform sampler2D streak : source_color, filter_nearest;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec2 size = vec2(0.03, 0.2);   // world width, world length
// A drop passing right by the lens would be a pillar across the frame, so it fades out between these
// distances from the camera (world units) instead.
uniform vec2 near_fade = vec2(1.5, 5.0);
// How much a streak fades in and out over its life (its process shader's CUSTOM.y, 0..1): 0 for rain,
// which writes no age, 1 for a blizzard's ground drift (#1269).
uniform float age_fade : hint_range(0.0, 1.0) = 0.0;

varying float seen_from;
varying float age;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 axis = normalize(MODEL_MATRIX[1].xyz);
	seen_from = distance(CAMERA_POSITION_WORLD, origin);
	age = INSTANCE_CUSTOM.y;
	vec3 to_camera = normalize(CAMERA_POSITION_WORLD - origin);
	vec3 side = normalize(cross(axis, to_camera));
	vec3 world = origin + side * VERTEX.x * size.x + axis * (VERTEX.y + 0.5) * size.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec4 t = texture(streak, UV);
	ALBEDO = t.rgb * tint.rgb;
	float life = mix(1.0, sin(3.14159 * clamp(age, 0.0, 1.0)), age_fade);
	ALPHA = t.a * tint.a * smoothstep(near_fade.x, near_fade.y, seen_from) * life;
}
