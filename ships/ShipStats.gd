extends RigidBody

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
	if node is VisualInstance:
		node.set_layer_mask(4)
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
	init_ship_recursively()
