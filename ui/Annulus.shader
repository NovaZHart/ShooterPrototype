shader_type spatial;
render_mode unshaded, skip_vertex_transform;

uniform float r_mid = 1.0;
uniform float thickness = 0.1;
uniform float scale = 0.1;
uniform vec4 color = vec4(1.0,1.0,1.0,0.3);

varying vec3 stored_vertex;

void vertex() {
	stored_vertex = VERTEX;
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float r = length(stored_vertex.xz);
	float weight = clamp((r-r_mid) * 2.0/(thickness*scale),-1.0,1.0);
	weight *= weight;
	weight = 1.0 - weight*weight;
	ALBEDO = color.rgb*weight;
	ALPHA = color.a*weight;
}