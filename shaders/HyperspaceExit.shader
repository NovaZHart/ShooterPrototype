shader_type spatial;
render_mode unshaded;

uniform sampler2D thickness_texture;
uniform sampler2D detail_texture: hint_albedo;
uniform vec3 exit_color_multiplier = vec3(1.0,1.0,1.0);
uniform float perturbation = 5;
uniform float period = 0.05;
//uniform float time = 0.125;
uniform int ship_id = 0;

//void vertex() {
//	if(UV.y>0.5) {
//		float v1 = fract(period*(TIME+float(ship_id)));
//		vec4 tex = texture(cargo_web_texture,vec2(UV.x,v1));
////		COLOR = tex;
//		VERTEX.x += UV2.x * tex.r * perturbation;
//		VERTEX.z += UV2.y * tex.r * perturbation;
////		if(time<0.125) {
////			VERTEX.x *= time*8.0;
////			VERTEX.z *= time*8.0;
////		}
//	}
//}

void fragment() {
	float v1 = fract(fract(period*TIME) + fract(float(ship_id)/1024.0));
	float u1 = fract(UV.x + 0.5*UV.y -period*TIME);
	vec4 tex = texture(thickness_texture,vec2(u1,v1));
	float v2 = fract(UV.y + period*TIME*5.0);
	
	float fadeout_radius = tex.r*0.5+0.5;
	float inner_alpha = (0.15+0.85*tex.r*tex.r)*(0.3+0.7*UV.y);

	ALBEDO = texture(detail_texture,vec2(u1,v2)).rgb*inner_alpha*exit_color_multiplier;

	
	if(UV.y>fadeout_radius && fadeout_radius>0.0) {
		float a = (1.0-UV.y)/(1.0-fadeout_radius);
		ALPHA = a*a;
	} else {
		ALPHA=1.0;
		//ALPHA=inner_alpha;
	}
}