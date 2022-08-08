shader_type canvas_item;
render_mode skip_vertex_transform;
render_mode unshaded;

uniform sampler2D xyz;
uniform sampler2D texture_cube16;
uniform sampler2D stripe_cube8;
uniform sampler2D colors;

uniform float sin_mult = 60.0;
uniform float yscale = 1.0; //6.7770534;
uniform float starting_weight_power = 0.25;
uniform float weight_power_power = 1.6;
uniform float invscale_power = 3.1707;
uniform float invscale_start = 0.307714;

float perlin_grad1c(int hash,float x,float y,float z) {
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

float interp_order5_scalar(float t) {
	// fifth-order interpolant for improved perlin noise
	return t*t*t * (t * (t*6.0-15.0) + 10.0);
}

float improved_perlin(vec3 invscale,vec3 uvw,sampler2D hash_cube,int perlin_cubes) {
	// Improved Perlin noise. References:
	// https://mrl.nyu.edu/~perlin/paper445.pdf
	// https://developer.nvidia.com/gpugems/gpugems/part-i-natural-effects/chapter-5-implementing-improved-perlin-noise
	// https://mrl.nyu.edu/~perlin/noise/
	vec3 cube_xyz=mod(uvw*invscale,1.0)*float(perlin_cubes);
	vec3 p=fract(cube_xyz),q=p-1.0;
	vec3 weight=interp_order5(p);

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

float perlin_linear(vec3 uvw,vec3 normal,int iterations) {
	float result = 0.0;
	float weight = 1.0;
	float invscale = invscale_start;
	float weight_sum = 0.0;
	float weight_power = starting_weight_power;
	for(int i=0;i<iterations;i++) {
		weight_sum+=weight;
		float w = clamp(weight,0.0,1.0);
		vec3 invscale3 = vec3(invscale,yscale*invscale,invscale);
		float perlin = improved_perlin(invscale3,uvw,texture_cube16,16);
		float stripes = (0.5*sin(sin_mult*(mix(perlin,normal.y,0.95*w)))+0.5);
		float noise = clamp(interp_order5_scalar(abs(perlin)*2.0),0.0,1.0);
		result += weight * mix(noise,stripes,pow(w,1.5));
		weight*=weight_power;
		weight_power*=weight_power_power;
		invscale*=invscale_power;
	}
	return result/weight_sum;
}

float srgb_to_linear_scalar(float srgb) {
	if(srgb<=0.04045)
		return srgb/12.92;
	else
		return pow((srgb+0.055)/1.055,2.4);
}

vec4 srgb_to_linear(vec4 what) {
	return vec4(
		srgb_to_linear_scalar(what.r),
		srgb_to_linear_scalar(what.g),
		srgb_to_linear_scalar(what.b),
		srgb_to_linear_scalar(what.a));
}

void fragment() {
	vec3 normal = texture(xyz,vec2(UV.x,1.0-UV.y)).xyz;
	vec3 uvw=normal*0.5+0.5;
	if(UV.x<=0.75) {
		float p = clamp(perlin_linear(uvw,normal,5),0.0,1.0);
		// Trick Godot into keeping a linear colorspace:
		COLOR = srgb_to_linear(vec4(texture(colors,vec2(0.5,p)).xyz,1.0));
	} else
		COLOR=vec4(0.7,0.7,0.7,1.0);
}
