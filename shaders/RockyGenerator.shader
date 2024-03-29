shader_type canvas_item;
render_mode skip_vertex_transform;
render_mode unshaded;
render_mode blend_disabled;

uniform sampler2D xyz;
uniform sampler2D texture_cube16;
uniform sampler2D coloring_cube16;

uniform float weight_power = 0.42;
uniform float invscale_power = 2.5;
uniform float invscale_start = 0.486;

float perlin_grad1c(int hash,float x,float y,float z) {
	// Gradients for improved perlin noise.
	// Get gradient at cube corner specified by p
	int h=hash&15;
	float u,v;
	u = h<8 ? x : y;
	v = (h<4) ? y : ((h==12||h==14) ? x : z);
	return ((h&1) == 0 ? u : -u) + ((h&2) == 0 ? v : -v);	
}

float improved_perlin(float invscale,vec3 uvw,sampler2D hash_cube,int perlin_cubes) {
	// Improved Perlin noise. References:
	// https://mrl.nyu.edu/~perlin/paper445.pdf
	// https://developer.nvidia.com/gpugems/gpugems/part-i-natural-effects/chapter-5-implementing-improved-perlin-noise
	// https://mrl.nyu.edu/~perlin/noise/
	vec3 cube_xyz=mod(uvw*invscale,1.0)*float(perlin_cubes);
	vec3 p=fract(cube_xyz),q=p-1.0;
	vec3 weight=p*p*p * (p * (p*6.0-15.0) + 10.0);

	ivec3 cube=ivec3(floor(cube_xyz))%perlin_cubes;
	ivec2 iuv = ivec2(cube.x+perlin_cubes*cube.y,cube.z);
	vec4 rhash = texelFetch(hash_cube,iuv,0);
	ivec4 ihash = ivec4(round(rhash*1024.0));

	float p000=perlin_grad1c(ihash.r,p.x,p.y,p.z),p001=perlin_grad1c(ihash.r>>4,q.x,p.y,p.z);
	float p010=perlin_grad1c(ihash.g,p.x,q.y,p.z),p011=perlin_grad1c(ihash.g>>4,q.x,q.y,p.z);
	float p100=perlin_grad1c(ihash.b,p.x,p.y,q.z),p101=perlin_grad1c(ihash.b>>4,q.x,p.y,q.z);
	float p110=perlin_grad1c(ihash.a,p.x,q.y,q.z),p111=perlin_grad1c(ihash.a>>4,q.x,q.y,q.z);
	
	vec4 px0 = vec4(p000,p010,p100,p110);
	vec4 px1 = vec4(p001,p011,p101,p111);
	vec4 py = mix(px0,px1,weight.x);
	vec2 pz = mix(py.xz,py.yw,weight.y);
	return mix(pz.x,pz.y,weight.z);
}

vec3 perlin_linear(vec3 uvw,vec3 normal,int iterations) {
	vec3 result = vec3(0.0,0.0,0.5);
	float weight = 1.0;
	float invscale = invscale_start;
	float weight_sum = 0.0;
	for(int i=0;i<iterations;i++) {
		result.x += improved_perlin(invscale,uvw,texture_cube16,16)*weight;
		result.y += abs(improved_perlin(invscale,uvw,coloring_cube16,16)*1.414)*weight;
		weight_sum += weight;
		weight *= weight_power;
		invscale *= invscale_power;
	}
	result /= weight_sum;
	return vec3(clamp(result.x,-1.0,1.0)*0.5+0.5,clamp(result.y,0.0,1.0),result.z);
}

void fragment() {
	vec4 xyzw = texture(xyz,vec2(UV.x,1.0-UV.y));
	if(xyzw.w>0.5) {
		vec3 normal = xyzw.xyz;
		vec3 uvw=normal*0.5+0.5;
		vec3 noise = vec3(0.0,0.7,0.7);
		noise = perlin_linear(uvw,normal,5);
		COLOR=vec4(noise,1.0);
	} else
		COLOR=vec4(0.5,0.5,0.5,1.0);
}
