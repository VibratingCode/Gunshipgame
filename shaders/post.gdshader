shader_type canvas_item;

// The sensor's post-process.
// IR imager: optical softness, blooming around hot sources, automatic gain control that pumps
// down after a big flash and claws its way back over seconds, sensor noise, fixed-pattern column
// and row non-uniformity, the faint seams between the detector's readout channels, a few dead and
// stuck pixels, image lag smearing anything that moves across the array, and heat shimmer rising
// off fires.
// Daylight TV camera: interlaced fields that comb when the turret slews, vertical CCD smear under
// anything blinding, a touch of chroma fringing, and grain that rises as the light goes.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float black_hot = 0.0;
// 1 = the turret's daylight colour TV camera instead of the IR imager
global uniform float color_mode;
// 0 white-hot, 1 black-hot, 2 ironbow false colour, 3 disco
uniform int palette = 0;

vec3 ironbow(float h) {
	vec3 c0 = vec3(0.0, 0.0, 0.0);
	vec3 c1 = vec3(0.13, 0.0, 0.42);
	vec3 c2 = vec3(0.6, 0.0, 0.6);
	vec3 c3 = vec3(0.92, 0.25, 0.1);
	vec3 c4 = vec3(1.0, 0.7, 0.0);
	vec3 c5 = vec3(1.0, 1.0, 0.85);
	if (h < 0.2) return mix(c0, c1, h / 0.2);
	if (h < 0.42) return mix(c1, c2, (h - 0.2) / 0.22);
	if (h < 0.62) return mix(c2, c3, (h - 0.42) / 0.2);
	if (h < 0.82) return mix(c3, c4, (h - 0.62) / 0.2);
	return mix(c4, c5, (h - 0.82) / 0.18);
}
uniform float flash = 0.0;
uniform float whiteout = 0.0;
uniform float agc = 0.0;
uniform float noise_amt = 0.045;
uniform float t = 0.0;
uniform float blur = 0.0;
uniform float gain = 1.4;
// weather on the lens: 0 none, 1 rain, 2 snow, 3 blowing dust
uniform int precip = 0;
uniform float precip_amt = 0.0;
// how far the picture moved over the last frame, in UV: the array's lag trails along it
uniform vec2 smear = vec2(0.0);
// heat shimmer sources on screen: (u, v, radius in screen heights, strength)
uniform vec4 haze_src[12];
uniform int haze_n = 0;
// 0..1: how much of the camera's own character to show (a pilot's eyes have no readout seams)
uniform float sensor_k = 1.0;

float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h12(i), h12(i + vec2(1.0, 0.0)), f.x), mix(h12(i + vec2(0.0, 1.0)), h12(i + vec2(1.0, 1.0)), f.x), f.y);
}

float precip_fx(vec2 uv) {
	if (precip == 1) {
		// rain: thin slanted streaks falling past the turret
		vec2 q = vec2(uv.x * 220.0 + uv.y * 30.0, uv.y);
		float lane = floor(q.x);
		float r = h12(vec2(lane, 3.7));
		float y = fract(uv.y * (2.0 + r) - t * (1.6 + r * 1.2) + r * 7.0);
		float s = smoothstep(0.0, 0.015, y) * (1.0 - smoothstep(0.015, 0.09, y));
		float thin = 1.0 - abs(fract(q.x) - 0.5) * 2.0;
		return s * smoothstep(0.55, 1.0, thin) * step(0.55, r) * precip_amt;
	} else if (precip == 2) {
		// snow: soft flakes drifting down and sideways
		vec2 g = uv * vec2(70.0, 40.0) + vec2(sin(t * 0.7 + uv.y * 6.0) * 0.6, -t * 1.6);
		vec2 cell = floor(g);
		vec2 f = fract(g) - 0.5;
		float r = h12(cell);
		vec2 off = (vec2(h12(cell + 3.1), h12(cell + 7.7)) - 0.5) * 0.6;
		return smoothstep(0.12, 0.0, length(f - off)) * step(0.55, r) * precip_amt;
	} else if (precip == 3) {
		// blowing dust: banded streaks racing across
		float n1 = h12(floor(vec2(uv.x * 40.0 - t * 30.0, uv.y * 200.0)));
		return smoothstep(0.85, 1.0, n1) * 0.6 * precip_amt;
	}
	return 0.0;
}

