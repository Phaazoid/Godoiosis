shader_type spatial;

// The see-through cone with NO DEPTH TEST (#1247): reach_cone_alpha.gdshader exactly, for the HOVERED
// unit's queued-attack pointers, which draw over everything -- units and their readouts included --
// at BoardOverlays.FOCUS_RENDER_PRIORITY. A fifth file rather than a flag, for the reason the others
// give: depth testing is render_mode, and render_mode is per shader file.
//
// `cull_back` is still what keeps the blend right (see reach_cone_alpha's header): a convex solid
// with its back faces culled covers each pixel once, so with depth testing off there is still only
// one face to draw.
render_mode unshaded, cull_back, depth_draw_never, depth_test_disabled;

uniform vec4 beam_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float cone_intensity = 1.0;

void fragment() {
	ALBEDO = beam_color.rgb * COLOR.rgb * cone_intensity;
	ALPHA = beam_color.a * COLOR.a;
}
