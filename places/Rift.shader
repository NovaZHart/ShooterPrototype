shader_type spatial;
render_mode unshaded, skip_vertex_transform;

uniform float time;
uniform float expansion_time;

void vertex() {
	vec3 vertex2 = vec3(UV2.x,VERTEX.y,UV2.y);
	vec3 final_vertex = mix(VERTEX,vertex2,clamp(abs(expansion_time-time)/expansion_time,0.0,1.0));
	VERTEX = (MODELVIEW_MATRIX * vec4(final_vertex,1.0)).xyz;
}

void fragment() {
	ALBEDO = vec3(1.0,1.0,0.0); // vec3(UV.y,UV.y*0.8,UV.y*0.3);
}