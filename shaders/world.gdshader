shader_type spatial;
render_mode unshaded, cull_disabled;

#include "res://shaders/thermal.gdshaderinc"

// Vertex colour channels:
//   r = base heat, g = solar-loading factor, b = surface noise, a = window flag (<1 = has windows)
//   For glowing things (r > 1.1), g says what kind of light: < 0.35 fire, 0.35-0.6 a red beacon,
//   > 0.6 an electric lamp.
// UV.x = material tag for the daylight colour camera (see MeshKit.TAG_* and world_builder.gd).
// Each object's heat is a random draw, so fract(heat * k) doubles as a per-object hash for colour.
varying vec3 wpos;
varying vec3 wnrm;
varying vec4 vcol;
varying float vtag;
// 0..1: a building the infected have taken over (a nest): packed with warm bodies on the
// thermal, fires burning behind the windows on the TV
uniform float infest = 0.0;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR;
	vtag = UV.x;
}

vec3 pick4(float r, vec3 a, vec3 b, vec3 c, vec3 d) {
	return r < 0.25 ? a : (r < 0.5 ? b : (r < 0.75 ? c : d));
}

float facade_u(vec3 p, vec3 n) {
	return abs(n.x) > 0.5 ? p.z : p.x;
}

// window grid on a facade (shared by the thermal and the colour paths)
float window_at(vec3 p, vec3 n) {
	vec2 g = vec2(facade_u(p, n) / 3.2, p.y / 3.4);
	vec2 f = fract(g);
	return step(0.25, f.x) * step(f.x, 0.75) * step(0.3, f.y) * step(f.y, 0.78) * step(2.0, p.y);
}

vec2 window_cell(vec3 p, vec3 n) {
	return floor(vec2(facade_u(p, n) / 3.2, p.y / 3.4)) + floor(p.xz * 0.02) * 17.0;
}

// A window to the daylight camera: glass giving back the sky, curtains or blinds behind some,
// others broken out or boarded over. Where the block has burnt, most are broken and black.
vec3 window_col(vec2 cell, vec3 p, float burnt) {
	float r = hash12(cell);
	if (r < 0.07 + burnt * 0.6) {
		return vec3(0.03, 0.03, 0.035);
	}
	if (r < 0.14 + burnt * 0.6) {
		return vec3(0.42, 0.33, 0.22);
	}
	if (r < 0.36) {
		return mix(vec3(0.55, 0.42, 0.3), vec3(0.62, 0.3, 0.26), hash12(cell * 3.1)) * 0.7;
	}
	if (r < 0.5) {
		return mix(vec3(0.62, 0.62, 0.58), vec3(0.48, 0.48, 0.45), step(0.5, fract(p.y * 4.0)));
	}
	return mix(vec3(0.16, 0.2, 0.26), sky_col * 0.55, 0.35 + 0.3 * hash12(cell * 1.7));
}

