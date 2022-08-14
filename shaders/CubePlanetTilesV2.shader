shader_type canvas_item;
render_mode skip_vertex_transform;

uniform sampler2D xyz;

uniform int perlin_cubes=8;

// blue planet
uniform int perlin_type=0;
uniform int perlin_seed=18492;
uniform vec3 color_scaling=vec3(0.909804,0.980392,0.980392);
uniform vec3 color_addition=vec3(0.207843,0.631373,0.662745);
uniform int color_scheme=2;
uniform float weight_power = 0.373333;
uniform float scale_power = 0.3577;
uniform float scale_start = 3.9;
uniform float perlin_bias = 0.5;

float interp_order5_scalar(float t) {
	// fifth-order interpolant for improved perlin noise
	return t*t*t * (t * (t*6.0-15.0) + 10.0);
}

int bob_hash(int k) {
	int a = k;
	a = (a+2127912214) + (a<<12);
	a = (a^3345072700) ^ (a>>19);
	a = (a+374761393)  + (a<<5);
	a = (a+3550635116) ^ (a<<9);
	a = (a+4251993797) + (a<<3);
	a = (a^3042594569) ^ (a>>16);
	return a;
}

float perlin_grad1(int hash,float x,float y,float z) {
	// Gradients for improved perlin noise.
	// Get gradient at cube corner specified by p
	int h=hash&15;
	float u,v;
	u = h<8 ? x : y;
	v = (h<4) ? y : ((h==12||h==14) ? x : z);
	return ((h&1) == 0 ? u : -u) + ((h&2) == 0 ? v : -v);
}

vec3 interp_order5(vec3 t) {
	// fifth-order interpolant for improved perlin noise
	return t*t*t * (t * (t*6.0-15.0) + 10.0);
}

float improved_perlin(int seed,float scale,int cubes,vec3 new_normal) {
	// Improved Perlin noise. References:
	// https://mrl.nyu.edu/~perlin/paper445.pdf
	// https://developer.nvidia.com/gpugems/gpugems/part-i-natural-effects/chapter-5-implementing-improved-perlin-noise
	// https://mrl.nyu.edu/~perlin/noise/
	vec3 uvw=new_normal*0.5+0.5;
	vec3 cube_xyz=mod(uvw/scale,1.0)*float(cubes);
	ivec3 cube=ivec3(floor(cube_xyz))%cubes;
	ivec3 next=(cube+1)%cubes;
	ivec3 last=(cube+1)%cubes;
	vec3 p=fract(cube_xyz),q=p-1.0;
	vec3 weight=interp_order5(p);
	
	int h=bob_hash(seed);
	int h0=bob_hash(h^cube.x),h1=bob_hash(h^next.x);
	int h00=bob_hash(h0^cube.y),h01=bob_hash(h1^cube.y);
	int h10=bob_hash(h0^next.y),h11=bob_hash(h1^next.y);
	int h000=bob_hash(h00^cube.z),h001=bob_hash(h01^cube.z);
	int h010=bob_hash(h10^cube.z),h011=bob_hash(h11^cube.z);
	int h100=bob_hash(h00^next.z),h101=bob_hash(h01^next.z);
	int h110=bob_hash(h10^next.z),h111=bob_hash(h11^next.z);
	float p000=perlin_grad1(h000,p.x,p.y,p.z),p001=perlin_grad1(h001,q.x,p.y,p.z);
	float p010=perlin_grad1(h010,p.x,q.y,p.z),p011=perlin_grad1(h011,q.x,q.y,p.z);
	float p100=perlin_grad1(h100,p.x,p.y,q.z),p101=perlin_grad1(h101,q.x,p.y,q.z);
	float p110=perlin_grad1(h110,p.x,q.y,q.z),p111=perlin_grad1(h111,q.x,q.y,q.z);
	return mix(mix(mix(p000,p001,weight.x),mix(p010,p011,weight.x),weight.y),
	           mix(mix(p100,p101,weight.x),mix(p110,p111,weight.x),weight.y),weight.z)/2.0;
}

float apply_perlin_type(int seed,float scale,int cubes,vec3 new_normal,float delta,int type) {
	float c=improved_perlin(seed,scale,cubes,new_normal);
	if(type==1)
		return abs(c);
	else if(type==10) // mix of types 1 and 0
		float a=abs(c);
		return 0.3*c + 0.7*abs(c);
	return c;
}

float multi_perlin_scalar(int seed,int cubes,vec3 new_normal,float delta,int noise_type,bool grad) {
	// vec4 perlin_and_delta(int seed,float scale,int cubes,vec3 new_normal,float delta,int type) {
	float result = 0.0;
	float weight=1.0;
	float scale=scale_start;
	float weight_sum = 0.0;
	int type = noise_type;
	if(type==3)
		type=1;
	for(int i=0;i<4;i++) {
		result += apply_perlin_type(seed,scale,cubes,new_normal,delta,noise_type)*weight;
		weight_sum+=weight;
		weight*=weight_power;
		scale*=scale_power;
	}
	if(noise_type==3)
		result = sin(7.0*(new_normal.y+result));
	result = 2.0*result/weight_sum;
	result += perlin_bias;
	return result;
}

void fragment() {
	vec4 xyzw = texture(xyz,vec2(UV.x,1.0-UV.y));
	if(xyzw.w>0.5) {
		vec3 normal = xyzw.xyz;
		float delta=0.03;
		float w = multi_perlin_scalar(perlin_seed,perlin_cubes,normal,delta,perlin_type,true);
		if(color_scheme==1)
			w=interp_order5_scalar(w);
		else
			w*=w;
		COLOR = vec4(w*color_scaling+color_addition,1.0);
	} else
		COLOR=vec4(0.0,0.0,0.0,0.0);
}