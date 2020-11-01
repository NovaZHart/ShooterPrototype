shader_type canvas_item;

uniform int seed=123123; //-915;
uniform int plasma_min_scale=0;
uniform int plasma_max_scale=6;
uniform float plasma_weight_scale=0.85;
uniform int method=0;
uniform int perlin_cubes=9;

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

float int2float(int k) { // float [0,1) from 23 lower bits of int
	//float f=float(k&8388607)/8388608.0;
	uint y = uint(1065353216)|uint(8388607)&uint(k);
	float f = uintBitsToFloat(y)-1.0;
	if(f<-.0001 || f>1.0001)
		return 9999999.9;
	return f;
}

vec2 fuv2d(vec3 uv) { // convert 3d spatial coords to 2d texture coords
	//return ivec2(iuv.x&63 | ((iuv.z&7)<<6), iuv.y&63 | ((iuv.z&56)<<3));
	float z=mod(uv.z,64.0);
	float x=mod(uv.x,64.0) + floor(z/8.0)*64.0;
	float y=mod(-(mod(uv.y,64.0)+mod(z,8.0)*64.0),512.0);
	return vec2(x,y);
}

vec3 fuv3d(vec2 uv) { // convert 2d texture coords to 3d spatial coords
	//return ivec3(iuv.x&63,iuv.y&63,((iuv.x&448)>>6) | ((iuv.y&48)>>3));
	float y=mod(-uv.y,512.0);
	return vec3(mod(uv.x,64.0),mod(y,64.0),floor(uv.x/64.0)*8.0+floor(y/64.0));
}

ivec2 iuv2d(ivec3 iuv) { // convert 3d spatial coords to 2d texture coords
	//return ivec2(iuv.x&63 | ((iuv.z&7)<<6), iuv.y&63 | ((iuv.z&56)<<3));
	int z=iuv.z%64;
	return ivec2(iuv.x%64 + (z/8)*64,(-(iuv.y%64+(z%8)*64))%512);
}

ivec3 iuv3d(ivec2 iuv) { // convert 2d texture coords to 3d spatial coords
	//return ivec3(iuv.x&63,iuv.y&63,((iuv.x&448)>>6) | ((iuv.y&48)>>3));
	int y=511-iuv.y; //(-iuv.y)&1023;
	return ivec3(iuv.x%64,y%64,(iuv.x/64)*8+y/64);
}

