extends Node

var SystemInfo = preload('res://SystemInfo.gd')

var known_systems: Dictionary = {
	'seti_alpha':SystemInfo.new('Seti-α',{
		'sun': {
			'display_name':'Seti-α', 'type':'yellow_sun', 'seed':1231333334,
		},
		'storm': {
			'display_name':'Storm', 'type':'ocean_planet', 'seed':321321321,
			'parent':'seti_alpha_sun', 'distance':70, 'period':300, 'size':3,
		},
	}),
	'alef_93':SystemInfo.new('א:93',{
		'astra': {
			'display_name':'Astra', 'type':'blue_sun', 'seed':91,
		},
		'hellscape': {
			'display_name':'Hellscape', 'type':'fiery_rock', 'seed':391,
			'parent':'astra', 'distance':40, 'period':91, 'size':2,
		},
		'pearl': {
			'display_name':'Pearl', 'type':'ice_planet', 'seed':913,
			'parent':'astra', 'distance':105, 'period':1092, 'size':4,
		},
	}),
}

func _init():
	var systems = Node.new()
	for system_name in known_systems:
		known_systems[system_name].name=system_name
		systems.add_child(known_systems[system_name])
	add_child(systems)

var system = known_systems['alef_93'] setget set_system,get_system
var planet_name: String = "" setget set_planet_name,get_planet_name

func get_system(): return system
func set_system(var s: String):
	system=known_systems[s]
	planet_name=""

func get_planet_name() -> String: return planet_name
func set_planet_name(s: String):
	planet_name = s if system.has_planet(s) else ''
