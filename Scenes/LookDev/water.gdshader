// The board's water surface (#552) -- the material every WATER tile's meshlib block wears, and this
// codebase's first spatial shader.
//
// The convention it sets, for whatever shader comes next: a cell's own SURFACE is its meshlib
// item, so this rides the GridMap's batching and one draw covers the whole lake; a MARKER is a
// per-cell node (#324's fire). Waves are driven off WORLD position, which is what makes a lake
// read as one body of water rather than as N tiles each rippling privately.
//
// Two rules it must not break. It never DISPLACES a vertex -- BoardSpace.lie_on, the hover bracket
// and every markup quad assume a flat top face at a known Y. And it stays OPAQUE, so it owes none
// of the depth-sorting checks presentation-effects.md catalogues for a new transparent surface.
//
// SHALLOW vs DEEP arrives per CELL, in the board mask's green channel, derived by BoardMirror from
// the tile's own `walkable` flag -- the flag the rules read -- so the tile cannot disagree with the
// hover card about which water drowns you. It was baked per MATERIAL until #552 slice 2b; this
// header still said so until #646.
//
// It wears BOTH surfaces of a water block and forks on the world normal: the up-facing quad is the
// SURFACE, the walls and the top rim are the BODY. Those are different questions, not one question
// with a flag, which is why the fork is on geometry rather than on a uniform.

shader_type spatial;
render_mode cull_back;

// The composed ground atlas. The tile's own art is the BASE colour, so the tileset stays the
// authority on what colour this water is and the flat view agrees with this one.
uniform sampler2D atlas : source_color, filter_nearest;
// The BODY's own sheet (water_side.png). A second sampler rather than reusing `atlas`, because the
// two surfaces carry different UVs -- surface 1 spans (0,0,1,1) while surface 0 holds the tile's
// atlas rect -- so one sampler would smear the whole tilesheet down every wall. That is the trap
// gen_lookdev_assets._block_mesh records, and it was a WATER bug when it last fired.
uniform sampler2D body_tex : source_color, filter_nearest;
// HOW DEEP a cell is comes from the board mask's GREEN channel, not from a per-material uniform.
// It used to be baked 0 or 1 into two materials, which is why the shallow/deep boundary was a hard
// step: every mix() below snapped at the cell edge and the bed popped from present to absent in one
// pixel. There was no code path that COULD blend. Now there is one water material, the mask is the
// single authority on how deep a cell is, and the value is exact at cell centres -- so away from a
// type seam this reads exactly as the baked version did.

// EVERY tuning value is a GLOBAL, pushed by BoardMirror's @exports -- a per-material one would mean
// writing into lookdev_meshlib.tres at runtime, i.e. mutating a generated artifact.
//
// And every one of them comes in a PAIR, because the two water types are tuned separately (dev,
// 2026-08-27: "we need these dials separate for the different water types"). This replaced a fixed
// RATIO -- shallow's wave scale was 1.7x deep's, its speed 1.35x, its body shade 0.6x, all consts in
// here. **A ratio between two authored things is itself an authored thing**, so burying it made it a
// feel value with no surface: moving Wave speed moved both types together and "shallow choppy, deep
// glassy" could not be expressed at all. The constants are DELETED rather than kept as a fallback.
global uniform float water_deep_wave_speed;
global uniform float water_shallow_wave_speed;
global uniform float water_deep_wave_scale;
global uniform float water_shallow_wave_scale;
global uniform float water_deep_band_contrast;
global uniform float water_shallow_band_contrast;
global uniform float water_deep_ripple;
global uniform float water_shallow_ripple;
global uniform float water_deep_roughness;
global uniform float water_shallow_roughness;
global uniform float water_deep_specular;
global uniform float water_shallow_specular;
global uniform float water_deep_seam;
global uniform float water_shallow_seam;
global uniform float water_deep_body_shade;
global uniform float water_shallow_body_shade;

// The SHORELINE (#552 slice 2). Foam is the other half of what the ticket says does the work, and
// it is the one effect in here that has to know about the cell NEXT DOOR -- which a meshlib item
// structurally cannot. That is what the board mask below is for.
//
// Width is in HALF-CELLS: 1.0 reaches from the shore to the cell's centre, which is as far as a
// one-texel-per-cell mask can say anything about. The colour's ALPHA is how hard it lands, so hue
// and strength stay ONE knob rather than two that are only meaningful together.
global uniform float water_deep_foam_width;
global uniform float water_shallow_foam_width;
global uniform vec4 water_deep_foam_color;
global uniform vec4 water_shallow_foam_color;