vec3 albedo(int tag, vec3 p, vec3 n, vec4 vc, float burnt) {
	float oh = fract(vc.r * 137.31 + vc.r * vc.r * 911.7);
	float nz = vnoise(p.xz * 0.35 + vec2(p.y * 0.5));
	bool roof = n.y > 0.6;
	float u = facade_u(p, n);
	vec3 c;
	if (tag == 1) {
		// asphalt, patched and oil-stained
		c = vec3(0.24, 0.24, 0.25) * (0.88 + 0.22 * vnoise(p.xz * 0.2));
		c *= 1.0 - 0.12 * smoothstep(0.6, 0.85, vnoise(p.xz * 0.7 + 13.0));
	} else if (tag == 2) {
		// poured concrete, T-walls, pads, pavements
		c = vec3(0.62, 0.61, 0.58) * (0.9 + 0.15 * nz);
		c *= 1.0 - 0.08 * step(0.94, fract(p.x / 2.5)) - 0.08 * step(0.94, fract(p.z / 2.5));
	} else if (tag == 3) {
		// city buildings: render, brick, stone or painted, with dark tar or clay roofs
		c = pick4(oh, vec3(0.74, 0.69, 0.6), vec3(0.6, 0.36, 0.28), vec3(0.66, 0.66, 0.64), vec3(0.82, 0.8, 0.74));
		if (roof) {
			c = fract(oh * 7.3) < 0.6 ? vec3(0.3, 0.3, 0.31) : vec3(0.55, 0.32, 0.24);
			c *= 0.88 + 0.18 * vnoise(p.xz * 0.8);
		} else {
			// floor slabs
			c *= 1.0 - 0.12 * step(fract(p.y / 3.4), 0.06) * step(3.0, p.y);
			if (vc.a < 0.99 && p.y < 4.4 && oh > 0.3 && vc.a < 0.5) {
				// ground-floor shopfronts: plate glass in bays, a sign board over them
				float bay = fract(u / 6.0);
				float bay_id = floor(u / 6.0);
				if (p.y > 3.5) {
					c = pick4(hash12(vec2(bay_id, oh * 31.0)), vec3(0.7, 0.15, 0.12), vec3(0.15, 0.3, 0.55), vec3(0.85, 0.75, 0.2), vec3(0.2, 0.45, 0.25));
				} else if (p.y > 0.4 && bay > 0.08 && bay < 0.92) {
					c = window_col(vec2(bay_id, oh * 50.0), p, burnt) * 1.1;
				}
			} else if (vc.a < 0.99 && window_at(p, n) > 0.5) {
				c = window_col(window_cell(p, n), p, burnt);
			}
			// weathering: rain streaks down from the roofline and the sills, grime at the foot
			c *= 1.0 - 0.1 * smoothstep(0.55, 0.9, vnoise(vec2(u * 1.1, p.y * 0.04)));
			c *= 1.0 - 0.18 * smoothstep(2.2, 0.0, p.y);
		}
		c *= 0.92 + 0.12 * nz;
	} else if (tag == 4) {
		// glass and steel towers
		c = mix(vec3(0.3, 0.42, 0.48), vec3(0.42, 0.5, 0.56), oh);
		float mull = step(0.9, fract(p.y / 3.4)) + step(0.94, fract(u / 3.0));
		c = mix(c, vec3(0.7, 0.72, 0.74), clamp(mull, 0.0, 1.0));
		// a few panes blown out
		if (hash12(floor(vec2(u / 3.0, p.y / 3.4)) + floor(p.xz * 0.02) * 9.0) < 0.05 + burnt * 0.5) {
			c = vec3(0.04);
		}
		if (roof) {
			c = vec3(0.4, 0.41, 0.42);
		}
	} else if (tag == 5) {
		// sun-baked mud brick
		c = mix(vec3(0.68, 0.55, 0.4), vec3(0.76, 0.64, 0.48), oh) * (0.9 + 0.15 * nz);
		c *= 1.0 - 0.15 * smoothstep(1.5, 0.0, p.y);
		if (vc.a < 0.99 && window_at(p, n) > 0.5) {
			c *= 0.35;
		}
	} else if (tag == 6) {
		// structural steel, streaked with rust
		c = vec3(0.45, 0.47, 0.5) * (1.0 - 0.15 * smoothstep(0.6, 0.9, vnoise(vec2(u * 2.0, p.y * 0.3))));
	} else if (tag == 7) {
		// shipping containers, ribbed
		c = pick4(oh, vec3(0.62, 0.18, 0.14), vec3(0.16, 0.32, 0.55), vec3(0.2, 0.42, 0.28), vec3(0.78, 0.5, 0.16));
		if (fract(oh * 5.1) > 0.8) {
			c = vec3(0.82, 0.82, 0.8);
		}
		c *= 0.85 + 0.15 * step(0.5, fract(u * 3.0));
	} else if (tag == 8) {
		// military olive drab
		c = vec3(0.34, 0.36, 0.25) * (0.9 + 0.12 * nz);
	} else if (tag == 9) {
		// HESCO and sandbags
		c = vec3(0.7, 0.62, 0.46) * (0.88 + 0.18 * nz);
		c *= 0.92 + 0.08 * step(0.5, fract(p.y * 3.0));
	} else if (tag == 10) {
		// mountains: rock, scree and, high up or on the ice, snow
		vec3 rock = ao_style > 3.5 && ao_style < 4.5 ? vec3(0.42, 0.42, 0.45) : (ao_style > 0.5 && ao_style < 1.5 ? vec3(0.62, 0.5, 0.38) : vec3(0.42, 0.44, 0.36));
		float snow = ao_style > 3.5 && ao_style < 4.5 ? smoothstep(80.0, 300.0, p.y) : smoothstep(650.0, 850.0, p.y);
		snow *= smoothstep(0.35, 0.75, n.y);
		c = mix(rock * (0.85 + 0.25 * fbm(p.xz * 0.01)), vec3(0.93, 0.95, 0.98), snow);
	} else if (tag == 11) {
		// snow berms
		c = vec3(0.9, 0.92, 0.96);
	} else if (tag == 12) {
		// painted white: ship hulls, station modules
		c = vec3(0.88, 0.88, 0.86) * (1.0 - 0.08 * smoothstep(0.6, 0.9, vnoise(vec2(u * 0.9, p.y * 0.05))));
		if (vc.a < 0.99 && window_at(p, n) > 0.5) {
			c = vec3(0.22, 0.26, 0.3);
		}
	} else if (tag == 13) {
		// painted red: polar station modules, crosses, markings
		c = vec3(0.72, 0.16, 0.12);
		if (vc.a < 0.99 && window_at(p, n) > 0.5) {
			c = vec3(0.2, 0.22, 0.26);
		}
	} else if (tag == 14) {
		// timber
		c = vec3(0.48, 0.36, 0.24) * (0.9 + 0.15 * nz);
	} else if (tag == 15) {
		// grass: pitches and lawns, mown in stripes, going to seed
		c = vec3(0.3, 0.5, 0.22) * (0.92 + 0.1 * step(0.5, fract(p.x / 6.0)));
		c = mix(c, vec3(0.45, 0.48, 0.26), smoothstep(0.55, 0.8, vnoise(p.xz * 0.15)) * 0.5);
	} else if (tag == 16) {
		// forested hills: canopy, with bare rock on the steep ground
		c = mix(vec3(0.16, 0.28, 0.12), vec3(0.24, 0.34, 0.16), fbm(p.xz * 0.01));
		c = mix(vec3(0.42, 0.42, 0.38), c, smoothstep(0.55, 0.8, n.y));
	} else if (tag == 17) {
		// tents and tarps
		c = pick4(oh, vec3(0.62, 0.58, 0.46), vec3(0.36, 0.4, 0.28), vec3(0.24, 0.38, 0.6), vec3(0.75, 0.74, 0.7));
	} else if (tag == 18) {
		// safety yellow
		c = vec3(0.86, 0.68, 0.14);
	} else if (tag == 19) {
		// dirt, berms and pits
		c = vec3(0.45, 0.38, 0.3) * (0.9 + 0.15 * nz);
	} else if (tag == 20) {
		// stadium seating: blocks of club colours
		float blk = hash12(floor(vec2(atan(p.z, p.x) * 8.0, p.y / 4.0)));
		c = pick4(blk, vec3(0.6, 0.1, 0.12), vec3(0.12, 0.22, 0.5), vec3(0.85, 0.85, 0.85), vec3(0.6, 0.1, 0.12));
	} else if (tag == 21) {
		// stone: headstones, kerbs
		c = vec3(0.7, 0.7, 0.68);
	} else if (tag == 22) {
		// dark metal, cables, masts
		c = vec3(0.2, 0.21, 0.22);
	} else if (tag == 23) {
		// burnt out: charcoal and soot, every window a black hole, rust where steel shows
		c = mix(vec3(0.07, 0.065, 0.06), vec3(0.2, 0.18, 0.16), nz * 0.7);
		c = mix(c, vec3(0.3, 0.16, 0.08), smoothstep(0.7, 0.95, vnoise(vec2(u * 0.7, p.y * 0.2))) * 0.6);
		if (vc.a < 0.99 && window_at(p, n) > 0.5) {
			c = vec3(0.02);
		}
	} else if (tag == 24) {
		// solar panels: dark blue cells in a silver frame
		vec2 g = fract(p.xz / vec2(1.0, 1.7));
		c = mix(vec3(0.08, 0.12, 0.22), vec3(0.6, 0.62, 0.64), step(0.93, max(g.x, g.y)));
	} else if (tag == 25) {
		// shop awnings: striped canvas
		vec3 base = pick4(oh, vec3(0.62, 0.14, 0.12), vec3(0.16, 0.4, 0.22), vec3(0.16, 0.26, 0.5), vec3(0.6, 0.45, 0.12));
		c = mix(base, vec3(0.86, 0.84, 0.78), step(0.5, fract(u * 1.25)) * 0.8);
	} else {
		// untagged: concrete, darkened if it was cold
		c = vec3(0.55, 0.55, 0.53) * (0.85 + 0.2 * nz);
	}
	return c;
}

