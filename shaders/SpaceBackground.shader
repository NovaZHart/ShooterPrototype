shader_type canvas_item;
render_mode unshaded;

uniform int plasma_seed=12332;
uniform int plasma_min=2;
uniform int plasma_max=12;
uniform float plasma_exponent=1.1;
uniform vec4 color = vec4(0.4,0.4,1.0,1.0);


vec4 int2float4(ivec4 k) {
	ivec4 y = ivec4(1065353216,1065353216,1065353216,1065353216) | ivec4(8388607,8388607,8388607,8388607)&k;
	return intBitsToFloat(y)-1.0;
}

ivec2 hash2( ivec2 a) {
	a = (a ^ ivec2(61,61)) ^ (a >> 16);
	a = a + (a << 3);
	a = a ^ (a >> 4);
	a = a * 0x27d4eb2d;
	a = a ^ (a >> 15);
	return a;
}
ivec4 hash4( ivec4 a) {
	a = (a ^ ivec4(61,61,61,61)) ^ (a >> 16);
	a = a + (a << 3);
	a = a ^ (a >> 4);
	a = a * 0x27d4eb2d;
	a = a ^ (a >> 15);
	return a;
}

void uv_decompose(int isc,vec2 uv,inout vec2 uvf,inout ivec2 uv0,inout ivec2 uv1) {
	float fsc=float(isc);
	uvf=mod(uv*fsc,fsc);
	uv0=ivec2(floor(uvf));
	uv1=(uv0+1)%isc;
}

vec4 i2vec4(int hash) {
	return int2float4(hash4(ivec4(hash^8934792,hash^130317788,hash^22831963,hash^32313223)));
}

vec4 colored_boxes(int seed,vec2 uvf,ivec2 uv0,ivec2 uv1,vec2 uvw) {
	ivec2 h_uvNy = hash2(ivec2(uv0[1],uv1[1]));
	ivec4 h_uvNx_uvNy = hash4(ivec4(seed,seed,seed,seed)^hash4(
		ivec4(uv1.xx,uv0.xx) ^ ivec4(h_uvNy.yx,h_uvNy.yx)));
	vec4 c00=i2vec4(h_uvNx_uvNy[3]);
	vec4 c01=i2vec4(h_uvNx_uvNy[2]);
	vec4 c10=i2vec4(h_uvNx_uvNy[1]);
	vec4 c11=i2vec4(h_uvNx_uvNy[0]);
	return mix(mix(c00,c01,uvw[1]),mix(c10,c11,uvw[1]),uvw[0]);
}

vec4 plasma(int seed,vec2 uv,int min_scale,int max_scale,float weight_scale) {
	vec2 uvf;
	vec4 sum=vec4(0,0,0,0);
	ivec2 uv0,uv1;
	float wsum=0.0,weight=1.0;
	for(int scale=max_scale;scale>=min_scale;scale/=2) {
		uv_decompose(scale,uv,uvf,uv0,uv1);
		weight*=weight_scale;
		vec2 uvw=0.5*(1.0-cos(fract(uvf)*3.141592653589793));
		sum+=weight*colored_boxes(seed^scale,uvf,uv0,uv1,uvw);
		wsum+=weight;
	}
	return sum/wsum;
}

void fragment() {
	vec4 prgbw = plasma(plasma_seed,UV,2<<plasma_min,2<<plasma_max,plasma_exponent);
	COLOR = vec4(prgbw.rgb*color.rgb * (prgbw.w*prgbw.w*prgbw.w), 1.0);
}