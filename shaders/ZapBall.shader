shader_type spatial;
render_mode skip_vertex_transform;

uniform float v_radius=2.0;
uniform float time=0.0;
uniform float duration=2.0;
uniform bool reverse=false;

varying vec3 stored_vertex;

void vertex() {
	stored_vertex=VERTEX;
	VERTEX = (MODELVIEW_MATRIX*vec4(VERTEX,1.0)).xyz;
}

void fragment() {
	float pi2 = 1.5707963267948966;
	float fade = 1.0-abs(2.0*time/duration-1.0);
	fade = clamp(fade,0.0,1.0);
	float ball_radius = v_radius * 0.5;
	vec3 r = vec3(stored_vertex.x,0.0,stored_vertex.z);
	float radius = length(r);
	if(radius<ball_radius) {
		vec3 n = r/ball_radius;
		n.y = sqrt(1.0-n.x*n.x-n.z*n.z);
		NORMAL = (INV_CAMERA_MATRIX*(WORLD_MATRIX*vec4(n,0.0))).xyz;
		float gb = 0.5*n.y*n.y+0.3;
		ALBEDO = vec3(1.0,gb,gb+0.2);
		ALPHA = fade;
	} else {
		NORMAL = vec3(0.0,0.0,-1.0);
		ALPHA = 0.0;
	}
}