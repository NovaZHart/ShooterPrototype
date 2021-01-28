shader_type spatial;

uniform sampler2D precalculated;
uniform vec3 color_scaling=vec3(0.870588,0.803922,0.533333);
uniform vec3 color_addition=vec3(0.239216,-0.223529,-0.176471);
uniform int color_scheme=1;

float interp_order5_scalar(float t) {
	// fifth-order interpolant for improved perlin noise
	return t*t*t * (t * (t*6.0-15.0) + 10.0);
}

void fragment() {
	float w = texture(precalculated,vec2(UV.x,UV.y/2.0+0.5)).x;

	vec4 normal = texture(precalculated,vec2(UV.x,UV.y/2.0));
	normal = vec4(normal.xyz*2.0-1.0,0.0);
	normal = WORLD_MATRIX*normal;
	NORMAL = (INV_CAMERA_MATRIX*normal).xyz;

	if(color_scheme==1)
		w=interp_order5_scalar(w);
	else
		w*=w;
	ALBEDO = w*color_scaling+color_addition;
	EMISSION=ALBEDO;
}