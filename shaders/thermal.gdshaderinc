// Shared helpers for the thermal (IR) look.
// Every surface outputs a scalar "heat" in roughly 0..1 (above 1 = saturating hot).
// heat_out() pre-linearises it so the value that reaches the screen texture is ~heat,
// and the post-process shader decides white-hot / black-hot.

global uniform float sim_time;
global uniform float haze_heat;
global uniform float haze_dist;

vec3 heat_out(float h) {
	return vec3(pow(max(h, 0.0), 2.2));
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

// Atmospheric path loss: long slant ranges wash contrast toward the AO's haze level
// (dust in the desert, blowing snow on the ice).
float haze(float h, float dist) {
	return mix(h, haze_heat, clamp(dist / haze_dist, 0.0, 0.3));
}

// ---------------------------------------------------------------- daylight colour TV
// The turret carries a colour TV camera as well as the IR imager. With color_mode on, every
// surface shows its daylight colour instead of its heat: lit by the sun and the sky, and
// washed toward the horizon colour with distance. Albedos are given in sRGB.
global uniform float color_mode;
global uniform vec3 sun_dir;
global uniform vec3 sky_col;
global uniform float tv_fog;
// 0 city, 1 desert, 2 port, 3 river, 4 arctic, 5 forest highlands
global uniform float ao_style;
// time of day and weather (main.gd): direct sun colour x strength, sky/moon ambient, 0 day .. 1 night
global uniform vec3 sun_col;
global uniform vec3 amb_col;
global uniform float night;

vec3 srgb_lin(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(2.2));
}

float tv_haze(float dist) {
	return (1.0 - exp(-dist / max(tv_fog, 1.0))) * 0.92;
}

vec3 tv_light(vec3 c, vec3 n, float dist) {
	vec3 sd = normalize(sun_dir);
	float sun = max(dot(n, sd), 0.0);
	float skyl = 0.55 + 0.45 * n.y;
	vec3 lit = c * (sun_col * sun + amb_col * skyl);
	return srgb_lin(mix(lit, sky_col, tv_haze(dist)));
}

// something that gives off its own light in daylight (fires, lamps, tracers): unlit
vec3 tv_glow(vec3 c, float dist) {
	return srgb_lin(mix(c, sky_col, tv_haze(dist) * 0.6));
}

// The one call every surface makes: heat in IR, sunlit colour in TV.
vec3 sensor_out(float h, vec3 albedo, vec3 n, float dist) {
	if (color_mode > 0.5) {
		return tv_light(albedo, n, dist);
	}
	return heat_out(haze(h, dist));
}

vec3 world_normal(vec3 view_n, mat4 inv_view) {
	return normalize((inv_view * vec4(view_n, 0.0)).xyz);
}

// a fire, flash or tracer seen in daylight: from deep red through orange to white
vec3 flame_col(float h) {
	return mix(mix(vec3(0.55, 0.08, 0.02), vec3(1.0, 0.5, 0.1), clamp(h, 0.0, 1.0)), vec3(1.0, 0.95, 0.8), clamp(h - 1.0, 0.0, 1.0));
}

// ---------------------------------------------------------------- incandescence
// Anything that glows does so at the colour of its temperature. The heat scale maps onto real
// temperatures: ~1.0 is a dull-red 900 K, 1.5 an orange 1,800 K, 2.0 a yellow 2,900 K, 3.0 white
// 5,600 K, and beyond that blue-white (lightning).
float heat_kelvin(float h) {
	return 900.0 * pow(max(h, 0.3), 1.7);
}

// Blackbody chromaticity (Tanner Helland's fit), in sRGB, brightest channel 1.
vec3 blackbody(float kelvin) {
	float t = kelvin / 100.0;
	vec3 c;
	c.r = t <= 66.0 ? 1.0 : clamp(1.29293618606 * pow(t - 60.0, -0.1332047592), 0.0, 1.0);
	c.g = t <= 66.0 ? clamp(0.39008157876 * log(max(t, 1.0)) - 0.63184144378, 0.0, 1.0) : clamp(1.12989086089 * pow(t - 60.0, -0.0755148492), 0.0, 1.0);
	c.b = t >= 66.0 ? 1.0 : (t <= 19.0 ? 0.0 : clamp(0.54320678911 * log(t - 10.0) - 1.19625408914, 0.0, 1.0));
	return c;
}

// What the daylight camera sees of something glowing at heat h: the blackbody colour of its
// temperature, nothing at all below ~800 K, brightness climbing steeply as it gets hotter. Linear.
vec3 glow_rgb(float h) {
	float k = heat_kelvin(h);
	float vis = smoothstep(780.0, 1100.0, k);
	float lum = vis * (0.35 + 1.4 * (1.0 - exp(-pow(k / 2600.0, 3.0))));
	return srgb_lin(blackbody(k)) * lum;
}

// ---------------------------------------------------------------- the battlefield over time
// the refuge's power grid: 1 on day one, failing district by district as the days go by
global uniform float grid_power;
// up to two illumination flares hanging over the AO: xyz position, w brightness
global uniform vec4 flare_a;
global uniform vec4 flare_b;
// persistent battle damage over the AO (+-3400 m): r = scorched and burnt out
global uniform sampler2D scorch_map;

float scorch_at(vec2 xz) {
	vec2 uv = (xz + 3400.0) / 6800.0;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 0.0;
	}
	return textureLod(scorch_map, uv, 0.0).r;
}

// Magnesium illumination flares light the ground for the daylight camera (they're ~3,000 K).
vec3 flare_light(vec3 p, vec3 n) {
	vec3 sum = vec3(0.0);
	for (int i = 0; i < 2; i++) {
		vec4 f = i == 0 ? flare_a : flare_b;
		if (f.w > 0.0) {
			vec3 d = f.xyz - p;
			float l2 = dot(d, d);
			float lambert = max(dot(n, d * inversesqrt(max(l2, 1.0))), 0.0) * 0.7 + 0.3;
			sum += vec3(f.w * lambert / (1.0 + l2 / 120000.0));
		}
	}
	return sum * vec3(1.0, 0.86, 0.66);
}

// As tv_light(), plus flare light, for surfaces that know where they are.
vec3 tv_light_at(vec3 c, vec3 n, float dist, vec3 wp) {
	vec3 sd = normalize(sun_dir);
	float sun = max(dot(n, sd), 0.0);
	float skyl = 0.55 + 0.45 * n.y;
	vec3 lit = c * (sun_col * sun + amb_col * skyl + flare_light(wp, n));
	return srgb_lin(mix(lit, sky_col, tv_haze(dist)));
}

vec3 sensor_out_at(float h, vec3 albedo, vec3 n, float dist, vec3 wp) {
	if (color_mode > 0.5) {
		return tv_light_at(albedo, n, dist, wp);
	}
	return heat_out(haze(h, dist));
}
