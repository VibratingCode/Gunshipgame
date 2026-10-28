shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

#include "res://shaders/thermal.gdshaderinc"

// Every projectile is a hot streak flying a real ballistic arc from its muzzle.
//   origin  = muzzle position at the moment of firing
//   basis.x = launch velocity (solved by the fire-control computer)
//   basis.y = (heat, width in metres, streak length in seconds)
//   custom  = (fire time, time of flight)

varying float vheat;
varying float vu;
varying float vx;

void vertex() {
	vec3 p0 = MODEL_MATRIX[3].xyz;
	vec3 v0 = MODEL_MATRIX[0].xyz;
	vec3 m1 = MODEL_MATRIX[1].xyz;
	float tf = INSTANCE_CUSTOM.y;
	float age = sim_time - INSTANCE_CUSTOM.x;
	float alive = step(0.0, age) * step(age, tf);
	float th = clamp(age, 0.0, tf);
	float tt = clamp(age - m1.z, 0.0, tf);
	vec3 head = p0 + v0 * th + vec3(0.0, -4.9 * th * th, 0.0);
	vec3 tail = p0 + v0 * tt + vec3(0.0, -4.9 * tt * tt, 0.0);
	vec3 hv = (VIEW_MATRIX * vec4(head, 1.0)).xyz;
	vec3 tv = (VIEW_MATRIX * vec4(tail, 1.0)).xyz;
	vec3 mid = (hv + tv) * 0.5;
	vec3 side = cross(hv - tv, mid);
	float sl = length(side);
	side = sl > 1e-6 ? side / sl : vec3(1.0, 0.0, 0.0);
	float dist = max(-mid.z, 1.0);
	float px = 2.0 * dist / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float w = max(m1.y, px * 1.4);
	vec3 pv = (VERTEX.y > 0.0 ? hv : tv) + side * VERTEX.x * w * 2.0 * alive;
	POSITION = PROJECTION_MATRIX * vec4(pv, 1.0);
	// right at the muzzle the streak is metres from the lens; ease it in so it reads as a round, not a bar
	vheat = m1.x * clamp(m1.y / w, 0.35, 1.0) * alive * mix(0.25, 1.0, smoothstep(0.0, 0.1, th));
	vu = VERTEX.y + 0.5;
	vx = VERTEX.x * 2.0;
}

void fragment() {
	// in daylight a streak glows at the colour of its temperature: tracer compound burns
	// orange-red, a re-entering rod or a pulse of light burns white
	ALBEDO = color_mode > 0.5 ? glow_rgb(vheat) * 1.25 : heat_out(vheat);
	ALPHA = (0.25 + 0.75 * vu * vu) * (1.0 - abs(vx) * 0.6);
}
