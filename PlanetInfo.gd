extends Node

const Planet = preload('res://Planet.tscn')

enum { PLANET=0, STAR=1 }

const yellow_sun = {
	'object_type':STAR, 'size':6.0, 'color_scaling':Color(-0.7,-0.7,-0.5),
	'color_addition':Color(1,0.7,0.3)
}

const blue_sun = {
	'object_type':STAR, 'size':6.0, 'color_scaling':Color(-0.4,-0.5,-0.5),
	'color_addition':Color(0.4,0.5,1.0)
}

const ocean_planet = {
	'object_type':PLANET, 'size':2.5, 'color_scaling':Color(0.7,0.7,0.2),
	'color_addition':Color(0,0,0.3)
}

const ice_planet = {
	'object_type':PLANET, 'size':2.5, 'color_scaling':Color(0.2,0.2,0.7),
	'color_addition':Color(.3,.3,.3)
}

const fiery_rock = {
	'object_type':PLANET, 'size':2.5, 'color_scaling':Color(0.7,0.2,0.2),
	'color_addition':Color(0.3,0,0)
}

var object_type = PLANET
var template_name: String = 'none'
var size: float = 3.0
var color_scaling: Color = Color(1,1,1,1)
var color_addition: Color = Color(0,0,0,1)
var display_name: String = 'Unnamed'
var shader_seed: int = 0
var orbit_radius: float = 0.0
var orbit_period: float = 0.0
var orbit_start: float = 0.0
var has_astral_gate: bool = false

func is_a_system() -> bool: return false
func is_a_planet() -> bool: return true

func _init(node_name: String,me: Dictionary,base: Dictionary):
	name = node_name
	object_type = get_it(me,base,'object_type',PLANET)
	template_name = get_it(me,base,'template_name','none')
	size = get_it(me,base,'size',2.5)
	color_scaling = get_it(me,base,'color_scaling',Color(1,1,1,1))
	color_addition = get_it(me,base,'color_addition',Color(0,0,0,1))
	display_name = get_it(me,base,'display_name','Unnamed')
	shader_seed = get_it(me,base,'shader_seed',0)
	orbit_radius = get_it(me,base,'orbit_radius',0.0)
	orbit_period = get_it(me,base,'orbit_period',0.0)
	orbit_start = get_it(me,base,'orbit_start',0.0)
	has_astral_gate = get_it(me,base,'has_astral_gate',object_type==STAR)

func add_planet(var p):
	add_child(p)
	return self

func astral_gate_path() -> NodePath:
	if has_astral_gate:
		return game_state.get_path_to(self)
	for child in get_children():
		if not child.get_class() == 'PlanetInfo':
			continue
		var p: NodePath = child.astral_gate_path()
		if not p.is_empty():
			return p
	return NodePath()

func get_it(info: Dictionary,type: Dictionary,key: String, var default):
	var result=info.get(key,null)
	return result if result!=null else type.get(key,default)

func make_unique_name() -> String:
	var uname = name
	var parent = get_parent()
	if parent==null:
		return uname
	elif parent.is_a_planet():
		return parent.make_unique_name() + '_' + uname
	return parent.name + '_' + uname

func full_display_name() -> String:
	var fp = display_name
	var parent = get_parent()
	if parent==null:
		return fp
	elif parent.is_a_planet() or parent.is_a_system():
		return parent.full_display_name() + '_' + fp
	return fp

func planet_translation(time: float) -> Vector3:
	var angle = 2*PI*time/orbit_period if (orbit_period>1e-6) else 0.0
	var loc = Vector3(orbit_radius*sin(angle+orbit_start),0,orbit_radius*cos(angle+orbit_start))
	
	var parent = get_parent()
	if parent!=null and parent.is_a_planet():
		loc += parent.planet_translation(time)
	return loc

func make_planet(detail: float=150, time: float=0):
	var texture_size: int = int(round(pow(2,max(7,min(11,int(log(detail*size)/log(2)))))))
	var planet=Planet.instance()
	if object_type==STAR:
		planet.make_sun(min(96,max(8,1+detail*size/60.0)),shader_seed,texture_size)
		planet.has_astral_gate = true
	else:
		planet.make_planet(min(96,max(8,1+detail*size/60.0)),shader_seed,texture_size)
	
	planet.color_sphere(color_scaling,color_addition)
	var x0z = planet_translation(time)
	planet.place_sphere(size,Vector3(x0z[0],-5,x0z[2]))
	
	planet.name = make_unique_name()
	planet.display_name = display_name
	planet.full_display_name = full_display_name()
	planet.has_astral_gate = has_astral_gate
	planet.game_state_path = game_state.get_path_to(self)
	return planet

func fill_system(var system,planet_time: float,ship_time: float,detail: float):
	system.spawn_planet(make_planet(detail,planet_time))
	for child in get_children():
		if child.is_a_planet():
			child.fill_system(system,planet_time,ship_time,detail)
