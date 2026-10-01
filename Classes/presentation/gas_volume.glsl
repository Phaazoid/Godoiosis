#[versions]

march = "#define MARCH_PASS";
composite = "#define COMPOSITE_PASS";

#[compute]

#version 450

#VERSION_DEFINES

// Gas volume (#508), the compositor half of GasMirror. MARCH runs at the volume resolution (half by
// default): each texel casts one ray through every gas region box it crosses, stops at the scene
// depth, and writes premultiplied colour plus the distance it used. COMPOSITE runs at full
// resolution: a depth-aware upsample of the march, then the POOL in closed form against full-res
// depth (so the cell edge stays crisp), over the colour buffer. The pixel style marches once per
// art-pixel block, folds the pool in there, posterizes, and the composite takes it nearest.
//
// Ported from round 4's spatial probe: Beer-Lambert extinction, a short sun march for self-shadow,
// a two-lobe Henyey-Greenstein phase, lamps, lightning glows, frost glints.
//
// A tear-out's diorama is the board lifted rigidly (BoardSpace.stage_offset), so a LIFTED region
// reads the same field at p - offset, and only from the cells that went up with it.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

struct Look {
	vec4 albedo;   // rgb, extinction
	vec4 emit;     // rgb emission, lightning (0/1)
	vec4 column;   // base height, column height, top softness, shape scale
	vec4 motion;   // stretch, erosion, rise speed, coverage boost
	vec4 pool;     // height, density, sparkle, 0
	vec4 wind;     // x, z drift, 0, 0
};

layout(set = 0, binding = 0) uniform sampler2D depth_tex;
#ifdef MARCH_PASS
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D march_out;
layout(r32f, set = 0, binding = 2) uniform restrict writeonly image2D march_depth_out;
#else
layout(rgba16f, set = 0, binding = 1) uniform restrict image2D color_image;
layout(set = 0, binding = 2) uniform sampler2D march_in;
layout(set = 0, binding = 3) uniform sampler2D march_depth_in;
#endif

layout(set = 0, binding = 4, std140) uniform Frame {
	mat4 inv_projection;
	mat4 camera_to_world;
	vec4 raster;         // full w, full h, full pixels per march texel, pixel style (0/1)
	vec4 screen_rect;    // full-res origin x, y; march origin x, y
	vec4 board_rect;     // x, z, w, h in cells (one cell is one world unit)
	vec4 sun_dir;        // xyz toward the sun, w ambient strength
	vec4 sun_color;      // rgb, w = gas time
	vec4 ambient;        // rgb, w = region count
	vec4 march0;         // steps, light steps, first light step, min step
	vec4 march1;         // g forward, g back, back mix, powder
	vec4 march2;         // thin floor, contain softness, pool softness, detail scale
	vec4 march3;         // flash energy, flash radius, glint size, upsample tolerance
	vec4 pixel;          // bands, cut, ink, 0
	vec4 flash_color;    // rgb, glint strength
	vec4 counts;         // lamp count, flash count, kind count, 0
	vec4 stage;          // the diorama's offset, w = 1 while a fight is staged
	vec4 lamps[8];       // xyz, range
	vec4 lamp_colors[8]; // rgb x energy
	vec4 flashes[4];     // xyz, strength now
} frame;

layout(set = 0, binding = 5, std430) restrict readonly buffer Looks {
	Look looks[];
};

#ifdef MARCH_PASS
layout(set = 0, binding = 6, std430) restrict readonly buffer Regions {
	vec4 regions[];      // pairs: (min xyz, lifted 0/1), (max xyz, 0)
};
#endif

layout(set = 0, binding = 7) uniform sampler2D cells_tex;         // R kinds held, G kinds near, B 8-neighbour gas bits, A staged
layout(set = 0, binding = 8) uniform sampler2DArray amount_tex;   // one layer per kind, amount / max
layout(set = 0, binding = 9) uniform sampler2DArray mask_tex;     // one layer per kind, upscaled smooth
layout(set = 0, binding = 10) uniform sampler2D ground_tex;       // NW, NE, SE, SW world y per cell
layout(set = 0, binding = 11) uniform sampler2D ground_mid_tex;   // the surface at the cell centre
layout(set = 0, binding = 12) uniform sampler3D shape_noise;
#ifdef MARCH_PASS
layout(set = 0, binding = 13) uniform sampler3D detail_noise;
#endif