// The bed and its caustics have no deep twin BY NATURE rather than by omission: they are what you
// see THROUGH shallow water, and deep water is opaque. They carry `shallow` in their names anyway,
// so no water knob leaves you working out which water it acts on.
global uniform float water_shallow_bed;
global uniform vec4 water_shallow_bed_color;
global uniform float water_shallow_bed_grain;
global uniform float water_shallow_caustics;
global uniform float water_shallow_caustics_scale;

// BOARD DATA, not tuning. These three name no water type because they describe the BOARD rather
// than either water, and nobody tunes them -- BoardMirror rebuilds them whenever the terrain
// changes. test_no_water_uniform_is_ambiguous_about_its_type knows this category by name and its
// guest list is CLOSED, so a real knob cannot slip in here unnamed. This slice widened it by one,
// which is the mechanism working as designed rather than around.
//
// One texel per cell, and its texel centres land on CELL centres -- so filter_linear does the
// interpolation and a fragment gets a smooth field for one texture read.
//
//   RED   signed distance to the shore, 0.5 exactly ON the water/land boundary, rising into the
//         water and falling into land, saturating water_board_shore_range cells out. It was a
//         BITMAP in slice 2 and that is what made corners rough: thresholding a binary mask gives
//         a band whose width follows the interpolation GRADIENT, which is steep across a straight
//         edge and shallow near a corner, so an L-shaped patch grew a fat mushy corner while its
//         straight runs stayed crisp. A real distance field has a constant gradient, so the band
//         has a constant width. The transform is a chamfer on the CPU, once per terrain edit.
//   GREEN how deep, dilated one cell into land so a cliff shore stays deep. Exact at cell centres.
//
// Clamped rather than repeated, so water running off the edge of the board meets its own value
// there and does not foam against the void.
//
// The rect says where the mask LIVES in world space -- xy origin, zw size, in cells, which are
// world units because BoardSpace.CELL_SIZE is 1.0.
global uniform sampler2D water_board_mask : filter_linear, repeat_disable;
global uniform vec4 water_board_mask_rect;
// How many CELLS the shore ramp runs over before it saturates -- the number that decodes R back
// into a distance. Pushed rather than spelled here as well: a const in each language is one edit
// away from two different answers with nothing to catch it.
global uniform float water_board_shore_range;

// Art pixels per cell -- the quantiser that keeps everything here pixel art instead of a smooth
// gradient. The sheet's own resolution (gen_lookdev_assets.TILE), so it is a const rather than a
// knob: moving it would mean re-cutting every tile.
const float PIXELS_PER_CELL = 32.0;
// How wide the cell seam runs, in those pixels.
const float SEAM_PIXELS = 1.5;
// The caustic net travels at its own fraction of the surface's pace. DERIVED rather than given its
// own knob, because it is the same water moving -- a second speed dial would let the two layers
// disagree about that and there is no reading in which they should.
const float CAUSTIC_SPEED = 0.45;
// How tight the caustic lines pinch. Higher is thinner and brighter.
const float CAUSTIC_SHARPNESS = 5.0;
// How far the BODY's texture runs before it repeats, in cells.
const float BODY_TILE = 1.0;
// How hard the shoreline BREATHES, as a fraction of the foam's own width. Derived rather than given
// its own dial, for CAUSTIC_SPEED's reason: it is the same water moving, and a wider band of surf
// swings further by itself. A band that does not move at all is a painted outline, not surf.
const float FOAM_WOBBLE = 0.35;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec2 cell_xz;


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// NORMAL is VIEW space by the time fragment() sees it, and "is this face up" is a world
	// question, so the world normal travels as its own varying.
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	// Cell-LOCAL, straight off the mesh: a block runs -0.5..0.5, so the seam below needs to know
	// nothing about the GridMap's cell size or its centring.
	cell_xz = VERTEX.xz;
}


float wave(vec2 p, float t, float scale) {
	return sin((p.x + p.y) * scale + t) * 0.6
			+ sin((p.x - p.y * 1.7) * scale * 1.6 - t * 0.8) * 0.4;
}


