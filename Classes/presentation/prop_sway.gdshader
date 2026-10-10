// A plant leaning in the wind (#1286), drawn the way the engine draws a plant's sprite: its
// ALPHA_CUT_OPAQUE_PREPASS mode, which writes depth so a unit behind a tree still sorts.
shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://Classes/presentation/prop_sway.gdshaderinc"
