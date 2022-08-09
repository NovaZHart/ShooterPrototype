shader_type spatial;

uniform float delta_u = 0.0075;
uniform float delta_v = 0.0150;
uniform float map_scale = 0.25;

uniform sampler2D precalculated;
uniform sampler2D xyz;
uniform sampler2D colors: hint_albedo;

varying vec3 planet_normal;

vec4 data_at(float u, float v) {
	vec2 uv = vec2(u,v);
	return vec4(texture(xyz,uv).xyz, texture(precalculated,uv).r*2.0-1.0);
}

vec3 vector_at(float u,float v) {
	vec4 data = data_at(u,v);
	return data.xyz * (1.0+map_scale*clamp(data.w,-1.0,1.0));
}

void vertex() {
	float h = texture(precalculated,UV).r;
	VERTEX *= 1.0+h*map_scale;
}

void fragment() {
	vec3 Tx_unnormalized = vector_at(UV.x+delta_u,UV.y)-vector_at(UV.x-delta_u,UV.y);
	vec3 Ty_unnormalized = vector_at(UV.x,UV.y+delta_v)-vector_at(UV.x,UV.y-delta_v);
	vec3 N = normalize(cross(Tx_unnormalized,Ty_unnormalized));
	vec2 hm = texture(precalculated,UV).rg;
	float h = hm.x*2.0-1.0;
	vec3 xyz0 = texture(xyz,UV).xyz;
	NORMAL=(INV_CAMERA_MATRIX*(WORLD_MATRIX*vec4(N,0.0))).xyz;
	planet_normal = (INV_CAMERA_MATRIX*(WORLD_MATRIX*vec4(xyz0,0.0))).xyz;
	ALBEDO=texture(colors,hm.xy).rgb;
}

void light() {
	vec3 light = normalize(LIGHT);
	float received=(clamp(dot(planet_normal, light),-0.1,1.0)+0.1)*0.909090909090909;
	float returned=min(received,dot(NORMAL,light)*0.5+0.5);
	DIFFUSE_LIGHT =ALBEDO*mix(received,returned,0.9);
}
