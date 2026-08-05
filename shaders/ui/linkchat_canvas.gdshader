shader_type canvas_item;
render_mode unshaded;

uniform vec4 base_color : source_color = vec4(0.985, 0.991, 1.0, 1.0);
uniform vec4 grid_color : source_color = vec4(0.47, 0.58, 0.72, 0.085);


float box_mask(vec2 point, vec2 half_size, float softness) {
	float distance = max(abs(point).x - half_size.x, abs(point).y - half_size.y);
	return 1.0 - smoothstep(0.0, softness, distance);
}


vec2 rotate_point(vec2 point, float angle) {
	float sine = sin(angle);
	float cosine = cos(angle);
	return mat2(vec2(cosine, -sine), vec2(sine, cosine)) * point;
}


void fragment() {
	vec2 grid_position = fract(UV * vec2(18.0, 12.0));
	float grid = max(
		1.0 - smoothstep(0.0, 0.025, min(grid_position.x, 1.0 - grid_position.x)),
		1.0 - smoothstep(0.0, 0.025, min(grid_position.y, 1.0 - grid_position.y))
	);
	vec4 color = mix(base_color, grid_color, grid);

	float top_lilac = box_mask(rotate_point(UV - vec2(0.91, 0.09), -0.58), vec2(0.24, 0.12), 0.012);
	float top_mint = box_mask(rotate_point(UV - vec2(0.78, 0.02), 0.42), vec2(0.14, 0.055), 0.01);
	float bottom_lilac = box_mask(rotate_point(UV - vec2(0.04, 0.98), 0.26), vec2(0.22, 0.12), 0.012);
	float bottom_cyan = box_mask(rotate_point(UV - vec2(0.0, 0.93), -0.46), vec2(0.12, 0.09), 0.01);

	color = mix(color, vec4(0.74, 0.78, 1.0, 1.0), top_lilac * 0.22);
	color = mix(color, vec4(0.68, 0.95, 0.84, 1.0), top_mint * 0.22);
	color = mix(color, vec4(0.74, 0.79, 1.0, 1.0), bottom_lilac * 0.18);
	color = mix(color, vec4(0.55, 0.91, 0.98, 1.0), bottom_cyan * 0.2);
	COLOR = color;
}
