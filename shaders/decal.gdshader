shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

#include "res://shaders/thermal.gdshaderinc"

// Ground heat marks: scorched craters and blood that cool over time.
// custom = (time created, start heat, residual heat, cooling time)

varying float vheat;
varying vec2 vseed;

void vertex() {
	float age = max(sim_time - INSTANCE_CUSTOM.x, 0.0);
	vheat = mix(INSTANCE_CUSTOM.y, INSTANCE_CUSTOM.z, smoothstep(0.0, max(INSTANCE_CUSTOM.w, 0.01), age));
	vseed = MODEL_MATRIX[3].xz;
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float n = vnoise(UV * 6.0 + vseed * 0.13);
	float a = smoothstep(1.0, 0.5, r + (n - 0.5) * 0.6);
	if (color_mode > 0.5) {
		// scorched earth and blood: dark, with embers glowing while it's still hot
		vec3 scorch = mix(vec3(0.1, 0.08, 0.07), vec3(0.24, 0.07, 0.05), step(0.55, fract(vseed.x * 0.37 + vseed.y * 0.11)) * 0.6);
		// embers glow at their temperature while the ground is still that hot
		vec3 ember = glow_rgb(vheat * (0.9 + n * 0.2)) * (1.0 - r);
		ALBEDO = srgb_lin(scorch * (0.8 + n * 0.4)) + ember;
		ALPHA = a * 0.85;
	} else {
		ALBEDO = heat_out(vheat * (0.9 + n * 0.2));
		ALPHA = a * 0.95;
	}
}
