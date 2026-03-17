shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform float effect_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.0;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform float exposure : hint_range(0.2, 2.0) = 1.0;
uniform vec4 gradient_top_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 gradient_bottom_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float gradient_strength : hint_range(0.0, 1.0) = 0.0;

vec3 srgb_to_linear(vec3 color) {
	return pow(max(color, vec3(0.0)), vec3(2.2));
}

vec3 linear_to_srgb(vec3 color) {
	return pow(max(color, vec3(0.0)), vec3(1.0 / 2.2));
}

vec3 apply_saturation(vec3 color, float amount) {
	float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
	return mix(vec3(luminance), color, amount);
}

void fragment() {
	vec4 screen_col = texture(screen_texture, SCREEN_UV);
	vec3 base_linear = srgb_to_linear(screen_col.rgb);
	vec3 graded = base_linear * exposure;

	graded = apply_saturation(graded, saturation);

	vec3 tint_linear = srgb_to_linear(tint_color.rgb);
	graded *= mix(vec3(1.0), tint_linear, tint_strength);

	vec3 gradient_linear = srgb_to_linear(mix(gradient_top_color.rgb, gradient_bottom_color.rgb, SCREEN_UV.y));
	graded = mix(graded, graded * gradient_linear, gradient_strength);

	vec3 final_linear = mix(base_linear, graded, effect_strength);
	COLOR = vec4(linear_to_srgb(final_linear), screen_col.a);
}
