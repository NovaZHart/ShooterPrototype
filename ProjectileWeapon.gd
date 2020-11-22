extends Spatial

export var Projectile: PackedScene #= preload("res://Projectile.tscn")
export var wait_time: float = 0.1 setget set_wait_time,get_wait_time

var projectile_guided: bool = false setget ,get_projectile_guided
var projectile_lifetime: float = 0.7 setget ,get_projectile_lifetime
var projectile_speed: float = 100 setget ,get_projectile_speed

signal shoot

func threat_at_time(var t: float) -> float:
	return ($Timer.wait_time+t)/$Timer.wait_time *4
func is_a_turret() -> bool: return false
func get_wait_time() -> float: return wait_time
func set_wait_time(f: float):
	wait_time=f
	$Timer.wait_time=f
func get_projectile_guided() -> bool: return projectile_guided
func get_projectile_lifetime() -> float: return projectile_lifetime
func get_projectile_speed() -> float: return projectile_speed

func get_weapon_range() -> float:
	return projectile_speed*projectile_lifetime

const y_axis: Vector3 = Vector3(0,1,0)

func _ready():
	$Timer.wait_time=wait_time
	var n: Spatial = Projectile.instance()
	n.visible=false
	add_child(n)
	projectile_guided = n.guided
	projectile_lifetime = n.get_lifetime()
	projectile_speed = n.max_speed
	remove_child(n)
	n.queue_free()

func shoot(ship_translation: Vector3, ship_rotation: float, ship_velocity: Vector3,
		ship_angular_velocity: float, team: int, target_path: NodePath):
	if $Timer.time_left > 0:
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
	$Timer.start()
	emit_signal('shoot',shot)
