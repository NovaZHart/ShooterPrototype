extends ColorRect

export var annulus_line_color: Color = Color(0,0,0,1.0)
export var ray_color: Color = Color(0,0,0.7,1.0)
export var theta_arc_color: Color = Color(0.8,0.6,0.1,1.0)
export var asteroid_color: Color = Color(0.3,0.3,0.6,1.0)
export var inner_radius: float = 50
export var outer_radius: float = 70
export var line_thickness: float = 4.0
export var asteroid_line_thickness: float = 2.0
export var world_size: Vector2 = Vector2(200,200)
export var orbit_period: float = 100.0
export var spacing: float = 1.5

var NativeIntersectionTest = preload("res://bin/IntersectionTest.gdns")
var native

var ray_start: Vector2 = Vector2(-50,0)
var ray_end: Vector2 = Vector2(50,-50)
var start_point_radius = world_size.x/100
var end_point_radius = world_size.x/150

var theta_regions: Array = [Vector2(0.2,0.6), Vector2(0.9,1.3)]

var asteroids: PoolVector3Array = PoolVector3Array()
var asteroids_mutex: Mutex = Mutex.new()

const CAST_RAY: int = 1
const INTERSECT_CIRCLE: int = 2
const INTERSECT_RECT: int = 3
#const INTERSECT_RECT_AT_0: int = 4
const MAX_MODE: int = 3
var mode = INTERSECT_RECT

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

func _process(delta):
	if native:
		native.step_time(delta)
		asteroids_mutex.lock()
		asteroids = native.get_asteroids()
		asteroids_mutex.unlock()
		update()

func _input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index==BUTTON_RIGHT and !event.pressed:
		mode = (mode%MAX_MODE) + 1
		if !Input.is_mouse_button_pressed(BUTTON_LEFT):
			run_native()
		update()
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
	var layer_dict: Dictionary = {
		"orbit_period": orbit_period,
		"inner_radius": inner_radius,
		"thickness": outer_radius-inner_radius,
		"spacing": spacing
	}
	print("Generate asteroids with data: "+str(layer_dict))
	native.set_asteroid_layer(layer_dict)
	run_native()

# func get_rect_at_0(xray_start,xray_end):
# 		var xrect: Rect2 = Rect2()
# 		if xray_start.y>0 and xray_end.y>0:
# 			xrect = Rect2(xray_start,Vector2(xray_end.x-xray_start.x,xray_start.y)).abs()
# 		elif xray_start.y<0 and xray_end.y<0:
# 			xrect = Rect2(Vector2(xray_start,Vector2(xray_end.x-xray_start.x,-xray_start.y)).abs()
# 		elif xray_start.x>0 and xray_end.x>0:
# 			xrect = Rect2(xray_start,Vector2(-xray_start.x,xray_end.y-xray_start.y)).abs()
# 		elif xray_start.x<0 and xray_end.x<0:
# 			xrect = Rect2(xray_start,Vector2(xray_start.x,xray_end.y-xray_start.y)).abs()
# 		else:
# 			xrect = Rect2(xray_start,xray_end-xray_start).abs()
# 		return xrect

func run_native():
	print('run_native')
	if mode==CAST_RAY:
		var result: Array = native.cast_ray(ray_start,ray_end)
		theta_regions = Array(result)
	elif mode==INTERSECT_CIRCLE:
		var result: Array = native.intersect_circle(ray_start,(ray_end-ray_start).length())
		theta_regions = result
	else: #if mode==INTERSECT_RECT:
		var rect: Rect2 = Rect2(ray_start,ray_end-ray_start).abs()
		var result: Array = native.intersect_rect(rect);
		theta_regions = result
	# else: # INTERSECT_RECT_AT_0
	# 	var result: Array = native.intersect_rect(get_rect_at_0(ray_start,ray_end))
	# 	theta_regions = result

	print('result: '+str(theta_regions))
	update()

func make_arc_polygon(r_inner: float, r_outer: float, center: Vector2, thetas: Vector2, full_circle_lines: int) -> PoolVector2Array:
	var a: PoolVector2Array = PoolVector2Array()
	var theta_width = fmod(thetas[1]-thetas[0]+20*PI,2*PI)
	var lines = int(max(10, full_circle_lines * theta_width/(2*PI)))
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

	# Draw the annulus first.
	var inpoly = make_circle_polygon(w.inner_radius_pixels,w.center_pixels,100)
	draw_polyline(inpoly,annulus_line_color,line_thickness,false)
	var outpoly = make_circle_polygon(w.outer_radius_pixels,w.center_pixels,100)
	draw_polyline(outpoly,annulus_line_color,line_thickness,false)

	# Draw theta regions on top of the annulus	
	for theta_region in theta_regions:
		var arc = make_arc_polygon(w.inner_radius_pixels,w.outer_radius_pixels,
			w.center_pixels, theta_region, 100)
		draw_colored_polygon(arc,theta_arc_color)


	# Draw asteroids under selection areas
	asteroids_mutex.lock()
	var show: PoolVector3Array = asteroids
	asteroids_mutex.unlock()
	if show.size():
		for asteroid in show:
			var asteroid_loc: Vector2 = w.world_to_pixels(Vector2(asteroid.x,asteroid.y))
			var asteroid_radius: float = w.world_scale*asteroid.z
			var poly = make_circle_polygon(asteroid_radius,asteroid_loc,10)
			draw_polyline(poly,asteroid_color,asteroid_line_thickness,false)
	else:
		push_warning("NO asteroids!")

	# Draw the selection start location	
	var pixel_start = w.world_to_pixels(ray_start)
	var start_poly = make_circle_polygon(start_point_radius*w.world_scale,pixel_start,20)
	draw_colored_polygon(start_poly,ray_color)

	# Selection end location	
	var pixel_end = w.world_to_pixels(ray_end)
	var end_poly = make_circle_polygon(end_point_radius*w.world_scale,pixel_end,20)
	draw_colored_polygon(end_poly,ray_color)

	# Selection shape	
	if mode==CAST_RAY:
		draw_line(pixel_start,pixel_end,ray_color,line_thickness,false)
	elif mode==INTERSECT_CIRCLE:
		var cpoly = make_circle_polygon((pixel_end-pixel_start).length(),pixel_start,100);
		draw_polyline(cpoly,ray_color,line_thickness,false)
	elif mode==INTERSECT_RECT:
		draw_line(pixel_start,Vector2(pixel_start.x,pixel_end.y),ray_color,line_thickness,false)
		draw_line(Vector2(pixel_start.x,pixel_end.y),pixel_end,ray_color,line_thickness,false)
		draw_line(pixel_end,Vector2(pixel_end.x,pixel_start.y),ray_color,line_thickness,false)
		draw_line(Vector2(pixel_end.x,pixel_start.y),pixel_start,ray_color,line_thickness,false)
	# elif mode==INTERSECT_RECT_AT_0:
	# 	var r=get_rect_at_0(pixel_start-w.center_pixels,pixel_end-w.center_pixels).abs()
	# 	r.position += w.center_pixels
	# 	var ps=r.position
	# 	var pe=r.position+r.size
	# 	draw_line(ps,Vector2(ps.x,pe.y),ray_color,line_thickness,false)
	# 	draw_line(Vector2(ps.x,pe.y),pe,ray_color,line_thickness,false)
	# 	draw_line(pe,Vector2(pe.x,ps.y),ray_color,line_thickness,false)
	# 	draw_line(Vector2(pe.x,ps.y),ps,ray_color,line_thickness,false)
