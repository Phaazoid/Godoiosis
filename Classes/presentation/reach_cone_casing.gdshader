shader_type spatial;

// The CASING round a squad tether's arrowhead (#1109 round 2): the ribbon's dark outline, carried onto
// the cone so the arrow reads on a pale floor the way its shaft now does.
//
// An INVERTED HULL. BoardOverlays emits a second, larger cone around each cased one (casing_cone) and
// draws it with its FRONT faces culled, so only its far inside shows -- behind the cone, and past its
// silhouette by exactly the casing's width. A fourth file for the reason the other three headers give:
// culling is render_mode, and render_mode is per shader file.
//
// It draws at one render priority BELOW its layer. It writes no depth, so at the cone's own priority
// the two would sort by distance and the far side of the hull could land over the arrowhead.
//
// Flat, with no facet shade: an outline is a band of colour, not a surface. Its alpha follows the line's
// -- the layer colour's and each cone's own tint -- so a see-through ghost and a fading moment take their
// outline with them.
render_mode unshaded, cull_front, depth_draw_never;

uniform vec4 beam_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 casing_color : source_color = vec4(0.0, 0.0, 0.0, 0.9);

void fragment() {
	ALBEDO = casing_color.rgb;
	ALPHA = casing_color.a * beam_color.a * COLOR.a;
}
