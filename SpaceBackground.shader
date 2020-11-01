shader_type canvas_item;
render_mode unshaded;

uniform int view_size_x;
uniform int view_size_y;
uniform int plasma_seed=12332;
uniform int plasma_min=2;
uniform int plasma_max=12;
uniform float plasma_exponent=1.1;
uniform float star_exponent=1.12;
uniform int star_seed=91312;
uniform int star_min=8;
uniform int star_max=18;
uniform vec3 color = vec3(0.4,0.4,1.0);
uniform bool make_plasma = true;
uniform bool make_stars = false;
uniform int pixels_per_star = 8000;

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

vec3 hsv2rgb(vec3 hsv) {
	vec3 rgb;
	if(hsv.y<1e-6)
	  return vec3(hsv.z,hsv.z,hsv.z);
	float hue=mod(hsv.x*6.0+12.0,6.0);
	int ihue=int(floor(hue))%6;
	float fhue=hue-float(ihue);
	float a=hsv.z*(1.0-hsv.y);
	float b=hsv.z*(1.0-hsv.y*fhue);
	float c=hsv.z*(1.0-hsv.y*(1.0-fhue));
	switch(ihue) {
		case 0: return vec3(hsv.z,c,a);
		case 1: return vec3(b,hsv.z,a);
		case 2: return vec3(a,hsv.z,c);
		case 3: return vec3(a,b,hsv.z);
		case 4: return vec3(c,a,hsv.z);
		default: return vec3(hsv.z,a,b);
	}
}

vec3 rgb2hsv(vec3 rgb) {
	float cmin=min(min(rgb.r,rgb.g),rgb.b);
	float cmax=max(max(rgb.r,rgb.g),rgb.b);
	vec3 hsv=vec3(0.0,0.0,cmax);
	float crange=cmax-cmin;
	if(crange<1e-6)
		return hsv;
	if(cmax<1e-6)
		return vec3(0.5,0.0,cmax);
	hsv.y=crange/cmax;
	if(rgb.r>cmax-1e-6)
		hsv.x=0.0+(rgb.g-rgb.b)/crange;
	else if(rgb.g>cmax-1e-6)
		hsv.x=2.0+(rgb.b-rgb.r)/crange;
	else if(rgb.b>cmax-1e-6)
		hsv.x=4.0+(rgb.r-rgb.g)/crange;
	hsv.x=mod(hsv.x,6.0)/6.0;
	return hsv;
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

vec4 scatter(int seed,vec2 uv) {
	vec2 f=vec2(1.0,1.0)/vec2(float(view_size_x),float(view_size_y));
	vec2 uvf=uv/f;
	ivec2 uvn=ivec2(floor(uvf));
	vec2 uvnf=uvf-vec2(uvn);
	vec4 result;
	int count;
	const int star_size=1;
	int hseed=bob_hash(seed);
	for(int iv=0;iv<1;iv++) {
		int iv0=(iv+uvn[1])%view_size_y;
		int ivh=bob_hash(iv0^hseed);
		for(int iu=0;iu<1;iu++) {
			int iu0=(iu+uvn[0])%view_size_x;
			int iuh=bob_hash(iu0^ivh);
			int pixel=iuh%(view_size_x*view_size_y);
			if(pixel/pixels_per_star==0) {
				// There is a star here.
				vec3 rgb=hsv2rgb(vec3(0.5+0.5*int2float(bob_hash(iuh)),0.2,0.8));
				float mag=exp(-distance(vec2(float(iu),float(iv)),uvnf)); //*rand[2];
				//vec3 hsv=vec3(rand[0],.8+rand[1]/5.0,mag);
				//vec3 rgb=hsv2rgb(hsv);
				count++;
				float c0=1.0/float(count),c1=1.0-c0;
				result=vec4(result.r+mag*rgb.r,result.g+mag*rgb.g,result.b+mag*rgb.b,min(1.0,max(result.a,mag)));
			}
		}
	}
	return result;
}

vec4 mult(int seed,vec2 uv,int min_scale,int max_scale,float weight_scale) {
	vec2 uvf;
	vec4 result=vec4(1.0,1.0,1.0,1.0);
	ivec2 uv0,uv1;
	float weight=1.0,w=1.0;
	for(int scale=max_scale;scale>=min_scale;scale/=2) {
		uv_decompose(scale,uv,uvf,uv0,uv1);
		vec2 uvw=0.5*(1.0-cos(fract(uvf)*3.141592653589793));
		w*=weight_scale;
		result=result*pow(colored_boxes(seed^scale,uvf,uv0,uv1,uvw),vec4(w,w,w,w));
		weight*=2.0;
	}
	return result*weight;
}

void light() {}

void fragment() {
	vec4 prgbw,m;
	vec3 prgb,mhsv,mrgb;
	if(make_plasma) {
		prgbw = plasma(plasma_seed,UV,2<<plasma_min,2<<plasma_max,plasma_exponent);
		prgb=vec3(prgbw.r*color.r,prgbw.g*color.g,prgbw.b*color.b)*pow(prgbw.w,3);
	}
	if(make_stars) {
		m = mult(star_seed,UV,2<<star_min,2<<star_max,star_exponent);
		//m = scatter(star_seed,UV);
		mhsv = rgb2hsv(vec3(m.r,m.g,m.b));
		mrgb = hsv2rgb(vec3(mhsv.x,mhsv.y/4.0,min(0.7,mhsv.z*mhsv.z)));
	}
	
	if(make_plasma) {
		if(make_stars) {
			vec3 combined=(mrgb*4.0+prgb)/5.0;
			COLOR=vec4(combined.r,combined.g,combined.b,1.0);
		} else
			COLOR=vec4(prgb.r/10.0,prgb.g/10.0,prgb.b/2.0,1.0);
	} else if(make_stars)
		//COLOR=vec4(mrgb.r*0.8,mrgb.g*0.8,mrgb.b*0.8,1.0); //step(m.a,0.02));
		//COLOR=vec4(pow(m.r,.25),pow(m.g,.25),pow(m.b,.25),step(m.a,0.25));
		COLOR=m;
	else
		COLOR=vec4(0.0,0.0,0.0,0.0);
}