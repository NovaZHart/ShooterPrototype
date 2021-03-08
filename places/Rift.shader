shader_type spatial;
render_mode unshaded, skip_vertex_transform;

uniform float time = 1.0;
uniform float expansion_time = 2.0;

void vertex() {
	vec3 vertex2 = vec3(UV2.x,VERTEX.y,UV2.y);
	float factor = clamp(abs(expansion_time-time)/expansion_time,0.0,1.0);
	vec3 final_vertex = mix(VERTEX,vertex2,factor*factor);
	VERTEX = (MODELVIEW_MATRIX * vec4(final_vertex,1.0)).xyz;
}

void fragment() {
	ALBEDO = vec3(0.5,0.2,0.4); // vec3(UV.y,UV.y*0.3,UV.y*0.8);
	ALPHA = 0.5*(1.0-clamp(abs(expansion_time-time)/expansion_time,0.0,1.0));
}