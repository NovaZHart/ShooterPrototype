extends Spatial

export var Projectile: PackedScene #= preload("res://Projectile.tscn")
export var projectile_lifetime: float = 0.7 setget set_projectile_lifetime,get_projectile_lifetime
export var projectile_speed: float = 100 setget set_projectile_speed,get_projectile_speed
export var wait_time: float = 0.1 setget set_wait_time,get_wait_time

signal shoot

func threat_at_time(var t: float) -> float:
	return ($Timer.wait_time+t)/$Timer.wait_time *4

func get_wait_time() -> float: return wait_time
func set_wait_time(f: float):
	wait_time=f
	$Timer.wait_time=f
func get_projectile_lifetime() -> float: return projectile_lifetime
func set_projectile_lifetime(f: float): projectile_lifetime=f
func get_projectile_speed() -> float: return projectile_speed
func set_projectile_speed(f: float): projectile_speed=f

func get_weapon_range() -> float:
	return projectile_speed*projectile_lifetime

const y_axis: Vector3 = Vector3(0,1,0)

func _enter_tree():
	$Timer.wait_time=wait_time

func shoot(ship_translation: Vector3, ship_rotation: float, ship_velocity: Vector3,
		ship_angular_velocity: float, team: int):
	if $Timer.time_left > 0:
		return # cannot fire yet
	var shot = Projectile.instance()
	if shot is RigidBody:
		shot.axis_lock_linear_y=true
		shot.contact_monitor=true
		shot.contacts_reported=1
	var rt = translation.rotated(y_axis,ship_rotation)
	shot.translation=ship_translation+rt
	var heading: Vector3 = Vector3(1,0,0).rotated(y_axis,ship_rotation)
	var to_center = asin(clamp(translation.z/(projectile_lifetime*projectile_speed),-1.0,1.0))
	shot.linear_velocity=(heading*projectile_speed + ship_velocity \
		+ ship_angular_velocity*rt.cross(y_axis)).rotated(y_axis,to_center)
	shot.rotation=Vector3(0,ship_rotation+to_center,0)
	shot.set_team(team)
	shot.set_lifetime(get_projectile_lifetime())
	$Timer.start()
	emit_signal('shoot',shot)
