shader_type spatial;
render_mode unshaded, shadows_disabled;

uniform vec4 class_color : source_color;
uniform float brightness = 1.0;
varying vec3 cube_position;

void vertex() {
	cube_position = VERTEX;
}

void fragment() {
	vec3 face = abs(cross(dFdx(cube_position), dFdy(cube_position)));
	vec2 grid_uv = cube_position.xy;
	if (face.x > max(face.y, face.z)) {
		grid_uv = cube_position.zy;
	} else if (face.y > face.z) {
		grid_uv = cube_position.xz;
	}
	vec2 cell = (grid_uv + vec2(0.5)) * 8.0;
	vec2 position_in_cell = fract(cell);
	vec2 edge = min(position_in_cell, 1.0 - position_in_cell);
	vec2 line_width = max(fwidth(cell), vec2(0.025));
	vec2 interior = smoothstep(vec2(0.035), 0.035 + line_width, edge);
	float checker = mod(floor(cell.x) + floor(cell.y), 2.0);
	float tone = mix(0.37, mix(0.72, 0.94, checker), min(interior.x, interior.y));
	ALBEDO = class_color.rgb * brightness * tone;
}
