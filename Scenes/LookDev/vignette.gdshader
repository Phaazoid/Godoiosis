// Look-dev vignette (#203): a full-screen radial darken, the last layer of the
// HD-2D post stack. Lives on the UI CanvasLayer's ColorRect; V toggles it.
shader_type canvas_item;

uniform float strength : hint_range(0.0, 1.0) = 0.35;
uniform float softness : hint_range(0.01, 1.0) = 0.55;

void fragment() {
	float dist = length(UV - vec2(0.5)) * 1.41421;
	float shade = smoothstep(1.0 - softness, 1.0, dist) * strength;
	COLOR = vec4(0.0, 0.0, 0.0, shade);
}
