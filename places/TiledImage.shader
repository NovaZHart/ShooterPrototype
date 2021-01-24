shader_type spatial;
render_mode unshaded;

uniform sampler2D texture_albedo;
uniform sampler2D texture_starfield;
uniform vec2 texture_size;
uniform vec2 uv_offset;
uniform vec2 uv2_offset;
uniform vec2 uv_whole=vec2(1.0,1.0);
uniform vec2 uv2_whole=vec2(1.0,1.0);
uniform vec2 uv_range=vec2(0.0,1.0);
uniform vec2 uv2_range=vec2(0.0,100.0);
uniform vec2 star_patch_size=vec2(16.0,16.0);
//uniform int seed=12332;
//uniform vec2 uv_scale;
//uniform int samples;
//uniform float star_density=3.0;

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

float h20float(int hash) {
	const float denom=1.0/1048576.0;
	return float(hash&1048575)*denom;
}

vec4 bilinear_interp_texture(vec2 uv,sampler2D img,vec2 img_size,vec2 offset,vec2 uv_all) {
	vec2 uv_base = mod(uv+offset,uv_all);
	
	vec2 fsize = img_size;
	ivec2 isize = ivec2(img_size);
	vec2 duv = vec2(1.0,1.0)/fsize;
	vec2 fuv = mod(uv_base-.5,duv)*fsize;
	ivec2 iuv0 = ivec2(floor((uv_base+.5)/duv))%isize, iuv1 = (iuv0+1)%isize;
	vec2 uv0 = vec2(iuv0)+0.5, uv1 = vec2(iuv1)+0.5;
	vec4 c00 = texture(img,vec2(uv0[0]/fsize[0],uv0[1]/fsize[1]));
	vec4 c01 = texture(img,vec2(uv0[0]/fsize[0],uv1[1]/fsize[1]));
	vec4 c10 = texture(img,vec2(uv1[0]/fsize[0],uv0[1]/fsize[1]));
	vec4 c11 = texture(img,vec2(uv1[0]/fsize[0],uv1[1]/fsize[1]));
	return mix(mix(c00,c10,fuv[0]),mix(c01,c11,fuv[0]),fuv[1]);
}

vec4 nearest_neighbor(vec2 uv,sampler2D img,vec2 img_size,vec2 offset,vec2 uv_all) {
	vec2 uv_base = mod(uv+offset,uv_all);
	
	vec2 fsize = img_size;
	ivec2 isize = ivec2(img_size);
	vec2 duv = vec2(1.0,1.0)/fsize;
	vec2 fuv = mod(uv_base-.5,duv)*fsize;
	ivec2 iuv0 = ivec2(floor((uv_base+.5)/duv))%isize, iuv1 = (iuv0+1)%isize;
	vec2 uv0 = vec2(iuv0)+0.5, uv1 = vec2(iuv1)+0.5;
	if(fuv[0]<0.5) {
		if(fuv[1]<0.5)
			return texture(img,vec2(uv0[0]/fsize[0],uv0[1]/fsize[1]));
		else
			return texture(img,vec2(uv0[0]/fsize[0],uv1[1]/fsize[1]));
	} else {
		if(fuv[1]<0.5)
			return texture(img,vec2(uv1[0]/fsize[0],uv0[1]/fsize[1]));
		else
			return texture(img,vec2(uv1[0]/fsize[0],uv1[1]/fsize[1]));
	}
}

vec4 interp_16point(vec2 uv,sampler2D img,vec2 img_size,vec2 offset,vec2 uv_all) {
	float weight;
	vec4 result;
	
	vec2 uv_base = mod(uv+offset,uv_all);
	vec2 uv2img = img_size;
	vec2 img2uv = vec2(1.0,1.0)/uv2img;
	vec2 img_at = uv_base*uv2img, img_at0 = floor(img_at)+0.5;
	
	const int stencil_width=2;
	
	const float exp_pre[4]={
		0.36787944117144233, 1.0, 0.36787944117144233, 0.01831563888873418
	};
	
	float mul_j=(img_at[1]-img_at0[1])/float(stencil_width);
	float exp_j = exp(-mul_j*mul_j*4.0);
	
	float mul_i = (img_at[0]-img_at0[0])/float(stencil_width);
	float exp_i = exp(-mul_i*mul_i*4.0);
	
	for(int j=-stencil_width+1;j<=stencil_width;j++) {
		float j_stencil=img_at0[1]+float(j);
		//float j_weight=1.+cos((img_at[1]-j_stencil)/float(stencil_width+1)*3.14159);
		float j_weight=exp_j*exp_pre[j-1+stencil_width];
		float v_stencil=mod(j_stencil*img2uv[1],1.0);
		for(int i=-stencil_width+1;i<=stencil_width;i++) {
			float i_stencil=img_at0[0]+float(i);
			//float i_weight=1.+cos((img_at[0]-i_stencil)/float(stencil_width+1)*3.14159);
			float i_weight=exp_i*exp_pre[i-1+stencil_width];
			float u_stencil=mod(i_stencil*img2uv[0],1.0);
			float stencil_weight=i_weight*j_weight;
			result += stencil_weight*texture(img,vec2(u_stencil,v_stencil));
			weight += stencil_weight;
		}
	}
	return result/weight;
}

