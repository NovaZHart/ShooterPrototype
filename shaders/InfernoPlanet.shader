shader_type spatial;
render_mode skip_vertex_transform;

uniform sampler2D precalculated : hint_albedo;

varying vec3 saved_vertex;

void vertex() {
	saved_vertex=VERTEX;
	VERTEX = (MODELVIEW_MATRIX*vec4(VERTEX,1.0)).xyz;
}

void fragment() {
	NORMAL = (INV_CAMERA_MATRIX*(WORLD_MATRIX*vec4(normalize(saved_vertex),0.0))).xyz;
	ALBEDO = texture(precalculated,UV).rgb;
}

void light() {
	float direction=clamp(dot(NORMAL, LIGHT),0.0,1.0);
	//DIFFUSE_LIGHT = direction*ALBEDO;
	DIFFUSE_LIGHT = mix(ALBEDO,ALBEDO*ALBEDO*0.15,1.0-direction);
}
