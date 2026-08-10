shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// 固定在镜头空间的两色插画光照。它不读取场景灯光，避免角色随直播间灯光变成 PBR 观感。
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec4 uv_transform = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 shadow_tint : source_color = vec4(0.82, 0.86, 0.94, 1.0);
uniform vec3 light_direction_view = vec3(-0.25, 0.45, 0.86);
uniform float shade_threshold : hint_range(0.0, 1.0) = 0.48;
uniform float shade_softness : hint_range(0.0, 0.5) = 0.06;
uniform float shade_strength : hint_range(0.0, 1.0) = 0.16;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec2 transformed_uv = UV * uv_transform.xy + uv_transform.zw;
	vec4 base = texture(albedo_texture, transformed_uv) * albedo_color;
	float normal_light = dot(normalize(NORMAL), normalize(light_direction_view)) * 0.5 + 0.5;
	float light_band = smoothstep(
		shade_threshold - shade_softness,
		shade_threshold + shade_softness,
		normal_light
	);
	vec3 shadow_color = base.rgb * shadow_tint.rgb;
	vec3 banded_color = mix(shadow_color, base.rgb, light_band);
	ALBEDO = mix(base.rgb, banded_color, shade_strength);
	ALPHA = base.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
}
