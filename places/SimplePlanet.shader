shader_type spatial;

uniform sampler2D precalculated;
uniform vec3 color_scaling=vec3(1.2,0.9,0.6);
uniform vec3 color_addition=vec3(0.5,0.4,0.2);
uniform int color_scheme=2;

float interp_order5_scalar(float t) {
	// fifth-order interpolant for improved perlin noise
	return t*t*t * (t * (t*6.0-15.0) + 10.0);
}

void fragment() {
	// use precalculated data
	float w = texture(precalculated,UV).x;
	
	vec4 normal = texture(precalculated,vec2(UV.x,UV.y+0.5));
	normal = vec4(normal.xyz*2.0-1.0,0.0);
	normal = WORLD_MATRIX*normal;
	NORMAL = (INV_CAMERA_MATRIX*normal).xyz;
	
	if(color_scheme==1)
		w=interp_order5_scalar(4.0*w)*2.0;
	else
		w*=w;
	ALBEDO=w*color_scaling+color_addition;
}

void light() {
    DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ALBEDO;
}
