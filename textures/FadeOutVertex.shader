shader_type spatial;
render_mode depth_draw_alpha_prepass;
render_mode shadows_disabled;
render_mode unshaded;

uniform sampler2D image_texture;

void vertex() {
	float time = INSTANCE_CUSTOM[0];
	float death_time = INSTANCE_CUSTOM[1];
	float duration = INSTANCE_CUSTOM[2];
	if(death_time<duration)
		duration += (death_time-duration)*0.6667;
	COLOR.w = clamp(time/duration,0.0,1.0);
}

void fragment() {
	vec4 sample = texture(image_texture,UV);
	ALPHA = COLOR.w*sample.w;
	ALBEDO = sample.rgb;
}