shader_type canvas_item;

// 背景转场 shader — 新背景从透明逐渐覆盖旧背景
// progress: 0.0 = 完全透明（显示旧背景），1.0 = 完全显示新背景
// transition_type: 0=fade, 1=dissolve, 2=wipe_left, 3=wipe_right, 4=wipe_up, 5=wipe_down

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform int transition_type : hint_range(0, 5) = 0;
uniform float smoothness : hint_range(0.0, 0.5) = 0.05;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	float alpha = 0.0;

	float p = progress * (1.0 + smoothness * 2.0) - smoothness;

	if (transition_type == 0) {
		alpha = progress;
	} else if (transition_type == 1) {
		float noise = hash(UV * 500.0);
		alpha = smoothstep(noise - smoothness, noise + smoothness, p);
	} else if (transition_type == 2) {
		alpha = smoothstep(UV.x - smoothness, UV.x + smoothness, p);
	} else if (transition_type == 3) {
		alpha = smoothstep((1.0 - UV.x) - smoothness, (1.0 - UV.x) + smoothness, p);
	} else if (transition_type == 4) {
		alpha = smoothstep(UV.y - smoothness, UV.y + smoothness, p);
	} else if (transition_type == 5) {
		alpha = smoothstep((1.0 - UV.y) - smoothness, (1.0 - UV.y) + smoothness, p);
	}

	COLOR = vec4(tex_color.rgb, tex_color.a * alpha);
}
