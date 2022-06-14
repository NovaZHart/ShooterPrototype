shader_type spatial;
render_mode unshaded;

uniform sampler2D cargo_web_texture;
uniform vec3 faction_color = vec3(1.0,0.5,0.5);
uniform float perturbation = 0.1;
uniform float period = .05;
uniform float time = 0.0;
uniform int ship_id = 0;

void vertex() {
	if(UV.y>0.5) {
		float v1 = fract(period*(TIME+float(ship_id)));
		vec4 tex = texture(cargo_web_texture,vec2(UV.x,v1));
		COLOR = tex;
		VERTEX.x += NORMAL.x * tex.r * perturbation;
		VERTEX.z += NORMAL.z * tex.r * perturbation;
		if(time<0.125) {
			VERTEX.x *= time*8.0;
			VERTEX.z *= time*8.0;
		}
	}
}

void fragment() {
	//vec4 tex = texture(cargo_web_texture,UV);
	ALBEDO=faction_color;
	ALPHA=0.05*COLOR.r*COLOR.r*UV.y;
}