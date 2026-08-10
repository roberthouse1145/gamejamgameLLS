shader_type canvas_item;
// 皮套后处理描边：基于透明 viewport 的 alpha 剪影向外勾线。
// 只描外轮廓，面部等内部线条由模型贴图自带，不受影响。

uniform vec4 outline_color : source_color = vec4(0.045, 0.055, 0.085, 1.0);
uniform float outline_width_px : hint_range(0.0, 24.0) = 3.0;

const int DIRECTIONS = 12;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float silhouette = 0.0;
	for (int i = 0; i < DIRECTIONS; i++) {
		float angle = TAU * float(i) / float(DIRECTIONS);
		vec2 offset = vec2(cos(angle), sin(angle)) * outline_width_px * TEXTURE_PIXEL_SIZE;
		silhouette = max(silhouette, texture(TEXTURE, UV + offset).a);
		silhouette = max(silhouette, texture(TEXTURE, UV + offset * 0.5).a);
	}
	vec3 rgb = mix(outline_color.rgb, tex.rgb, tex.a);
	float alpha = max(tex.a, silhouette * outline_color.a);
	COLOR = vec4(rgb, alpha);
}
