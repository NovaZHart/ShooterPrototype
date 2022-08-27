shader_type canvas_item;
render_mode skip_vertex_transform;
render_mode unshaded;

uniform sampler2D xyz;
uniform sampler2D temperature_cube8;
uniform sampler2D altitude_cube16;
uniform sampler2D cloud_cube16;
uniform sampler2D colors:hint_albedo;

uniform float altitude_weight_power = 0.473333;
uniform float cloud_mesoscale_weight_power = 0.573333;
uniform float cloud_synoptic_weight_power = 0.1;

uniform float scale_power = 0.3077;
uniform float scale_start = 3.9;

uniform sampler2D crater_data;
uniform int crater_count;
uniform float crater_scale = 0.3;

float apply_craters(float starting_height,vec3 xyz_norm) {
	float height = starting_height;
	for(int i=0;i<crater_count;i++) {
		ivec2 iuv = ivec2(i&15,i>>4);
		vec4 data = texelFetch(crater_data,iuv,0);
		float angular_size = data.w;
		if(angular_size<0.08726646259971647 || angular_size>1.4835298641951802)
			continue;
		vec3 center = data.xyz*2.0-1.0;
		float xyz_cos_angle = dot(xyz_norm,center);
		float min_cos_angle = cos(angular_size);
		if(xyz_cos_angle<min_cos_angle)
			continue;
		float crater_depth = (xyz_cos_angle-min_cos_angle)/(1.0-min_cos_angle);
		height-=crater_scale*crater_depth;
	}
	return height;
}

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

float improved_perlin(float scale,vec3 uvw,sampler2D hash_cube,int perlin_cubes) {
	// Improved Perlin noise. References:
	// https://mrl.nyu.edu/~perlin/paper445.pdf
	// https://developer.nvidia.com/gpugems/gpugems/part-i-natural-effects/chapter-5-implementing-improved-perlin-noise
	// https://mrl.nyu.edu/~perlin/noise/
	vec3 cube_xyz=mod(uvw/scale,1.0)*float(perlin_cubes);
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

vec3 perlin_linear(vec3 uvw,vec3 normal,int altitude_cloud_iterations) {
	vec4 result = vec4(0.0,0.0,0.0,0.0);
	vec3 weight=vec3(1.0,1.0,1.0);
	float scale=scale_start;
	vec3 weight_sum = vec3(0.0,0.0,0.0);
	for(int i=0;i<altitude_cloud_iterations;i++) {
		float q = improved_perlin(scale,uvw,altitude_cube16,16);
		float r = 0.0;
		if(i<2) {
			r = improved_perlin(scale,uvw,cloud_cube16,16);
		} else {
			r = q;
		}
		r = abs(r);
		float s = sin(8.0*(normal.y+r));
		result.xyz += vec3(q,r,s) * weight;
		weight_sum+=weight;
		weight*=vec3(altitude_weight_power,cloud_mesoscale_weight_power,cloud_synoptic_weight_power);
		scale*=scale_power;
	}
	result.w = improved_perlin(scale_start,uvw,temperature_cube8,8);
	return vec3(clamp(result.x/weight_sum.x +0.5,0.0,1.0),
		clamp((result.z/weight_sum.z*0.5+0.5) * (result.y/weight_sum.y) * 2.0, 0.0,1.0),
		clamp(result.w+0.5,0.0,1.0));
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
	vec4 xyzw = texture(xyz,vec2(UV.x,1.0-UV.y));
	if(xyzw.w>0.5) {
		vec3 normal = xyzw.xyz;
		vec3 uvw=normal*0.5+0.5;
		vec3 altitude_cloud_tpert = perlin_linear(uvw,normal,4);
		float altitude = clamp(altitude_cloud_tpert.x,0.0,1.0);
		//altitude = clamp(apply_craters(altitude*0.5+0.5,xyzw.xyz),0.0,1.0);
		float cloud = altitude_cloud_tpert.y;
		float temperature_perturbation = altitude_cloud_tpert.z;
		//float temperature_perturbation = clamp(perlin_linear(uvw,1,temperature_cube8,8),0.0,1.0);
		float mean_temperature = cos(normal.y*1.5707963267948966);
		float temperature = temperature_perturbation; //mix(temperature_perturbation,mean_temperature,0.2);
		temperature = 1.0-temperature;
		//temperature = min(temperature,mean_temperature);
		// Trick Godot into keeping a linear colorspace:
		vec4 result = mix(texture(colors,vec2(temperature,altitude)),vec4(1.0,1.0,1.0,1.0),cloud*cloud);
		//vec4 result = texture(colors,vec2(temperature,altitude));
		COLOR = srgb_to_linear(result);
	} else
		COLOR=vec4(0.0,0.0,0.0,1.0);
}