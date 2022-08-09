shader_type spatial;

uniform sampler2D precalculated : hint_albedo;

varying float vx;
varying float vy;
varying float vz;

void vertex() {
	vx = VERTEX.x;
	vy = VERTEX.y;
	vz = VERTEX.z;
}

void fragment() {
	NORMAL = (INV_CAMERA_MATRIX*(WORLD_MATRIX*vec4(normalize(vec3(vx,vy,vz)),0.0))).xyz;
	ALBEDO = texture(precalculated,UV).rgb;
}

void light() {
	float direction=clamp(dot(NORMAL, LIGHT),0.0,1.0);
	DIFFUSE_LIGHT = mix(ALBEDO,ALBEDO*ALBEDO*0.15,1.0-direction);
}
