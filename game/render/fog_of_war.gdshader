shader_type spatial;
// Fog of war as a screen pass: a full-screen quad in front of the camera reads
// the depth buffer, rebuilds each pixel's world position and darkens it:
// black where the party has never been, dimmed where it has been but nobody
// sees now, clear within sight of a party member.
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
// One texel per tile: 1 = explored.
uniform sampler2D explored : filter_linear, repeat_disable;
// World size the explored texture covers (tiles * tile size), metres.
uniform vec2 world_size = vec2(64.0);
// Party members' world positions (xz) and how many there are.
uniform vec2 seers[8];
uniform int seer_count = 0;
uniform float sight = 15.0;
uniform float edge = 4.0;
uniform float remembered = 0.55;
uniform vec3 fog_color : source_color = vec3(0.02, 0.02, 0.03);

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).x;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	vec2 uv = world.xz / world_size;
	float seen = 0.0;
	if (uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0) {
		seen = texture(explored, uv).r;
	}
	float near = 0.0;
	for (int i = 0; i < seer_count; i++) {
		float d = distance(world.xz, seers[i]);
		near = max(near, 1.0 - smoothstep(sight - edge, sight, d));
	}
	float dark = mix(1.0, remembered, smoothstep(0.0, 1.0, seen));
	ALBEDO = fog_color;
	ALPHA = dark * (1.0 - near * seen);
}
