// A snowflake (#1269): a camera-facing quad at the sprites' own texel density, drawing one of the two
// frames of WeatherArt.flakes -- a single art pixel or a plus -- picked per flake by snow.gdshader's
// CUSTOM.z, and fading as CUSTOM.y says the landed flake melts.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

uniform sampler2D flakes : source_color, filter_nearest;
uniform vec4 tint : source_color = vec4(1.0);
uniform float size = 0.1;   // world width of one frame
// A flake passing right by the lens would be a blot across the frame, so it fades out between these
// distances from the camera (world units) instead -- rain_drop's rule.
uniform vec2 near_fade = vec2(1.5, 5.0);

varying float seen_from;
varying float frame;
varying float melted;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	seen_from = distance(CAMERA_POSITION_WORLD, origin);
	frame = INSTANCE_CUSTOM.z > 0.5 ? 1.0 : 0.0;
	melted = INSTANCE_CUSTOM.y;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = origin + (right * VERTEX.x + up * VERTEX.y) * size;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec4 t = texture(flakes, vec2((UV.x + frame) * 0.5, UV.y));
	ALBEDO = t.rgb * tint.rgb;
	ALPHA = t.a * tint.a * smoothstep(near_fade.x, near_fade.y, seen_from) * (1.0 - clamp(melted, 0.0, 1.0));
}