// The surface at p, crossfaded between the two water types by `d`.
//
// A PHASE PARAMETER CANNOT BE INTERPOLATED ACROSS SPACE; AN AMPLITUDE ONE CAN. Slice 2b made every
// knob pair mix() on `d` so the seam would glide, which is right for the amplitudes and wrong for
// these two: a sinusoid's frequency and phase RATE do not lerp. A spatially varying `scale` makes
// the surface a CHIRP -- phase is (p.x + p.y) * scale, so at board (20, 10) a glide of 1.4 crams
// ~6.7 extra periods into the one-cell transition, and worse the further the lake sits from the
// world origin -- while a spatially varying speed makes the phase gap grow as TIME * 0.94, without
// bound. It ringed the bands, the shoreline and the specular at once, because all three read `w`.
//
// So evaluate BOTH fields and interpolate the RESULT, which is an amplitude. Costs one extra
// wave() per sample; the alternative, branching on 0 < d < 1 to skip the second field away from a
// seam, buys nothing measurable here and trades it for divergence.
float wave_at(vec2 p, float ts, float td, float d) {
	return mix(wave(p, ts, water_shallow_wave_scale), wave(p, td, water_deep_wave_scale), d);
}


// The light net on the bottom -- two ridged sine fields crossed. RIDGED (1 - abs) rather than
// plain sines because what reads as caustics is thin bright lines between wide dark cells, which is
// the opposite of what a sine gives you.
float caustic(vec2 p, float t, float scale) {
	float a = sin(p.x * scale + t) + sin(p.y * scale * 1.3 - t * 0.9);
	float b = sin((p.x + p.y) * scale * 0.7 + t * 1.1);
	float ridge = 1.0 - abs(a * 0.35 + b * 0.4);
	return pow(max(ridge, 0.0), CAUSTIC_SHARPNESS);
}


// FRACT BEFORE THE SIN. cell_px runs into the hundreds on a real board, so the dot lands near 1e5,
// where float32 carries about 0.01 against sin's 6.28 period -- the distribution skews and
// neighbouring pixels correlate into blotches. Wrapping first keeps the argument well conditioned.
float speckle(vec2 cell_px) {
	float h = fract(dot(cell_px, vec2(0.1031, 0.1030)));
	return fract(sin(h * 43.7585453) * 43758.5453);
}


