shader_type canvas_item;
render_mode unshaded;

const int perlin_squares=32;
uniform sampler2D hash_square;

uniform vec4 color = vec4(0.4,0.4,1.0,1.0);

uniform float weight_power = 0.53;
uniform float scale_power = 1.7;
uniform float scale_start = 1.0;
uniform int perlin_type = 10;

vec2 interp_order5(vec2 t) {
	// fifth-order interpolant for improved perlin noise
	return t*t*t * (t * (t*6.0-15.0) + 10.0);
}

float improved_perlin(float scale,vec2 new_normal,int layer) {
	// Improved Perlin noise. References:
	// https://mrl.nyu.edu/~perlin/paper445.pdf
	// https://developer.nvidia.com/gpugems/gpugems/part-i-natural-effects/chapter-5-implementing-improved-perlin-noise
	// https://mrl.nyu.edu/~perlin/noise/
	vec2 uv=new_normal;
	vec2 xy=mod(uv*scale,1.0)*float(perlin_squares);
	vec2 p=fract(xy),q=p-1.0;
	vec2 weight=interp_order5(p);
	
	ivec2 square=ivec2(floor(xy))%perlin_squares;
	ivec2 iuv = ivec2(square.x+perlin_squares*square.y,layer);
	vec4 rhash = 6.28318*texelFetch(hash_square,iuv,0);
	//ivec4 ihash = ivec4(round(rhash*32.0));
	
	float p00=dot(vec2(sin(rhash.r),cos(rhash.r)),vec2(p.x,p.y));
	float p01=dot(vec2(sin(rhash.g),cos(rhash.g)),vec2(p.x,q.y));
	float p10=dot(vec2(sin(rhash.b),cos(rhash.b)),vec2(q.x,p.y));
	float p11=dot(vec2(sin(rhash.a),cos(rhash.a)),vec2(q.x,q.y));
	
	vec2 px0 = vec2(p00,p01);
	vec2 px1 = vec2(p10,p11);
	vec2 px = mix(px0,px1,weight.x);
	return mix(px.x,px.y,weight.y);
}

float apply_perlin_type(float scale,vec2 new_normal,int layer,int type) {
	float c=improved_perlin(scale,new_normal,layer); // -1 to 1
	if(type==4)
		return sqrt(abs(c));
	else if(type==1)
		return abs(c)*4.0;
	else if(type==10) {// mix of types 1 and 0
		float a=c*4.0;
		return 1.6667*(0.3*a + 0.7*abs(a) - 0.4);
	}
	return 0.5*(c+1.0);
}

void fragment() {
//	COLOR=test(scale_start,UV,11);
	float result = 0.0;
	float weight=1.0;
	float scale=1.0;
	float weight_sum = 0.0;
	for(int i=0;i<9;i++) {
		if(i>5)
			result += apply_perlin_type(scale,UV,i,10)*weight;
		else
			result += apply_perlin_type(scale,UV,i,0)*weight;
		weight_sum+=weight;
		weight*=weight_power;
		scale*=scale_power;
	}
	result/=weight_sum;
	COLOR = vec4(result*color.rgb,result);
}
