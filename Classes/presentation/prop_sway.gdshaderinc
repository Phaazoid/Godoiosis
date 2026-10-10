// A plant leaning in the wind (#1286): the engine's own sprite (sprite_material.gdshaderinc) with its
// quad sheared above the base. Included by prop_sway.gdshader (the plant, the engine's opaque prepass)
// and prop_sway_cap.gdshader (its snow cap, an alpha blend), which differ only in render_mode.
//
// A plant's quad stands on its base at local y = 0 (BoardMirror plants every billboard by its foot),
// so a vertex moves by `lean` times its own height along the wind: the base stays put and the top
// leans furthest, with no plant's height needed. `flutter` rocks it on top of that, each plant on its
// own phase off where it stands; sway_time is the mirror's own clock, so a hitstop freezes the lot.

#include "res://Classes/presentation/sprite_material.gdshaderinc"

uniform vec2 wind_heading = vec2(1.0, 0.0);   // the wind's direction on x / z
uniform float lean = 0.0;                     // how far the top leans, times the plant's height
uniform float flutter = 0.0;                  // how far it rocks either way, times its height
uniform float sway_speed = 1.6;               // rocks a second
uniform float sway_time = 0.0;

void vertex() {
	mat4 basis = sprite_billboard(MAIN_CAM_INV_VIEW_MATRIX, MODEL_MATRIX);
	vec3 along = vec3(wind_heading.x, 0.0, wind_heading.y);
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453) * 6.2831853;
	float bend = (lean + flutter * sin(sway_time * sway_speed * 6.2831853 + phase)) * max(VERTEX.y, 0.0);
	VERTEX.x += dot(along, basis[0].xyz) * bend;
	VERTEX.z += dot(along, basis[2].xyz) * bend;
	MODELVIEW_MATRIX = VIEW_MATRIX * basis;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 albedo_tex = texture(texture_albedo, UV) * sprite_tint(COLOR, OUTPUT_IS_SRGB);
	ALBEDO = albedo.rgb * albedo_tex.rgb;
	METALLIC = metallic;
	SPECULAR = specular;
	ROUGHNESS = roughness;
	ALPHA *= albedo.a * albedo_tex.a;
}
