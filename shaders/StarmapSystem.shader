shader_type spatial;

uniform int poly=2;

void vertex() {
	COLOR = INSTANCE_CUSTOM;
}

void fragment() {
	int shape = int(ceil(COLOR.w*9.99));
	float x = (UV.x-0.5)*2.0;
	x*=x;
	if(poly>2) {
		x*=x;
	}
	if(shape==1) {
		float y = mod(UV.y*10.0-1.0,2.0);
		y*=y;
		x*=y;
	}
	ALPHA = 1.0-x;
	ALBEDO = COLOR.rgb*ALPHA;
}