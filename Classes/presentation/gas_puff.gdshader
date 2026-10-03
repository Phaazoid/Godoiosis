// The pixel puffs (#508): one MultiMesh, every quad a Y-billboard standing on its feet, animated here
// from GasMirror's pushed clock -- the boil, the bob, the wander and each gas's moving extra -- so
// nothing is moved by script per frame. Ported from round 4's probe, which moved 700 sprites by hand.
//
// INSTANCE_CUSTOM: x = kind, y = role (0 puff, 1 wisp, 2 soot, 3 bubble, 4 snow, 5 bolt, 6 curl),
// z = phase, w = a puff's size * 3 + variant. COLOR: rgb = the light at the instance, a = how lit
// its lightning is right now (GasMirror's flash schedule).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled, fog_disabled;

uniform sampler2DArray art : source_color, filter_nearest;
uniform float gas_time = 0.0;
uniform float pixel_size = 0.03125;
uniform float canvas_height = 32.0;   // art pixels, GasPuffArt.LAYER_SIZE.y
uniform float stride = 16.0;
uniform float extra_base = 9.0;
uniform float boil_seconds[6];
uniform vec2 bob[6];                   // art pixels of bob, rate
uniform float sway[6];                 // art pixels of side-to-side drift
uniform float drift = 0.0;             // world units a puff wanders around its spot (the mix's)
uniform float bolt_threshold = 0.35;   // how lit a strike must be before its bolt shows

varying flat float layer;
varying vec4 tint;

float snap(float art_pixels) {
	return round(art_pixels) * pixel_size;
}

void vertex() {
	int kind = int(INSTANCE_CUSTOM.x + 0.5);
	int role = int(INSTANCE_CUSTOM.y + 0.5);
	float ph = INSTANCE_CUSTOM.z;
	float t = gas_time;
	float base = float(kind) * stride;
	vec3 offset = vec3(0.0);
	bool shown = true;
	// Every extra is drawn bottom-centred like a puff, so lifting it by half its own height puts its
	// middle where the probe put it.
	float half_height = 0.0;
	if (role == 0) {
		float slot = INSTANCE_CUSTOM.w;
		float size = floor(slot / 3.0 + 0.01);
		float variant = slot - size * 3.0;
		float boil = mod(floor(t / max(boil_seconds[kind], 0.05) + ph), 3.0);
		layer = base + size * 3.0 + mod(variant + boil, 3.0);
		offset.y = snap(sin(t * bob[kind].y + ph) * bob[kind].x);
		float wander = drift / pixel_size;
		offset.x = snap(sin(t * 0.5 + ph) * sway[kind] + sin(t * 0.43 + ph * 3.0) * wander);
		offset.z = snap(sin(t * 0.31 + ph * 5.0) * wander);
	} else if (role == 1) {
		float u = fract(t / 1.8 + ph);
		layer = base + extra_base + (u < 0.55 ? 0.0 : 1.0);
		shown = u < 0.9;
		half_height = u < 0.55 ? 5.0 : 3.5;
		offset.y = 0.55 + u * 0.9;
	} else if (role == 2) {
		float u = fract(t / 3.0 + ph);
		layer = base + extra_base;
		half_height = 1.5;
		offset = vec3(snap(sin(u * TAU) * 3.0), 0.5 + u * 1.3, 0.0);
	} else if (role == 3) {
		float u = fract(t / 1.9 + ph);
		layer = base + extra_base + (u < 0.68 ? 0.0 : 1.0);
		shown = u < 0.76;
		half_height = 3.5;
		offset.y = u < 0.68 ? 0.08 + u / 0.68 * 0.4 : 0.5;
	} else if (role == 4) {
		float u = fract(t / 2.2 + ph);
		layer = base + extra_base;
		half_height = 2.5;
		offset = vec3(snap(sin(u * 9.0 + ph * 6.0) * 2.0), 0.95 - u * 0.9, 0.0);
	} else if (role == 5) {
		layer = base + extra_base;
		shown = COLOR.a > bolt_threshold;
		half_height = 10.0;
		offset.y = 0.34;
	} else {
		float u = fract(t / 2.4 + ph);
		layer = base + extra_base + mod(floor(t / 0.2 + ph * 4.0), 4.0);
		shown = u < 0.85;
		half_height = 4.5;
		offset = vec3(snap(sin(u * 6.0) * 2.0), 0.45 + u * 0.9, 0.0);
	}
	offset.y -= half_height * pixel_size;
	tint = COLOR;
	if (!shown) {
		VERTEX = vec3(0.0);
	}
	// A Y-billboard at the instance's own origin, the engine's BILLBOARD_FIXED_Y spelled out.
	vec4 origin = MODEL_MATRIX[3] + vec4(offset, 0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		origin);
}

void fragment() {
	vec4 texel = texture(art, vec3(UV, layer));
	ALBEDO = texel.rgb * tint.rgb * (1.0 + tint.a * 1.3);
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
