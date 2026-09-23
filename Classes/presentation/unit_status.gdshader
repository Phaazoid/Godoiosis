// A REAL unit sprite wearing an element state (#358): the engine's ALPHA_CUT_OPAQUE_PREPASS mode.
shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://Classes/presentation/unit_status.gdshaderinc"
