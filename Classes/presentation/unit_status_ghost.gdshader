// A planning GHOST wearing its unit's element state (#358): the engine's ALPHA_CUT_DISABLED mode,
// a plain alpha blend. Its material carries the sprite's render_priority, which the engine applies
// to its own material in this mode and would not apply to an override (#317).
shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://Classes/presentation/unit_status.gdshaderinc"
