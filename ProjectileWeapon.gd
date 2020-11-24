extends Spatial

export var Projectile: PackedScene #= preload("res://Projectile.tscn")
export var wait_time: float = 0.1 setget set_wait_time,get_wait_time

var projectile_guided: bool = false setget ,get_projectile_guided
var projectile_lifetime: float = 0.7 setget ,get_projectile_lifetime
var projectile_speed: float = 100 setget ,get_projectile_speed
var projectile_max_threat: float = 0 setget ,get_projectile_max_threat
var turning_rate: float = 0 setget set_turning_rate, get_turning_rate

signal shoot

func is_secondary() -> bool: return false
func threat_at_time(var t: float) -> float:
	return projectile_max_threat * t/wait_time
func is_a_turret() -> bool: return turning_rate>1e-5
func is_ready() -> bool:
	var timer=get_node_or_null('Timer')
	return timer==null or not timer.time_left>0
func get_wait_time() -> float: return wait_time
func set_wait_time(f: float):
	wait_time=max(0.99/60,f)
	var timer=get_node_or_null('Timer')
	if timer!=null:
		timer.wait_time=max(0.99/60,f)
func get_projectile_guided() -> bool: return projectile_guided
func get_projectile_lifetime() -> float: return projectile_lifetime
func get_projectile_speed() -> float: return projectile_speed
func get_projectile_max_threat() -> float: return projectile_max_threat
func set_turning_rate(f: float): turning_rate=f
func get_turning_rate() -> float: return turning_rate

func get_weapon_range() -> float:
	return projectile_speed*projectile_lifetime

const y_axis: Vector3 = Vector3(0,1,0)

func _ready():
	var timer=get_node_or_null('Timer')
	if timer!=null:
		$Timer.wait_time=wait_time
	var n: Spatial = Projectile.instance()
	n.visible=false
	add_child(n)
	projectile_guided = n.guided
	projectile_lifetime = n.get_lifetime()
	projectile_speed = n.max_speed
	projectile_max_threat = n.get_max_threat()
	remove_child(n)
	n.queue_free()

func shoot(ship_translation: Vector3, ship_rotation: float, ship_velocity: Vector3,
		ship_angular_velocity: float, team: int, target_path: NodePath):
	var timer=get_node_or_null('Timer')
	if timer!=null and timer.time_left>0:
		return # cannot fire yet
	var shot = Projectile.instance()
	var rt = translation.rotated(y_axis,ship_rotation)
	shot.translation=ship_translation+rt
	var heading: Vector3 = Vector3(1,0,0).rotated(y_axis,ship_rotation)
	var to_center = asin(clamp(translation.z/(projectile_lifetime*projectile_speed),-1.0,1.0))
	shot.linear_velocity=(heading*projectile_speed + ship_velocity \
		+ ship_angular_velocity*rt.cross(y_axis)).rotated(y_axis,to_center)
	shot.rotation=Vector3(0,ship_rotation+to_center,0)
	shot.set_team(team)
	if not target_path.is_empty() and shot.has_method('set_target_path'):
		shot.target_path=target_path
	if timer!=null:
		$Timer.start()
	emit_signal('shoot',shot)
