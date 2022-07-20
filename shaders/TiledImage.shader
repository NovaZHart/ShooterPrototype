shader_type spatial;
render_mode unshaded;

uniform sampler2D texture_albedo;
uniform sampler2D texture_starfield;
uniform vec2 texture_size;
uniform vec2 uv_offset;
uniform vec2 uv2_offset;
uniform vec2 uv_whole=vec2(1.0,1.0);
uniform vec2 uv2_whole=vec2(1.0,1.0);
uniform float uv_range=100.0;
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

vec3 star_overlay(vec2 uv) {
	float uv_scale=uv_range/uv_whole.y;
	float scale=clamp(uv_scale/5.0,0.02,0.2);
	vec2 uvs=uv/7.0, uvos=uv_offset/7.0, uvws=uv_whole;
	vec2 uv_base = mod(uvs+uvos,uvws);
	vec2 ftexel = uv_base*vec2(texture_size)/uvws+0.5;
	ivec2 itexel = ivec2(ftexel);
	vec2 within = fract(ftexel);
	vec4 star = texelFetch(texture_starfield,itexel,0);
	float dist=distance(within,scale+(1.0-2.0*scale)*star.xy);
	if(dist>scale)
		return vec3(0.0,0.0,0.0);
	float kelvin=star.x*10000.0+star.y*3000.0+500.0;
	float intensity=clamp((scale-dist)/scale*star.z,0.0,1.0);
	return kelvin_to_rgb(kelvin)*intensity;
	//return vec4(rgb.r,rgb.g,rgb.b,1.0)*intensity;
}

void fragment() {
	vec3 star=star_overlay(UV);
	vec3 hires = texture(texture_albedo,mod(UV+uv_offset,1.0)).rgb;
	//vec3 hires2 = texture(texture_albedo,mod(4.0*(UV+uv_offset),1.0)).rgb;
	vec3 lores = texture(texture_albedo,mod(UV2+uv2_offset,1.0)).rgb;
	vec3 lohi = 0.25*lores + 0.35*hires; // + 0.4*hires2;
	ALBEDO=max(lohi.rgb,star.rgb);
}