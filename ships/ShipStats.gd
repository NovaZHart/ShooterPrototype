extends RigidBody

export var ship_display_name: String = 'Unnamed'
export var hull_display_name: String = 'Unnamed'
export var base_mass: float = 50
export var base_thrust: float = 3000
export var base_reverse_thrust: float = 800
export var base_shields: float = 800
export var base_armor: float = 500
export var base_structure: float = 300
export var heal_shields: float = 20
export var heal_armor: float = 5
export var heal_structure: float = 0
export var base_drag: float = 1.5
export var base_turn_rate: float = 2
export var base_threat: float = -1
export var base_explosion_damage: float = 100
export var base_explosion_radius: float = 5
export var base_explosion_impulse: float = 500
export var base_explosion_delay: int = 10
export var override_size: Vector3 = Vector3(0,0,0)

var combined_stats: Dictionary = {'weapons':[]}
var team: int = 0
var enemy_team: int = 1
var enemy_mask: int = 2
var height: float = 5

func set_team(new_team: int):
	team=new_team
	enemy_team=1-new_team
	collision_layer = 1<<team
	enemy_mask = 1<<enemy_team

func init_ship_recursively(node: Node = self):
	if node.has_method("add_weapon_stats"):
		node.rotation=Vector3(0,0,0)
	for child in node.get_children():
		if node==self and child is VisualInstance:
			child.translation.y+=height
		init_ship_recursively(child)

func get_combined_aabb(node: Node = self):
	var result: AABB = AABB()
	if node is VisualInstance:
		result = node.get_aabb()
	for child in node.get_children():
		result=result.merge(get_combined_aabb(child))
	return result

func make_stats(node: Node, stats: Dictionary) -> Dictionary:
	if node.has_method("add_stats"):
		node.add_stats(stats)
	var children: Array = node.get_children()
	for child in children:
		var _discard = make_stats(child,stats)
	return stats

func repack_stats() -> Dictionary:
	return make_stats(self,combined_stats)
	
func pack_stats() -> Dictionary:
	return combined_stats

func add_stats(stats: Dictionary) -> void:
#	export var base_explosion_damage: float = 100
#export var base_explosion_radius: float = 5
#export var base_explosion_impact: float = 500
#export var base_explosion_delay: int = 10
	stats['explosion_damage']=base_explosion_damage
	stats['explosion_radius']=base_explosion_radius
	stats['explosion_impulse']=base_explosion_impulse
	stats['explosion_delay']=base_explosion_delay
	stats['name']=name
	stats['rid']=get_rid()
	stats['thrust']=base_thrust
	stats['reverse_thrust']=base_reverse_thrust
	stats['turn_rate']=base_turn_rate
	if base_threat<0:
		stats['threat'] = (base_shields+base_armor+base_structure)/60 + \
			heal_shields+heal_armor+heal_structure
	else:
		stats['threat'] = base_threat
	stats['max_shields']=base_shields
	stats['max_armor']=base_armor
	stats['max_structure']=base_structure
	stats['heal_shields']=heal_shields
	stats['heal_armor']=heal_armor
	stats['heal_structure']=heal_structure
	if override_size.length()>1e-5:
		var size: Vector3 = Vector3(override_size.x,1,override_size.z)
		stats['aabb']=AABB(-size*0.5,size)
	else:
		stats['aabb']=get_combined_aabb()
	stats['enemy_mask']=enemy_mask
	stats['collision_layer']=collision_layer
	stats['team']=team
	stats['enemy_team']=enemy_team
	stats['rotation']=rotation
	stats['position']=Vector3(translation.x,0,translation.z)
	stats['transform']=transform
	stats['mass']=base_mass
	stats['drag']=base_drag
	stats['weapons']=Array()

func make_cell(key,value) -> String:
	return '[cell]'+key+'[/cell][cell]'+str(value)+'[/cell]'

func max_and_repair(key,maxval,repairval) -> String:
	if repairval>0:
		return make_cell(key,maxval)
	return make_cell(key,str(maxval)+' (+'+str(repairval)+'/s)')

func get_bbcode() -> String:
	var contents: String = '' #'[b]Contents:[/b]\n'
	var dps: float = 0
	for child in get_children():
		if child.has_method('get_bbcode_for_ship_table'):
			contents += child.get_bbcode_for_ship_table()+'\n'
			if child.mount_type=='gun' or child.mount_type=='turret':
				dps += child.damage / max(1.0/60,child.firing_delay)
	
	var s: Dictionary = combined_stats
	var bbcode = '[center][b]Ship [i]'+ship_display_name+'[/i][/b][/center]\n\n[table=5]'
	bbcode += make_cell('Hull Design:',hull_display_name)
	bbcode += '[cell]    [/cell]'
	bbcode += make_cell('Weapon Damage:',str(round(dps))+'/s')

	bbcode += max_and_repair('Shields:',s['max_shields'],s['heal_shields'])
	bbcode += '[cell]    [/cell]'
	bbcode += '[cell]Death Explosion:[/cell][cell][/cell]'

	bbcode += max_and_repair('Armor:',s['max_armor'],s['heal_armor'])
	bbcode += '[cell]    [/cell]'
	bbcode += make_cell('Radius:',s['explosion_radius'])

	bbcode += max_and_repair('Structure:',s['max_structure'],s['heal_structure'])
	bbcode += '[cell]    [/cell]'
	bbcode += make_cell('Damage:',s['explosion_damage'])

	var max_thrust = max(max(s['reverse_thrust'],s['thrust']),0)
	bbcode += make_cell('Max Speed:',round(max_thrust/max(1e-9,s['drag']*s['mass'])*10)/10)
	bbcode += '[cell]    [/cell]'
	bbcode += make_cell('Hit Force:',s['explosion_impulse'])

	bbcode += make_cell('Thrust:',s['thrust'])
	bbcode += '[cell]    [/cell]'
	bbcode += make_cell('Delay:',str(round(1.0/max(1.0/60,s['explosion_delay'])*10)/10)+'/s')

	if s['reverse_thrust']>0:
		bbcode += make_cell('Reverse:',s['reverse_thrust'])
		bbcode += '[cell]    [/cell]'
		bbcode += '[cell][/cell][cell][/cell]'

	bbcode += make_cell('Mass:',s['mass'])
	bbcode += '[cell]    [/cell]'
	bbcode += '[cell][/cell][cell][/cell]'

	bbcode += make_cell('Drag:',s['drag'])
	bbcode += '[cell]    [/cell]'
	bbcode += '[cell][/cell][cell][/cell]'

	bbcode += '[/table]\n\n'

	if contents:
		bbcode += contents
	return bbcode

func _ready():
	var _discard = make_stats(self,combined_stats)
	height = (randi()%11)*2 - 5
	collision_mask=0
	mass=combined_stats['mass']
	linear_damp=combined_stats['drag']
	gravity_scale=0
	axis_lock_linear_y=true
	axis_lock_angular_x=true
	axis_lock_angular_z=true
	can_sleep=false
	for child in get_children():
		if child is VisualInstance:
			child.translation.y+=height
	#init_ship_recursively()
