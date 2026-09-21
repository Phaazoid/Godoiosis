shader_type spatial;

// THE PROJECT'S RIBBON (#506, shared since #887): a camera-facing strip expanded in the VERTEX
// stage, so one built mesh is correct at every camera angle. BoardOverlays.add_beam_strip feeds it
// a centreline emitted twice per point -- NORMAL carries the (joint-averaged) tangent and UV.y the
// 0/1 side flag -- and this shader pushes each pair apart perpendicular to the view direction.
//
// Two tenants: the hovered aim's sight beam, which is one ribbon whose colour is a verdict, and the
// arc's bolts (#887), which are twenty ribbons on one mesh at twenty different ages. The file name
// is the first one's; the shader is both.
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

// --- The travelling BEAD (#1042) ---------------------------------------------------------------
// Defaults to INERT, which is what keeps the sight bead and the arc's bolts exactly what they
// were: BoardOverlays only feeds these on the layers that declare them.
//
// The bead is a window in WORLD distance along the mark (UV2.x), never in UV.x -- normalized, a
// two-cell mark and a nine-cell one would pulse at wildly different speeds off one number.
//
// THE FELLING FLASH THAT LIVED HERE IS GONE (#1069). It had exactly one tenant, the fatal intent
// layer, and that layer went with the intent readout -- a reach line answers who can reach a cell,
// which cannot know lethality without running the ladder. reach_cone.gdshader shares the bead and
// has no flash either, so nothing was left behind for a second layer to inherit.
uniform float bead_length = 0.0;    // cells; 0 = no bead
uniform float bead_speed = 3.4;     // cells per second, enemy -> victim
uniform float bead_gap = 9.0;       // cells between successive beads
uniform vec4 bead_color : source_color = vec4(1.0, 0.92, 0.98, 1.0);
// #217's composed read, pushed by BoardOverlays. 0 FREEZES the bead -- direction is still carried
// by the CONE, which is geometry.
uniform float motion = 1.0;

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
	// UV2.y carries a per-vertex width SCALE as `scale - 1.0`, so ZERO means unchanged and every
	// caller that writes none -- the sight bead, the arc's bolts, every stroke with no taper -- is
	// untouched by construction (#1059). It is what lets the intent mark's CONE converge to a point
	// on the same layer, and therefore the same material, as the shaft it grows out of.
	float width_scale = max(1.0 + UV2.y, 0.0);
	view_pos += side * side_sign * beam_width * width_scale * 0.5;
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
	// COLOR is the PER-RIBBON term (#887) and beam_color the per-DRAW one. A material can only carry
	// one colour, and the arc needs one mesh to hold bolts that were struck at different moments and
	// are therefore at different brightnesses -- so the age rides in the vertex colour, which is the
	// only channel that varies within a draw. A mesh with no colour array reads vec4(1.0) here, so
	// the sight beam is exactly what it was.
	float live = step(0.5, motion);

	// The bead: a window of `bead_length` travelling along the mark's own world measure, repeating
	// every `bead_gap`. mod() of a negative is positive in GLSL, so a mark measured from either end
	// behaves; the smoothstep gives it a soft tail rather than a hard edge.
	float bead = 0.0;
	if (bead_length > 0.0 && live > 0.5) {
		float behind = mod(TIME * bead_speed - UV2.x, max(bead_gap, 0.001));
		bead = 1.0 - smoothstep(0.0, bead_length, behind);
	}

	vec3 tint = mix(beam_color.rgb, bead_color.rgb, bead);
	float alpha = beam_color.a * (1.0 + bead * bead_color.a);
	ALBEDO = tint * COLOR.rgb * beam_intensity;
	ALPHA = clamp(alpha, 0.0, 1.0) * COLOR.a * falloff;
}
