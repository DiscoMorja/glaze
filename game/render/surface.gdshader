shader_type spatial;
// Ground surfaces drawn on a mesh that hugs the floor. The shape comes from
// two masks with one texel per column (mask: R water, G oil, B ice; mask2:
// R vines, G poison; A how full), sampled with bilinear filtering and cut at a
// threshold: puddles
// get rounded corners and merge smoothly across cells instead of showing the
// square grid. A little noise on the threshold keeps the outline organic.

render_mode blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D mask : filter_linear, repeat_disable;
uniform sampler2D mask2 : filter_linear, repeat_disable;
// Level size in cells (x, z): the mask covers it one texel per column.
uniform vec2 grid_size = vec2(64.0, 64.0);
// How much the outline wanders (0 = smooth rounded cells).
uniform float edge_noise = 0.2;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 xz = world_pos.xz;
	vec4 m = texture(mask, xz / grid_size);
	vec4 m2 = texture(mask2, xz / grid_size);
	float edge = 0.5 + (noise(xz * 1.6) - 0.5) * edge_noise;
	vec3 cover = smoothstep(vec3(edge - 0.05), vec3(edge + 0.05), m.rgb);
	vec2 cover2 = smoothstep(vec2(edge - 0.05), vec2(edge + 0.05), m2.rg);
	float total = max(max(cover.r, max(cover.g, cover.b)), max(cover2.r, cover2.g));
	if (total < 0.01) {
		discard;
	}
	float sum = max(cover.r + cover.g + cover.b + cover2.r + cover2.g, 0.0001);
	vec3 weight = cover / sum;
	vec2 weight2 = cover2 / sum;

	// Water: clear blue with drifting ripples and pale foam at the edge.
	float ripple = noise(xz * 3.0 + TIME * 0.35) + noise(xz * 5.3 - TIME * 0.27);
	float foam = 1.0 - smoothstep(edge, edge + 0.18, m.r);
	vec3 water = vec3(0.06, 0.36, 0.86) + 0.15 * smoothstep(1.05, 1.45, ripple) + foam * vec3(0.4, 0.45, 0.45);
	// Oil: dark amber, glossy, with a rainbow sheen and a lighter rim so it
	// doesn't read as a shadow.
	float hue = noise(xz * 1.3 + TIME * 0.04);
	vec3 sheen = 0.5 + 0.5 * cos(6.2831 * (hue + vec3(0.0, 0.33, 0.67)));
	float oil_rim = 1.0 - smoothstep(edge, edge + 0.2, m.g);
	vec3 oil = vec3(0.26, 0.15, 0.05) + sheen * 0.14 * smoothstep(0.35, 0.75, hue) + oil_rim * vec3(0.2, 0.13, 0.05);
	// Ice: pale blue-white with dark crack lines.
	float crack = 1.0 - smoothstep(0.0, 0.035, abs(noise(xz * 2.2) - 0.5));
	vec3 ice = vec3(0.78, 0.9, 0.98) - crack * 0.3;
	// Vines: a tangle of dark and light leafy greens.
	float leaves = noise(xz * 6.0) + 0.5 * noise(xz * 13.0);
	vec3 vines = mix(vec3(0.12, 0.3, 0.08), vec3(0.35, 0.6, 0.18), smoothstep(0.6, 1.2, leaves));
	// Poison: sickly yellow-green water with slow bubbles.
	float bubble = noise(xz * 4.0 + TIME * 0.2);
	vec3 poison = vec3(0.35, 0.5, 0.08) + 0.2 * smoothstep(0.7, 0.9, bubble) * vec3(0.8, 0.9, 0.3);

	ALBEDO = water * weight.r + oil * weight.g + ice * weight.b + vines * weight2.r + poison * weight2.g;
	// Mostly diffuse: glossy settings reflect the sky and wash colours out.
	ROUGHNESS = 0.25 * weight.r + 0.3 * weight.g + 0.5 * weight.b + 0.9 * weight2.r + 0.3 * weight2.g;
	SPECULAR = 0.35;
	// A little self-light keeps the colours readable in shade.
	EMISSION = ALBEDO * (0.18 * weight.r + 0.08 * weight.g + 0.1 * weight.b + 0.05 * weight2.r + 0.2 * weight2.g);
	// Thin water films are more see-through; oil, ice and vines stay opaque.
	float opacity = mix(0.6, 0.88, m.a) * weight.r + 1.0 * weight.g + 0.95 * weight.b + 1.0 * weight2.r + mix(0.7, 0.9, m2.a) * weight2.g;
	ALPHA = total * opacity;
}
