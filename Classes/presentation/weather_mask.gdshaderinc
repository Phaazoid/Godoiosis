// Where a drop lands (#1260): the WeatherMask texel under a world point, evaluated the way
// Terrain.height_at_uv is. WeatherMask.surface_at is this in GDScript, and the two are pinned together
// by tests/presentation/test_weather_mask.gd -- change one, change both.

uniform sampler2D mask : filter_nearest, repeat_disable;
uniform vec2 mask_origin = vec2(0.0);   // the mask rect's first cell
uniform float cell_size = 1.0;

const float WEATHER_VOID = -100000.0;

float weather_surface(vec2 p) {
	vec2 at = p / cell_size;
	ivec2 cell = ivec2(floor(at)) - ivec2(mask_origin);
	ivec2 size = textureSize(mask, 0);
	if (cell.x < 0 || cell.y < 0 || cell.x >= size.x || cell.y >= size.y) {
		return WEATHER_VOID;
	}
	vec4 c = texelFetch(mask, cell, 0);
	if (c.r < -10000.0) {
		return WEATHER_VOID;
	}
	float u = fract(at.x);
	float v = fract(at.y);
	if (abs(c.g - c.a) < 0.0001) {
		if (u + v <= 1.0) {
			return c.r + (c.g - c.r) * u + (c.a - c.r) * v;
		}
		return c.b + (c.a - c.b) * (1.0 - u) + (c.g - c.b) * (1.0 - v);
	}
	if (v <= u) {
		return c.r + (c.g - c.r) * u + (c.b - c.g) * v;
	}
	return c.r + (c.a - c.r) * v + (c.b - c.a) * u;
}

uint weather_hash(uint x) {
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	return (x >> uint(16)) ^ x;
}

float weather_rand(inout uint seed) {
	seed = weather_hash(seed);
	return float(seed % uint(65536)) / 65535.0;
}
