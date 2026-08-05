shader_type canvas_item;
render_mode unshaded;

uniform vec4 grid_color : source_color = vec4(0.47, 0.58, 0.72, 0.24);
uniform vec2 grid_count = vec2(24.0, 14.0);
uniform float line_width : hint_range(0.005, 0.08) = 0.032;


void fragment() {
	vec2 grid_position = fract(UV * grid_count);
	float grid = max(
		1.0 - smoothstep(0.0, line_width, min(grid_position.x, 1.0 - grid_position.x)),
		1.0 - smoothstep(0.0, line_width, min(grid_position.y, 1.0 - grid_position.y))
	);
	float bottom_emphasis = mix(0.32, 1.0, smoothstep(0.08, 0.82, UV.y));
	COLOR = vec4(grid_color.rgb, grid_color.a * grid * bottom_emphasis);
}
