shader_type spatial;

uniform float delta_u = 0.0075;
uniform float delta_v = 0.0150;
uniform float height_map_scale = 0.4;

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
	return data.xyz * (1.0+height_map_scale*clamp(data.w,-1.0,1.0));
}

float height_at(float u,float v) {
	return texture(precalculated,vec2(u,v)).r*2.0-1.0;
}

void vertex() {
	float h = 0.2 * ( height_at(UV.x,UV.y)
		+ height_at(UV.x+delta_u,UV.y) + height_at(UV.x-delta_u,UV.y)
		+ height_at(UV.x,UV.y+delta_v) + height_at(UV.x,UV.y-delta_v));
	VERTEX *= 1.0+h*height_map_scale;
}

void fragment() {
	vec3 Tx_unnormalized = vector_at(UV.x+delta_u,UV.y)-vector_at(UV.x-delta_u,UV.y);
	vec3 Ty_unnormalized = vector_at(UV.x,UV.y+delta_v)-vector_at(UV.x,UV.y-delta_v);
	vec3 N = normalize(cross(Tx_unnormalized,Ty_unnormalized));
	NORMAL=(INV_CAMERA_MATRIX*(WORLD_MATRIX*vec4(N,0.0))).xyz;
	ALBEDO=texture(colors,texture(precalculated,UV).rg).rgb;
}