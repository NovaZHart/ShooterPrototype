extends ColorRect

export var annulus_line_color: Color = Color(0,0,0,1.0)
export var ray_color: Color = Color(0,0,0.7,1.0)
export var theta_arc_color: Color = Color(0.8,0.6,0.1,1.0)
export var asteroid_color: Color = Color(0.3,0.3,0.6,1.0)
export var hit_color: Color = Color(0.9,0.3,0.3,1.0)
export var line_thickness: float = 4.0
export var asteroid_line_thickness: float = 2.0
export var world_size: Vector2 = Vector2(1500,1500)

export var inner_radius: float = 450
export var outer_radius: float = 650

export var layer_data: Array = [
	{
		"orbit_period": 300.0,
		"inner_radius": 500,
		"thickness": 100,
		"spacing": 10.0,
		"min_scale": 0.8,
		"max_scale": 2.0,
	},
	{
		"orbit_period": 225.0,
		"inner_radius": 480,
		"thickness": 71,
		"spacing": 7.0,
		"min_scale": 0.7,
		"max_scale": 1.6,
	},
	{
		"orbit_period": 225.0,
		"inner_radius": 550,
		"thickness": 70,
		"spacing": 7.0,
		"min_scale": 0.7,
		"max_scale": 1.6,
	},
	{
		"orbit_period": 150.0,
		"inner_radius": 460,
		"thickness": 91,
		"spacing": 4.0,
		"min_scale": 0.5,
		"max_scale": 1.3,
	},
	{
		"orbit_period": 150.0,
		"inner_radius": 550,
		"thickness": 90,
		"spacing": 4.0,
		"min_scale": 0.5,
		"max_scale": 1.3,
	},
	{
		"orbit_period": 75.0,
		"inner_radius": 450,
		"thickness": 101,
		"spacing": 3.5,
		"min_scale": 0.5,
		"max_scale": 0.9,
	},
	{
		"orbit_period": 75.0,
		"inner_radius": 550,
		"thickness": 100,
		"spacing": 3.5,
		"min_scale": 0.5,
		"max_scale": 0.9,
	},
]

var NativeIntersectionTest = preload("res://bin/IntersectionTest.gdns")
var native

var step: int = 0

var ray_start: Vector2 = Vector2(-400,0)
var ray_end: Vector2 = Vector2(-650,250)
var start_point_radius = world_size.x/100
var end_point_radius = world_size.x/150

var theta_regions: Array = [Vector2(0.2,0.6), Vector2(0.9,1.3)]

var asteroids: PoolVector3Array = PoolVector3Array()
var hit: PoolVector3Array = PoolVector3Array()
var asteroids_mutex: Mutex = Mutex.new()

const CAST_RAY: int = 1
const INTERSECT_CIRCLE: int = 2
const INTERSECT_RECT: int = 3
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
	step=step+1
	if native:
		var visible_region: Rect2 = Rect2(-world_size/2,world_size);
		native.step_time(delta,visible_region)
		asteroids_mutex.lock()
		if mode==INTERSECT_RECT:
			asteroids=native.overlapping_rect(Rect2(ray_start,ray_end-ray_start).abs())
		elif mode==INTERSECT_CIRCLE:
			var radius: float = (ray_end-ray_start).length()
			asteroids=native.overlapping_circle(ray_start,radius)
			hit=native.first_in_circle(ray_start,radius)
		elif mode==CAST_RAY:
			asteroids=native.overlapping_rect(Rect2(ray_start,ray_end-ray_start).abs())
			hit=native.cast_ray_first_hit(ray_start,ray_end)
		asteroids_mutex.unlock()
		update()
		if step%60==0:
			print("FPS: "+str(Engine.get_frames_per_second())+" asteroids="+str(asteroids.size()))

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
	print("Generate asteroids with data: "+str(layer_data))
	native.set_asteroid_field(layer_data)
	run_native()

func run_native():
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
	var pixel_start: Vector2 = w.world_to_pixels(ray_start)
	var pixel_end: Vector2 = w.world_to_pixels(ray_end)

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
		# if mode==INTERSECT_RECT:
		# 	var display_rect = Rect2(pixel_start,pixel_end-pixel_start).abs()
		# 	for asteroid in show:
		# 		var asteroid_loc: Vector2 = w.world_to_pixels(Vector2(asteroid.x,asteroid.y))
		# 		var asteroid_radius: float = w.world_scale*asteroid.z
		# 		if display_rect.grow(2*asteroid_radius).has_point(asteroid_loc):
		# 			var poly = make_circle_polygon(asteroid_radius,asteroid_loc,6)
		# 			draw_polyline(poly,asteroid_color,asteroid_line_thickness,false)
		# elif mode==INTERSECT_CIRCLE:
		# 	var radius = (pixel_end-pixel_start).length()
		# 	for asteroid in show:
		# 		var asteroid_loc: Vector2 = w.world_to_pixels(Vector2(asteroid.x,asteroid.y))
		# 		var asteroid_radius: float = w.world_scale*asteroid.z
		# 		if asteroid_loc.distance_to(pixel_start)<=asteroid_radius+radius:
		# 			var poly = make_circle_polygon(asteroid_radius,asteroid_loc,6)
		# 			draw_polyline(poly,asteroid_color,asteroid_line_thickness,false)
		# else:
		# 	for asteroid in show:
		# 		var asteroid_loc: Vector2 = w.world_to_pixels(Vector2(asteroid.x,asteroid.y))
		# 		var asteroid_radius: float = w.world_scale*asteroid.z
		# 		var poly = make_circle_polygon(asteroid_radius,asteroid_loc,6)
		# 		draw_polyline(poly,asteroid_color,asteroid_line_thickness,false)
		for asteroid in show:
			var asteroid_loc: Vector2 = w.world_to_pixels(Vector2(asteroid.x,asteroid.y))
			var asteroid_radius: float = w.world_scale*asteroid.z
			var poly = make_circle_polygon(asteroid_radius,asteroid_loc,6)
			draw_polyline(poly,asteroid_color,asteroid_line_thickness,false)
	#else:
	#	push_warning("NO asteroids!")

	# Draw the selection start location	
	var start_poly = make_circle_polygon(start_point_radius*w.world_scale,pixel_start,20)
	draw_colored_polygon(start_poly,ray_color)

	# Selection end location	
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
	if (mode==CAST_RAY or mode==INTERSECT_CIRCLE) and hit.size()>0:
		var hit_location: Vector2 = w.world_to_pixels(Vector2(hit[0].x,hit[0].y))
		var cpoly = make_circle_polygon(start_point_radius,hit_location,20)
		draw_polyline(cpoly,hit_color,line_thickness,false)
