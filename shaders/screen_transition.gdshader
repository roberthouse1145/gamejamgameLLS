shader_type canvas_item;

// 转场 uber-shader — 支持多种转场效果
// progress: 0.0 = 完全透明（显示画面），1.0 = 完全遮挡（显示 fade_color）
// transition_type: 0=fade, 1=dissolve, 2=wipe_left, 3=wipe_right, 4=wipe_up, 5=wipe_down

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 fade_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform int transition_type : hint_range(0, 5) = 0;
uniform float smoothness : hint_range(0.0, 0.5) = 0.05;

// 简单伪随机 hash（用于 dissolve）
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float alpha = 0.0;

	// 将 progress 扩展到 [-smoothness, 1+smoothness] 范围
	// 确保 progress=0 时 alpha 恒为 0，progress=1 时 alpha 恒为 1
	float p = progress * (1.0 + smoothness * 2.0) - smoothness;

	if (transition_type == 0) {
		// Fade — 简单透明度渐变
		alpha = progress;
	} else if (transition_type == 1) {
		// Dissolve — 噪声溶解
		float noise = hash(UV * 500.0);
		alpha = smoothstep(noise - smoothness, noise + smoothness, p);
	} else if (transition_type == 2) {
		// Wipe Left — 从右向左擦除
		alpha = smoothstep(UV.x - smoothness, UV.x + smoothness, p);
	} else if (transition_type == 3) {
		// Wipe Right — 从左向右擦除
		alpha = smoothstep((1.0 - UV.x) - smoothness, (1.0 - UV.x) + smoothness, p);
	} else if (transition_type == 4) {
		// Wipe Up — 从下向上擦除
		alpha = smoothstep(UV.y - smoothness, UV.y + smoothness, p);
	} else if (transition_type == 5) {
		// Wipe Down — 从上向下擦除
		alpha = smoothstep((1.0 - UV.y) - smoothness, (1.0 - UV.y) + smoothness, p);
	}

	COLOR = vec4(fade_color.rgb, alpha * fade_color.a);
}
