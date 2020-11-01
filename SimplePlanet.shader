shader_type spatial;
render_mode skip_vertex_transform;

uniform bool normal_map=true;
uniform int perlin_seed=9;
uniform int perlin_type=0;
uniform int perlin_cubes=8;
uniform sampler2D precalculated;
uniform vec3 color_scaling=vec3(1.2,0.9,0.6);
uniform vec3 color_addition=vec3(0.5,0.4,0.2);
uniform int color_scheme=2;

float interp_order5_scalar(float t) {
	// fifth-order interpolant for improved perlin noise
	return t*t*t * (t * (t*6.0-15.0) + 10.0);
}

vec3 sphere_normal_from_uv(vec2 uv,int tile) {
	const float pi=3.141592653589793238;
	vec2 ij = tan(pi/2.0*(fract(uv*4.0)-0.5))/sqrt(2.0);
	vec3 side = vec3( ij.x, ij.y, 1.0/sqrt(2.0) );
	
	if(tile==5)
		side = transpose(mat3(vec3(1.0,0.0,0.0),vec3(0.0,0.0,-1.0),vec3(0.0,1.0,0.0)))*side;
	else if(tile==4)
		side = transpose(mat3(vec3(0.0,0.0,-1.0),vec3(0.0,1.0,0.0),vec3(1.0,0.0,0.0)))*side;
	else if(tile==2)
		side = transpose(mat3(vec3(0.0,0.0,1.0),vec3(0.0,1.0,0.0),vec3(-1.0,0.0,0.0)))*side;
	else if(tile==3)
		side = transpose(mat3(vec3(-1.0,0.0,0.0),vec3(0.0,1.0,0.0),vec3(-0.0,0.0,-1.0)))*side;
	else if(tile==6)
		side = transpose(mat3(vec3(1.0,0.0,0.0),vec3(0.0,0.0,1.0),vec3(0.0,-1.0,0.0)))*side;
	return normalize(side);
}

int tile_for_section(ivec2 section) {
	ivec2 s2=ivec2(section.x,section.y%2);
	int tile=0;
	
	if(s2[0]==1 && s2[1]==0) // tile 4
		tile=5;
	else if(s2[0]==0 && s2[1]==1) // tile 3
		tile=4;
	else if(s2[0]==2 && s2[1]==1) // tile 1
		tile=2;
	else if(s2[0]==3 && s2[1]==1) // tile 2
		tile=3;
	else if(s2[0]==0 && s2[1]==0) // tile 5
		tile=6;
	else if(s2[0]==1 && s2[1]==1) // tile 0
		tile=1;
		
	if(section.y>1)
		tile=-tile;
		
	return tile;
}

varying flat mat4 modelview_matrix;

void vertex() {
//	FIXME: Update this to use precalculated data
//	if(move_vertices) {
//		vec4 n=multi_perlin(NORMAL,false);
//		VERTEX = NORMAL*(1.0+n.w*0.125);
//	}
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	modelview_matrix=MODELVIEW_MATRIX;
}

void fragment() {
	ivec2 section = ivec2(mod(UV*4.0,4.0));
	//ivec2 patch = ivec2(round(fract(UV*4.0)*float(tile_size)+0.5));
	int tile = tile_for_section(section);
	vec3 normal;
	float w;
	
	// use precalculated data
	vec4 tex2=texture(precalculated,UV);
	w=tex2.x;
	if(normal_map) {
		vec4 tex1=texture(precalculated,vec2(UV.x,UV.y+0.5));
		normal=tex1.xyz*2.0-1.0;
	} else {
		normal=normalize(sphere_normal_from_uv(UV,tile));
	}

	NORMAL=(modelview_matrix*vec4(normal,0.0)).xyz;

	if(color_scheme==1) {
		float five=interp_order5_scalar(4.0*w)*2.0;
		ALBEDO=five*color_scaling+color_addition;
	} else {
		float len=w*w;
		ALBEDO=vec3(len,len,len)*color_scaling+color_addition;
	}
}