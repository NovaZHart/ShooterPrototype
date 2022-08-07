shader_type canvas_item;
render_mode skip_vertex_transform;
render_mode unshaded;

uniform sampler2D xyz;
uniform sampler2D texture_cube16;
uniform sampler2D inferno_cube8;
uniform sampler2D colors;

uniform float weight_power = 0.43333;
uniform float invscale_power = 2.156388034665918;
uniform float invscale_start = 0.48641025641025644;
uniform float perlin_bias = 0.5;

float perlin_grad1c(int hash,float x,float y,float z) {
	// Gradients for improved perlin noise.
	// Get gradient at cube corner specified by p
	switch(hash&15) {
		case 0: return  x +y;
		case 1: return -x +y;
		case 2: return  x -y;
		case 3: return -x -y;
		case 4: return  x +z;
		case 5: return -x +z;
		case 6: return  x -z;
		case 7: return -x -z;
		case 8: return  y +z;
		case 9: return -y +z;
		case 10:return  y -z;
		case 11:return -y -z;
		case 12:return  y +x;
		case 13:return -y +z;
		case 14:return  y -x;
		case 15:return -y -z;
	}
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

float crabs(float f) {
	return f>0.0 ? f : f*0.1;
}

float perlin_linear(vec3 uvw,vec3 normal,int iterations) {
	float result = 0.0;
	float weight = 1.0;
	float invscale = invscale_start;
	float weight_sum = 0.0;
	for(int i=0;i<iterations;i++) {
		if(i<3) {
			vec3 invscale3 = vec3(invscale,3.0*invscale,invscale);
			float f = improved_perlin(invscale3,uvw,inferno_cube8,8);
			result += (0.5*sin(7.0*(normal.y+f))+0.5) * weight;
		} else {
			vec3 invscale3 = vec3(invscale,invscale,invscale);
			float f = min(1.0,abs(improved_perlin(invscale3,uvw,texture_cube16,16)));
			f = interp_order5_scalar(1.0-f);
			result += f * weight;
		}
		weight_sum+=weight;
		weight*=weight_power;
		invscale*=invscale_power;
	}
	return result/weight_sum;
}

void fragment() {
	vec3 normal = texture(xyz,vec2(UV.x,1.0-UV.y)).xyz;
	vec3 uvw=normal*0.5+0.5;
	if(UV.x<=0.75) {
		float p = clamp(perlin_linear(uvw,normal,5),0.0,1.0);
		p*=p*p;
		COLOR = vec4(p,p*0.5,p*0.5,1.0);
	} else
		COLOR=vec4(0.7,0.7,0.7,1.0);
}
