shader_type spatial;
render_mode unshaded, cull_disabled;

#include "res://shaders/thermal.gdshaderinc"
#include "res://shaders/lamp.gdshaderinc"

// Streetlights. UV.x: 0 pole and arm, 1 the lamp head. A lit head glows sodium orange on the TV
// and sits warm on the thermal; a dead one is just a cold pole.
varying float vpart;
varying float von;
varying vec3 wn;
varying vec3 wp;

void vertex() {
	von = lamp_on(MODEL_MATRIX[3].xyz);
	vpart = UV.x;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dist = length(VERTEX);
	if (color_mode > 0.5) {
		vec3 c = tv_light_at(vec3(0.22, 0.23, 0.24), wn, dist, wp);
		if (vpart > 0.5) {
			c = mix(c, sodium() * 2.5, von);
		}
		ALBEDO = c;
	} else {
		ALBEDO = heat_out(haze(0.25 + (vpart > 0.5 ? 0.08 + 0.4 * von : 0.0), dist));
	}
}
