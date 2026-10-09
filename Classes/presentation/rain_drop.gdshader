// A drop's streak (#1260): a quad standing on the particle's own Y axis (the fall, reversed) and
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

varying float seen_from;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 axis = normalize(MODEL_MATRIX[1].xyz);
	seen_from = distance(CAMERA_POSITION_WORLD, origin);
	vec3 to_camera = normalize(CAMERA_POSITION_WORLD - origin);
	vec3 side = normalize(cross(axis, to_camera));
	vec3 world = origin + side * VERTEX.x * size.x + axis * (VERTEX.y + 0.5) * size.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec4 t = texture(streak, UV);
	ALBEDO = t.rgb * tint.rgb;
	ALPHA = t.a * tint.a * smoothstep(near_fade.x, near_fade.y, seen_from);
}
