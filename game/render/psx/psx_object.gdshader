shader_type spatial;
// PSX-style surface: per-vertex (Gouraud) lighting, nearest-filtered texture
// and vertices snapped to the (low) internal pixel grid, which gives the
// slight wobble of PS1 geometry. Built from a StandardMaterial3D by PsxLook.

render_mode vertex_lighting, diffuse_lambert, specular_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform bool has_texture = false;
uniform bool use_vertex_color = false;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
// Internal pixels per snap step; higher snaps coarser.
uniform float snap_pixels = 1.0;

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec2 grid = VIEWPORT_SIZE * 0.5 / snap_pixels;
	clip.xy = round(clip.xy / clip.w * grid) / grid * clip.w;
	POSITION = clip;
}

void fragment() {
	vec4 c = albedo;
	if (has_texture) {
		c *= texture(albedo_texture, UV);
	}
	if (use_vertex_color) {
		c *= COLOR;
	}
	ALBEDO = c.rgb;
}