float remap01(float v, float lo, float hi) {
	return clamp((v - lo) / max(hi - lo, 1e-4), 0.0, 1.0);
}

float hg(float c, float g) {
	float g2 = g * g;
	return (1.0 - g2) / pow(max(1.0 + g2 - 2.0 * g * c, 1e-4), 1.5);
}

float phase(float c) {
	return mix(hg(c, frame.march1.x), hg(c, -frame.march1.y), frame.march1.z);
}

ivec2 cell_of(vec2 xz) {
	return ivec2(floor(xz - frame.board_rect.xy));
}

// R kinds held, G kinds near, B neighbour bits, A staged; zero off the board.
uvec4 bits_at(ivec2 c) {
	if (c.x < 0 || c.y < 0 || c.x >= int(frame.board_rect.z) || c.y >= int(frame.board_rect.w)) {
		return uvec4(0);
	}
	return uvec4(round(texelFetch(cells_tex, c, 0) * 255.0));
}

// Gas near this cell that belongs to this copy of the board: the lifted diorama only shows the
// cells that went up, and the board left behind only the ones that stayed.
uint kinds_near(ivec2 c, bool lifted) {
	uvec4 b = bits_at(c);
	bool staged = frame.stage.w > 0.5 && b.a > 0u;
	return staged == lifted ? b.g : 0u;
}

float tri_height(vec2 p, vec2 a, vec2 b, vec2 c, float ha, float hb, float hc) {
	vec2 v0 = b - a;
	vec2 v1 = c - a;
	vec2 v2 = p - a;
	float den = v0.x * v1.y - v1.x * v0.y;
	float u = (v2.x * v1.y - v1.x * v2.y) / den;
	float v = (v0.x * v2.y - v2.x * v0.y) / den;
	return ha + u * (hb - ha) + v * (hc - ha);
}

// The surface under xz as a fan of four triangles around the cell centre. The centre is
// Terrain.height_at_uv's own answer and lies on whichever diagonal that rule splits on, so each fan
// triangle lies inside one true triangle and this is exact on every corner form.
float ground_at(vec2 xz) {
	vec2 local = xz - frame.board_rect.xy;
	ivec2 c = clamp(ivec2(floor(local)), ivec2(0), ivec2(frame.board_rect.zw) - 1);
	vec2 f = clamp(local - vec2(c), 0.0, 1.0);
	vec4 k = texelFetch(ground_tex, c, 0);
	float m = texelFetch(ground_mid_tex, c, 0).r;
	vec2 d = f - 0.5;
	if (abs(d.x) > abs(d.y)) {
		if (d.x > 0.0) {
			return tri_height(f, vec2(1.0, 0.0), vec2(1.0, 1.0), vec2(0.5), k.y, k.z, m);
		}
		return tri_height(f, vec2(0.0, 0.0), vec2(0.0, 1.0), vec2(0.5), k.x, k.w, m);
	}
	if (d.y < 0.0) {
		return tri_height(f, vec2(0.0, 0.0), vec2(1.0, 0.0), vec2(0.5), k.x, k.y, m);
	}
	return tri_height(f, vec2(0.0, 1.0), vec2(1.0, 1.0), vec2(0.5), k.w, k.z, m);
}

// Smoothstep-weighted bilinear: rounds off the diamonds plain bilinear leaves between cells.
float amount_of(vec2 xz, int kind) {
	vec2 st = (xz - frame.board_rect.xy) - 0.5;
	vec2 i = floor(st);
	vec2 f = fract(st);
	f = f * f * (3.0 - 2.0 * f);
	return texture(amount_tex, vec3((i + f + 0.5) / frame.board_rect.zw, float(kind))).r;
}

float mask_of(vec2 xz, int kind) {
	return texture(mask_tex, vec3((xz - frame.board_rect.xy) / frame.board_rect.zw, float(kind))).r;
}

vec3 unproject(vec2 uv, float depth) {
	vec4 view = frame.inv_projection * vec4(uv * 2.0 - 1.0, depth, 1.0);
	return view.xyz / view.w;
}

