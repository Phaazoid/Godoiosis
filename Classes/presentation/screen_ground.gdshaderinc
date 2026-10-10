// What a full-screen pass over the board (BoardOverlays.make_screen_pass) asks of the depth buffer: the
// world point each pixel shows, whether the pixel is sky, and the art grid a pixel-art pass snaps to.
// Shared by the fog's pass, the clouds' shadows and the aurora's curtains. Functions only: each pass
// declares its own depth sampler and cell_size, so this include adds no uniform to collide with
// weather_mask.gdshaderinc's.

// A depth at or below this is the sky: the ray hit nothing.
const float SCREEN_SKY = 0.00001;

bool screen_is_sky(float depth) {
	return depth <= SCREEN_SKY;
}

// The world point a pixel shows, from its depth and the view's inverse matrices.
vec3 screen_world(float depth, vec2 screen_uv, mat4 inv_view, mat4 inv_projection) {
	vec4 world = inv_view * inv_projection * vec4(screen_uv * 2.0 - 1.0, depth, 1.0);
	return world.xyz / world.w;
}

// A ground point snapped to the centre of its art pixel, `pixels_per_cell` to a cell `cell_width` wide.
vec2 screen_art_snap(vec2 p, float pixels_per_cell, float cell_width) {
	return (floor(p * pixels_per_cell / cell_width) + 0.5) * cell_width / pixels_per_cell;
}

// A 0..1 value stepped into `bands` levels, so an edge reads as pixel art.
float screen_steps(float v, float bands) {
	return floor(v * bands + 0.5) / bands;
}
