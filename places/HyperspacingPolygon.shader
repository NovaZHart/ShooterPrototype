shader_type spatial;
render_mode unshaded;

uniform sampler2D texture_albedo;
uniform vec2 xy_location=vec2(0.0,0.0);
uniform float texture_scale=1.0;
uniform float radius = 0.8;
uniform int spin_speed = 4;
uniform float falloff_thickness = 0.05;
uniform float full_alpha = 0.8;
uniform float time=0.5;
uniform float duration=1.0;
uniform float death_time=9999.99; // anything much larger than 1.0 is okay here
uniform bool half_animation = false;

const float PI = 3.14159;


float get_shape_radius(float subtime,float theta,float spin) {
	//0.5*r*(t/d + (1-t/d)*(1+math.sin(np.pi + 2*((theta+t/d*7*np.pi)%(np.pi/2)))))
	return 0.5*radius*(subtime+(1.0-subtime)*(1.0+sin(PI+2.0*mod((theta+spin*2.0*PI),(PI/2.0)))));
}

float spin_expand(float subtime,float theta,float point_radius,bool shrink,float death_fadeout) {
	float spin = float(spin_speed);
	if(shrink) {
		subtime = 1.0-subtime;
		spin = -spin;
	}
	float radius_at_theta = get_shape_radius(0.0,theta,spin*subtime)*(0.2+subtime*0.8)*radius*death_fadeout;
	if(point_radius<radius_at_theta)
		return full_alpha;
	else if(point_radius>=radius_at_theta && point_radius<=radius_at_theta+falloff_thickness)
		return full_alpha*(1.0-(point_radius-radius_at_theta)/falloff_thickness);
	else
		return 0.0;
}
	
float spinup(float subtime,float theta,float point_radius,bool spindown,float death_fadeout) {
	float spin = float(spin_speed);
	if(spindown) {
		subtime = 1.0-subtime;
		spin = -spin;
	}
	float radius_at_theta = get_shape_radius(subtime,theta,spin*subtime)*radius*death_fadeout;
	if(point_radius<radius_at_theta)
		return full_alpha;
	else if(point_radius>=radius_at_theta && point_radius<=radius_at_theta+falloff_thickness)
		return full_alpha*(1.0-(point_radius-radius_at_theta)/falloff_thickness);
	else
		return 0.0;
}

void fragment() {
	vec2 there = UV+texture_scale*xy_location;
	vec3 lores = texture(texture_albedo,mod(there/2.0,1.0)).rgb;
	vec3 midres = texture(texture_albedo,mod(there,1.0)).rgb;
	vec3 hires = texture(texture_albedo,mod(there*2.0,1.0)).rgb;
	ALBEDO = (lores+midres+hires)/3.0;
	vec2 xy = 2.0*(UV-0.5);
	float theta = atan(xy.y,xy.x);
	float r = length(xy);
	float fulltime;
	float death_fadeout=1.0;
	if(death_time<duration/2.0) {
		death_fadeout = clamp(4.0*(time-death_time)/(duration-death_time),0.0,1.0);
	}
	if(half_animation)
		fulltime = 0.5+0.5*clamp(time/duration,0.0,1.0);
	else
		fulltime = clamp(time/duration,0.0,1.0);
	float subtime = mod(fulltime*4.0,1.0);
	if(fulltime>=0.0 && fulltime<0.25)  {
		ALPHA = spin_expand(subtime,theta,r,false,death_fadeout);
	} else if(fulltime<0.5) {
		ALPHA = spinup(subtime,theta,r,false,death_fadeout);
	} else if(fulltime<0.75) {
		ALPHA = spinup(subtime,theta,r,true,death_fadeout);
	} else if(fulltime<=1.0) {
		ALPHA = spin_expand(subtime,theta,r,true,death_fadeout);
	} else {
		ALPHA = 0.5;
	}
	ALPHA *= death_fadeout;
}
