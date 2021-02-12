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
export var base_fuel: float = 100
export var heal_shields: float = 20
export var heal_armor: float = 5
export var heal_structure: float = 0
export var heal_fuel: float = 3
export var fuel_efficiency: float = 0.9
export var base_drag: float = 1.5
export var base_turn_drag: float = 1.5
#export var base_turn_rate: float = 2
export var base_threat: float = -1
export var base_explosion_damage: float = 100
export var base_explosion_radius: float = 5
export var base_explosion_impulse: float = 500
export var base_explosion_delay: int = 10
export var fuel_density: float = 10.0
export var armor_density: float = 10.0
export var override_size: Vector3 = Vector3(0,0,0)

var combined_stats: Dictionary = {'weapons':[],'equipment':[]}
var stats_overridden: Dictionary = {}
var non_weapon_stats: Array = []
var team: int = 0
var enemy_team: int = 1
var enemy_mask: int = 2
var height: float = 5
var random_height: bool = true
var transforms: Dictionary = {}
var retain_hidden_mounts: bool = false

var skipped_runtime_stats: bool = true

func is_ShipStats(): pass # for type detection; never called

func save_transforms():
	for child in get_children():
		if child is Spatial:
			transforms[child.name] = child.transform

func restore_transforms():
	for key in transforms:
		var child = get_node_or_null(key)
		if child!=null:
			child.transform=transforms[key]

func set_entry_method(method: int, quiet: bool = false, skip_runtime_stats: bool = false):
	if not combined_stats.has('empty_mass'):
		if not quiet:
			push_error('No stats in set_entry_method! Making stats now.')
		combined_stats = make_stats(self,{'weapons':[],'equipment':[]},skip_runtime_stats)
	combined_stats['entry_method'] = method

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

func get_combined_aabb(node: Node = self) -> AABB:
	if override_size.length()>1e-5:
		var size: Vector3 = Vector3(override_size.x,1,override_size.z)
		return AABB(-size*0.5,size)
	else:
		var result: AABB = AABB()
		if node is VisualInstance:
			result = node.get_aabb()
		for child in node.get_children():
			result=result.merge(get_combined_aabb(child))
		return result

func make_stats(node: Node, stats: Dictionary,skip_runtime_stats=false) -> Dictionary:
	if node.has_method("add_stats"):
		node.add_stats(stats,skip_runtime_stats)
	var children: Array = node.get_children()
	for child in children:
		var _discard = make_stats(child,stats,skip_runtime_stats)
	return stats

func repack_stats(skip_runtime_stats=false) -> Dictionary:
	var new_stats = make_stats(self,{'weapons':[],'equipment':[]},
		skip_runtime_stats and skipped_runtime_stats)
	if not new_stats['equipment'] and combined_stats and combined_stats['equipment']:
		new_stats['equipment'] = combined_stats['equipment']
	combined_stats = new_stats
	return combined_stats
	
func pack_stats(quiet: bool = false, skip_runtime_stats=false) -> Dictionary:
	if not combined_stats.has('empty_mass'):
		if not quiet:
			push_error('No stats in pack_stats! Making stats now.')
		combined_stats = make_stats(self,{'weapons':[],'equipment':[]},skip_runtime_stats)
	elif not skip_runtime_stats and skipped_runtime_stats:
		update_stats()
	return combined_stats

func restore_combat_stats(stats: Dictionary, skip_runtime_stats: bool = false, quiet: bool = false) -> void:
	if not combined_stats.has('empty_mass'):
		if not quiet:
			push_error('No stats in restore_combat_stats! Making stats now.')
		combined_stats = make_stats(self,{'weapons':[],'equipment':[]},skip_runtime_stats)
	for varname in [ 'fuel', 'shields', 'armor', 'structure' ]:
		if stats.has(varname):
			combined_stats[varname] = clamp(stats[varname],0.0,combined_stats['max_'+varname])

func add_stats(stats: Dictionary,skip_runtime_stats=false) -> void:
	stats['explosion_damage']=base_explosion_damage
	stats['explosion_radius']=base_explosion_radius
	stats['explosion_impulse']=base_explosion_impulse
	stats['explosion_delay']=base_explosion_delay
	stats['name']=name
	if not skip_runtime_stats and is_inside_tree():
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
	stats['max_fuel']=base_fuel
	stats['heal_shields']=heal_shields
	stats['heal_armor']=heal_armor
	stats['heal_structure']=heal_structure
	stats['heal_fuel']=heal_fuel
	stats['fuel_efficiency']=fuel_efficiency
	stats['aabb']=get_combined_aabb()
	stats['turn_drag']=base_turn_drag
	stats['enemy_mask']=enemy_mask
	stats['collision_layer']=collision_layer
	stats['team']=team
	stats['enemy_team']=enemy_team
	stats['rotation']=rotation
	stats['position']=Vector3(translation.x,0,translation.z)
	stats['transform']=transform
	stats['empty_mass']=base_mass
	stats['armor_density']=armor_density
	stats['fuel_density']=fuel_density
	stats['drag']=base_drag
	stats['weapons']=Array()
	stats['equipment']=Array()
	
	# Used for text generation, not CombatEngine:
	stats['display_name']=ship_display_name
	stats['help_page']=help_page
	skipped_runtime_stats = skip_runtime_stats

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
	combined_stats['aabb']=get_combined_aabb()
	skipped_runtime_stats=false

func make_cell(key,value) -> String:
	return '[cell]'+key+'[/cell][cell]'+str(value)+'[/cell]'

func max_and_repair(key,maxval,repairval) -> String:
	if repairval>0:
		return make_cell(key,str(maxval)+' (+'+str(repairval)+'/s)')
	return make_cell(key,maxval)

func get_bbcode() -> String:
	return text_gen.make_ship_bbcode(pack_stats(true),true,'')

func _ready():
	var must_update: bool = false
	if not combined_stats.has('empty_mass'):
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
		height = (randi()%11)*1.99 - 8.445
	collision_mask=0
	mass=utils.ship_mass(combined_stats)
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
