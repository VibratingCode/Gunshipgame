shader_type spatial;
render_mode unshaded;

#include "res://shaders/thermal.gdshaderinc"

// Foliage is cooler than the ground at night: dark blobs in white-hot.
// In daylight colour each canopy gets its own shade of green (dusty olive in the desert).
varying float vh;
varying vec3 vcol;
varying vec3 wn;
varying vec3 wp;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float r = hash12(o.xz);
	vh = 0.16 + r * 0.06 + VERTEX.y * 0.012;
	vec3 green = mix(vec3(0.17, 0.3, 0.12), vec3(0.3, 0.42, 0.16), r);
	if (ao_style > 0.5 && ao_style < 1.5) {
		green = mix(vec3(0.36, 0.38, 0.22), vec3(0.45, 0.44, 0.28), r);
	}
	// sunlit crown, shaded underside
	vcol = green * (0.8 + 0.25 * clamp(VERTEX.y, -1.0, 1.0));
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// trees in a burnt-out block are bare and black
	float sc = scorch_at(wp.xz);
	vcol = mix(vcol, vec3(0.08, 0.07, 0.06), sc * 0.85);
	vh = mix(vh, 0.24, sc * 0.6);
}

void fragment() {
	ALBEDO = sensor_out_at(vh, vcol, wn, length(VERTEX), wp);
}