vec4 interp_36point(vec2 uv,sampler2D img,vec2 img_size,vec2 offset,vec2 uv_all) {
	float weight;
	vec4 result;
	
	vec2 uv_base = mod(uv+offset,uv_all);
	vec2 uv2img = img_size;
	vec2 img2uv = vec2(1.0,1.0)/uv2img;
	vec2 img_at = uv_base*uv2img, img_at0 = floor(img_at)+0.5;
	
	const int stencil_width=3;
	const float exp_pre[6]={
		0.1690133154060661, 0.6411803884299546, 1.0, 
		0.6411803884299546, 0.1690133154060661, 0.01831563888873418
	};
	
	float mul_j=(img_at[1]-img_at0[1])/float(stencil_width);
	float exp_j = exp(-mul_j*mul_j*4.0);
	
	float mul_i = (img_at[0]-img_at0[0])/float(stencil_width);
	float exp_i = exp(-mul_i*mul_i*4.0);
	
	for(int j=-stencil_width+1;j<=stencil_width;j++) {
		float j_stencil=img_at0[1]+float(j);
		//float j_weight=1.+cos((img_at[1]-j_stencil)/float(stencil_width+1)*3.14159);
		float j_weight=exp_j*exp_pre[j-1+stencil_width];
		float v_stencil=mod(j_stencil*img2uv[1],1.0);
		for(int i=-stencil_width+1;i<=stencil_width;i++) {
			float i_stencil=img_at0[0]+float(i);
			//float i_weight=1.+cos((img_at[0]-i_stencil)/float(stencil_width+1)*3.14159);
			float i_weight=exp_i*exp_pre[i-1+stencil_width];
			float u_stencil=mod(i_stencil*img2uv[0],1.0);
			float stencil_weight=i_weight*j_weight;
			result += stencil_weight*texture(img,vec2(u_stencil,v_stencil));
			weight += stencil_weight;
		}
	}
	return result/weight;
}

vec4 draw_texture(vec2 uv,sampler2D img,vec2 img_size,vec2 offset,vec2 uv_all,vec2 viewport_size,vec2 uv_rng) {
	float psize=uv_rng[1]/viewport_size[1];
	vec2 tsize=psize*img_size;
	float tmax=max(tsize[0],tsize[1]);
	if(tmax>2.0)
		return interp_36point(uv,img,img_size,offset,uv_all);
	if(tmax>1.0)
		return interp_16point(uv,img,img_size,offset,uv_all);
	return bilinear_interp_texture(uv,img,img_size,offset,uv_all);
}

vec3 kelvin_to_rgb(float kelvin) {
	if(kelvin<1000.0)
		return mix(vec3(0.5,0.0,0.0),vec3(1.0,0.2,0.0),kelvin/1000.0);
	else if(kelvin<4000.0)
		return mix(vec3(1.0,0.2,0.0),vec3(1.0,0.8,0.6),(kelvin-1000.0)/3000.0);
	else if(kelvin<6600.0)
		return mix(vec3(1.0,0.8,0.6),vec3(1.0,1.0,1.0),(kelvin-4000.0)/2600.0);
	else if(kelvin<40000.0)
		return mix(vec3(1.0,1.0,1.0),vec3(0.6,0.75,1.0),(kelvin-6600.0)/33400.0);
	else if(kelvin<1e6)
		return mix(vec3(0.6,0.75,1.0),vec3(0.0,0.0,0.5),kelvin/1e6);
	return vec3(0.0,0.0,0.5);
}

vec4 star_overlay(vec2 uv) {
	float uv_scale=(uv_range[1]-uv_range[0])/uv_whole.y;
	float scale=clamp(uv_scale/5.0,0.02,0.2);
	vec2 uvs=uv/7.0, uvos=uv_offset/7.0, uvws=uv_whole;
	vec2 uv_base = mod(uvs+uvos,uvws);
	vec2 ftexel = uv_base*vec2(texture_size)/uvws+0.5;
	ivec2 itexel = ivec2(ftexel);
	vec2 within = fract(ftexel);
	vec4 star = texelFetch(texture_starfield,itexel,0);
	float dist=distance(within,scale+(1.0-2.0*scale)*star.xy);
	if(dist>scale)
		return vec4(0.0,0.0,0.0,0.0);
	float kelvin=star.x*10000.0+star.y*3000.0+500.0;
	float intensity=clamp((scale-dist)/scale*star.z,0.0,1.0);
	vec3 rgb = kelvin_to_rgb(kelvin);
	return vec4(rgb.r,rgb.g,rgb.b,1.0)*intensity;
}

void fragment() {
	vec4 low_res_texture=bilinear_interp_texture(UV,texture_albedo,texture_size,uv_offset,uv_whole);
	vec4 high_res_texture=bilinear_interp_texture(UV2,texture_albedo,texture_size,uv2_offset,uv2_whole);
	vec4 star=star_overlay(UV);
	vec4 lohi=mix(low_res_texture,high_res_texture,.3);
	ALBEDO=max(lohi.rgb,star.rgb);
}