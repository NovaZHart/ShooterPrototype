shader_type spatial;
render_mode unshaded;

uniform sampler2D texture_albedo;
uniform vec2 texture_size;
uniform vec2 uv_offset;
uniform vec2 uv2_offset;

void fragment() {
	vec3 hires = texture(texture_albedo,mod(UV+uv_offset,1.0)).rgb;
	vec3 lores = texture(texture_albedo,mod(UV2+uv2_offset,1.0)).rgb;
	ALBEDO = mix(lores,hires,0.3);
}