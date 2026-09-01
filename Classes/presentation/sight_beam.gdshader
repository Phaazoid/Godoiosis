shader_type spatial;

// The aim's sight beam (#506): a camera-facing ribbon expanded in the VERTEX stage, so one built
// mesh is correct at every camera angle. BoardOverlays.set_line feeds it a centreline emitted
// twice per point -- NORMAL carries the (joint-averaged) tangent and UV.y the 0/1 side flag -- and
// this shader pushes each pair apart perpendicular to the view direction.
//
// WHY NOT ON THE CPU: the side vector depends on where the camera is, so a GDScript ribbon would
// need rebuilding every frame the rig orbits or zooms, which is most frames. BoardOverlays has no
// _process and should not grow one for a beam.
//
// cull_disabled is LOAD-BEARING, not caution: side = cross(tangent, to_camera) flips sign with the
// tangent's direction relative to the camera, so the strip's winding flips too and half the orbit
// would render nothing. depth_draw_never keeps a translucent beam from writing depth over itself;
// the depth TEST stays on, so terrain still occludes it exactly as the old line strip was occluded.
//
// WIDTH IS PURELY WORLD-SPACE, and that is a scar rather than a preference. This carried a second
// term -- a floor in SCREEN PIXELS, so zooming out could not re-thin the beam -- derived from view
// depth over PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y. It shipped, and the beam came out as huge
// flaring wedges that no knob could shrink, because that term dominated the max() at every setting.
// The screenshot is what identified it: the beam was NARROW at the shooter and WIDER at the target,
// and perspective does the exact opposite, so the only depth-dependent term in the shader had to be
// the culprit whatever its denominator was really doing. A `max(denominator, 0.000001)` written as
// safety is what turned a bad read into a silently enormous width instead of a visible NaN.
// Re-adding a screen-space floor means PASSING the viewport size in as a uniform rather than
// trusting a builtin in this stage, and it is not worth a third visual regression on a nicety.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// Colour arrives per draw as the verdict tint (SightTrace2D.CLEAR_COLOR / BLOCKED_COLOR, copied by
// OverlayMirror), so it is 0-1 like every other overlay colour and stays the SAME answer the flat
// view uses. Brightness is a separate uniform on purpose: the dev panel's colour row is four 0-255
// sliders, so an HDR colour could not be authored there, and one stored number cannot mean
// "clamped white" in 2D and "blooms" in 3D.
uniform vec4 beam_color : source_color = vec4(1.0, 1.0, 1.0, 0.9);
// Multiplies ALBEDO past the diorama's glow_hdr_threshold (1.2) so the beam blooms. 1.0 = no bloom.
uniform float beam_intensity = 2.0;
// The beam's full width in world units (a cell is BoardSpace.CELL_SIZE = 1.0). It is the ONE term
// in the offset, so the ribbon cannot be any wider than this however far away it is drawn.
uniform float beam_width = 0.06;
// Edge falloff exponent: 1.0 is a linear fade to the rim, higher concentrates a bright core.
uniform float beam_softness = 1.5;

void vertex() {
	// UV.y is the side flag as 0/1; remap to -1/+1. UV.x is the normalized position along the beam
	// (see set_line) -- unused here, and #674's marching dashes are what would read it.
	float side_sign = UV.y * 2.0 - 1.0;

	vec3 view_pos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 view_tangent = (MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	// A zero-length tangent (two coincident samples) would poison normalize() and blank the strip.
	view_tangent = length(view_tangent) > 0.000001 ? normalize(view_tangent) : vec3(0.0, 1.0, 0.0);

	// The camera sits at the view-space origin looking down -Z, so this is the per-vertex direction
	// back to it -- a true billboard, not a plane-facing approximation that would shear near the
	// screen edges.
	vec3 to_camera = normalize(-view_pos);
	vec3 side = cross(view_tangent, to_camera);
	side = length(side) > 0.000001 ? normalize(side) : vec3(1.0, 0.0, 0.0);

	// No depth term, deliberately -- see the render_mode note. The offset is bounded by the knob.
	view_pos += side * side_sign * beam_width * 0.5;
	POSITION = PROJECTION_MATRIX * vec4(view_pos, 1.0);
}

void fragment() {
	// A bright core fading to the rim, which is what separates a beam from a flat strip with hard
	// edges. beam_softness only shapes the falloff; the rim always reaches zero, so the ribbon has
	// no visible boundary to read as geometry.
	//
	// THE DISTANCE ACROSS THE RIBBON IS ONLY KNOWABLE HERE. Every VERTEX sits on a rim, at side
	// -1 or +1, so `abs(side)` is 1.0 at all of them -- taking it in the vertex stage and passing
	// the result interpolates 1.0 with 1.0, reads 1.0 across the whole surface, and makes ALPHA
	// uniformly ZERO. That shipped: the beam was perfectly built, perfectly positioned and
	// completely invisible, and no knob could reach it (width widened nothing, glow multiplied an
	// ALBEDO never blended in, softness was pow(0, n) either way). The ABS MUST FOLLOW THE
	// INTERPOLATION. Reading UV.y back here rather than passing a varying is the same fix with one
	// less moving part -- UV interpolates on its own, 0 and 1 at the rims and 0.5 down the middle.
	float edge = abs(UV.y * 2.0 - 1.0);
	float falloff = pow(max(1.0 - edge, 0.0), beam_softness);
	ALBEDO = beam_color.rgb * beam_intensity;
	ALPHA = beam_color.a * falloff;
}
