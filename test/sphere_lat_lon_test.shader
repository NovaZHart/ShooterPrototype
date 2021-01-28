shader_type spatial;
render_mode unshaded;
uniform sampler2D xyz;

float in_range(float x, float mn, float mx) {
	if(x>mn && x<mx)
		return 0.666;
	else if(x>=mx)
		return 1.0;
	else if(x<=mn)
		return 0.333;
	else
		return 0.0;
}

void fragment() {
	vec3 tex=texture(xyz,UV).xyz;
	//ALBEDO = vec3(in_range(tex.x,-1.0,1.0),in_range(tex.y,-1.0,1.0),in_range(tex.z,-1.0,1.0));
	ALBEDO = tex/2.0+0.5;
}