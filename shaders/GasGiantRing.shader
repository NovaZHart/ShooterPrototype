shader_type spatial;
render_mode skip_vertex_transform;

uniform float r_mid = 1.0;
uniform float thickness = 0.1;
uniform float scale = 0.1;
uniform vec4 color = vec4(1.0,1.0,1.0,0.3);
uniform sampler2D ring_noise;
uniform vec3 planet_world_norm;
uniform float shadow_cos_inner;
uniform float shadow_start;
uniform float shadow_cos_outer;

varying vec3 stored_vertex;

void vertex() {
	stored_vertex = VERTEX;
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 vertex_world = (WORLD_MATRIX*vec4(stored_vertex.x,0,stored_vertex.z,1.0)).xyz;
	vertex_world.y=0.0;
	float vertex_distance = length(vertex_world);
	float r = length(stored_vertex.xz);
	float scaled = clamp((r-r_mid) * 2.0/(thickness*scale),-1.0,1.0);
	float weight = 1.0 - scaled*scaled;
	float k = texture(ring_noise,vec2(scaled,scaled)).r;
	ALBEDO = k*weight*color.rgb;
	ALPHA = k*weight;
	if(vertex_distance>shadow_start) {
		vec3 vertex_world_norm = vertex_world/vertex_distance;
		float cos_here = dot(vertex_world_norm,planet_world_norm);
		if(cos_here>shadow_cos_outer) {
			if(cos_here>=shadow_cos_inner || shadow_cos_inner<=shadow_cos_outer)
				ALBEDO *= 0.2;
			else {
				float fade = (cos_here-shadow_cos_outer)/(shadow_cos_inner-shadow_cos_outer);
				ALBEDO *= clamp(1.0-0.8*fade*fade,0.2,1.0);
			}
		}
	}
}