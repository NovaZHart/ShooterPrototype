shader_type spatial;
render_mode depth_draw_alpha_prepass;
render_mode shadows_disabled;
render_mode unshaded;

uniform sampler2D image_texture;
uniform float time=0.5;
uniform float duration=1.0;
uniform float death_time=9999.99; // anything much larger than 1.0 is okay here

void fragment() {
	vec4 sample = texture(image_texture,UV);
	ALPHA = time/duration*sample.w;
	ALBEDO = sample.rgb;
}