void fragment() {
	// Where this fragment sits in the board mask. Read BEFORE the surface/body fork, because how
	// deep the cell is comes out of it and the body wears a depth-dependent shade too.
	vec2 mask_uv = (world_pos.xz - water_board_mask_rect.xy)
			/ max(water_board_mask_rect.zw, vec2(1.0));
	vec4 board = texture(water_board_mask, mask_uv);
	// Exactly 0 or 1 at a cell CENTRE, gliding only across a shallow/deep seam -- so this reads
	// identically to the material-baked version everywhere except the boundary it exists to soften.
	float d = board.g;

	// Every one of these picks between the two dials. A mix rather than a branch is what lets a
	// boundary GLIDE instead of snapping, which is the whole of slice 2b.
	float body_shade = mix(water_shallow_body_shade, water_deep_body_shade, d);
	float seam = mix(water_shallow_seam, water_deep_seam, d);

	if (abs(world_normal.y) < 0.5) {
		// THE BODY -- a block's walls, plus the four rim quads _block_mesh puts in surface 0 beside
		// the up-facing one. Water seen edge-on is not a surface: no waves, no highlight. Sampled on
		// a WORLD-derived UV so a wall and a rim agree; the mesh's own UVs disagree by construction
		// between the two surfaces.
		vec2 body_uv = vec2((world_pos.x + world_pos.z) / BODY_TILE, -world_pos.y / BODY_TILE);
		ALBEDO = texture(body_tex, body_uv).rgb * (1.0 - body_shade);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
	} else {
		float band_contrast = mix(water_shallow_band_contrast, water_deep_band_contrast, d);
		float ripple = mix(water_shallow_ripple, water_deep_ripple, d);

		vec3 base = texture(atlas, UV).rgb;
		float px = 1.0 / PIXELS_PER_CELL;
		vec2 cell_px = floor(world_pos.xz * PIXELS_PER_CELL);
		vec2 p = cell_px * px;
		// Each type's own clock, never a blend of the two -- see wave_at.
		float ts = TIME * water_shallow_wave_speed;
		float td = TIME * water_deep_wave_speed;

		// --- What is UNDER the water -------------------------------------------------------
		// The bed is hashed off the STATIC art-pixel index, so it stays nailed to the board while
		// the caustics travel over it. That contrast is the depth cue, and it is the one thing an
		// ice sheet cannot fake -- a frozen pane moves all of itself or none of it.
		vec2 grain = floor(world_pos.xz * (PIXELS_PER_CELL / max(water_shallow_bed_grain, 1.0)));
		vec3 bed = water_shallow_bed_color.rgb * mix(0.72, 1.28, speckle(grain));
		// SHALLOW's clock, not a blended one. The bed is a shallow-only layer, gated on (1.0 - d)
		// two lines down, so it has no business reading deep's speed -- and a blended one chirps
		// the caustic net across the seam exactly as it did the bands.
		bed += vec3(caustic(p, ts * CAUSTIC_SPEED, water_shallow_caustics_scale)
				* water_shallow_caustics);
		// Seen THROUGH the water, so the water tints it. Without this the bed reads as painted on
		// the surface rather than lying beneath it.
		vec3 through = bed * base;

		// Deep water is opaque and unchanged; shallow lets its bottom show.
		vec3 col = mix(base, through, clamp(water_shallow_bed * (1.0 - d), 0.0, 1.0));

		// --- What happens ON the water ------------------------------------------------------
		// Bands are a SURFACE phenomenon and go on top, additively -- they must ride over the bed,
		// never modulate it, or the bed reads as noise painted across the highlights. Two hard
		// thresholds rather than a gradient, which is how pixel water reads.
		float w = wave_at(p, ts, td, d);
		float tone = step(0.20, w) * 0.45 + step(0.72, w) * 0.55;
		col += base * tone * band_contrast;

		// The cell seam. A lake driven off world position erases the grid, and the hover bracket is
		// then the only thing saying where a tile ends -- so the surface draws its own boundary.
		// 0 turns it off and hands the job back to the bracket alone. Per type, because the bed's
		// mottle already breaks shallow water up while a deep expanse has nothing else going on
		// (dev, 2026-08-27).
		float edge = 0.5 - max(abs(cell_xz.x), abs(cell_xz.y));
		col *= 1.0 - seam * (1.0 - smoothstep(0.0, SEAM_PIXELS * px, edge));

		// --- The SHORELINE -------------------------------------------------------------------
		// AFTER the seam on purpose: the seam draws EVERY cell boundary, and a grid line running
		// through the surf is exactly what a shore must not have.
		//
		// 3D ONLY, and declared here rather than left to be rediscovered (#292, #285 is the model).
		// The flat view's water is a TILE PICK, and a shoreline is a sub-tile gradient no tile pick
		// can express. That view already carries the one distinction the RULES make -- shallow vs
		// deep, via TileData.modulate -- so foam adds no rule information to the authority view.
		float foam_width = mix(water_shallow_foam_width, water_deep_foam_width, d);
		vec4 foam_color = mix(water_shallow_foam_color, water_deep_foam_color, d);
		// Sampled at the ART PIXEL's centre rather than at the fragment's own position, so the
		// shoreline stair-steps like the bands and the bed do. It was the one smooth anti-aliased
		// curve on a surface quantised to 32 pixels a cell, which is the other half of why corners
		// read soft. `p` is the pixel's corner in world units, so half a pixel reaches its middle.
		vec2 pixel_uv = (p + vec2(px * 0.5) - water_board_mask_rect.xy)
				/ max(water_board_mask_rect.zw, vec2(1.0));
		// Decoded back into CELLS, so foam_width goes on meaning half-cells whatever the encoding
		// does. The same wave field that moves the surface moves the shoreline, so the band breathes
		// instead of sitting there.
		float shore = (texture(water_board_mask, pixel_uv).r - 0.5)
				* 2.0 * water_board_shore_range + w * FOAM_WOBBLE * foam_width;
		// Width 0 means OFF, not a hairline: a zero-wide smoothstep still fires on whichever pixel
		// lands exactly on the boundary.
		float foam = foam_width <= 0.0
				? 0.0
				: 1.0 - smoothstep(0.0, 0.5 * foam_width, shore);
		col = mix(col, foam_color.rgb, foam * foam_color.a);

		ALBEDO = col;
		ROUGHNESS = mix(water_shallow_roughness, water_deep_roughness, d);
		SPECULAR = mix(water_shallow_specular, water_deep_specular, d);
		METALLIC = 0.0;

		// The highlight has to TRAVEL, so the wave bends the normal. A finite difference over the
		// same quantised field, carried into view space by hand: a NORMAL_MAP would want tangents
		// the block mesh does not generate.
		vec3 bent = normalize(vec3(
				-(wave_at(p + vec2(px, 0.0), ts, td, d) - w) * ripple,
				1.0,
				-(wave_at(p + vec2(0.0, px), ts, td, d) - w) * ripple));
		NORMAL = normalize((VIEW_MATRIX * vec4(bent, 0.0)).xyz);
	}
}
