shader_type spatial;
// Ground surfaces (water, oil, ice) drawn on a mesh that hugs the floor. The
// shape comes from a mask with one texel per column (R water, G oil, B ice,
// A how full), sampled with bilinear filtering and cut at a threshold: puddles
// get rounded corners and merge smoothly across cells instead of showing the
// square grid. A little noise on the threshold keeps the outline organic.

render_mode blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D mask : filter_linear, repeat_disable;
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
	float edge = 0.5 + (noise(xz * 1.6) - 0.5) * edge_noise;
	vec3 cover = smoothstep(vec3(edge - 0.05), vec3(edge + 0.05), m.rgb);
	float total = max(cover.r, max(cover.g, cover.b));
	if (total < 0.01) {
		discard;
	}
	vec3 weight = cover / max(cover.r + cover.g + cover.b, 0.0001);

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

	ALBEDO = water * weight.r + oil * weight.g + ice * weight.b;
	// Mostly diffuse: glossy settings reflect the sky and wash colours out.
	ROUGHNESS = 0.25 * weight.r + 0.3 * weight.g + 0.5 * weight.b;
	SPECULAR = 0.35;
	// A little self-light keeps the colours readable in shade.
	EMISSION = ALBEDO * (0.18 * weight.r + 0.08 * weight.g + 0.1 * weight.b);
	// Thin water films are more see-through; oil and ice stay opaque.
	float opacity = mix(0.6, 0.88, m.a) * weight.r + 1.0 * weight.g + 0.95 * weight.b;
	ALPHA = total * opacity;
}
