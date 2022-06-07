shader_type spatial;
render_mode unshaded;
uniform sampler2D xyz;

void fragment() {
	vec3 tex=texture(xyz,UV).xyz;
	ALBEDO = tex/2.0+0.5;
}