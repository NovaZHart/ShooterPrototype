shader_type spatial;
render_mode unshaded;

uniform float projectile_scale = 3.0;
uniform sampler2D shield_texture;

void fragment() {
	float r0 = 2.0*(UV.y-0.5)/projectile_scale;
	ALPHA = 0.333333*max(0.0,1.0-r0*r0);
	
	if(ALPHA>0.0) {
		float u1 = fract(fract(TIME)*0.1+UV.x*0.1);
		vec3 tex = texture(shield_texture,vec2(u1,UV.y)).rgb;
		float rgb = (tex.r+tex.g+tex.b)*0.3333333333333;
		ALBEDO = COLOR.rgb*rgb;
	} else
		ALBEDO = vec3(0.0,0.0,0.0);
}