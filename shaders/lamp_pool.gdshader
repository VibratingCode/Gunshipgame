shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

#include "res://shaders/thermal.gdshaderinc"
#include "res://shaders/lamp.gdshaderinc"

// The pool of sodium light a lit streetlight throws on the road under it, for the TV camera
// (the thermal imager doesn't see light). The quad sits under the lamp head; the instance
// transform is the lamp's own, so it's lit exactly when its lamp is.
varying float von;
varying vec2 vuv;

void vertex() {
	von = lamp_on(MODEL_MATRIX[3].xyz);
	vuv = UV;
}

void fragment() {
	float r = length(vuv - 0.5) * 2.0;
	float a = smoothstep(1.0, 0.0, r);
	ALBEDO = color_mode > 0.5 ? sodium() * von * a * a * 0.22 : vec3(0.0);
}
