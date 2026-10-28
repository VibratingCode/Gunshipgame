shader_type canvas_item;

// Picture-in-picture weapon view: the munition's own seeker, graded like the main sensor.

uniform int palette = 0;
uniform float t = 0.0;

float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 ironbow(float h) {
	vec3 c0 = vec3(0.0);
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

void fragment() {
	float h = texture(TEXTURE, UV).r;
	h = (h - 0.30) * 1.5 + 0.32;
	h += (h12(floor(UV * 360.0) + fract(t * 53.1) * 311.0) - 0.5) * 0.08;
	h = clamp(h, 0.0, 1.0);
	vec3 col = palette == 2 ? ironbow(h) : vec3(palette == 1 ? 1.0 - h : h);
	float vig = smoothstep(0.75, 0.3, length(UV - 0.5));
	COLOR = vec4(col * mix(0.55, 1.0, vig), 1.0);
}
