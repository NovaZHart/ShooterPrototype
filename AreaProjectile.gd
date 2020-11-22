extends Area

var team: int = 1 setget set_team,get_team
var enemy: int = 0 setget ,get_enemy
var linear_velocity: Vector3 setget set_linear_velocity,get_linear_velocity
var angular_velocity: Vector3 setget set_angular_velocity,get_angular_velocity
export var damage: float = 50 setget set_damage,get_damage
export var threat: float = 9 setget set_threat,get_threat
export var lifetime: float = 0.7 setget set_lifetime,get_lifetime
export var guided: bool = false setget set_guided,get_guided
export var guidance_uses_velocity: bool = true setget set_guidance_uses_velocity, get_guidance_uses_velocity
var target_path: NodePath setget set_target_path, get_target_path

export var thrust: float = 100 setget set_thrust,get_thrust
export var mass: float = 1 setget set_mass,get_mass # only used for thrust=>acceleration
export var max_speed: float = 50 setget set_max_speed,get_max_speed
export var max_angular_velocity: float = 5 setget set_max_angular_velocity,get_max_angular_velocity

signal launch
signal hit
signal timeout

func get_angular_velocity() -> Vector3: return angular_velocity
func set_angular_velocity(f: Vector3): angular_velocity=f
func get_linear_velocity() -> Vector3: return linear_velocity
func set_linear_velocity(f: Vector3): linear_velocity=f

func get_threat() -> float: return threat
func set_threat(f: float): threat=f
func get_damage() -> float: return damage
func set_damage(f: float): damage=f
func get_guided() -> bool: return guided
func set_guided(f: bool): guided=f
func get_guidance_uses_velocity() -> bool: return guidance_uses_velocity
func set_guidance_uses_velocity(f: bool): guidance_uses_velocity=f
func get_target_path() -> NodePath: return target_path
func set_target_path(f: NodePath): target_path=f
func set_thrust(f: float): thrust=f
func get_thrust() -> float: return thrust
func set_mass(f: float): mass=f
func get_mass() -> float: return mass
func get_reverse_thrust() -> float: return 0.0
func set_max_speed(f: float): max_speed=f
func get_max_speed() -> float: return max_speed
func set_max_angular_velocity(f: float): max_angular_velocity=f
func get_max_angular_velocity(): return max_angular_velocity

func is_a_ship() -> bool: return false
func is_a_planet() -> bool: return false
func is_a_projectile() -> bool: return true
func is_immobile() -> bool: return false
func get_velocity() -> Vector3: return linear_velocity
func threat_at_time(var _t: float) -> float: return threat
func get_team(): return team
func get_enemy(): return enemy
func receive_damage(_f: float): pass

func position_at_time(var t: float) -> Vector3:
	return get_position() + linear_velocity*t

func get_position() -> Vector3:
	return Vector3(translation[0],0,translation[2])

func set_team(var new_team: int):
	team=new_team
	enemy = 0 if team else 1
	collision_layer = 1 << (team*2+1)
	collision_mask = 1 << (enemy*2)

func set_lifetime(f: float):
	lifetime=f
	if get_node_or_null("Timer")!=null:
		$Timer.wait_time=lifetime
func get_lifetime() -> float:
	return lifetime

func _on_body_entered(body: Node):
	if body.has_method('receive_damage'):
		body.receive_damage(damage)
	emit_signal('hit',body,damage)
	queue_free()

func guide_if_have_target(delta: float):
	if not guided:
		return
	if target_path.is_empty():
		angular_velocity=Vector3(0,0,0)
		return
	var target=get_node_or_null(target_path)
	if target==null or not target.has_method('is_a_ship') or not target.is_a_ship():
		# Invalid target
		target_path=NodePath()
	elif not target.is_alive():
		target_path=NodePath()
	else:
		ship_tool.guide_AreaProjectile(self,delta,target,guidance_uses_velocity)

func _physics_process(delta: float):
	guide_if_have_target(delta)
	translation += delta*linear_velocity
	rotation += delta*angular_velocity

func _init():
	var _discard=connect('body_entered',self,'_on_body_entered')

func _ready():
	$Timer.wait_time=lifetime
	$Timer.start()
	emit_signal('launch')

func _on_Timer_timeout():
	emit_signal('timeout')
	queue_free()
