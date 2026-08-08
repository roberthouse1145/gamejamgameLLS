shader_type canvas_item;
// 直播画面统一调色层：背景与皮套一起过同一道轻微色调/对比/暗角，
// 模拟同一路直播采集画面的质感。

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform vec3 tint : source_color = vec3(0.84, 0.89, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.45;
uniform float contrast : hint_range(0.8, 1.2) = 1.04;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.18;

void fragment() {
	vec3 color = texture(screen_texture, SCREEN_UV).rgb;
	color = mix(color, color * tint, tint_strength);
	color = (color - 0.5) * contrast + 0.5;
	float falloff = smoothstep(0.85, 0.35, distance(SCREEN_UV, vec2(0.5)));
	color *= mix(1.0 - vignette_strength, 1.0, falloff);
	COLOR = vec4(color, 1.0);
}
