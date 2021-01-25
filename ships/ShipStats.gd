extends RigidBody

export var ship_display_name: String = 'Unnamed'
export var help_page: String = 'hulls'
export var base_mass: float = 50
export var base_thrust: float = 3000
export var base_reverse_thrust: float = 800
export var base_turn_thrust: float = 100
export var base_shields: float = 800
export var base_armor: float = 500
export var base_structure: float = 300
export var heal_shields: float = 20
export var heal_armor: float = 5
export var heal_structure: float = 0
export var base_drag: float = 1.5
export var base_turn_drag: float = 1.5
#export var base_turn_rate: float = 2
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
var random_height: bool = true
var transforms: Dictionary = {}
var retain_hidden_mounts: bool = false

func save_transforms():
	for child in get_children():
		if child is Spatial:
			transforms[child.name] = child.transform

func restore_transforms():
	for key in transforms:
		var child = get_node_or_null(key)
		if child!=null:
			child.transform=transforms[key]

func set_team(new_team: int):
	team=new_team
	enemy_team=1-new_team
	collision_layer = 1<<team
	enemy_mask = 1<<enemy_team

func init_ship_recursively(node: Node = self):
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
	combined_stats = make_stats(self,{'weapons':[]})
	return combined_stats
	
func pack_stats(quiet: bool = false) -> Dictionary:
	if not combined_stats.has('mass'):
		if not quiet:
			push_error('No stats in pack_stats! Making stats now.')
		combined_stats = make_stats(self,{'weapons':[]})
	return combined_stats

func add_stats(stats: Dictionary) -> void:
	stats['explosion_damage']=base_explosion_damage
	stats['explosion_radius']=base_explosion_radius
	stats['explosion_impulse']=base_explosion_impulse
	stats['explosion_delay']=base_explosion_delay
	stats['name']=name
	if is_inside_tree():
		stats['rid']=get_rid()
	stats['thrust']=base_thrust
	stats['reverse_thrust']=base_reverse_thrust
	stats['turn_thrust']=base_turn_thrust
	#stats['turn_rate']=base_turn_rate
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
	elif is_inside_tree():
		stats['aabb']=get_combined_aabb()
	stats['turn_drag']=base_turn_drag
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

func update_stats():
	combined_stats['team']=team
	combined_stats['enemy_team']=enemy_team
	combined_stats['name']=name
	combined_stats['enemy_mask']=enemy_mask
	combined_stats['rid'] = get_rid()
	combined_stats['team']=team
	combined_stats['rotation']=rotation
	combined_stats['position']=Vector3(translation.x,0,translation.z)
	combined_stats['transform']=transform
	for wep in combined_stats['weapons']:
		var child = get_node_or_null(wep['name'])
		if child==null:
			printerr('ShipStats._ready: weapon "',wep['name'],'" vanished.')
		else:
			wep['node_path'] = child.get_path()
			assert(not wep['node_path'].is_empty())
	if override_size.length()>1e-5:
		var size: Vector3 = Vector3(override_size.x,1,override_size.z)
		combined_stats['aabb']=AABB(-size*0.5,size)
	else:
		combined_stats['aabb']=get_combined_aabb()

func make_cell(key,value) -> String:
	return '[cell]'+key+'[/cell][cell]'+str(value)+'[/cell]'

func max_and_repair(key,maxval,repairval) -> String:
	if repairval>0:
		return make_cell(key,str(maxval)+' (+'+str(repairval)+'/s)')
	return make_cell(key,maxval)

func get_bbcode() -> String:
	var contents: String = '' #'[b]Contents:[/b]\n'
	var dps: float = 0
	for child in get_children():
		if child.has_method('get_bbcode_for_ship_table'):
			contents += child.get_bbcode_for_ship_table()+'\n'
			if child.mount_type=='gun' or child.mount_type=='turret':
				dps += child.damage / max(1.0/60,child.firing_delay)
	
	var s: Dictionary = pack_stats(true)
	var max_thrust = max(max(s['reverse_thrust'],s['thrust']),0)
	#var bbcode = '[center][b]Ship [i]'+ship_display_name+'[/i][/b][/center]\n\n'
	var bbcode = '[b]Hull:[/b] {ref '+help_page+'}\n[table=5]'


	bbcode += max_and_repair('Shields:',s['max_shields'],s['heal_shields'])
	bbcode += '[cell] [/cell]'
	bbcode += make_cell('Damage:',str(round(dps))+'/s')

	bbcode += max_and_repair('Armor:',s['max_armor'],s['heal_armor'])
	bbcode += '[cell] [/cell]'
	bbcode += make_cell('Max Speed:',round(max_thrust/max(1e-9,s['drag']*s['mass'])*10)/10)

	bbcode += max_and_repair('Structure:',s['max_structure'],s['heal_structure'])
	bbcode += '[cell] [/cell]'
	bbcode += make_cell('Turn RPM:',round(s['turn_thrust']/max(1e-9,s['turn_drag']*s['mass'])*100)/100)

	bbcode += '[cell][/cell][cell][/cell]'
	bbcode += '[cell] [/cell]'
	bbcode += '[cell]Death Explosion[/cell][cell][/cell]'

	bbcode += make_cell('Mass:',s['mass'])
	bbcode += '[cell] [/cell]'
	bbcode += make_cell('Radius:',s['explosion_radius'])

	bbcode += make_cell('Drag:',s['drag'])
	bbcode += '[cell] [/cell]'
	bbcode += make_cell('Damage:',s['explosion_damage'])

	bbcode += make_cell('Thrust:',s['thrust'])
	bbcode += '[cell] [/cell]'
	bbcode += make_cell('Delay:',str(round(1.0/max(1.0/60,s['explosion_delay'])*10)/10)+'s')

	if s['reverse_thrust']>0:
		bbcode += make_cell('Reverse:',s['reverse_thrust'])
	else:
		bbcode += '[cell][/cell][cell][/cell]'
	bbcode += '[cell] [/cell]'
	bbcode += make_cell('Hit Force:',s['explosion_impulse'])
	
	bbcode += '[/table]\n\n'

	if contents:
		bbcode += contents
	return bbcode

func _ready():
	var must_update: bool = false
	if not combined_stats.has('mass'):
		var _discard = pack_stats(false)
	else:
		must_update = true

	if not retain_hidden_mounts:
		for child in get_children():
			if child.has_method('is_mount_point') and \
					child.mount_type!='gun' and child.mount_type!='turret':
				remove_child(child)
				child.queue_free()
				must_update=true
	if must_update:
		update_stats()
	
	if random_height:
		#height = (randi()%5)*1.99 - 1.48
		height = (randi()%11)*1.99 - 8.445
	collision_mask=0
	mass=combined_stats['mass']
	linear_damp=combined_stats['drag']
	gravity_scale=0
	axis_lock_linear_y=true
	axis_lock_angular_x=true
	axis_lock_angular_z=true
	can_sleep=false
	
	# Sometimes Godot trashes the CollisionShape transforms:
	restore_transforms()
	
	for child in get_children():
		if child is VisualInstance or child is Position3D:
			child.translation.y+=height
	#init_ship_recursively()
