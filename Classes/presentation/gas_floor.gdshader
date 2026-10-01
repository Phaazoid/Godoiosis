// The fog floor under the pixel puffs (#508's look harness): which cells hold gas, drawn on the ground
// in each gas's palette and pattern. Ported from round 4's probe, which baked a CPU texture over the
// whole board; here every art pixel works it out from one fetch of its cell's neighbour bits, so a
// brush stroke rebuilds a mesh and two small textures rather than a board-sized image.
//
// The shape: a cell's side facing a gas-less neighbour is an edge, an outer corner (both its sides
// edges) is rounded, an inner corner stays square. One ink pixel at the edge, then a light rim, then
// the fill with the gas's own pattern. A mixed cell dithers between its gases by their amounts.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D cells_tex : filter_nearest;       // R kinds held, B the 8 neighbour bits (GasMirror)
uniform sampler2DArray amount_tex : filter_nearest; // one layer per kind
uniform vec4 board_rect;                            // x, z, w, h in cells
uniform float art_pixels = 32.0;                    // per cell
uniform float corner_radius = 10.0;                 // art pixels
uniform vec4 palettes[24];                          // kind * 4: light, mid, dark, ink
uniform int patterns[6];                            // GasLook.FloorPattern per kind
uniform int kind_count = 6;
uniform vec4 alphas = vec4(0.95, 0.9, 0.55, 0.8);   // ink, rim, fill, pattern mark

varying vec3 world;
varying vec4 light;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	light = COLOR;
}

float bayer4(ivec2 p) {
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[(p.y & 3) * 4 + (p.x & 3)]) + 0.5) / 16.0;
}

// 0 = plain fill, 1 = a light mark, 2 = a dark mark.
int pattern_at(int pattern, int x, int y) {
	if (pattern == 0) {
		return ((x % 8 == 2 && y % 8 == 2) || (x % 8 == 6 && y % 8 == 6)) ? 1 : 0;
	} else if (pattern == 1) {
		return (x + y) % 6 == 0 ? 2 : 0;
	} else if (pattern == 2) {
		int lx = x % 10;
		int ly = (y + ((x / 10) % 2) * 5) % 10;
		return abs(length(vec2(float(lx) - 4.5, float(ly) - 4.5)) - 2.2) < 0.55 ? 1 : 0;
	} else if (pattern == 3) {
		int lx = (x + ((y / 10) % 2) * 5) % 10;
		int ly = y % 10;
		return ((lx == 5 && ly >= 3 && ly <= 7) || (ly == 5 && lx >= 3 && lx <= 7)) ? 1 : 0;
	} else if (pattern == 4) {
		int k = x % 8;
		return y % 8 == (k < 4 ? k : 7 - k) + 2 ? 1 : 0;
	}
	return y % 7 == int(round(sin(float(x) * 0.6) * 1.4)) + 3 ? 2 : 0;
}

bool has_bit(uint bits, int i) {
	return ((bits >> uint(i)) & 1u) != 0u;
}

void fragment() {
	vec2 local = world.xz - board_rect.xy;
	ivec2 cell = ivec2(floor(local));
	uvec4 b = uvec4(round(texelFetch(cells_tex, cell, 0) * 255.0));
	if (b.r == 0u) {
		discard;
	}
	// Art pixel coordinates: global for the patterns, and the pixel's centre within its cell.
	ivec2 px = ivec2(floor(local * art_pixels));
	float n = art_pixels;
	vec2 c = vec2(px - cell * int(n)) + 0.5;
	// Neighbour bits, row by row from the north-west: 1 north, 3 west, 4 east, 6 south.
	bool open_n = !has_bit(b.b, 1);
	bool open_w = !has_bit(b.b, 3);
	bool open_e = !has_bit(b.b, 4);
	bool open_s = !has_bit(b.b, 6);
	float d = 1e3;
	if (open_n) { d = min(d, c.y); }
	if (open_s) { d = min(d, n - c.y); }
	if (open_w) { d = min(d, c.x); }
	if (open_e) { d = min(d, n - c.x); }
	float r = corner_radius;
	vec2 corners[4] = vec2[](vec2(r, r), vec2(n - r, r), vec2(n - r, n - r), vec2(r, n - r));
	bool rounded[4] = bool[](open_n && open_w, open_n && open_e, open_s && open_e, open_s && open_w);
	for (int i = 0; i < 4; i++) {
		vec2 k = corners[i];
		bool in_corner = (i == 0 || i == 3 ? c.x < k.x : c.x > k.x) && (i < 2 ? c.y < k.y : c.y > k.y);
		if (rounded[i] && in_corner) {
			float dist = length(c - k);
			if (dist > r) {
				discard;
			}
			d = min(d, r - dist);
		}
	}
	// Which gas this pixel shows: the kinds held, dithered by their shares.
	float total = 0.0;
	for (int k = 0; k < kind_count; k++) {
		if (has_bit(b.r, k)) {
			total += texelFetch(amount_tex, ivec3(cell, k), 0).r;
		}
	}
	float pick = bayer4(px) * total;
	int kind = 0;
	float run = 0.0;
	for (int k = 0; k < kind_count; k++) {
		if (has_bit(b.r, k)) {
			kind = k;
			run += texelFetch(amount_tex, ivec3(cell, k), 0).r;
			if (pick < run) {
				break;
			}
		}
	}
	vec4 col;
	if (d < 1.0) {
		col = vec4(palettes[kind * 4 + 3].rgb, alphas.x);
	} else if (d < 2.0) {
		col = vec4(palettes[kind * 4].rgb, alphas.y);
	} else {
		int mark = pattern_at(patterns[kind], px.x, px.y);
		vec3 tone = mark == 0 ? palettes[kind * 4 + 1].rgb : (mark == 1 ? palettes[kind * 4].rgb : palettes[kind * 4 + 2].rgb);
		col = vec4(tone, mark == 0 ? alphas.z : alphas.w);
	}
	ALBEDO = col.rgb * light.rgb;
	ALPHA = col.a;
}
