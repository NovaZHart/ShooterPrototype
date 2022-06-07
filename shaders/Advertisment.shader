shader_type spatial;
render_mode unshaded;

uniform sampler2D advertisment;

void fragment() {
	ALBEDO=texture(advertisment,UV).rgb;
	//ALBEDO=vec3(1,0,1);
}