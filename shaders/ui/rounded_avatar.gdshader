shader_type canvas_item;

uniform float corner_radius : hint_range(0.0, 0.5) = 0.18;
uniform float outline_width : hint_range(0.0, 0.2) = 0.035;
uniform vec4 outline_color : source_color = vec4(0.04, 0.04, 0.05, 1.0);


float rounded_box_sdf(vec2 point, vec2 half_size, float radius) {
	vec2 distance_to_edge = abs(point) - half_size + vec2(radius);
	return min(max(distance_to_edge.x, distance_to_edge.y), 0.0)
		+ length(max(distance_to_edge, vec2(0.0))) - radius;
}


void fragment() {
	float radius = clamp(corner_radius, 0.0, 0.5);
	float distance = rounded_box_sdf(UV - vec2(0.5), vec2(0.5), radius);
	float antialias_width = max(fwidth(distance) * 1.5, 0.0005);
	float outer_mask = 1.0 - smoothstep(-antialias_width, antialias_width, distance);
	float inner_mask = 1.0 - smoothstep(
		-outline_width - antialias_width,
		-outline_width + antialias_width,
		distance
	);
	vec4 source = texture(TEXTURE, UV);
	vec4 result = mix(outline_color, source, inner_mask);
	result.a *= outer_mask;
	COLOR = result;
}
