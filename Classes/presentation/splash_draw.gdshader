// A splash ring (#1260): WeatherArt's strip played as a flipbook on the particle's age, which
// splash.gdshader counts into CUSTOM.y. The quad lies on the particle's basis, i.e. on the ground.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

uniform sampler2D strip : source_color, filter_nearest;
uniform float frames = 4.0;
uniform vec4 tint : source_color = vec4(1.0);

varying float age;

void vertex() {
	age = INSTANCE_CUSTOM.y;
}

void fragment() {
	float frame = clamp(floor(age * frames), 0.0, frames - 1.0);
	vec4 t = texture(strip, vec2((UV.x + frame) / frames, UV.y));
	ALBEDO = t.rgb * tint.rgb;
	ALPHA = t.a * tint.a;
}
