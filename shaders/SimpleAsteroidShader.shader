shader_type spatial;
render_mode specular_disabled;
render_mode shadows_disabled;

uniform sampler2D tex1;
uniform sampler2D tex2;

void vertex() {
	vec4 ic = INSTANCE_CUSTOM*2.0-1.0;

	float z = UV2.y;
	vec4 ic1 = vec4(ic.r+ic.r,ic.r+ic.b,ic.g+ic.b,ic.a+ic.a)*0.5;
	float f = dot(vec4(0.4*sin(z*3.14159),0.4*cos(z*3.14159),0.6*sin(z*6.28319),0.6*cos(z*6.28319)),ic1);
	f += dot(vec4(0.2*sin(z*9.424778),0.2*cos(z*9.424778),0.1*sin(z*12.56637),0.1*cos(z*12.56637)),ic1);
	
	float a = UV2.x;
	vec4 ic2 = vec4(ic.r+ic.g,ic.r+ic.a,ic.g+ic.a,ic.g+ic.g)*0.5;
	float g = dot(vec4(0.4*sin(a),0.4*cos(a),0.6*sin(a*2.0),0.6*cos(a*2.0)),ic2);
	g += dot(vec4(0.2*sin(3.0*a),0.2*cos(3.0*a),0.1*sin(a*4.0),0.1*cos(a*4.0)),ic2);
	
	VERTEX *= clamp(0.5*f*g+0.55,0.2,1.1);
	
	UV2 = vec2(mod(UV2.x,6.28319)/6.28319,UV2.y*0.5+0.5);
	COLOR=INSTANCE_CUSTOM;
}

void fragment() {
	vec3 c = mix(vec3(0.9,0.8,0.4),vec3(1.0,0.5,0.5),COLOR.g);
	vec3 s = mix(c,vec3(0.7,0.7,0.7),COLOR.r*COLOR.r);
	ALBEDO = mix(texture(tex1, UV).rgb,texture(tex2,UV2).rgb,COLOR.a)*s;
}
