shader_type spatial;
render_mode unshaded;

uniform sampler2D string_texture;

void fragment() {
	vec4 tex = texture(string_texture,UV);
	ALBEDO = tex.rgb;
	ALPHA = tex.a;
}