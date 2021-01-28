shader_type spatial;
render_mode unshaded;

uniform sampler2D xyz;
uniform sampler2D generated;

void fragment() {
	vec3 tex = texture(generated,vec2(UV.x,UV.y/2.0+0.5)).rgb;
	vec4 normal = vec4(texture(generated,vec2(UV.x,UV.y/2.0)).xyz,0.0);
//	vec4 normal = vec4(texture(xyz,UV).xyz,0.0);
	normal = WORLD_MATRIX*normal;
	NORMAL = (INV_CAMERA_MATRIX*normal).xyz;
	ALBEDO = tex; // normal.xyz/2.0+0.5;
	EMISSION=ALBEDO;
	//ALPHA = clamp(0.9*abs(NORMAL.z)*abs(NORMAL.z), 0.0, 1.0);
}