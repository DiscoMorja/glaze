shader_type spatial;
// Retro surface: per-vertex (Gouraud) lighting, optional nearest-filtered
// texture and optional vertex snapping to the internal pixel grid (the slight
// wobble of PS1 geometry). Built from a StandardMaterial3D by RetroLook.

render_mode vertex_lighting, diffuse_lambert, specular_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D albedo_texture_nearest : source_color, filter_nearest_mipmap, repeat_enable;
uniform bool has_texture = false;
uniform bool nearest = false;
uniform bool use_vertex_color = false;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
// Internal pixels per snap step; 0 turns snapping off.
uniform float snap_pixels = 0.0;

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
	// Writing POSITION replaces Godot's own projection, so always write it.
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (snap_pixels > 0.0) {
		vec2 grid = VIEWPORT_SIZE * 0.5 / snap_pixels;
		clip.xy = round(clip.xy / clip.w * grid) / grid * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	vec4 c = albedo;
	if (has_texture) {
		c *= nearest ? texture(albedo_texture_nearest, UV) : texture(albedo_texture, UV);
	}
	if (use_vertex_color) {
		c *= COLOR;
	}
	ALBEDO = c.rgb;
}
