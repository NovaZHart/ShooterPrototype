shader_type spatial;
render_mode unshaded;

uniform vec4 color = vec4(1.0,1.0,1.0,0.5);
uniform float u_middle_radius = 0.5; // middle radius of annulus
uniform float u_width = 0.9; // difference between annulus radii
uniform float scale = 1.0; // actual width = u_scale*u_width
// Note: terrible things will happen if u_scale is not within
// 0.001-ish and 1, inclusive

void fragment() {
	float r = clamp((UV.x-u_middle_radius) * 2.0/(u_width*scale),-1.0,1.0);
	r *= r;
	float weight = 1.0-r*r;
	ALPHA = weight*color.a;
	ALBEDO = color.rgb;
}