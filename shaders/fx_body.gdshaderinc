// Shared vertex stage for pooled effect particles (see fx.gd).
// The instance transform is used as a data carrier, not a transform:
//   origin   = spawn position
//   basis.x  = initial velocity
//   basis.y  = (gravity scale, drag, start heat)
//   basis.z  = (kind, rotation, unused)
//   custom   = (spawn time, lifetime, start size, end size)
// kinds: 0 flash, 1 fireball, 2 smoke/dust, 3 spark/debris, 4 ground shock ring

#include "res://shaders/thermal.gdshaderinc"

varying float vheat;
varying vec2 vuv;
varying float vkind;
varying float vk;

void vertex() {
	vec3 p0 = MODEL_MATRIX[3].xyz;
	vec3 v0 = MODEL_MATRIX[0].xyz;
	vec3 m1 = MODEL_MATRIX[1].xyz;
	vec3 m2 = MODEL_MATRIX[2].xyz;
	float life = max(INSTANCE_CUSTOM.y, 0.0001);
	float age = sim_time - INSTANCE_CUSTOM.x;
	float k = age / life;
	float alive = step(0.0, age) * step(k, 1.0);
	float dr = max(m1.y, 0.0001);
	float f = (1.0 - exp(-dr * age)) / dr;
	vec3 pos = p0 + v0 * f + vec3(0.0, -4.9 * m1.x * age * age, 0.0);
	pos.y = max(pos.y, 0.1);
	float kk = clamp(k, 0.0, 1.0);
	float sz = mix(INSTANCE_CUSTOM.z, INSTANCE_CUSTOM.w, 1.0 - (1.0 - kk) * (1.0 - kk)) * alive;
	float kind = m2.x;
	vec2 q = VERTEX.xy;
	float ca = cos(m2.y);
	float sa = sin(m2.y);
	q = vec2(q.x * ca - q.y * sa, q.x * sa + q.y * ca);
	vec3 w;
	if (kind > 3.5) {
		w = pos + vec3(VERTEX.x, 0.0, VERTEX.y) * sz;
	} else {
		vec3 right = INV_VIEW_MATRIX[0].xyz;
		vec3 up = INV_VIEW_MATRIX[1].xyz;
		w = pos + (right * q.x + up * q.y) * sz;
	}
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(w, 1.0);
	vuv = VERTEX.xy + 0.5;
	vkind = kind;
	vk = kk;

	float h = m1.z;
	if (kind < 0.5) {
		h *= (1.0 - kk) * (1.0 - kk);
	} else if (kind < 1.5) {
		// a fireball cools fast; a long-burning flame (napalm, thermite, white phosphorus) holds
		// its heat and dies down from orange to dull red over its life
		h *= mix(exp(-3.0 * kk), 1.0 - 0.55 * kk, smoothstep(3.0, 10.0, life));
	} else if (kind < 2.5) {
		h = mix(h, 0.30, smoothstep(0.0, 0.5, kk));
	} else if (kind < 3.5) {
		h *= 1.0 - kk * kk;
	} else {
		h *= 1.0 - kk;
	}
	vheat = h;
}
