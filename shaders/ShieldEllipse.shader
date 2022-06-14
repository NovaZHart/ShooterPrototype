shader_type spatial;
render_mode unshaded;

uniform float projectile_scale = 3.0;
uniform float thickness = 1.0;
uniform int ship_id = 0;
uniform sampler2D shield_texture;

void vertex() {
	VERTEX += NORMAL*UV.y*thickness*(projectile_scale-1.0)/2.0;
	UV.y = 2.0*UV.y-1.0;
}

void fragment() {
	float m = 1.0-UV.y*UV.y;
	if(m>0.0) {
		ALPHA = 0.333333*m;
		float t = TIME + float(ship_id);
		float v1 = fract(fract(t*0.1)+UV.y*0.05);
		float u1 = fract(fract(t*0.0113)+UV.x);
		ALBEDO = COLOR.rgb*texture(shield_texture,vec2(u1,v1)).b;
	} else {
		ALBEDO = vec3(0.0,0.0,0.0);
		ALPHA = 0.0;
	}
}