vec4 color(int hseed,ivec3 iuv) { // random color for spatial coord
	ivec2 tex=iuv2d(iuv);
	int red=bob_hash(tex.x^bob_hash(tex.y^hseed));
	int green=bob_hash(red^3081777);
	int blue=bob_hash(green^9160414);
	int alpha=bob_hash(blue^5821387);
	return vec4(int2float(red),int2float(green),int2float(blue),int2float(alpha));
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

vec4 perlin_grad4(int hash,float x,float y,float z) {
	// Four color version of perlin_grad1
	return vec4(
		perlin_grad1(hash,x,y,z),
		perlin_grad1(hash>>4,x,y,z),
		perlin_grad1(hash>>8,x,y,z),
		perlin_grad1(hash>>12,x,y,z));
}

vec4 improved_perlin(int perlin_seed,vec2 uv) {
	// Improved Perlin noise. References:
	// https://mrl.nyu.edu/~perlin/paper445.pdf
	// https://developer.nvidia.com/gpugems/gpugems/part-i-natural-effects/chapter-5-implementing-improved-perlin-noise
	// https://mrl.nyu.edu/~perlin/noise/
	vec2 uvflip=vec2(uv.x,1.0-uv.y);
	int cubes=perlin_cubes;
	int per_cube=63/cubes;
	vec2 tex2d_uv=uv*512.0;
	ivec2 tex2d_iuv=ivec2(floor(uv*512.0));
	ivec3 tex3d_iuvw=iuv3d(tex2d_iuv);
	vec3 tex3d_uvw=fuv3d(tex2d_uv);
	vec3 cube_xyz=mod(tex3d_uvw/float(per_cube),float(cubes));
	ivec3 cube_ixyz=ivec3(floor(cube_xyz))%cubes;
	ivec3 next_ixyz=(cube_ixyz+1)%cubes;
	vec3 p=fract(cube_xyz),q=p-1.0;
	vec3 weight=interp_order5(p);
	
	int hseed=bob_hash(perlin_seed);
	int h0=bob_hash(hseed^cube_ixyz.x),h1=bob_hash(hseed^next_ixyz.x);
	int h00=bob_hash(h0^cube_ixyz.y),h01=bob_hash(h1^cube_ixyz.y);
	int h10=bob_hash(h0^next_ixyz.y),h11=bob_hash(h1^next_ixyz.y);
	int h000=bob_hash(h00^cube_ixyz.z),h001=bob_hash(h01^cube_ixyz.z);
	int h010=bob_hash(h10^cube_ixyz.z),h011=bob_hash(h11^cube_ixyz.z);
	int h100=bob_hash(h00^next_ixyz.z),h101=bob_hash(h01^next_ixyz.z);
	int h110=bob_hash(h10^next_ixyz.z),h111=bob_hash(h11^next_ixyz.z);
	vec4 p000=perlin_grad4(h000,p.x,p.y,p.z),p001=perlin_grad4(h001,q.x,p.y,p.z);
	vec4 p010=perlin_grad4(h010,p.x,q.y,p.z),p011=perlin_grad4(h011,q.x,q.y,p.z);
	vec4 p100=perlin_grad4(h100,p.x,p.y,q.z),p101=perlin_grad4(h101,q.x,p.y,q.z);
	vec4 p110=perlin_grad4(h110,p.x,q.y,q.z),p111=perlin_grad4(h111,q.x,q.y,q.z);
	vec4 x=mix(mix(mix(p000,p001,weight.x),mix(p010,p011,weight.x),weight.y),
	           mix(mix(p100,p101,weight.x),mix(p110,p111,weight.x),weight.y),weight.z)/4.0+0.5;
	return x;
}

vec4 plasma3d(int plasma_seed,vec2 uv,int min_scale,int max_scale,float weight_scale) {
	ivec2 iuv2=ivec2(floor(uv*512.0));
	ivec3 iuv=iuv3d(iuv2);
	vec3 fuv = vec3(iuv);
	int hseed=bob_hash(plasma_seed);
	vec4 sum;
	vec4 bad=vec4(-9.9,-9.9,-9.9,-9.9);
	float weight=1.0,wsum;
	if(min_scale<1) {
		sum=color(hseed,iuv);
		wsum+=weight;
		min_scale=1;
	}
	if(max_scale>7)
		max_scale=7;
	for(int scale=min_scale;scale<=max_scale;scale++) {
		weight*=weight_scale;
		ivec3 kuv=iuv>>scale;
		ivec3 ul=kuv<<scale, lr=((kuv+1)<<scale)%64;
		vec3 iw = vec3(iuv%(1<<(scale+1)))/float(1<<(scale+1));
		ivec3 i000 = ivec3(ul.x,ul.y,ul.z);
		ivec3 i001 = ivec3(ul.x,ul.y,lr.z);
		ivec3 i010 = ivec3(ul.x,lr.y,ul.z);
		ivec3 i011 = ivec3(ul.x,lr.y,lr.z);
		ivec3 i100 = ivec3(lr.x,ul.y,ul.z);
		ivec3 i101 = ivec3(lr.x,ul.y,lr.z);
		ivec3 i110 = ivec3(lr.x,lr.y,ul.z);
		ivec3 i111 = ivec3(lr.x,lr.y,lr.z);
		sum += weight * mix(
			mix(mix(color(hseed,i000),color(hseed,i001),iw.z),
				mix(color(hseed,i010),color(hseed,i011),iw.z),iw.y),
			mix(mix(color(hseed,i100),color(hseed,i101),iw.z),
				mix(color(hseed,i110),color(hseed,i111),iw.z),iw.y),iw.x);
		wsum+=weight;
	}
	return sum/wsum;
}

void fragment() {
	//COLOR=plasma3d(seed,UV,plasma_min_scale,plasma_max_scale,plasma_weight_scale);
	COLOR=improved_perlin(seed,UV);
}