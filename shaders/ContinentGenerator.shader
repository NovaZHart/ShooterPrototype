shader_type canvas_item;
render_mode skip_vertex_transform;
//render_mode unshaded;

uniform sampler2D xyz;
uniform sampler2D cube8;
uniform sampler2D cube16;
uniform sampler2D colors;

// blue planet
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

float improved_perlin(float scale,vec3 new_normal,sampler2D hash_cube,int perlin_cubes) {
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
	return mix(pz.x,pz.y,weight.z);
}

float multi_perlin_scalar(vec3 new_normal,int iterations,sampler2D hash_cube,int perlin_cubes) {
	float result = 0.0;
	float weight=1.0;
	float scale=scale_start;
	float weight_sum = 0.0;
	for(int i=0;i<iterations;i++) {
		result += improved_perlin(scale,new_normal,hash_cube,perlin_cubes)*weight;
		weight_sum+=weight;
		weight*=weight_power;
		scale*=scale_power;
	}
	result = result/weight_sum*2.0;
	return (result+1.0)*0.5;
}

void fragment() {
	vec3 normal = texture(xyz,vec2(UV.x,1.0-UV.y)).xyz;
	COLOR=vec4(0.7,0.7,0.7,1.0);
	if(UV.x<=0.75) {
		float altitude = clamp(multi_perlin_scalar(normal,4,cube16,16),0.0,1.0);
		float temperature_perturbation = clamp(multi_perlin_scalar(normal,1,cube8,8),0.0,1.0);
		float mean_temperature = cos(normal.y*3.14159);
		//mean_temperature*=mean_temperature;
		float temperature = mix(temperature_perturbation,mean_temperature,0.2);
		COLOR = texture(colors,vec2(temperature,altitude));
	}
}