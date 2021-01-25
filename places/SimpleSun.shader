shader_type spatial;
render_mode unshaded;

uniform sampler2D precalculated;
uniform vec3 color_scaling=vec3(1.2,0.9,0.6);
uniform vec3 color_addition=vec3(0.5,0.4,0.2);
uniform int color_scheme=2;

float interp_order5_scalar(float t) {
	// fifth-order interpolant for improved perlin noise
	return t*t*t * (t * (t*6.0-15.0) + 10.0);
}

void fragment() {
	float w = texture(precalculated,UV).x;
	if(color_scheme==1)
		w=interp_order5_scalar(4.0*w)*2.0;
	else
		w*=w;
	ALBEDO=w*color_scaling+color_addition;
	EMISSION=ALBEDO;
}