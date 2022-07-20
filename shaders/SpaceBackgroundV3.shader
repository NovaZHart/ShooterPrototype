shader_type canvas_item;
render_mode unshaded;

const int perlin_squares=32;
uniform sampler2D hash_square;

uniform vec4 color = vec4(0.4,0.4,1.0,1.0);

uniform float weight_power = 0.794;
uniform float scale_power = 0.5;
uniform float scale_start = 1;
uniform int perlin_type = 2;

float perlin_grad1(int hash,float x,float y) {
	// Gradients for improved perlin noise.
	// Get gradient at corner specified by p
	int h=hash&15;
	float u,v;
	u = h<8 ? x : y;
	// 3D version: v = (h<4) ? y : ((h==12||h==14) ? x : z);
	v = (h<4) ? y : ((h==12||h==14) ? x : y);
	return ((h&1) == 0 ? u : -u) + ((h&2) == 0 ? v : -v);
}

vec2 interp_order5(vec2 t) {
	// fifth-order interpolant for improved perlin noise
	return t*t*t * (t * (t*6.0-15.0) + 10.0);
}

float improved_perlin(float scale,vec2 new_normal) {
	// Improved Perlin noise. References:
	// https://mrl.nyu.edu/~perlin/paper445.pdf
	// https://developer.nvidia.com/gpugems/gpugems/part-i-natural-effects/chapter-5-implementing-improved-perlin-noise
	// https://mrl.nyu.edu/~perlin/noise/
	vec2 uv=new_normal;
	vec2 xy=mod(uv/scale,1.0)*float(perlin_squares);
	vec2 p=fract(xy),q=p-1.0;
	vec2 weight=interp_order5(p);

	ivec2 square=ivec2(floor(xy))%perlin_squares;
	vec4 rhash = texelFetch(hash_square,square,0);
	ivec4 ihash = ivec4(round(rhash*32.0));

	float p00=perlin_grad1(ihash.r,p.x,p.y);
	float p01=perlin_grad1(ihash.g,p.x,q.y);
	float p10=perlin_grad1(ihash.b,q.x,p.y);
	float p11=perlin_grad1(ihash.a,q.x,q.y);
	
	vec2 px0 = vec2(p00,p01);
	vec2 px1 = vec2(p10,p11);
	vec2 px = mix(px0,px1,weight.x);
	return mix(px.x,px.y,weight.y);
}

float apply_perlin_type(float scale,vec2 new_normal) {
	float c=improved_perlin(scale,new_normal); // -1 to 1
	if(perlin_type==1)
		return abs(c);
	else if(perlin_type==10) // mix of types 1 and 0
		return 1.6667*(0.3*c + 0.7*abs(c) - 0.4);
	return 0.5*(c+1.0);
}

void fragment() {
	float result = 0.0;
	float weight=1.0;
	float scale=scale_start;
	float weight_sum = 0.0;
	for(int i=0;i<7;i++) {
		result += apply_perlin_type(scale,UV)*weight;
		weight_sum+=weight;
		weight*=weight_power;
		scale*=scale_power;
	}
	result/=weight_sum;
	COLOR = vec4(result*color.rgb,result);
}
