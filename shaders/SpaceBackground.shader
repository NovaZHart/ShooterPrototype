shader_type canvas_item;
render_mode unshaded;

uniform int plasma_seed=12332;
uniform int plasma_min=2;
uniform int plasma_max=12;
uniform float plasma_exponent=1.1;
uniform vec4 color = vec4(0.4,0.4,1.0,1.0);

// 32-bit integer hash from https://burtleburtle.net/bob/hash/integer.html
// which is public domain as of this writing (September 2020)
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

float int2float(int k) {
	int y = 1065353216|8388607&k;
	return intBitsToFloat(y)-1.0;
}

void uv_decompose(int isc,vec2 uv,inout vec2 uvf,inout ivec2 uv0,inout ivec2 uv1) {
	float fsc=float(isc);
	uvf=mod(uv*fsc,fsc);
	uv0=ivec2(floor(uvf));
	uv1=(uv0+1)%isc;
}

vec4 i2vec4(int uvx,int uvy,int seed) {
	int hash=bob_hash(seed^bob_hash(uvx^bob_hash(uvy)));
	return vec4(int2float(hash),int2float(bob_hash(hash^1)),int2float(bob_hash(hash^2)),int2float(bob_hash(hash^3)));
}

vec4 colored_boxes(int seed,vec2 uvf,ivec2 uv0,ivec2 uv1,vec2 uvw) {
	vec4 c00=i2vec4(uv0[0],uv0[1],seed);
	vec4 c01=i2vec4(uv0[0],uv1[1],seed);
	vec4 c10=i2vec4(uv1[0],uv0[1],seed);
	vec4 c11=i2vec4(uv1[0],uv1[1],seed);
	return mix(mix(c00,c01,uvw[1]),mix(c10,c11,uvw[1]),uvw[0]);
}

vec4 plasma(int seed,vec2 uv,int min_scale,int max_scale,float weight_scale) {
	vec2 uvf;
	vec4 sum;
	ivec2 uv0,uv1;
	float wsum,weight=1.0;
	for(int scale=max_scale;scale>=min_scale;scale/=2) {
		uv_decompose(scale,uv,uvf,uv0,uv1);
		weight*=weight_scale;
		vec2 uvw=0.5*(1.0-cos(fract(uvf)*3.141592653589793));
		sum+=weight*colored_boxes(seed^scale,uvf,uv0,uv1,uvw);
		wsum+=weight;
	}
	return sum/wsum;
}

void light() {}

void fragment() {
	vec4 prgbw;
	vec3 prgb;
	prgbw = plasma(plasma_seed,UV,2<<plasma_min,2<<plasma_max,plasma_exponent);
	prgb=vec3(prgbw.r*color.r,prgbw.g*color.g,prgbw.b*color.b)*prgbw.w*prgbw.w*prgbw.w;
	COLOR=vec4(prgb.r,prgb.g,prgb.b,1.0);
}