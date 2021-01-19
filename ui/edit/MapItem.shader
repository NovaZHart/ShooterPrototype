shader_type spatial;

uniform int poly=2;

void vertex() {
	COLOR = INSTANCE_CUSTOM;
}

void fragment() {
	float x = (UV.x-0.5)*2.0;
	x*=x;
	if(poly>2) {
		x*=x;
	}
	ALPHA = 1.0-x;
	ALBEDO = COLOR.rgb*ALPHA;
}