// FrozenInIce's glass (#1506): a crystal is clear where a face looks at the camera and dark and near
// solid along its edges, so the ice reads against an ice floor while the body inside still shows.
// Writes no depth: the body behind it is opaque and already drawn. Values are pushed every frame from
// StatusLook.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

uniform vec4 ice_color : source_color = vec4(0.557, 0.827, 0.918, 1.0);
uniform vec4 edge_color : source_color = vec4(0.12, 0.28, 0.5, 1.0);
uniform float face_alpha = 0.16;
uniform float edge_alpha = 0.95;
uniform float edge_sharpness = 1.4;
uniform float glow = 0.12;

void fragment() {
	float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), edge_sharpness);
	ALBEDO = mix(ice_color.rgb, edge_color.rgb, edge);
	ALPHA = mix(face_alpha, edge_alpha, edge);
	ROUGHNESS = 0.12;
	SPECULAR = 1.0;
	EMISSION = ice_color.rgb * glow;
}
