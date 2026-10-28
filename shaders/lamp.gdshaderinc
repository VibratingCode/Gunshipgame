// Streetlights share one rule for whether they're lit: after dusk, if their district still has
// power. The grid fails district by district as the days go by (grid_power, 1 on day one), and a
// district right on the edge of failing flickers. o = the lamp's foot.
float lamp_on(vec3 o) {
	float district = hash12(floor(o.xz / 420.0) + vec2(3.7, 1.3));
	float own = hash12(o.xz * 0.37);
	float on = step(district, grid_power * 1.02) * step(own, 0.93);
	float edge = 1.0 - smoothstep(0.0, 0.07, abs(district - grid_power));
	float flick = 1.0 - edge * step(0.45, hash12(vec2(floor(sim_time * 9.0), own * 97.0)));
	return on * flick * smoothstep(0.15, 0.5, night);
}

// High-pressure sodium: the orange of a ~2,100 K source.
vec3 sodium() {
	return srgb_lin(blackbody(2100.0));
}
