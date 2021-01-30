shader_type spatial;
render_mode unshaded;

uniform sampler2D xyz;
uniform sampler2D generated;
uniform float emission_fraction = 0.0;

void fragment() {
	vec2 uv = vec2(UV.x,UV.y/2.0);
	vec3 tex = texture(generated,vec2(uv.x,uv.y+0.5)).rgb;
	vec4 pert = vec4(texture(generated,uv).xyz*2.0-1.0,0.0);
	vec4 base = vec4(texture(xyz,UV).xyz,0.0);
	
	vec4 normal = normalize(base+pert*0.1);
	normal = WORLD_MATRIX*normal;
	NORMAL = (INV_CAMERA_MATRIX*normal).xyz;
	ALBEDO = tex;
	EMISSION=ALBEDO;
	ALPHA = clamp(1.9*abs(NORMAL.z)*abs(NORMAL.z), 0.0, 1.0)*length(ALBEDO);
}

//void light() {
//	//if(emission_fraction<0.5)
//    	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ALBEDO;
//		//SPECULAR_LIGHT += 0.11111*clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ALBEDO;
//}