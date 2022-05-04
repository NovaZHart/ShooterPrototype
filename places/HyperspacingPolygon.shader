shader_type spatial;
render_mode unshaded;

uniform sampler2D texture_albedo;
uniform vec2 xy_location=vec2(0.0,0.0);
uniform float texture_scale=1.0;
uniform float time_zero_radius = 0.8;
uniform float time_middle_radius = 0.4;
uniform float time_end_radius = 0.0;
uniform float falloff_thickness = 0.05;

uniform float time=0.5;
uniform float duration=1.0;

void fragment() {
  vec2 there = UV+texture_scale*xy_location;
  vec3 lores = texture(texture_albedo,mod(there/2.0,1.0)).rgb;
  vec3 midres = texture(texture_albedo,mod(there,1.0)).rgb;
  vec3 hires = texture(texture_albedo,mod(there*2.0,1.0)).rgb;
  ALBEDO = (lores+midres+hires)/3.0;



  float point_radius = clamp(length((UV-vec2(0.5,0.5))*2.0),0.0,1.0);

  //ALBEDO = vec3(point_radius,0.0,1.0-point_radius);
  //ALBEDO = vec3(UV.x,UV.y,1.0);

  float circle_radius;
  float when=clamp(time/duration,0.0,1.0);
  if(when<0.5) {
	float weight = 1.0-when*2.0;
	circle_radius = time_zero_radius*weight + time_middle_radius*(1.0-weight);
  } else {
	float weight = 1.0-(when-0.5)*2.0;
    circle_radius = time_middle_radius*weight + time_end_radius*(1.0-weight);
  }
  circle_radius = sin(circle_radius*2.0/3.14159);
  if(point_radius<circle_radius) {
    ALPHA=0.8;
  } else if(point_radius>=circle_radius && point_radius<=circle_radius+falloff_thickness) {
    ALPHA=0.8*(1.0-(point_radius-circle_radius)/falloff_thickness);
  } else {
    ALPHA=0.0;
  }
}
