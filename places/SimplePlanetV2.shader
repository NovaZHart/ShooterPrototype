shader_type spatial;
render_mode skip_vertex_transform;

uniform sampler2D precalculated;

varying vec3 saved_vertex;

void vertex() {
	saved_vertex=VERTEX;
	VERTEX = (MODELVIEW_MATRIX*vec4(VERTEX,1.0)).xyz;
}

void fragment() {
	vec2 uv_half = vec2(UV.x,UV.y/2.0);
	NORMAL = (INV_CAMERA_MATRIX*(WORLD_MATRIX*vec4(normalize(saved_vertex),0.0))).xyz;

//	vec4 base = vec4(normalize(saved_vertex),0.0);
//	vec4 pert = vec4(texture(precalculated,uv_half).xyz*2.0-1.0,0.0);
//	vec4 normal = normalize(base+pert*0.1);
//	normal = WORLD_MATRIX*normal;
//	NORMAL = (INV_CAMERA_MATRIX*normal).xyz;

	ALBEDO = texture(precalculated,vec2(uv_half.x,uv_half.y+0.5)).rgb;
//	ALPHA = clamp(1.9*abs(NORMAL.z)*abs(NORMAL.z), 0.0, 1.0)*length(ALBEDO);
}

void light() {
    DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT),0.0,1.0) * ALBEDO;
}
