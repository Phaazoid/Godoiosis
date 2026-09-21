shader_type spatial;

// The SOLID cone at a reach mark's victim end (#1069). The shaft beside it is sight_beam.gdshader;
// this is that shader with the two things a volume must not have taken out, and it exists as a
// second file rather than a branch for a reason that is measured rather than stylistic.
//
// WHY THE BEAM SHADER COULD NOT GROW A FLAG. Its whole look is `falloff = pow(1.0 - edge, softness)`
// -- a bright core reaching ZERO alpha at both rims, by construction, so every ribbon is translucent
// and edgeless and no width or intensity can make one read as a volume. That is exactly right for a
// beam and exactly what the dev reported as "a see through triangle". Forcing falloff to 1.0 would
// make it an OPAQUE TRIANGLE, still flat and still camera-facing. And its render_mode carries
// `depth_draw_never` -- load-bearing for a translucent ribbon that overlaps itself -- so an opaque
// surface drawn through it would resolve its own back faces by EMISSION ORDER and flicker as the
// rig orbits. render_mode is per SHADER FILE, not per material, so the fork is a file.
//
// NO `ALPHA` WRITE AT ALL, which is what makes this opaque: Godot classifies a spatial shader that
// never touches ALPHA as opaque, so it lands in the opaque pass, writes depth and depth-tests like
// any object in the world. That is also why `cull_disabled` is safe here where it would be fatal
// with blending -- a closed convex solid resolves front-over-back by DEPTH rather than by winding,
// so the cone cannot be turned inside out by a mis-wound triangle and needs no render_priority.
render_mode unshaded, cull_disabled;

// Per draw, the same value the shaft's material carries, so the two halves of one mark are one
// colour by construction rather than by two knobs being kept in step.
uniform vec4 beam_color : source_color = vec4(1.0, 0.251, 0.784, 0.95);
// ALBEDO multiplier, and DELIBERATELY NOT the shaft's `beam_intensity`. See BoardOverlays'
// cone_intensity: a ribbon at 2.4 is far dimmer than 2.4 over most of its area because its rim
// fades out, while a solid at 2.4 is 2.4 everywhere -- past the diorama's glow_hdr_threshold of
// 1.2 across the whole face, which blooms the shape into a white blob and erases the shading below.
uniform float cone_intensity = 1.0;

// The BEAD, shared with the shaft so the pulse runs off one and into the other as a single sweep.
// UV2.x carries the same world measure BoardOverlays.set_marks chains across a mark's strokes, so
// the cone's vertices continue the shaft's count rather than restarting at zero.
uniform float bead_length = 0.0;    // cells; 0 = no bead
uniform float bead_speed = 3.4;     // cells per second, enemy -> victim
uniform float bead_gap = 9.0;       // cells between successive beads
uniform vec4 bead_color : source_color = vec4(1.0, 0.92, 0.98, 1.0);
// #217's composed read. 0 FREEZES the bead; the cone still says which way the mark runs, because
// direction is carried by the SHAPE here and not by the motion.
uniform float motion = 1.0;

void fragment() {
	// COLOR.r is the BAKED FACET SHADE -- one value per triangle, written by
	// BoardOverlays.add_beam_cone against a fixed world-space direction. The material is unshaded
	// (the dev's standing ruling for board markup, and a lit StandardMaterial3D under BoardOverlays
	// fails that file's own law), so the only way a face can differ from its neighbour is the vertex
	// colour, which is UnitHealthBar._build_cube_mesh's trick one surface along.
	//
	// The bake is against a WORLD direction rather than the camera, and that is the design: vertex
	// colour is baked when the mark is rebuilt -- on a hover change -- not per frame, so a
	// camera-relative bake would be stale the moment the rig orbited. A world-fixed one holds still,
	// which is what lets the shape read as a volume while you turn.
	float shade = COLOR.r;

	// The bead, byte-for-byte the shaft's window so the two cannot drift: a run of `bead_length`
	// travelling along the mark's own world measure, repeating every `bead_gap`.
	float live = step(0.5, motion);
	float bead = 0.0;
	if (bead_length > 0.0 && live > 0.5) {
		float behind = mod(TIME * bead_speed - UV2.x, max(bead_gap, 0.001));
		bead = 1.0 - smoothstep(0.0, bead_length, behind);
	}

	vec3 tint = mix(beam_color.rgb * shade, bead_color.rgb, bead * bead_color.a);
	ALBEDO = tint * cone_intensity;
}
