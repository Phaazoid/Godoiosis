// A blown speck (#1286): a camera-facing quad of one of WeatherArt.specks' frames, picked per speck by
// wind_speck.gdshader's CUSTOM.z. A leaf tumbles through its frames as it flies; a mote holds its own.
// Tinted a leaf's or a mote's colour, faded in and out over its life, and near the lens, rain_drop's
// rule. Drawn at the sprites' art density, as a flake is.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D specks : source_color, filter_nearest;
uniform vec4 leaf_tint : source_color = vec4(1.0);
uniform vec4 dust_tint : source_color = vec4(1.0);
uniform float size = 0.15625;           // world size of one frame
uniform float leaf_frames = 4.0;
uniform float dust_frames = 2.0;
uniform float tumbles = 6.0;            // leaf frames a leaf turns through over its life
uniform vec2 near_fade = vec2(3.0, 9.0);

varying float seen_from;
varying float frame;
varying float age;
varying float leaf;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	seen_from = distance(CAMERA_POSITION_WORLD, origin);
	age = INSTANCE_CUSTOM.y;
	leaf = INSTANCE_CUSTOM.w;
	frame = INSTANCE_CUSTOM.z;
	if (leaf > 0.5) {
		frame = mod(frame + floor(age * tumbles), leaf_frames);
	}
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = origin + (right * VERTEX.x + up * VERTEX.y) * size;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec4 t = texture(specks, vec2((UV.x + frame) / (leaf_frames + dust_frames), UV.y));
	vec4 tint = leaf > 0.5 ? leaf_tint : dust_tint;
	float life = sin(3.14159265 * clamp(age, 0.0, 1.0));
	ALBEDO = t.rgb * tint.rgb;
	ALPHA = t.a * tint.a * life * smoothstep(near_fade.x, near_fade.y, seen_from);
}
