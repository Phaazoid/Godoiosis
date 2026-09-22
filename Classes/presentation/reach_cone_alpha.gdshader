shader_type spatial;

// The SEE-THROUGH cone (#1070 follow-up): reach_cone.gdshader's facet shading with its colour's
// ALPHA honoured, for the squad tethers' arrowheads -- a tether colour faded on the Game tab fades
// the arrow with the shaft. The reach mark's own cone stays on the opaque file, #1069's ruling.
//
// A THIRD FILE rather than a flag, for the reason the other two headers give: blending and culling
// are render_mode, and render_mode is per shader file.
//
// `cull_back` IS WHAT KEEPS IT RIGHT. A convex closed solid with its back faces culled covers every
// pixel exactly ONCE, so the blend has no order to get wrong. With culling off -- the opaque cone's
// mode -- the near and far faces both blend, in EMISSION order: alpha 0.5 reads as ~0.75, and which
// face lands on top flips as the rig orbits. BoardOverlays.add_beam_cone winds every triangle so the
// OUTSIDE is Godot's front face, which is what this mode relies on.
//
// NO BEAD: no layer drawing this cone carries one, and a tether's arrowhead must not pulse on a dark
// shaft. If one ever does, the bead window moves into an include both cone files read.
render_mode unshaded, cull_back, depth_draw_never;

uniform vec4 beam_color : source_color = vec4(1.0, 0.55, 0.12, 0.95);
// The same albedo multiplier the solid cone reads, so one knob brightens every arrowhead.
uniform float cone_intensity = 1.0;

void fragment() {
	// COLOR.r is the baked facet shade -- see reach_cone.gdshader, which this reads identically.
	ALBEDO = beam_color.rgb * COLOR.r * cone_intensity;
	ALPHA = beam_color.a;
}
