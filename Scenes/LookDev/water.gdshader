// The board's water surface (#552 slice 1) -- the material every WATER tile's meshlib block wears
// on its TOP surface, and this codebase's first spatial shader.
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

shader_type spatial;
render_mode cull_back;

// The composed ground atlas. The tile's own art is the BASE colour, so the tileset stays the
// authority on what colour this water is and the flat view agrees with this one.
uniform sampler2D atlas : source_color, filter_nearest;
// 0 = shallow, 1 = deep. Content, not tuning, which is why it is per-material and not a global.
uniform float deep : hint_range(0.0, 1.0) = 1.0;

// Every tuning value is a GLOBAL, pushed by BoardMirror's @exports. Per-material uniforms would
// mean writing into lookdev_meshlib.tres at runtime -- mutating a generated artifact.
global uniform float water_wave_speed;
global uniform float water_wave_scale;
global uniform float water_band_contrast;
global uniform float water_ripple;
global uniform float water_roughness;
global uniform float water_specular;
global uniform float water_bed;
global uniform float water_seam;
global uniform float water_body_shade;

// Art pixels per cell -- the quantiser that keeps the waves pixel art instead of a smooth
// gradient. The sheet's own resolution (gen_lookdev_assets.TILE), so it is a const rather than a
// knob: moving it would mean re-cutting every tile.
const float PIXELS_PER_CELL = 32.0;
// How wide the cell seam runs, in those pixels.
const float SEAM_PIXELS = 1.5;
// How much tighter and quicker SHALLOW water moves than deep. The character split, not the pace:
// water_wave_scale/speed set how fast the pair goes, these only say which one is the busier.
const float SHALLOW_SCALE = 1.7;
const float SHALLOW_SPEED = 1.35;

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


float speckle(vec2 cell_px) {
	return fract(sin(dot(cell_px, vec2(127.1, 311.7))) * 43758.5453);
}


void fragment() {
	vec3 base = texture(atlas, UV).rgb;

	if (abs(world_normal.y) < 0.5) {
		// A SIDE face -- the four rim quads _block_mesh puts in this surface beside the up-facing
		// one. Water seen edge-on is the BODY, not the surface: no waves, and darker with depth.
		ALBEDO = base * (1.0 - water_body_shade * mix(0.6, 1.0, deep));
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
	} else {
		float px = 1.0 / PIXELS_PER_CELL;
		vec2 cell_px = floor(world_pos.xz * PIXELS_PER_CELL);
		vec2 p = cell_px * px;
		float scale = water_wave_scale * mix(SHALLOW_SCALE, 1.0, deep);
		float t = TIME * water_wave_speed * mix(SHALLOW_SPEED, 1.0, deep);
		float w = wave(p, t, scale);

		// Two hard thresholds rather than a gradient -- a crest and a broader mid band, which is
		// how pixel water reads. Proportional to the tile's own colour, so the authored tint
		// survives being lit up.
		float tone = step(0.20, w) * 0.45 + step(0.72, w) * 0.55;
		vec3 col = base + base * tone * water_band_contrast;

		// SHALLOW shows its bed, as a STATIC mottle -- the bottom does not move. Off in deep water,
		// which is the whole difference between wading and drowning said in one channel.
		col = mix(col, col * mix(0.78, 1.16, speckle(cell_px)), water_bed * (1.0 - deep));

		// The cell seam. A lake driven off world position erases the grid, and the hover bracket is
		// then the only thing saying where a tile ends -- so the surface draws its own boundary.
		// 0 turns it off and hands the job back to the bracket alone.
		float edge = 0.5 - max(abs(cell_xz.x), abs(cell_xz.y));
		col *= 1.0 - water_seam * (1.0 - smoothstep(0.0, SEAM_PIXELS * px, edge));

		ALBEDO = col;
		ROUGHNESS = water_roughness;
		SPECULAR = water_specular;
		METALLIC = 0.0;

		// The highlight has to TRAVEL, so the wave bends the normal. A finite difference over the
		// same quantised field, carried into view space by hand: a NORMAL_MAP would want tangents
		// the block mesh does not generate.
		vec3 bent = normalize(vec3(
				-(wave(p + vec2(px, 0.0), t, scale) - w) * water_ripple,
				1.0,
				-(wave(p + vec2(0.0, px), t, scale) - w) * water_ripple));
		NORMAL = normalize((VIEW_MATRIX * vec4(bent, 0.0)).xyz);
	}
}
