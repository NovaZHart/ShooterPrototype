extends ColorRect

export var annulus_line_color: Color = Color(0,0,0,1.0)
export var ray_color: Color = Color(0,0,0.7,1.0)
export var theta_arc_color: Color = Color(0.8,0.6,0.1,1.0)
export var line_thickness: float = 4.0

var NativeIntersectionTest = preload("res://bin/IntersectionTest.gdns")
var native

var world_size: Vector2 = Vector2(12,12)
var inner_radius: float = 2
var outer_radius: float = 4

var ray_start: Vector2 = Vector2(-1,0)
var ray_end: Vector2 = Vector2(1,5)

var theta_regions: Array = [Vector2(0.2,0.6), Vector2(0.9,1.3)]

const CAST_RAY: int = 1
const INTERSECT_CIRCLE: int = 2
var mode = INTERSECT_CIRCLE

class WorldInfo:
	var world_scale: float
	var inner_radius_pixels: float
	var outer_radius_pixels: float
	var center_pixels: Vector2
	
	func _init(world_size: Vector2, rect_size_in: Vector2, inner_radius: float, outer_radius: float):
		var scale: Vector2 = rect_size_in/world_size
		world_scale = min(scale.x,scale.y)
		center_pixels = rect_size_in/2
		inner_radius_pixels = inner_radius * world_scale
		outer_radius_pixels = outer_radius * world_scale
	
	func pixels_to_world(pixels: Vector2) -> Vector2:
		var wrong: Vector2 = (pixels-center_pixels)/world_scale
		return Vector2(wrong.x,-wrong.y)
	
	func world_to_pixels(world: Vector2) -> Vector2:
		var q: Vector2 = world*world_scale+center_pixels
		return Vector2(q.x,2*center_pixels.y-q.y)

func _input(event: InputEvent):
	if (event is InputEventMouseButton and event.button_index==BUTTON_LEFT) \
			or (event is InputEventMouseMotion and Input.is_mouse_button_pressed(BUTTON_LEFT)):
		var w = WorldInfo.new(world_size, rect_size, inner_radius, outer_radius)
		var there = w.pixels_to_world(event.position)
		if event is InputEventMouseMotion:
			ray_end = there
		elif event.pressed:
			ray_start = there
			ray_end = there
			theta_regions = []
		else:
			ray_end = there
			run_native()
		update()

func _ready():
	print('initialize native')
	native = NativeIntersectionTest.new()
	native.set_annulus(inner_radius,outer_radius)
	run_native()

func run_native():
	print('run_native')
	if mode==CAST_RAY:
		var result: Array = native.cast_ray(ray_start,ray_end)
		theta_regions = Array(result)
	else: # INTERSECT_CIRCLE
		var result: Array = native.intersect_circle(ray_start,(ray_end-ray_start).length())
		theta_regions = result
	print('result: '+str(theta_regions))
	update()

func make_arc_polygon(r_inner: float, r_outer: float, center: Vector2, thetas: Vector2, full_circle_lines: int) -> PoolVector2Array:
	var a: PoolVector2Array = PoolVector2Array()
	var theta_width = fmod(thetas[1]-thetas[0],2*PI)
	var lines = int(max(10, full_circle_lines * theta_width/2*PI))
	var nvertex = 2*(lines+1)+1
	a.resize(nvertex)
	for i in range(lines+1):
		var angle = thetas[0]+i*theta_width/lines
		a[i] = r_inner*Vector2(cos(angle),sin(angle))+center
		a[nvertex-i-2] = r_outer*Vector2(cos(angle),sin(angle))+center
	a[2*(lines+1)] = a[0]
	return a
	
func make_circle_polygon(radius: float, center: Vector2, lines: int) -> PoolVector2Array:
	var a: PoolVector2Array = PoolVector2Array()
	a.resize(lines+1)
	for i in range(lines):
		var angle: float = 2*PI*i/lines
		a[i] = radius*Vector2(cos(angle),sin(angle))+center
	a[lines] = a[0]
	return a

func _draw():
	var w = WorldInfo.new(world_size, rect_size, inner_radius, outer_radius)
	var inpoly = make_circle_polygon(w.inner_radius_pixels,w.center_pixels,100)
	draw_polyline(inpoly,annulus_line_color,line_thickness,false)
	var outpoly = make_circle_polygon(w.outer_radius_pixels,w.center_pixels,100)
	draw_polyline(outpoly,annulus_line_color,line_thickness,false)
	
	for theta_region in theta_regions:
		print("theta region: "+str(theta_region))
		var arc = make_arc_polygon(w.inner_radius_pixels,w.outer_radius_pixels,
			w.center_pixels, theta_region, 100)
		draw_colored_polygon(arc,theta_arc_color)
	
	var pixel_start = w.world_to_pixels(ray_start)
	var start_poly = make_circle_polygon(0.1*w.world_scale,pixel_start,20)
	draw_colored_polygon(start_poly,ray_color)
	
	var pixel_end = w.world_to_pixels(ray_end)
	var end_poly = make_circle_polygon(0.04*w.world_scale,pixel_end,20)
	draw_colored_polygon(end_poly,ray_color)
	
	assert(mode==INTERSECT_CIRCLE)
	
	if mode==CAST_RAY:
		draw_line(pixel_start,pixel_end,ray_color,line_thickness,false)
	elif mode==INTERSECT_CIRCLE:
		var cpoly = make_circle_polygon((pixel_end-pixel_start).length(),pixel_start,100);
		draw_polyline(cpoly,ray_color,line_thickness,false)
