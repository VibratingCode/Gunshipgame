shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

#include "res://shaders/fx_body.gdshaderinc"

void fragment() {
	float r = length(vuv - 0.5) * 2.0;
	float n = vnoise(vuv * 4.0 + vec2(vk * 2.0, vkind * 3.0));
	float a = smoothstep(1.0, 0.2, r + (n - 0.5) * 0.55) * (1.0 - vk) * 0.62;
	if (color_mode > 0.5) {
		// smoke: sooty black over a fire, greying as it rises and thins; dust takes the ground's colour
		vec3 dust = ao_style > 3.5 && ao_style < 4.5 ? vec3(0.85, 0.88, 0.92) : (ao_style > 0.5 && ao_style < 1.5 ? vec3(0.72, 0.62, 0.48) : vec3(0.52, 0.48, 0.42));
		vec3 smoke = mix(vec3(0.14, 0.13, 0.12), dust, clamp(vk * 1.4 + (1.0 - vheat) * 0.6, 0.0, 1.0));
		ALBEDO = tv_light(smoke * (0.85 + 0.3 * n), vec3(0.0, 1.0, 0.0), length(VERTEX));
	} else {
		ALBEDO = heat_out(vheat);
	}
	ALPHA = a;
}
