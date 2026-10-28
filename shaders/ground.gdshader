shader_type spatial;
render_mode unshaded;

#include "res://shaders/thermal.gdshaderinc"

// kind: 0 city + farmland, 1 desert, 2 port (sea to the south), 3 river, 4 arctic, 5 forest valley
uniform int kind = 0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Must agree with is_water() in world_builder.gd.
float water_mask(vec2 p) {
	if (kind == 2) {
		return step(40.0, p.y);
	}
	if (kind == 3) {
		float m = 25.0 * sin(p.x * 0.004);
		float river = step(abs(p.y - m), 270.0);
		float isl = step((p.x / 230.0) * (p.x / 230.0) + (p.y / 160.0) * (p.y / 160.0), 1.0);
		return river * (1.0 - isl);
	}
	return 0.0;
}

float city_farm(vec2 p) {
	float h = 0.27 + (fbm(p * 0.004) - 0.5) * 0.08 + (vnoise(p * 0.09) - 0.5) * 0.035;
	// farmland patchwork outside the town: ploughed rows show up clearly in IR
	float farm = smoothstep(1150.0, 1350.0, max(abs(p.x), abs(p.y)));
	vec2 cell = floor(p / 160.0);
	float ch = hash12(cell);
	float ang = ch * 3.14159;
	vec2 dir = vec2(cos(ang), sin(ang));
	float rows = 0.5 + 0.5 * sin(dot(p, dir) * 1.3);
	float fieldh = 0.21 + ch * 0.12 + rows * 0.035 * step(0.4, ch);
	vec2 fc = fract(p / 160.0);
	float hedge = clamp(step(fc.x, 0.025) + step(fc.y, 0.025), 0.0, 1.0);
	fieldh = mix(fieldh, 0.17, hedge);
	return mix(h, fieldh, farm);
}

float desert(vec2 p) {
	float dunes = sin(dot(p, vec2(0.012, 0.007)) + fbm(p * 0.003) * 6.0) * 0.5 + 0.5;
	float h = 0.19 + (fbm(p * 0.002) - 0.5) * 0.06 + dunes * 0.025 + (vnoise(p * 0.15) - 0.5) * 0.02;
	// dry wadis wind through the sand, damp and cooler
	float w = abs(fbm(p * 0.0011 + 3.7) - 0.5);
	h = mix(h, 0.14, smoothstep(0.03, 0.01, w));
	// gravel pan around the FOB holds more heat
	h += 0.035 * smoothstep(420.0, 110.0, length(p));
	return h;
}

float arctic(vec2 p) {
	float sastrugi = vnoise(vec2(p.x * 0.02 + p.y * 0.003, p.y * 0.25));
	float h = 0.105 + (fbm(p * 0.003) - 0.5) * 0.04 + (sastrugi - 0.5) * 0.025;
	float lake = smoothstep(270.0, 240.0, length(p - vec2(-650.0, 420.0)));
	h = mix(h, 0.135 + (vnoise(p * 0.02) - 0.5) * 0.01, lake);
	h += 0.02 * smoothstep(260.0, 80.0, length(p));
	return h;
}

float forest_floor(vec2 p) {
	// valley meadow: cold air pools here at night; grass in patches, the firebase gravel warmer
	float h = 0.205 + (fbm(p * 0.003) - 0.5) * 0.05 + (vnoise(p * 0.05) - 0.5) * 0.03;
	h += (vnoise(p * 0.4) - 0.5) * 0.015;
	h += 0.07 * smoothstep(360.0, 180.0, length(p));
	return h;
}

float water(vec2 p) {
	// open water at night is warmer than the land and almost perfectly flat
	float rip = vnoise(vec2(p.x * 0.05 + sim_time * 0.4, p.y * 0.22));
	float swell = vnoise(p * 0.006 + vec2(sim_time * 0.02, 0.0));
	return 0.30 + (rip - 0.5) * 0.014 + (swell - 0.5) * 0.02;
}

