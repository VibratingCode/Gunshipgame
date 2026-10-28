shader_type spatial;
render_mode unshaded, cull_disabled;

#include "res://shaders/thermal.gdshaderinc"

// Abandoned vehicles. UV.x tags the parts: 0 body, 1 glasshouse, 2 wheels.
// INSTANCE_CUSTOM = (burnt out, still burning, paint seed, engine still warm).
// Most are cold metal in the usual car-park paint; a few still have a warm engine block; the
// burnt-out wrecks are blistered black and rust with the glass gone; a handful are still alight.
varying float vh;
varying vec3 vcol;
varying vec3 wn;
varying vec3 wp;
varying float vfire;

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	float part = UV.x;
	float burnt = cd.x;
	float burning = cd.y;
	float front = step(VERTEX.z, -1.0);
	vh = 0.21 + fract(cd.z * 7.3) * 0.05 + cd.w * front * step(part, 0.5) * 0.34 + step(0.5, part) * step(part, 1.5) * 0.02;
	vh = mix(vh, 0.18, burnt) + burning * (0.6 + 0.25 * fract(cd.z * 3.1));
	vfire = burning;
	float p = cd.z;
	vec3 paint = p < 0.22 ? vec3(0.85, 0.85, 0.84) : (p < 0.4 ? vec3(0.58, 0.6, 0.62) : (p < 0.55 ? vec3(0.1, 0.1, 0.11) : (p < 0.68 ? vec3(0.6, 0.12, 0.1) : (p < 0.8 ? vec3(0.14, 0.24, 0.48) : (p < 0.9 ? vec3(0.3, 0.32, 0.34) : vec3(0.62, 0.56, 0.42))))));
	vec3 glass = vec3(0.14, 0.17, 0.2);
	vec3 tyre = vec3(0.06, 0.06, 0.065);
	vcol = part < 0.5 ? paint : (part < 1.5 ? glass : tyre);
	vec3 wreck = mix(vec3(0.08, 0.07, 0.065), vec3(0.32, 0.17, 0.09), fract(p * 13.7));
	vcol = mix(vcol, part < 1.5 ? wreck : tyre, burnt);
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = sensor_out_at(vh, vcol, wn, length(VERTEX), wp);
	if (color_mode > 0.5 && vfire > 0.5) {
		// still burning: the flames are at the colour of their temperature
		ALBEDO += glow_rgb(1.3 + 0.3 * vnoise(wp.xz * 2.0 + vec2(sim_time * 3.0, wp.y))) * 0.6;
	}
}
