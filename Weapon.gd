extends Timer

export var Projectile: PackedScene #= preload("res://Projectile.tscn")

signal shoot

func threat_at_time(var t: float) -> float:
	return (wait_time+t)/wait_time *4

func get_projectile_lifetime() -> float:
	return 0.7

func initial_projectile_speed() -> float:
	return 100.0

func predict_projectile_velocity(var ship_rotation: float, var ship_velocity: Vector3) -> Vector3:
	var heading: Vector3 = Vector3(1,0,0).rotated(Vector3(0,1,0),ship_rotation)
	return heading*initial_projectile_speed() + ship_velocity

func shoot(var translation: Vector3, var rotation: float, var velocity: Vector3, var team: int):
	if time_left > 0:
		return # cannot fire yet
	var shot = Projectile.instance()
	shot.axis_lock_linear_y=true
	shot.contact_monitor=true
	shot.contacts_reported=1
	shot.translation=translation
	shot.linear_velocity=predict_projectile_velocity(rotation,velocity)
	shot.rotation=Vector3(0,rotation,0)
	shot.set_team(team)
	shot.set_lifetime(get_projectile_lifetime())
	start()
	emit_signal('shoot',shot)
