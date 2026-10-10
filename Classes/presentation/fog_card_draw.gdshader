// A fog card (#1285): a camera-facing quad of one of WeatherArt.fog_wisps' frames, picked per card by
// fog_card.gdshader's CUSTOM.z. It fades in and out over its life (CUSTOM.y), with the fog under it
// (CUSTOM.x), as it dissolves against rising ground (the particle's COLOR.a), and near the lens,
// rain_drop's rule. Drawn at the ground art's pixel size, the density the
// dev picked it at, so it is deliberately chunkier than a unit's sprite.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D wisps : source_color, filter_nearest;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec2 size = vec2(2.75, 0.875);   // world size of one frame
uniform float frames = 3.0;
uniform vec2 near_fade = vec2(3.0, 9.0);

varying float seen_from;
varying float frame;
varying float age;
varying float present;
varying float whole;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	seen_from = distance(CAMERA_POSITION_WORLD, origin);
	frame = INSTANCE_CUSTOM.z;
	age = INSTANCE_CUSTOM.y;
	present = INSTANCE_CUSTOM.x;
	whole = COLOR.a;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = origin + right * VERTEX.x * size.x + up * VERTEX.y * size.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec4 t = texture(wisps, vec2((UV.x + frame) / frames, UV.y));
	float life = sin(3.14159265 * clamp(age, 0.0, 1.0));
	ALBEDO = t.rgb * tint.rgb;
	ALPHA = t.a * tint.a * life * present * whole * smoothstep(near_fade.x, near_fade.y, seen_from);
}
