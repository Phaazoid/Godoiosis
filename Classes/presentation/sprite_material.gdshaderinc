// A HAND COPY OF THE ENGINE'S OWN Sprite3D MATERIAL (#358): BaseMaterial3D's code for a shaded,
// double-sided, FIXED_Y-billboarded sprite whose albedo comes from the vertex colour. Measured
// pixel-identical to the engine sprite on 4.7.1 (tools/sprite_parity/), shadows and flip included. The
// engine stays authoritative; after an engine upgrade, re-run that probe before trusting this copy.
//
// ONE copy, split out of unit_status.gdshaderinc when the wind's plant sway (#1286) became its second
// reader: a unit wearing a state and a plant leaning in the wind both draw through it, so the two can
// never disagree with each other about what the engine does.

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color, filter_nearest, repeat_enable;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float specular : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float metallic : hint_range(0.0, 1.0, 0.01) = 0.0;

// The engine's FIXED_Y billboard as a model matrix: the camera's horizontal axes, world up, and the
// node's own origin -- its rotation and scale dropped, as the engine drops them.
mat4 sprite_billboard(mat4 cam_inv_view, mat4 model) {
	return mat4(
			vec4(normalize(cross(vec3(0.0, 1.0, 0.0), cam_inv_view[2].xyz)), 0.0),
			vec4(0.0, 1.0, 0.0, 0.0),
			vec4(normalize(cross(cam_inv_view[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
			model[3]);
}

// The vertex colour (the sprite's modulate), decoded to linear the way the engine decodes it when the
// output is not sRGB.
vec4 sprite_tint(vec4 color, bool output_is_srgb) {
	vec4 tint = color;
	if (!output_is_srgb) {
		tint.rgb = mix(pow((tint.rgb + vec3(0.055)) * (1.0 / (1.0 + 0.055)), vec3(2.4)),
				tint.rgb * (1.0 / 12.92), lessThan(tint.rgb, vec3(0.04045)));
	}
	return tint;
}
