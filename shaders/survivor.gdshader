shader_type spatial;
render_mode unshaded, cull_disabled;

#include "res://shaders/thermal.gdshaderinc"

// Survivors mill about their spot. INSTANCE_CUSTOM = (wander radius, pace, seed, heat).
// In daylight colour they wear whatever they fled in; the garrison wears uniform.

varying float vheat;
varying vec3 vcol;
varying vec3 wn;
varying vec3 wp;

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float s = max(length(MODEL_MATRIX[0].xyz), 0.001);
	float t = sim_time * c.y;
	vec2 off = vec2(sin(t + c.z * 10.0) + 0.5 * sin(t * 2.3 + c.z * 3.0),
			cos(t * 0.8 + c.z * 7.0) + 0.5 * cos(t * 1.7 + c.z)) * c.x;
	VERTEX.xz += off / s;
	vheat = c.w + step(1.45, VERTEX.y) * 0.08;
	float part = UV.x;
	float sd = c.z;
	bool soldier = abs(c.w - 0.95) < 0.001;
	vec3 skin = mix(vec3(0.42, 0.3, 0.22), vec3(0.86, 0.7, 0.58), fract(sd * 5.3));
	vec3 top = soldier ? vec3(0.38, 0.4, 0.3) : mix(vec3(0.2, 0.3, 0.55), vec3(0.75, 0.3, 0.2), fract(sd * 3.1));
	vec3 legs = soldier ? vec3(0.36, 0.38, 0.28) : mix(vec3(0.18, 0.22, 0.32), vec3(0.4, 0.36, 0.3), fract(sd * 7.7));
	vcol = part < 1.5 ? legs : (part < 2.5 ? top : (part < 3.5 ? skin : (soldier ? top : skin)));
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = sensor_out_at(vheat, vcol, wn, length(VERTEX), wp);
}