void fragment() {
	float h = vcol.r;
	float solar = vcol.g;
	// walls that faced the afternoon sun still radiate; roofs dump heat to the sky
	h += dot(wnrm, normalize(vec3(-0.5, 0.15, 0.7))) * 0.045 * solar;
	h -= max(wnrm.y, 0.0) * 0.03 * solar;
	h += (vnoise(wpos.xz * 0.5 + vec2(wpos.y * 0.7)) - 0.5) * 0.05 * vcol.b;
	float burnt = scorch_at(wpos.xz);
	bool facade = vcol.a < 0.99 && abs(wnrm.y) < 0.5;
	h += infest * (0.2 + 0.05 * sin(sim_time * 1.3 + wpos.y * 0.2));
	if (facade) {
		// occupied rooms hold heat behind the glass; fewer of them as the power goes
		vec2 g = vec2(facade_u(wpos, wnrm) / 3.2, wpos.y / 3.4);
		float win = window_at(wpos, wnrm);
		float lit = step(0.6 + (1.0 - grid_power) * 0.25, hash12(floor(g) + vec2(floor(wpos.x * 0.02), floor(wpos.z * 0.02))));
		h += win * (0.03 + lit * 0.1) * (1.0 - vcol.a) * (1.0 - burnt);
	}
	float dist = length(VERTEX);
	if (color_mode > 0.5) {
		if (vcol.r > 1.1) {
			vec3 g;
			if (vcol.g > 0.6) {
				// an electric lamp: warm white, steady
				g = srgb_lin(blackbody(3300.0)) * (1.2 + night * 1.5);
			} else if (vcol.g > 0.35) {
				// a red obstruction beacon, blinking
				g = vec3(1.0, 0.05, 0.03) * 2.0 * step(0.5, fract(sim_time * 0.8 + hash12(wpos.xz)));
			} else {
				// fire: incandescent, at the colour of its temperature, flickering
				float fl = 0.8 + 0.4 * vnoise(vec2(sim_time * 6.0, wpos.x * 0.7 + wpos.z * 0.3));
				g = glow_rgb(vcol.r * fl) * (1.0 + night);
			}
			ALBEDO = mix(g, srgb_lin(sky_col), tv_haze(dist) * 0.6);
		} else {
			vec3 alb = albedo(int(vtag + 0.5), wpos, wnrm, vcol, burnt);
			// burnt by the fighting: soot climbing the walls from the ground and the windows
			if (burnt > 0.01) {
				float soot = 0.65 + 0.35 * smoothstep(0.3, 0.8, vnoise(vec2(facade_u(wpos, wnrm) * 0.8, wpos.y * 0.15)));
				alb = mix(alb, vec3(0.06, 0.055, 0.05), burnt * soot * 0.85);
			}
			ALBEDO = tv_light_at(alb, wnrm, dist, wpos);
			if (night > 0.05 && facade) {
				// lit rooms after dark, fewer as the grid fails; a few candles where it has
				vec2 g2 = vec2(facade_u(wpos, wnrm) / 3.2, wpos.y / 3.4);
				vec2 cell = floor(g2) + vec2(floor(wpos.x * 0.02), floor(wpos.z * 0.02));
				float win = window_at(wpos, wnrm) * (1.0 - burnt);
				float lit2 = step(0.55 + (1.0 - grid_power) * 0.42, hash12(cell));
				float candle = step(0.975, hash12(cell + 41.0)) * (1.0 - lit2) * (0.75 + 0.25 * sin(sim_time * 9.0 + hash12(cell) * 50.0));
				ALBEDO += srgb_lin(blackbody(2900.0)) * win * lit2 * night * 0.55;
				ALBEDO += srgb_lin(blackbody(1850.0)) * win * candle * night * 0.35;
			}
			if (infest > 0.0 && facade) {
				vec2 cell3 = floor(vec2(facade_u(wpos, wnrm) / 3.2, wpos.y / 3.4));
				float fire = step(0.7, hash12(cell3 + 7.0)) * window_at(wpos, wnrm);
				ALBEDO += glow_rgb(1.15 + 0.25 * vnoise(vec2(sim_time * 4.0, cell3.x + cell3.y * 3.0))) * fire * infest * 0.8;
			}
		}
	} else {
		ALBEDO = heat_out(haze(h, dist));
	}
}
