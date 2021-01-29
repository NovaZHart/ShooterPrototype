shader_type spatial;

uniform sampler2D precalculated;
uniform sampler2D xyz;

void fragment() {
//	vec4 normal = vec4(texture(xyz,UV).xyz,0.0);
//	normal = WORLD_MATRIX*normal;
//	NORMAL = (INV_CAMERA_MATRIX*normal).xyz;
	
	ALBEDO = texture(precalculated,vec2(UV.x,UV.y/2.0+0.5)).rgb;
	EMISSION = ALBEDO;
//	ALPHA = clamp(1.9*abs(NORMAL.z)*abs(NORMAL.z), 0.0, 1.0)*length(ALBEDO);
}
