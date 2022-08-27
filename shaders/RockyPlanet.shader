shader_type spatial;
//render_mode skip_vertex_transform;

uniform float delta_u = 0.0075;
uniform float delta_v = 0.0150;
uniform float height_map_scale = 0.4;

uniform sampler2D precalculated;
uniform sampler2D xyz;
uniform sampler2D colors: hint_albedo;

varying vec3 planet_normal;
//varying vec3 saved_vertex;
//varying vec3 saved_normal;
//varying vec3 saved_tangent;
//varying vec3 saved_binormal;

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

void light() {
	vec3 light=normalize(LIGHT);
	float mag=length(light);
	if(mag>0.0) {
		float d=dot(normalize(NORMAL),light/mag);
		if(d>0.0) {
			DIFFUSE_LIGHT += mag*(d*d*d+d*d)*ALBEDO;
		}
	}
}

void vertex() {
//	saved_vertex = VERTEX;
//	float h = 0.2 * ( height_at(UV.x,UV.y)
//		+ height_at(UV.x+delta_u,UV.y) + height_at(UV.x-delta_u,UV.y)
//		+ height_at(UV.x,UV.y+delta_v) + height_at(UV.x,UV.y-delta_v));
//	VERTEX *= 1.0+h*height_map_scale;
//	saved_normal = NORMAL;
//	saved_tangent = TANGENT;
//	saved_binormal = BINORMAL;
//	VERTEX = (MODELVIEW_MATRIX*vec4(VERTEX,1.0)).xyz;
	VERTEX *= 1.0+height_at(UV.x,UV.y)*height_map_scale;
}

//void fragment() {
//	// Calculate normal in interpolated coordinate system
//	float dhu = height_at(UV.x+delta_u,UV.y)-height_at(UV.x-delta_u,UV.y);
//	float dhv = height_at(UV.x,UV.y+delta_v)-height_at(UV.x,UV.y-delta_v);
//	float du = delta_u;
//	float dv = delta_v;
//	//vec3 binormal=cross(saved_tangent,saved_normal);
//	vec3 surface_normal_interp = normalize(-dhu*dv*saved_binormal -dhv*du*saved_tangent +du*dv*saved_normal);
//
//	// Calculate transform from interpolated coordinate system to sphere-relative coordinate system
//	vec3 interp_norm = saved_normal;
//	vec3 sphere_norm = normalize(saved_vertex);
//	float v_dot_t=dot(interp_norm,sphere_norm);
//	vec3 v_cross_t=cross(interp_norm,sphere_norm);
//	float sin_theta=length(v_cross_t);
//	vec3 unit_v_cross_t=v_cross_t/sin_theta;
//
//	// Transform surface normal to sphere-relative space
//	vec3 surface_normal_sphere = normalize((1.0-v_dot_t)*dot(surface_normal_interp,unit_v_cross_t)
//		+surface_normal_interp*v_dot_t +cross(v_cross_t,surface_normal_interp));
//	NORMAL=(INV_CAMERA_MATRIX*(WORLD_MATRIX*vec4(surface_normal_sphere,0.0))).xyz;
//
//	// Look up color
//	ALBEDO=texture(colors,texture(precalculated,UV).rg).rgb;
//
//	//ALBEDO=0.5+0.5*(surface_normal_sphere);
//}

void fragment() {
	vec3 Tx_unnormalized = vector_at(UV.x+delta_u,UV.y)-vector_at(UV.x-delta_u,UV.y);
	vec3 Ty_unnormalized = vector_at(UV.x,UV.y+delta_v)-vector_at(UV.x,UV.y-delta_v);
	vec3 N = normalize(cross(Tx_unnormalized,Ty_unnormalized));
	NORMAL=(INV_CAMERA_MATRIX*(WORLD_MATRIX*vec4(N,0.0))).xyz;
	ALBEDO=texture(colors,texture(precalculated,UV).rg).rgb;
}