vec3 view_dir_world(vec2 uv) {
	vec3 near_point = unproject(uv, 1.0);   // reversed-Z: 1 is the near plane
	return normalize(mat3(frame.camera_to_world) * normalize(near_point));
}

// Lamplight scattered toward the eye from p, before the medium's albedo.
vec3 lamps_at(vec3 p, vec3 rd) {
	vec3 sum = vec3(0.0);
	for (int i = 0; i < int(frame.counts.x); i++) {
		vec3 to_l = frame.lamps[i].xyz - p;
		float dist = length(to_l);
		float att = pow(clamp(1.0 - dist / frame.lamps[i].w, 0.0, 1.0), 2.0);
		sum += frame.lamp_colors[i].rgb * att * phase(dot(rd, to_l / max(dist, 1e-3)));
	}
	return sum;
}

vec3 flashes_at(vec3 p, float radius_scale) {
	vec3 sum = vec3(0.0);
	for (int i = 0; i < int(frame.counts.y); i++) {
		float reach = frame.march3.y * radius_scale;
		float att = pow(clamp(1.0 - length(frame.flashes[i].xyz - p) / reach, 0.0, 1.0), 2.0);
		sum += frame.flash_color.rgb * frame.march3.x * frame.flashes[i].w * att;
	}
	return sum;
}

// --- the pool: a crisp slab on the cells, integrated in closed form where the ray ends -----------

// Every kind's pool in front of `hit`: total optical depth, the radiance it scatters and its colour
// (both extinction-weighted averages).
void pool_at(vec3 hit, vec3 rd, float t, out float od, out vec3 radiance, out vec3 albedo) {
	od = 0.0;
	radiance = vec3(0.0);
	albedo = vec3(0.0);
	bool lifted = false;
	vec3 q = hit;
	if (frame.stage.w > 0.5 && hit.y - ground_at(hit.xz) > frame.stage.y * 0.5) {
		lifted = true;
		q = hit - frame.stage.xyz;
	}
	uint near = kinds_near(cell_of(q.xz), lifted);
	if (near == 0u) {
		return;
	}
	float h_end = q.y - ground_at(q.xz);
	float down = max(-rd.y, 0.08);
	float ripple = texture(shape_noise, vec3(q.x * 0.45, t * 0.04, q.z * 0.45)).r;
	float soft = frame.march2.z;
	vec3 light = frame.sun_color.rgb * phase(dot(rd, frame.sun_dir.xyz)) * 0.6 + frame.ambient.rgb * frame.sun_dir.w;
	for (int k = 0; k < int(frame.counts.z); k++) {
		if ((near & (1u << uint(k))) == 0u) {
			continue;
		}
		Look L = looks[k];
		if (L.pool.y <= 0.0) {
			continue;
		}
		float a = max(amount_of(q.xz, k), frame.march2.x);
		float top = L.pool.x * (0.7 + 0.6 * ripple) * (0.65 + 0.35 * a);
		float seg = max(top - h_end, 0.0) / down;
		if (seg <= 0.0) {
			continue;
		}
		float m = 0.5 * (mask_of(q.xz, k) + mask_of(q.xz - rd.xz * seg, k));
		float od_k = L.pool.y * L.albedo.w * smoothstep(0.5 - soft, 0.5 + soft, m) * seg;
		if (od_k <= 0.0) {
			continue;
		}
		vec3 emit = L.emit.rgb;
		if (L.emit.w > 0.0) {
			emit += L.albedo.rgb * flashes_at(hit, 1.4) * 0.6;
		}
		radiance += (L.albedo.rgb * light + emit) * od_k;
		albedo += L.albedo.rgb * od_k;
		od += od_k;
	}
	if (od > 0.0) {
		radiance /= od;
		albedo /= od;
	}
}

#ifdef MARCH_PASS

// --- the billows ------------------------------------------------------------------------------

