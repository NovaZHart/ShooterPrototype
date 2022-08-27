shader_type canvas_item;
render_mode skip_vertex_transform;
//render_mode unshaded;

uniform sampler2D xyz;
uniform sampler2D hash_cube;

const int perlin_cubes=16;

// blue planet
uniform int perlin_type=0;
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

float improved_perlin(float scale,vec3 new_normal) {
	// Improved Perlin noise. References:
	// https://mrl.nyu.edu/~perlin/paper445.pdf
	// https://developer.nvidia.com/gpugems/gpugems/part-i-natural-effects/chapter-5-implementing-improved-perlin-noise
	// https://mrl.nyu.edu/~perlin/noise/
	vec3 uvw=new_normal*0.5+0.5;
	vec3 cube_xyz=mod(uvw/scale,1.0)*float(perlin_cubes);
	vec3 p=fract(cube_xyz),q=p-1.0;
	vec3 weight=interp_order5(p);

	ivec3 cube=ivec3(floor(cube_xyz))%perlin_cubes;
	ivec2 iuv = ivec2(cube.x+perlin_cubes*cube.y,cube.z);
	vec4 rhash = texelFetch(hash_cube,iuv,0);
	ivec4 ihash = ivec4(round(rhash*1024.0));

	float p000=perlin_grad1(ihash.r,p.x,p.y,p.z),p001=perlin_grad1(ihash.r>>4,q.x,p.y,p.z);
	float p010=perlin_grad1(ihash.g,p.x,q.y,p.z),p011=perlin_grad1(ihash.g>>4,q.x,q.y,p.z);
	float p100=perlin_grad1(ihash.b,p.x,p.y,q.z),p101=perlin_grad1(ihash.b>>4,q.x,p.y,q.z);
	float p110=perlin_grad1(ihash.a,p.x,q.y,q.z),p111=perlin_grad1(ihash.a>>4,q.x,q.y,q.z);
	
	vec4 px0 = vec4(p000,p010,p100,p110);
	vec4 px1 = vec4(p001,p011,p101,p111);
	vec4 py = mix(px0,px1,weight.x);
	vec2 pz = mix(py.xz,py.yw,weight.y);
	return mix(pz.x,pz.y,weight.z)/2.0;
}

float apply_perlin_type(float scale,vec3 new_normal) {
	float c=improved_perlin(scale,new_normal);
	if(perlin_type==1 || perlin_type==3)
		return abs(c);
	else if(perlin_type==10) // mix of types 1 and 0
		return 0.3*c + 0.7*abs(c);
	return c;
}

float multi_perlin_scalar(vec3 new_normal) {
	float result = 0.0;
	float weight=1.0;
	float scale=scale_start;
	float weight_sum = 0.0;
	for(int i=0;i<4;i++) {
		result += apply_perlin_type(scale,new_normal)*weight;
		weight_sum+=weight;
		weight*=weight_power;
		scale*=scale_power;
	}
	if(perlin_type==3)
		result = sin(7.0*(new_normal.y+result));
	result = 2.0*result/weight_sum;
	result += perlin_bias;
	return result;
}

void fragment() {
	vec4 xyzw = texture(xyz,vec2(UV.x,1.0-UV.y));
	if(xyzw.w>0.5) {
		vec3 normal = xyzw.xyz;
		float w = multi_perlin_scalar(normal);
		if(color_scheme==1)
			w=interp_order5_scalar(w);
		else
			w*=w;
		COLOR = vec4(w*color_scaling+color_addition,1.0);
	} else
		COLOR=vec4(0.7,0.7,0.7,1.0);
}