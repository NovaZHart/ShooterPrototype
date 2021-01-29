shader_type spatial;

uniform sampler2D precalculated;
uniform sampler2D xyz;

void fragment() {
	vec2 uv_half = vec2(UV.x,UV.y/2.0);
	
//	vec4 pert = vec4(texture(precalculated,uv_half).xyz*2.0-1.0,0.0);
//	vec4 base = vec4(texture(xyz,UV).xyz,0.0);
//	vec4 normal = base; // normalize(base+pert*0.1);
//	normal = WORLD_MATRIX*normal;
//	NORMAL = (INV_CAMERA_MATRIX*normal).xyz;
	
	ALBEDO = texture(precalculated,vec2(uv_half.x,uv_half.y+0.5)).rgb;
//	ALPHA = clamp(1.9*abs(NORMAL.z)*abs(NORMAL.z), 0.0, 1.0)*length(ALBEDO);
}

void light() {
    DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT),0.0,1.0) * ALBEDO;
}
