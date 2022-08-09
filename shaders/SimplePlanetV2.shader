shader_type spatial;

uniform sampler2D precalculated: hint_albedo;

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
	float d = dot(NORMAL,LIGHT)+0.05;
	float e = d*d*sign(d)*0.9070294784580498;
	DIFFUSE_LIGHT += clamp(e,0.0,1.0) * ALBEDO;
}
