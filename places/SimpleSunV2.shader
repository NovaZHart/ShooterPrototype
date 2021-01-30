shader_type spatial;
render_mode unshaded;

uniform sampler2D precalculated;

void fragment() {
	ALBEDO = texture(precalculated,vec2(UV.x,UV.y/2.0+0.5)).rgb;
	EMISSION = ALBEDO;
//	ALPHA = clamp(1.9*abs(NORMAL.z)*abs(NORMAL.z), 0.0, 1.0)*length(ALBEDO);
}
