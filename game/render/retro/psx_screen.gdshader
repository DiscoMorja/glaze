shader_type canvas_item;
// PSX-style screen pass: chunky pixels (nearest upscale of a low internal
// resolution) and reduced colour depth with 4x4 ordered dithering.

uniform sampler2D screen : hint_screen_texture, filter_nearest;
// Screen pixels per PSX pixel.
uniform float pixel_size = 3.0;
// Levels per colour channel (the PS1 drew 15-bit colour: 32 levels).
uniform float color_levels = 32.0;
uniform float dither_strength = 1.0;

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

void fragment() {
	vec2 cell = floor(SCREEN_UV / SCREEN_PIXEL_SIZE / pixel_size);
	vec2 uv = (cell + 0.5) * pixel_size * SCREEN_PIXEL_SIZE;
	vec3 c = textureLod(screen, uv, 0.0).rgb;
	int i = int(mod(cell.y, 4.0)) * 4 + int(mod(cell.x, 4.0));
	float threshold = (BAYER[i] + 0.5) / 16.0 - 0.5;
	float steps = color_levels - 1.0;
	c = floor(c * steps + 0.5 + threshold * dither_strength) / steps;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
