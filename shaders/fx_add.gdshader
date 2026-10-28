shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

#include "res://shaders/fx_body.gdshaderinc"

void fragment() {
	float r = length(vuv - 0.5) * 2.0;
	float a;
	if (vkind > 3.5) {
		a = smoothstep(0.72, 0.93, r) * smoothstep(1.0, 0.94, r);
	} else if (vkind > 2.5) {
		a = smoothstep(1.0, 0.0, r);
	} else {
		a = pow(clamp(1.0 - r, 0.0, 1.0), 1.5);
	}
	if (color_mode > 0.5) {
		// in daylight everything that burns glows at the colour of its temperature: a cooling
		// fireball goes white, yellow, orange, dull red, then out. The shock ring is raised dust.
		ALBEDO = vkind > 3.5 ? srgb_lin(vec3(0.35, 0.32, 0.28) * vheat) * 0.8 : glow_rgb(vheat) * 0.85;
	} else {
		ALBEDO = heat_out(vheat);
	}
	ALPHA = a;
}
