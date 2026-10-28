shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

#include "res://shaders/thermal.gdshaderinc"

// Directed-energy beams: the air along the path is heated white-hot and shimmers.
// The node is a unit cube stretched from the source (+Z face) to the target (-Z face).
// fade_source > 0 fades the beam in over that fraction of its length from the source end,
// so a beam leaving our own aircraft doesn't smear across the lens.
uniform float heat = 1.6;
uniform float fade_source = 0.0;

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	float core = 1.0 - smoothstep(0.0, 0.5, length(lpos.xy) * 1.4);
	float shimmer = 0.8 + 0.2 * sin(sim_time * 90.0 + lpos.z * 40.0);
	float along = 0.5 - lpos.z;
	float fade = fade_source > 0.0 ? smoothstep(0.0, fade_source, along) : 1.0;
	// the IR camera sees heated air; the TV camera sees the plasma channel glowing at its
	// temperature (lightning hottest of all, blue-white)
	ALBEDO = color_mode > 0.5 ? glow_rgb(heat * shimmer) * 0.8 : heat_out(heat * shimmer);
	ALPHA = clamp(core, 0.15, 1.0) * fade;
}
