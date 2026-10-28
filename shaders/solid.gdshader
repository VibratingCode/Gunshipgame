shader_type spatial;
render_mode unshaded, cull_disabled;

#include "res://shaders/thermal.gdshaderinc"

// Munitions, aircraft parts and other single-heat objects.
uniform float heat = 0.8;
uniform vec3 albedo = vec3(0.46, 0.48, 0.5);

void fragment() {
	vec3 n = world_normal(NORMAL, INV_VIEW_MATRIX);
	ALBEDO = sensor_out(heat, albedo, n, length(VERTEX));
}
