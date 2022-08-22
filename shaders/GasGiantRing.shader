shader_type spatial;
render_mode skip_vertex_transform;

uniform float r_mid = 1.0;
uniform float thickness = 0.1;
uniform float scale = 0.1;
uniform vec4 color = vec4(1.0,1.0,1.0,0.3);
uniform sampler2D ring_noise;

varying vec3 stored_vertex;

void vertex() {
	stored_vertex = VERTEX;
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float r = length(stored_vertex.xz);
	float scaled = clamp((r-r_mid) * 2.0/(thickness*scale),-1.0,1.0);
//	weight *= weight;
	float weight = 1.0 - scaled*scaled;
	//float k = texture(ring_noise,vec2(weight*0.5+0.5,weight*0.5+0.5)).r;
	float k = texture(ring_noise,vec2(scaled,scaled)).r;
	ALBEDO = k*weight*color.rgb;
	ALPHA = k*weight;
}