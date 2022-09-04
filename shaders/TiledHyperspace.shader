shader_type spatial;
render_mode unshaded;

uniform sampler2D texture_albedo : hint_albedo;
uniform sampler2D texture_starfield;
uniform vec2 texture_size;
uniform float uv_range=100.0;
uniform float star_scale=0.2;
uniform float nebula_thickness=50.0;
uniform float nebula_scale=0.313;
uniform bool show_stars = true;

vec3 kelvin_to_rgb(float kelvin) {
	if(kelvin<6600.0) {
		if(kelvin<4000.0) {
			if(kelvin<1000.0)
				return mix(vec3(0.5,0.0,0.0),vec3(1.0,0.2,0.0),kelvin/1000.0);
			else
				return mix(vec3(1.0,0.2,0.0),vec3(1.0,0.8,0.6),(kelvin-1000.0)/3000.0);
		} else 
			return mix(vec3(1.0,0.8,0.6),vec3(1.0,1.0,1.0),(kelvin-4000.0)/2600.0);
	} else if(kelvin<1e6) {
		if(kelvin<40000.0)
			return mix(vec3(1.0,1.0,1.0),vec3(0.6,0.75,1.0),(kelvin-6600.0)/33400.0);
		else
			return mix(vec3(0.6,0.75,1.0),vec3(0.0,0.0,0.5),kelvin/1e6);
	}
	return vec3(0.0,0.0,0.5);
}

vec3 star_overlay(vec2 uv) {
	vec2 ftexel = fract(uv)*vec2(texture_size);
	ivec2 itexel = ivec2(floor(ftexel));
	vec2 within = fract(ftexel);
	vec4 star = texelFetch(texture_starfield,itexel,0);
	float dist = distance(within,star_scale+(1.0-2.0*star_scale)*star.xy);
	
	if(dist>star_scale)
		return vec3(0.0,0.0,0.0);
	float kelvin=(1.0-star.z*star.z)*10000.0+cos(5.0*(star.x+star.y))*10000.0+2000.0;
	float intensity=clamp((star_scale-dist)/star_scale*star.z,0.0,1.0);
	return kelvin_to_rgb(kelvin)*intensity;
}

void fragment() {
	vec3 supalo = texture(texture_albedo,fract(UV*4.0)).rgb;
	vec3 lores = texture(texture_albedo,fract(UV*16.0)).rgb;
	vec3 hires = texture(texture_albedo,fract(UV*64.0)).rgb;
	vec3 mixed = mix(mix(supalo,lores,0.313),hires,0.313);
	if(show_stars) {
		float weight = clamp(nebula_thickness*(mixed.r+mixed.g+mixed.b),0.0,1.0);
		if(weight<1.0) {
			vec2 star_uv = fract(UV);
			mixed = mix(star_overlay(fract(star_uv)),mixed,weight);
		}
	}
	ALBEDO=mixed;
}