// ---------------------------------------------------------------- daylight colour
vec3 tv_city_farm(vec2 p) {
	// in town: worn concrete lots, kerbs and scrubby verges
	vec3 town = mix(vec3(0.46, 0.45, 0.42), vec3(0.4, 0.44, 0.3), smoothstep(0.45, 0.7, fbm(p * 0.01)));
	town *= 0.9 + 0.2 * vnoise(p * 0.3);
	// outside it a patchwork of fields: wheat, green crops, ploughed earth, pasture
	vec2 cell = floor(p / 160.0);
	float ch = hash12(cell);
	vec3 crop = ch < 0.3 ? vec3(0.72, 0.62, 0.34) : (ch < 0.55 ? vec3(0.36, 0.5, 0.2) : (ch < 0.75 ? vec3(0.42, 0.32, 0.22) : vec3(0.44, 0.56, 0.28)));
	float ang = ch * 3.14159;
	vec2 dir = vec2(cos(ang), sin(ang));
	float rows = 0.5 + 0.5 * sin(dot(p, dir) * 1.3);
	crop *= 0.9 + 0.12 * rows * step(0.3, ch) + 0.08 * (vnoise(p * 0.05) - 0.5);
	vec2 fc = fract(p / 160.0);
	float hedge = clamp(step(fc.x, 0.025) + step(fc.y, 0.025), 0.0, 1.0);
	crop = mix(crop, vec3(0.2, 0.3, 0.14), hedge);
	float farm = smoothstep(1150.0, 1350.0, max(abs(p.x), abs(p.y)));
	return mix(town, crop, farm);
}

vec3 tv_desert(vec2 p) {
	float dunes = sin(dot(p, vec2(0.012, 0.007)) + fbm(p * 0.003) * 6.0) * 0.5 + 0.5;
	vec3 c = mix(vec3(0.76, 0.64, 0.46), vec3(0.84, 0.72, 0.52), dunes);
	c *= 0.92 + 0.16 * fbm(p * 0.02);
	float w = abs(fbm(p * 0.0011 + 3.7) - 0.5);
	c = mix(c, vec3(0.58, 0.52, 0.42), smoothstep(0.03, 0.01, w));
	// gravel pan around the FOB
	c = mix(c, vec3(0.6, 0.57, 0.5), smoothstep(420.0, 110.0, length(p)));
	return c;
}

vec3 tv_arctic(vec2 p) {
	float sastrugi = vnoise(vec2(p.x * 0.02 + p.y * 0.003, p.y * 0.25));
	vec3 c = vec3(0.9, 0.93, 0.97) * (0.95 + 0.06 * sastrugi + 0.04 * (fbm(p * 0.003) - 0.5));
	float lake = smoothstep(270.0, 240.0, length(p - vec2(-650.0, 420.0)));
	c = mix(c, vec3(0.62, 0.76, 0.86), lake);
	c = mix(c, vec3(0.72, 0.72, 0.74), smoothstep(160.0, 60.0, length(p)) * 0.6);
	return c;
}

vec3 tv_forest(vec2 p) {
	vec3 c = mix(vec3(0.34, 0.46, 0.22), vec3(0.45, 0.52, 0.27), fbm(p * 0.004));
	c *= 0.9 + 0.18 * vnoise(p * 0.06);
	// firebase gravel and packed earth
	c = mix(c, vec3(0.55, 0.5, 0.42), smoothstep(360.0, 180.0, length(p)));
	return c;
}

vec3 tv_water(vec2 p, float dist) {
	float rip = vnoise(vec2(p.x * 0.05 + sim_time * 0.4, p.y * 0.22));
	vec3 c = kind == 3 ? vec3(0.22, 0.3, 0.24) : vec3(0.1, 0.26, 0.36);
	c *= 0.85 + 0.3 * rip;
	// sun glint off the chop
	c += vec3(0.25) * pow(rip, 8.0);
	return c;
}

void fragment() {
	vec2 p = wpos.xz;
	float h;
	if (kind == 1) {
		h = desert(p);
	} else if (kind == 4) {
		h = arctic(p);
	} else if (kind == 5) {
		h = forest_floor(p);
	} else {
		h = city_farm(p);
	}
	float wm = water_mask(p);
	if (wm > 0.5) {
		h = water(p);
	}
	vec3 alb;
	if (kind == 1) {
		alb = tv_desert(p);
	} else if (kind == 4) {
		alb = tv_arctic(p);
	} else if (kind == 5) {
		alb = tv_forest(p);
	} else {
		alb = tv_city_farm(p);
	}
	if (wm > 0.5) {
		alb = tv_water(p, length(VERTEX));
	} else {
		// burnt ground: black char and grey ash where the fighting has been, for the rest of the sortie
		float sc = scorch_at(p);
		if (sc > 0.01) {
			vec3 ash = mix(vec3(0.06, 0.055, 0.05), vec3(0.26, 0.25, 0.24), smoothstep(0.4, 0.8, vnoise(p * 0.3)) * 0.6);
			alb = mix(alb, ash, sc * 0.9);
			h += 0.012 * sc;
		}
	}
	ALBEDO = sensor_out_at(h, alb, vec3(0.0, 1.0, 0.0), length(VERTEX), wpos);
}