float kind_density(vec3 q, float h, float t, bool detailed, int k) {
	Look L = looks[k];
	float m = mask_of(q.xz, k);
	// Held to the cells, a little more loosely up top: the pool marks the cells exactly, so a
	// cloud's crown may round off instead of standing as a sheer wall.
	float cs = frame.march2.y + h * 0.08;
	if (m < 0.5 - cs) {
		return 0.0;
	}
	float a = max(amount_of(q.xz, k), frame.march2.x) * smoothstep(0.5 - cs, 0.5 + cs, m);
	float column = L.column.x + L.column.y * a;
	float vert = 1.0 - smoothstep(column * (1.0 - L.column.z), column, h);
	float base = a * vert;
	if (base <= 0.0) {
		return 0.0;
	}
	vec3 drift = vec3(L.wind.x, L.motion.z, L.wind.y) * t;
	vec3 sq = vec3(L.column.w, L.column.w * L.motion.x, L.column.w);
	float seed = float(k) * 0.37;
	float n = texture(shape_noise, (q - drift) * sq + vec3(seed)).r;
	float coverage = clamp(base * L.motion.w, 0.0, 1.0);
	float d = remap01(n, 1.0 - coverage, 1.0) * coverage;
	if (detailed && d > 0.0) {
		float w = texture(detail_noise, (q - drift * 1.6) * frame.march2.w + vec3(seed)).r;
		d = remap01(d, L.motion.y * w * 0.6, 1.0);
	}
	return d;
}

// Total extinction at p; when `detailed`, also the extinction-weighted albedo, glow, lightning and
// glint weight.
float medium_at(vec3 p, bool lifted, float t, bool detailed, out vec3 alb, out vec3 emit, out float flash,
		out float glint) {
	alb = vec3(0.0);
	emit = vec3(0.0);
	flash = 0.0;
	glint = 0.0;
	vec3 q = lifted ? p - frame.stage.xyz : p;
	uint near = kinds_near(cell_of(q.xz), lifted);
	if (near == 0u) {
		return 0.0;
	}
	float h = q.y - ground_at(q.xz);
	if (h < 0.0) {
		return 0.0;
	}
	float sigma = 0.0;
	for (int k = 0; k < int(frame.counts.z); k++) {
		if ((near & (1u << uint(k))) == 0u) {
			continue;
		}
		float d = kind_density(q, h, t, detailed, k);
		if (d <= 0.0) {
			continue;
		}
		Look L = looks[k];
		float s = d * L.albedo.w;
		sigma += s;
		if (detailed) {
			alb += L.albedo.rgb * s;
			emit += L.emit.rgb * s;
			flash += L.emit.w * s;
			glint += L.pool.z * s;
		}
	}
	if (detailed && sigma > 0.0) {
		alb /= sigma;
		emit /= sigma;
		flash /= sigma;
		glint /= sigma;
	}
	return sigma;
}

float bayer4(ivec2 p) {
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[(p.y & 3) * 4 + (p.x & 3)]) + 0.5) / 16.0;
}