// Air rising off a fire bends the light: the picture wobbles above anything burning.
vec2 shimmer(vec2 uv, float aspect) {
	vec2 hz = vec2(0.0);
	for (int i = 0; i < 12; i++) {
		if (i >= haze_n) {
			break;
		}
		vec4 s = haze_src[i];
		vec2 d = uv - s.xy;
		d.x *= aspect;
		float r = max(s.z, 0.002);
		float up = -d.y / r;
		float side = d.x / r;
		float infl = exp(-side * side * 1.4) * smoothstep(-0.5, 0.25, up) * exp(-max(up, 0.0) * 0.45) * s.w;
		if (infl > 0.003) {
			vec2 q = vec2(uv.x * aspect * 70.0, uv.y * 55.0 + t * 2.4);
			hz += (vec2(vn(q), vn(q + vec2(7.3, 1.9))) - 0.5) * infl;
		}
	}
	return hz;
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	float aspect = px.y / px.x;
	vec2 uv = SCREEN_UV + shimmer(SCREEN_UV, aspect) * 0.007;
	vec2 cell = floor(SCREEN_UV / px);
	float n = h12(cell + fract(t * 61.7) * 917.0) - 0.5;
	// detector saturation after a nuclear flash: the image washes to full scale, then the scene
	// bleeds back through blooming streaks as the array recovers
	float streak = h12(vec2(floor(SCREEN_UV.y / px.y * 0.25), floor(t * 20.0)));
	vec2 dd = SCREEN_UV - 0.5;
	dd.x *= aspect;
	float vig = mix(0.5, 1.0, smoothstep(0.95, 0.35, length(dd)));
	vec3 col;
	if (color_mode > 0.5) {
		// interlaced fields: every other line is the field before, so motion combs it
		float field = mod(cell.y, 2.0);
		vec2 tuv = uv + smear * field * 0.5 * sensor_k + vec2((h12(vec2(floor(t * 60.0), field)) - 0.5) * px.x * 0.7 * sensor_k, 0.0);
		vec3 rgb = vec3(0.0);
		float ws = 0.0;
		for (int k = 0; k < 3; k++) {
			float f = float(k) / 2.0;
			float wk = exp(-f * 2.5);
			vec2 su = tuv + smear * f * 0.6;
			// a little chroma fringing: the colour channels don't quite line up
			rgb += vec3(textureLod(screen_tex, su + vec2(px.x * 0.8 * sensor_k, 0.0), blur).r,
				textureLod(screen_tex, su, blur).g,
				textureLod(screen_tex, su - vec2(px.x * 0.8 * sensor_k, 0.0), blur).b) * wk;
			ws += wk;
		}
		rgb /= ws;
		vec3 bl = textureLod(screen_tex, uv, 3.5).rgb;
		rgb = mix(rgb, bl, 0.06) + max(bl - 0.75, vec3(0.0)) * 0.5;
		// vertical CCD smear: a column bleeds under anything blinding (flares, fireballs, the sun on water)
		float sm = 0.0;
		for (int k = 0; k < 12; k++) {
			vec3 q = textureLod(screen_tex, vec2(uv.x, (float(k) + 0.5) / 12.0), 3.0).rgb;
			sm += max(max(q.r, max(q.g, q.b)) - 0.9, 0.0);
		}
		rgb += vec3(1.0, 0.97, 0.92) * sm * 0.12 * sensor_k;
		float luma = dot(rgb, vec3(0.299, 0.587, 0.114));
		rgb = mix(vec3(luma), rgb, 1.12);
		rgb = (rgb - 0.5) * 1.06 + 0.5 - agc * 0.35;
		rgb += vec3(n * noise_amt * 0.45);
		rgb += vec3(flash);
		rgb = mix(rgb, vec3(1.0), clamp(whiteout * (0.85 + 0.3 * streak), 0.0, 1.0));
		// the fields don't quite match in brightness either
		rgb *= 1.0 + (field - 0.5) * 0.014 * sensor_k;
		float scan_tv = 0.985 + 0.015 * sin(SCREEN_UV.y / px.y * 3.14159);
		col = clamp(rgb, 0.0, 1.0) * mix(0.7, 1.0, vig) * scan_tv;
	} else {
		// image lag: the array still holds a little of where everything was a moment ago
		float c = 0.0;
		float ws = 0.0;
		for (int k = 0; k < 5; k++) {
			float f = float(k) / 4.0;
			float wk = exp(-f * 2.2);
			c += textureLod(screen_tex, uv + smear * f, blur).r * wk;
			ws += wk;
		}
		c /= ws;
		float s1 = textureLod(screen_tex, uv, 1.0 + blur).r;
		float b2 = textureLod(screen_tex, uv, 3.0).r;
		float b4 = textureLod(screen_tex, uv, 5.0).r;
		float h = mix(c, s1, 0.2);
		h += (c - s1) * 0.35;
		h += max(b2 - 0.6, 0.0) * 0.55 + max(b4 - 0.5, 0.0) * 0.45;
		// automatic gain control: a big flash drags the gain down and flattens the picture, and
		// the AGC claws it back over the next few seconds
		h = (h - 0.30 - agc * 0.5) * gain * (1.0 - agc * 0.45) + 0.32;
		h += n * noise_amt;
		// fixed pattern: column and row non-uniformity, and the seams between readout channels
		h += (h12(vec2(cell.x, 7.0)) - 0.5) * 0.012 * sensor_k;
		h += (h12(vec2(3.0, cell.y)) - 0.5) * 0.005 * sensor_k;
		// (in whole pixels: 16 channels across, 8 down, a one-pixel seam at the edge of each)
		vec2 chan = max(floor(1.0 / px / vec2(16.0, 8.0)), vec2(2.0));
		float seam = step(chan.x - 1.0, mod(cell.x, chan.x)) * 0.02 + step(chan.y - 1.0, mod(cell.y, chan.y)) * 0.01;
		h -= seam * sensor_k;
		h += flash;
		h = mix(h, 1.0, clamp(whiteout * (0.85 + 0.3 * streak), 0.0, 1.0));
		// dead and stuck pixels, always in the same place on the array
		float dp = h12(cell * 0.913 + 17.0);
		if (dp > 0.99995) {
			h = mix(h, 1.0, sensor_k);
		} else if (dp < 0.00004) {
			h = mix(h, 0.0, sensor_k);
		}
		h = clamp(h, 0.0, 1.0);
		float scan = 0.965 + 0.035 * sin(SCREEN_UV.y / px.y * 3.14159);
		if (palette == 2) {
			col = ironbow(h) * vig * scan;
		} else if (palette == 3) {
			// DISCO: anything warm in a rolling rainbow, the cold world a purple dance floor, on the beat
			float hue = fract(h * 1.3 + t * 0.15 + (SCREEN_UV.x + SCREEN_UV.y) * 0.35);
			vec3 rgb = clamp(abs(mod(hue * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
			float warm = smoothstep(0.35, 0.8, h);
			col = mix(vec3(0.05, 0.0, 0.1) + vec3(0.25, 0.1, 0.35) * h, rgb * (0.4 + 0.8 * h), warm);
			col *= (0.9 + 0.1 * step(0.5, fract(t * 2.0))) * vig * scan;
		} else {
			float g = palette == 1 ? 1.0 - h : h;
			col = vec3(g * vig * scan);
		}
	}
	float pv = precip_fx(SCREEN_UV);
	if (precip == 3 && color_mode > 0.5) {
		col = mix(col, vec3(0.62, 0.5, 0.36), pv * 0.5);
	} else {
		col += vec3(pv * 0.2);
	}
	COLOR = vec4(col, 1.0);
}
