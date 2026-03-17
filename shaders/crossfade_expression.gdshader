shader_type canvas_item;

uniform sampler2D old_texture : hint_default_white;
uniform float progress : hint_range(0.0, 1.0) = 0.0;

vec3 srgb_to_linear(vec3 color) {
	return pow(color, vec3(2.2));
}


vec3 linear_to_srgb(vec3 color) {
	return pow(max(color, vec3(0.0)), vec3(1.0 / 2.2));
}


void fragment() {
	vec4 old_col = texture(old_texture, UV);
	vec4 new_col = texture(TEXTURE, UV);
	vec3 old_linear = srgb_to_linear(old_col.rgb);
	vec3 new_linear = srgb_to_linear(new_col.rgb);
	vec3 old_premul = old_linear * old_col.a;
	vec3 new_premul = new_linear * new_col.a;

	float mixed_alpha = mix(old_col.a, new_col.a, progress);
	vec3 mixed_premul = mix(old_premul, new_premul, progress);
	vec3 mixed_linear = mixed_premul / max(mixed_alpha, 0.0001);
	vec3 mixed_srgb = linear_to_srgb(mixed_linear);

	COLOR = vec4(mixed_srgb, mixed_alpha) * COLOR;
}
