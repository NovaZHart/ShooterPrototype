shader_type canvas_item;

uniform int seed=9876867;

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

float perlin_grad(int hash,float x,float y) {
	float theta=5.992112452678286e-06*float(hash&1048575);
	return x*cos(theta)-y*sin(theta);
}

vec2 interp_order5(vec2 t) {
	// fifth-order interpolant for improved perlin noise
	return t*t*t * (t * (t*6.0-15.0) + 10.0);
}

float improved_perlin(float scale,vec2 uv) {
	// Improved Perlin noise. References:
	// https://mrl.nyu.edu/~perlin/paper445.pdf
	// https://developer.nvidia.com/gpugems/gpugems/part-i-natural-effects/chapter-5-implementing-improved-perlin-noise
	// https://mrl.nyu.edu/~perlin/noise/
	vec2 scaled=uv*scale*64.0;
	ivec2 cube=ivec2(floor(scaled))%64;
	ivec2 next=(cube+1)%64;
	vec2 p=fract(scaled),q=p-1.0;
	vec2 weight=interp_order5(p);
	
	int h=bob_hash(seed);
	int h0=bob_hash(h^cube.x),h1=bob_hash(h^next.x);
	int h00=bob_hash(h0^cube.y),h01=bob_hash(h1^cube.y);
	int h10=bob_hash(h0^next.y),h11=bob_hash(h1^next.y);
	float p00=perlin_grad(h00,p.x,p.y);
	float p01=perlin_grad(h01,q.x,p.y);
	float p10=perlin_grad(h10,p.x,q.y);
	float p11=perlin_grad(h11,q.x,q.y);
	return mix(mix(p00,p01,weight.x),mix(p10,p11,weight.x),weight.y);
}

float fog(float scale,vec2 uv) {
	float s=scale;
	float r=improved_perlin(s,uv);
	float w=1.0,ws=w;
	for(int i=1;i<5;i++) {
		w*=0.5;
		s*=0.5;
		r+=improved_perlin(s,uv);
		ws+=w;
	}
	return r/ws;
}

float veins(float scale,vec2 uv) {
	float s=scale;
	float r=abs(improved_perlin(s,uv));
	float w=1.0,ws=w;
	for(int i=1;i<8;i++) {
		w*=0.5;
		s*=2.0;
		r+=abs(improved_perlin(s,uv));
		ws+=w;
	}
	return 1.0 - r/ws;
}

void fragment() {
	int iu=int(UV.x*1048576.0);
	int iv=int(UV.y*1048576.0);
	int n=bob_hash(iu^bob_hash(iv^bob_hash(seed)));
	float x=float((n&1044480)>>12)/256.0;
	float y=float((n&267386880)>>20)/256.0;
	float v=veins(2.0,UV);
	v*=v*v;
	float f=fog(2.0,UV);
	float intensity = (v*5.0+abs(f))/6.0;
	COLOR=vec4(x,y,intensity,1.0);
}