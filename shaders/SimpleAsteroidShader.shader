shader_type spatial;
render_mode shadows_disabled;

uniform sampler2D tex1;
uniform sampler2D tex2;

void vertex() {
	vec4 ic1 = INSTANCE_CUSTOM*2.0-1.0;
	vec4 ic2 = fract(ic1*7.0);
	vec4 ic3 = fract(ic2*7.0);
	vec4 ic4 = fract(ic3*7.0);

	float b = UV2.y;
	float f = dot(vec4(0.2*sin(b*2.0),0.2*cos(b*2.0),0.4*sin(b*3.0),0.4*cos(b*3.0)),ic1);
	f += dot(vec4(0.5*sin(b*4.0),0.5*cos(b*4.0),0.3*sin(b*5.0),0.3*cos(b*5.0)),ic2);
	
	float a = UV2.x;
	float g = dot(vec4(0.2*sin(a*2.0),0.2*cos(a*2.0),0.4*sin(a*3.0),0.4*cos(a*3.0)),ic3);
	g += dot(vec4(0.5*sin(4.0*a),0.5*cos(4.0*a),0.3*sin(a*5.0),0.3*cos(a*5.0)),ic4);
	
	VERTEX *= clamp(0.5*f*g+0.55,0.2,1.5)*1.4;
}

void fragment() {
	ALBEDO = mix(texture(tex1,UV).rgb,texture(tex2,UV).rgb,COLOR.a)*COLOR.rgb;
}
