shader_type spatial;
render_mode unshaded, cull_disabled;

#include "res://shaders/thermal.gdshaderinc"

// Bodies: instance transform = lying pose at the death point,
// INSTANCE_CUSTOM = (death time, launch velocity xyz). Blast victims fly a ballistic arc,
// tumble a whole number of half-turns so they land flat, then cool. A death time pushed up by
// 100,000 marks a body killed by fire: charred, and smouldering a while longer.

varying float vheat;
varying float vdist;
varying vec3 vcol;
varying vec3 wn;
varying vec3 wp;
varying float vburnt;

void vertex() {
	float td_raw = INSTANCE_CUSTOM.x;
	float burnt = step(50000.0, td_raw);
	float td = td_raw - burnt * 100000.0;
	vec3 v0 = INSTANCE_CUSTOM.yzw;
	float age = max(sim_time - td, 0.0);
	float tl = max(2.0 * v0.y / 9.8, 0.0);
	float tau = min(age, tl);
	float flips = 1.0 + floor(fract(td * 7.13 + MODEL_MATRIX[3].x * 0.37) * 3.0);
	float a = tl > 0.01 ? flips * 3.14159265 * (tau / tl) : 0.0;
	vec3 p = VERTEX - vec3(0.0, 0.9, 0.0);
	float c = cos(a);
	float sn = sin(a);
	p = vec3(p.x, p.y * c - p.z * sn, p.y * sn + p.z * c) + vec3(0.0, 0.9, 0.0);
	vec3 w = (MODEL_MATRIX * vec4(p, 1.0)).xyz + v0 * tau + vec3(0.0, -4.9 * tau * tau, 0.0);
	wp = w;
	vec4 vp = VIEW_MATRIX * vec4(w, 1.0);
	POSITION = PROJECTION_MATRIX * vp;
	vdist = length(vp.xyz);
	// A fresh body loses most of its heat in a couple of seconds and is close to the ground's
	// temperature within about fifteen, limbs first, so the living stand out against the dead.
	// It never quite gets back to ambient: the trail of a fight stays faintly readable.
	float part = UV.x;
	float extremity = step(part, 1.5) + step(4.5, part);
	float core = 0.6 * exp(-age / (1.5 + burnt * 3.0)) + 0.4 * exp(-age / (8.0 + burnt * 10.0));
	core *= mix(1.0, exp(-age / 4.0), extremity * 0.6);
	vheat = 0.31 + (0.5 + burnt * 0.55) * core + step(2.5, part) * step(part, 3.5) * 0.04 * core;
	vburnt = burnt;
	// daylight: the same filthy clothes, darkened and bloodied; or burnt black
	float sd = fract(td * 7.13 + MODEL_MATRIX[3].z * 0.11);
	vec3 cloth = mix(vec3(0.22, 0.24, 0.3), vec3(0.4, 0.22, 0.18), sd);
	vcol = mix(part > 2.5 ? vec3(0.45, 0.45, 0.38) : cloth, vec3(0.32, 0.06, 0.05), 0.35) * 0.8;
	vcol = mix(vcol, vec3(0.06, 0.05, 0.045), burnt * 0.9);
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	ALBEDO = sensor_out_at(vheat, vcol, wn, vdist, wp);
	if (color_mode > 0.5 && vburnt > 0.5) {
		// still smouldering: embers at the colour of their temperature
		ALBEDO += glow_rgb(vheat * (0.85 + 0.3 * vnoise(wp.xz * 3.0 + vec2(sim_time * 0.7, 0.0)))) * 0.6;
	}
}
