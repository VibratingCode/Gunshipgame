shader_type spatial;
render_mode unshaded, cull_disabled;

#include "res://shaders/thermal.gdshaderinc"

// Zombies are simulated analytically: the instance transform holds the spawn point and
// heading, INSTANCE_CUSTOM holds (spawn time, speed, path length, seed). Position along the
// path is evaluated here on the GPU; horde.gd evaluates the identical formula on the CPU
// whenever it needs to know where a zombie is (hit tests, grid buckets).
// UV.x tags body parts: 0/1 legs, 2 torso, 3 head, 4 arms.

varying float vheat;
varying vec3 vcol;
varying vec3 wn;
varying vec3 wp;

void vertex() {
	float t0 = INSTANCE_CUSTOM.x;
	float spd = INSTANCE_CUSTOM.y;
	float len = INSTANCE_CUSTOM.z;
	float seed = INSTANCE_CUSTOM.w;
	float s = max(length(MODEL_MATRIX[0].xyz), 0.001);

	float travel = max(sim_time - t0, 0.0) * spd;
	float d = min(travel, len);
	float amp = 1.0 + fract(seed * 13.7) * 2.5;
	float lat = sin(d * 0.045 + seed * 6.2831853) * amp;
	float arrived = step(len, travel);
	float runner = step(2.0, spd);
	float part = UV.x;

	vec3 p = VERTEX;
	// gait phase advances with distance covered, so feet never skate:
	// shuffling ~0.5 m steps (1 m cycle), jogging ~1 m steps (2 m cycle); big bodies take
	// proportionally longer strides
	float phase = d * mix(6.2, 3.2, runner) / s + seed * 40.0;
	float boss = step(3.0, s);
	if (part < 1.5) {
		float side = part < 0.5 ? 1.0 : -1.0;
		float k = clamp(1.0 - p.y / 0.9, 0.0, 1.0);
		p.z += sin(phase) * side * mix(0.28, 0.45, runner) * k * (1.0 - arrived);
	}
	// at the wall they claw and pound
	float att = arrived * sin(sim_time * (6.0 + fract(seed * 5.1) * 4.0) + seed * 30.0);
	if (part > 3.5) {
		p.y += (sin(phase * 0.5) * 0.06 + att * 0.25) * clamp(-p.z * 2.0, 0.0, 1.0);
	}
	p.x += sin(phase * 0.5 + seed * 9.0) * 0.05 * p.y;
	// dummies that never walk (the dev farm) sway on the spot
	float idle = 1.0 - step(0.01, spd);
	p.x += idle * sin(sim_time * 1.3 + seed * 20.0) * 0.05 * p.y;
	p.z += idle * sin(sim_time * 0.9 + seed * 11.0) * 0.03 * p.y;
	p.z -= p.y * (mix(0.08, 0.3, runner) + att * 0.05);

	// walk: local -Z is forward, local +X is the lateral wobble axis
	p.z -= d / s;
	p.x += lat / s;
	VERTEX = p;

	// The infected run a raging fever, and each kind wears it differently on the thermal:
	//   walkers: a warm torso, a hot head, cooler legs and arms; some burn hotter than others
	//   runners: hotter all over from the exertion, the head and breath pulsing with every stride
	//   brutes:  a big slab of heat in the chest that holds it, throbbing slowly; cold limbs
	//   bosses:  hotter still, with a slow throb you can pick out across the map
	float brute = step(1.4, s) * (1.0 - boss);
	float headp = step(2.5, part) * step(part, 3.5);
	float torso = step(1.5, part) * step(part, 2.5);
	float legs = step(part, 1.5);
	float arms = step(3.5, part);
	float fever = fract(seed * 7.31);
	vheat = 0.64 + fever * 0.1 + runner * 0.1 + arrived * 0.04
		+ headp * (0.16 + runner * 0.05 + runner * 0.06 * max(sin(phase * 0.5), 0.0))
		+ torso * (0.04 + brute * 0.12 + brute * 0.04 * sin(sim_time * 1.5 + seed * 20.0))
		- legs * (0.08 + brute * 0.03)
		- arms * (0.05 + brute * 0.04)
		+ boss * (0.14 + 0.06 * sin(sim_time * 2.2 + seed * 20.0));

	// daylight colour: grey-green infected skin, filthy torn clothes; bosses a bloated mottled grey-red
	vec3 skin = mix(vec3(0.46, 0.5, 0.4), vec3(0.6, 0.58, 0.5), fract(seed * 4.7));
	vec3 shirt = mix(vec3(0.3, 0.28, 0.25), mix(vec3(0.32, 0.36, 0.5), vec3(0.55, 0.22, 0.18), fract(seed * 9.1)), 0.6);
	vec3 pants = mix(vec3(0.2, 0.24, 0.32), vec3(0.3, 0.27, 0.22), fract(seed * 6.3));
	vcol = part < 1.5 ? pants : (part < 2.5 ? shirt : skin);
	vcol *= 0.85 + 0.25 * fract(seed * 17.9);
	vcol = mix(vcol, vec3(0.5, 0.36, 0.34), boss * 0.8);
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = sensor_out_at(vheat, vcol, wn, length(VERTEX), wp);
}
