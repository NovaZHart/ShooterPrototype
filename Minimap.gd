extends Node2D

var map_center: Vector2 setget set_map_center, get_map_center
var map_radius: float = 300 setget set_map_radius,get_map_radius

var background_color: Color = Color(0,0,0,0.3)
var border_color: Color = Color(0.5,0.5,0.5,1.0)
var neutral_color: Color = Color(.7,.7,.7)
var hostile_color: Color = Color(1,0,0)
var friendly_color: Color = Color(0,0,1)
var projectile_color: Color = neutral_color

var line_start: Vector2
var line_end: Vector2
var requested_heading: Vector2 = Vector2(0,0)

var crosshairs_width: float = 1

var planet_layer: Array
var ship_layer: Array
var projectile_layer: Array

var player_velocity: Vector2 = Vector2(0,0)
var player_heading: Vector2 = Vector2(0,-1)

func set_minimap_line(var start: Vector2, var end: Vector2):
	line_start = start
	line_end = end

func set_request_heading(var new_heading: Vector2):
	requested_heading=new_heading

func fill_map(planets, ships, projectiles,
		_new_player_velocity: Vector2, _new_player_heading: Vector2,
		_aim_point1: Vector2, _aim_point2: Vector2):
	var planet_info=[]
	var ship_info=[]
	var projectile_info=[]
	
	for planet in planets:
		planet_info.append({
			'location':planet.get('location',Vector2(0,0)),
			'scale':planet.get('scale',1.0),
			'color':planet.get('color',neutral_color),
			'target':planet.get('target',false)
		})
	for ship in ships:
		var info = {
			'location':ship.get('location',Vector2(0,0)),
			'scale':ship.get('scale',2.0),
			'target':ship.get('target',false),
			'hostile':ship.get('hostile',false),
			'friendly':ship.get('friendly',false),
			'color':ship.get('color',null),
			'player':ship.get('player',false)
		}
		if info['player']:
			info['requested_heading'] = requested_heading
		if info['target'] or info['player']:
			info['velocity'] = ship.get('velocity',Vector2(0,0))
			info['heading'] = ship.get('heading',Vector2(1,0))
		if info['color'] == null:
			info['color'] = neutral_color
			if info['hostile']:
				info['color'] = hostile_color
			elif info['friendly']:
				info['color'] = friendly_color
		ship_info.append(info)
	for proj in projectiles:
		# location, color
		projectile_info.append({
			'location':proj.get('location',Vector2(0,0)),
			'scale':proj.get('scale',1.0),
			'color':proj.get('color',projectile_color)
		})
	planet_layer = planet_info
	ship_layer = ship_info
	projectile_layer = projectile_info
	update()

func place_map(var center: Vector2, var radius: float):
	map_center = center
	map_radius = radius
	update()

func set_map_center(var center: Vector2):
	map_center = center

func set_map_radius(var radius: float):
	map_radius = radius

func get_map_center() -> Vector2:
	return map_center

func get_map_radius() -> float:
	return map_radius

func draw_map_bounds(var _viewport_size: Vector2,var radius: float,var center: Vector2):
	radius = radius*0.95
	draw_circle(center,radius,background_color)
	draw_arc(center,radius,0,2*PI,80,border_color,1.5,true)

func place_center(var where: Vector2,var minimap_radius: float,var minimap_center: Vector2):
	var minimap_scaled = (where-map_center)/map_radius*minimap_radius
	var outside=minimap_radius*0.95
	if minimap_scaled.length() > outside:
		minimap_scaled = minimap_scaled.normalized()*outside
	return minimap_scaled + minimap_center

func scale_radius(var what: float,var minimap_radius: float):
	return what/map_radius*minimap_radius

func draw_crosshairs(var loc: Vector2, var minimap_radius: float, var color: Color):
		var small_x = Vector2(minimap_radius*0.02,0)
		var small_y = Vector2(0,minimap_radius*0.02)
		var big_x = Vector2(minimap_radius*0.07,0)
		var big_y = Vector2(0,minimap_radius*0.07)
		draw_line(loc-big_x,loc-small_x,color,crosshairs_width,true)
		draw_line(loc+big_x,loc+small_x,color,crosshairs_width,true)
		draw_line(loc-big_y,loc-small_y,color,crosshairs_width,true)
		draw_line(loc+big_y,loc+small_y,color,crosshairs_width,true)
		#draw_arc(loc,minimap_radius*0.04,0,2*PI,8,color,crosshairs_width,true)
		draw_arc(loc,big_x[0],0,2*PI,16,color,crosshairs_width,true)

func draw_velocity(var ship: Dictionary, var loc: Vector2,
		var minimap_radius: float, var minimap_center: Vector2):
	var away: Vector2 = place_center(ship['location']+ship['velocity'],
		minimap_radius,minimap_center)
	draw_line(loc,away,ship['color'],1,true)

func draw_heading(var ship: Dictionary, var loc: Vector2,
		var minimap_radius: float, var minimap_center: Vector2):
	var heading: Vector2 = place_center(ship['location']+10*ship['heading'],
		minimap_radius,minimap_center)
	draw_line(loc,heading,ship['color'],2,true)

func draw_minimap_line(var minimap_radius: float, var minimap_center: Vector2):
	var start: Vector2 = place_center(line_start,minimap_radius,minimap_center)
	var end: Vector2 = place_center(line_end,minimap_radius,minimap_center)
	draw_line(start,end,Color(1,0,1,1),0.5,true)
	draw_circle(start,2,Color(1,0,1,1))

func draw_requested_heading(var ship: Dictionary, var loc: Vector2,
		var minimap_radius: float, var minimap_center: Vector2):
	var heading: Vector2 = place_center(ship['location']+30*ship['requested_heading'],
		minimap_radius,minimap_center)
	draw_line(loc,heading,Color(1,1,1,1),1,true)

func _draw():
	var viewport_size: Vector2 = get_viewport_rect().size
	var goal = viewport_size*Vector2(.1,.17)
	var minimap_radius = min(goal[0],goal[1])
	var minimap_center: Vector2 = Vector2(minimap_radius,minimap_radius)
	var crosshairs = []
	
	draw_map_bounds(viewport_size,minimap_radius,minimap_center)
	
	for planet in planet_layer:
		var loc = place_center(planet['location'],minimap_radius,minimap_center)
		var rad = scale_radius(planet['scale'],minimap_radius)
		if planet['target']:
			crosshairs.append([loc,planet['color']])
		draw_arc(loc,rad*3,0,2*PI,80,planet['color'],1.5)
	
	for ship in ship_layer: # location, scale, 
		var loc = place_center(ship['location'],minimap_radius,minimap_center)
		if ship['target'] or ship['player']:
			draw_heading(ship,loc,minimap_radius,minimap_center)
			draw_velocity(ship,loc,minimap_radius,minimap_center)
		if ship['player']:
			draw_requested_heading(ship,loc,minimap_radius,minimap_center)
		draw_circle(loc,ship['scale'],ship['color'])
	
	var outside=minimap_radius*0.95
	for projectile in projectile_layer: # location, color
		var minimap_scaled = (projectile['location']-map_center)/map_radius*minimap_radius
		if minimap_scaled.length() > outside:
			continue
		draw_circle(minimap_center+minimap_scaled,1,projectile['color'])
	
	for cross in crosshairs:
		draw_crosshairs(cross[0],minimap_radius,cross[1])
	
	draw_minimap_line(minimap_radius, minimap_center)