void march_span(vec3 ro, vec3 rd, vec2 span, bool lifted, float jitter, inout vec3 color, inout float T,
		inout vec3 alb_acc) {
	float t_gas = frame.sun_color.w;
	int steps = int(frame.march0.x);
	float dt = max((span.y - span.x) / float(steps), frame.march0.w);
	float t = span.x + dt * jitter;
	float sun_phase = phase(dot(rd, frame.sun_dir.xyz));
	for (int i = 0; i < steps; i++) {
		if (t >= span.y || T < 0.01) {
			break;
		}
		vec3 p = ro + rd * t;
		vec3 alb;
		vec3 emit;
		float fl;
		float gl;
		float sigma = medium_at(p, lifted, t_gas, true, alb, emit, fl, gl);
		if (sigma > 0.01) {
			float od = 0.0;
			float ls = frame.march0.z;
			vec3 lp = p;
			for (int j = 0; j < int(frame.march0.y); j++) {
				lp += frame.sun_dir.xyz * ls;
				vec3 a2;
				vec3 e2;
				float f2;
				float g2;
				od += medium_at(lp, lifted, t_gas, false, a2, e2, f2, g2) * ls;
				ls *= 1.5;
			}
			float sun_t = exp(-od);
			float powder_term = mix(1.0, clamp((1.0 - exp(-sigma * 0.5)) * 2.0, 0.0, 1.0), frame.march1.w);
			if (fl > 0.0) {
				emit += alb * flashes_at(p, 1.0) * fl;
			}
			if (gl > 0.0) {
				// Glints: one point in some cells of a falling grid, lit when the ray passes near it --
				// a distance to the LINE, so a glint never depends on a step landing on it.
				vec3 gq = (p + vec3(0.0, t_gas * 0.3, 0.0)) * 3.0;
				vec3 ci = floor(gq);
				float hs = fract(sin(dot(ci, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
				if (hs > 0.72) {
					vec3 gp = (ci + vec3(fract(hs * 7.13), fract(hs * 13.71), fract(hs * 3.37))) / 3.0
						- vec3(0.0, t_gas * 0.3, 0.0);
					float dline = length(cross(gp - ro, rd));
					float twinkle = 0.55 + 0.45 * sin(t_gas * 5.0 + hs * 40.0);
					emit += vec3(frame.flash_color.w) * gl * smoothstep(frame.march3.z, 0.0, dline) * twinkle;
				}
			}
			vec3 radiance = alb * (frame.sun_color.rgb * sun_t * sun_phase * powder_term
				+ frame.ambient.rgb * frame.sun_dir.w + lamps_at(p, rd)) + emit;
			float st = exp(-sigma * dt);
			color += T * radiance * (1.0 - st);
			alb_acc += T * alb * (1.0 - st);
			T *= st;
		}
		t += dt;
	}
}

void main() {
	ivec2 tex = ivec2(gl_GlobalInvocationID.xy) + ivec2(frame.screen_rect.zw);
	ivec2 out_size = imageSize(march_out);
	if (tex.x >= out_size.x || tex.y >= out_size.y) {
		return;
	}
	vec2 full = frame.raster.xy;
	float block = frame.raster.z;
	bool pixel_style = frame.raster.w > 0.5;
	ivec2 full_i = ivec2(full) - 1;

	// The depth this texel stands for. Smooth: a checkerboard of nearest and farthest over its block,
	// so the upsample always has a tap on each side of a unit's edge. Pixel: the block's centre.
	ivec2 origin = ivec2(vec2(tex) * block);
	float depth;
	if (pixel_style) {
		depth = texelFetch(depth_tex, clamp(origin + ivec2(block * 0.5), ivec2(0), full_i), 0).r;
	} else {
		bool nearest = ((tex.x + tex.y) & 1) == 0;
		depth = nearest ? 0.0 : 1.0;
		int b = int(block);
		for (int y = 0; y < b; y++) {
			for (int x = 0; x < b; x++) {
				float d = texelFetch(depth_tex, clamp(origin + ivec2(x, y), ivec2(0), full_i), 0).r;
				depth = nearest ? max(depth, d) : min(depth, d);   // reversed-Z: larger is nearer
			}
		}
	}
	vec2 uv = clamp((vec2(tex) + 0.5) * block / full, vec2(0.0), vec2(1.0));
	vec3 ro = frame.camera_to_world[3].xyz;
	vec3 rd = view_dir_world(uv);
	float dist = depth > 0.0 ? length(unproject(uv, depth)) : 1e6;

	// The region boxes this ray crosses, front to back. GasRegions keeps them disjoint, so their
	// intervals along one ray never overlap and no stretch of gas is counted twice.
	vec3 spans[8];   // tn, tf, lifted
	int span_count = 0;
	vec3 inv = 1.0 / rd;
	for (int r = 0; r < int(frame.ambient.w) && span_count < 8; r++) {
		vec4 lo = regions[r * 2];
		vec4 hi = regions[r * 2 + 1];
		vec3 t0 = (lo.xyz - ro) * inv;
		vec3 t1 = (hi.xyz - ro) * inv;
		vec3 tlo = min(t0, t1);
		vec3 thi = max(t0, t1);
		float tn = max(max(max(tlo.x, tlo.y), tlo.z), 0.0);
		float tf = min(min(min(thi.x, thi.y), thi.z), dist);
		if (tf <= tn) {
			continue;
		}
		int i = span_count;
		while (i > 0 && spans[i - 1].x > tn) {
			spans[i] = spans[i - 1];
			i--;
		}
		spans[i] = vec3(tn, tf, lo.w);
		span_count++;
	}

	vec3 color = vec3(0.0);
	float T = 1.0;
	vec3 alb_acc = vec3(0.0);
	float jitter = fract(52.9829189 * fract(dot(vec2(tex), vec2(0.06711056, 0.00583715))));
	for (int s = 0; s < span_count; s++) {
		march_span(ro, rd, spans[s].xy, spans[s].z > 0.5, jitter, color, T, alb_acc);
	}

	if (pixel_style) {
		// The pool belongs to this block too, then the whole block is posterized against the gas's
		// OWN colour, so dark smoke stays dark, and its fringe dithers.
		if (depth > 0.0) {
			float od;
			vec3 rad;
			vec3 alb_pool;
			pool_at(ro + rd * dist, rd, frame.sun_color.w, od, rad, alb_pool);
			if (od > 0.0) {
				float st = exp(-od);
				color += T * rad * (1.0 - st);
				alb_acc += T * alb_pool * (1.0 - st);
				T *= st;
			}
		}
		float A = 1.0 - T;
		float b = bayer4(tex);
		float cut = frame.pixel.y + (b - 0.5) * 0.35;
		float solid = step(cut, A);
		vec3 c = color / max(A, 1e-3);
		vec3 alb_avg = alb_acc / max(A, 1e-3);
		float lit = dot(c, vec3(0.3, 0.59, 0.11)) / max(dot(alb_avg, vec3(0.3, 0.59, 0.11)), 0.03);
		float q = max(floor(lit * frame.pixel.x + b) / frame.pixel.x, 1.0 / frame.pixel.x);
		vec3 cq = alb_avg * q;
		cq = mix(cq, cq * 0.55, step(A, cut + frame.pixel.z));
		imageStore(march_out, tex, vec4(cq * solid, solid));
	} else {
		imageStore(march_out, tex, vec4(color, 1.0 - T));
	}
	imageStore(march_depth_out, tex, vec4(dist));
}

#else

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy) + ivec2(frame.screen_rect.xy);
	vec2 full = frame.raster.xy;
	if (px.x >= int(full.x) || px.y >= int(full.y)) {
		return;
	}
	float block = frame.raster.z;
	bool pixel_style = frame.raster.w > 0.5;
	ivec2 march_size = textureSize(march_in, 0);
	float depth = texelFetch(depth_tex, px, 0).r;
	vec2 uv = (vec2(px) + 0.5) / full;
	vec3 ro = frame.camera_to_world[3].xyz;
	vec3 rd = view_dir_world(uv);
	float dist = depth > 0.0 ? length(unproject(uv, depth)) : 1e6;

	vec4 gas;
	if (pixel_style) {
		gas = texelFetch(march_in, clamp(ivec2(vec2(px) / block), ivec2(0), march_size - 1), 0);
	} else {
		// Depth-aware upsample: bilinear weights, each tap discounted by how far its depth sits from
		// this pixel's, so gas does not bleed across a unit's silhouette.
		vec2 mp = (vec2(px) + 0.5) / block - 0.5;
		ivec2 b = ivec2(floor(mp));
		vec2 f = fract(mp);
		vec4 sum = vec4(0.0);
		float wsum = 0.0;
		vec4 best = vec4(0.0);
		float best_err = 1e9;
		float tol = max(frame.march3.w * dist, 0.05);
		for (int j = 0; j < 2; j++) {
			for (int i = 0; i < 2; i++) {
				ivec2 tp = clamp(b + ivec2(i, j), ivec2(0), march_size - 1);
				vec4 g = texelFetch(march_in, tp, 0);
				float err = abs(texelFetch(march_depth_in, tp, 0).r - dist);
				float w = (i == 0 ? 1.0 - f.x : f.x) * (j == 0 ? 1.0 - f.y : f.y);
				w *= exp(-err / tol);
				sum += g * w;
				wsum += w;
				if (err < best_err) {
					best_err = err;
					best = g;
				}
			}
		}
		gas = wsum > 1e-4 ? sum / wsum : best;
	}

	float pool_od = 0.0;
	vec3 pool_rad = vec3(0.0);
	if (!pixel_style && depth > 0.0) {
		vec3 alb_pool;
		pool_at(ro + rd * dist, rd, frame.sun_color.w, pool_od, pool_rad, alb_pool);
	}
	if (gas.a <= 0.0 && pool_od <= 0.0) {
		return;
	}
	vec4 scene = imageLoad(color_image, px);
	float st = exp(-pool_od);
	vec3 under = pool_rad * (1.0 - st) + scene.rgb * st;
	imageStore(color_image, px, vec4(gas.rgb + (1.0 - gas.a) * under, scene.a));
}

#endif
