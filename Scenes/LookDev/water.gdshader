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
// SHALLOW vs DEEP is `deep`, baked per material by gen_lookdev_assets from the tile's own
// `walkable` flag -- the flag the rules read -- so the tile cannot disagree with the hover card
// about which water drowns you.
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
// 0 = shallow, 1 = deep. Content, not tuning, which is why it is per-material and not a global.
uniform float deep : hint_range(0.0, 1.0) = 1.0;

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

// The bed and its caustics have no deep twin BY NATURE rather than by omission: they are what you
// see THROUGH shallow water, and deep water is opaque. They carry `shallow` in their names anyway,
// so no water knob leaves you working out which water it acts on.
global uniform float water_shallow_bed;
global uniform vec4 water_shallow_bed_color;
global uniform float water_shallow_bed_grain;
global uniform float water_shallow_caustics;
global uniform float water_shallow_caustics_scale;

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
	// `deep` is baked 0.0 or 1.0, so every one of these is an exact pick between the two dials --
	// and a mix rather than a branch keeps it sensible if a fractional depth is ever authored.
	float body_shade = mix(water_shallow_body_shade, water_deep_body_shade, deep);
	float seam = mix(water_shallow_seam, water_deep_seam, deep);

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
		float wave_speed = mix(water_shallow_wave_speed, water_deep_wave_speed, deep);
		float wave_scale = mix(water_shallow_wave_scale, water_deep_wave_scale, deep);
		float band_contrast = mix(water_shallow_band_contrast, water_deep_band_contrast, deep);
		float ripple = mix(water_shallow_ripple, water_deep_ripple, deep);

		vec3 base = texture(atlas, UV).rgb;
		float px = 1.0 / PIXELS_PER_CELL;
		vec2 cell_px = floor(world_pos.xz * PIXELS_PER_CELL);
		vec2 p = cell_px * px;
		float t = TIME * wave_speed;

		// --- What is UNDER the water -------------------------------------------------------
		// The bed is hashed off the STATIC art-pixel index, so it stays nailed to the board while
		// the caustics travel over it. That contrast is the depth cue, and it is the one thing an
		// ice sheet cannot fake -- a frozen pane moves all of itself or none of it.
		vec2 grain = floor(world_pos.xz * (PIXELS_PER_CELL / max(water_shallow_bed_grain, 1.0)));
		vec3 bed = water_shallow_bed_color.rgb * mix(0.72, 1.28, speckle(grain));
		bed += vec3(caustic(p, t * CAUSTIC_SPEED, water_shallow_caustics_scale)
				* water_shallow_caustics);
		// Seen THROUGH the water, so the water tints it. Without this the bed reads as painted on
		// the surface rather than lying beneath it.
		vec3 through = bed * base;

		// Deep water is opaque and unchanged; shallow lets its bottom show.
		vec3 col = mix(base, through, clamp(water_shallow_bed * (1.0 - deep), 0.0, 1.0));

		// --- What happens ON the water ------------------------------------------------------
		// Bands are a SURFACE phenomenon and go on top, additively -- they must ride over the bed,
		// never modulate it, or the bed reads as noise painted across the highlights. Two hard
		// thresholds rather than a gradient, which is how pixel water reads.
		float w = wave(p, t, wave_scale);
		float tone = step(0.20, w) * 0.45 + step(0.72, w) * 0.55;
		col += base * tone * band_contrast;

		// The cell seam. A lake driven off world position erases the grid, and the hover bracket is
		// then the only thing saying where a tile ends -- so the surface draws its own boundary.
		// 0 turns it off and hands the job back to the bracket alone. Per type, because the bed's
		// mottle already breaks shallow water up while a deep expanse has nothing else going on
		// (dev, 2026-08-27).
		float edge = 0.5 - max(abs(cell_xz.x), abs(cell_xz.y));
		col *= 1.0 - seam * (1.0 - smoothstep(0.0, SEAM_PIXELS * px, edge));

		ALBEDO = col;
		ROUGHNESS = mix(water_shallow_roughness, water_deep_roughness, deep);
		SPECULAR = mix(water_shallow_specular, water_deep_specular, deep);
		METALLIC = 0.0;

		// The highlight has to TRAVEL, so the wave bends the normal. A finite difference over the
		// same quantised field, carried into view space by hand: a NORMAL_MAP would want tangents
		// the block mesh does not generate.
		vec3 bent = normalize(vec3(
				-(wave(p + vec2(px, 0.0), t, wave_scale) - w) * ripple,
				1.0,
				-(wave(p + vec2(0.0, px), t, wave_scale) - w) * ripple));
		NORMAL = normalize((VIEW_MATRIX * vec4(bent, 0.0)).xyz);
	}
}
