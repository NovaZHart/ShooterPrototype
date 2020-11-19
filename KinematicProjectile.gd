extends KinematicBody

var team: int = 1 setget set_team,get_team
var enemy: int = 0 setget ,get_enemy
var linear_velocity: Vector3 setget set_linear_velocity,get_linear_velocity
export var damage: float = 50 setget set_damage,get_damage
export var threat: float = 9 setget set_threat,get_threat

func get_threat() -> float: return threat
func set_threat(f: float): threat=f
func get_damage() -> float: return damage
func set_damage(f: float): damage=f
func is_a_ship() -> bool: return false
func is_a_planet() -> bool: return false
func is_a_projectile() -> bool: return true
func is_immobile() -> bool: return false
func threat_at_time(var _t: float) -> float: return threat
func get_team(): return team
func get_enemy(): return enemy
func receive_damage(_f: float): pass
func get_velocity() -> Vector3: return linear_velocity

func set_linear_velocity(f: Vector3): linear_velocity=f
func get_linear_velocity() -> Vector3: return linear_velocity

func position_at_time(var t: float) -> Vector3:
	return get_position() + linear_velocity*t

func get_position() -> Vector3:
	return Vector3(translation[0],0,translation[2])

func set_team(var new_team: int):
	team=new_team
	enemy = 0 if team else 1
	collision_layer = 1 << (team*2+1)
	collision_mask = 1 << (enemy*2)

func set_lifetime(var seconds: float):
	$Timer.wait_time=seconds

func _physics_process(var delta: float):
	var movement = linear_velocity*delta
	var collision = move_and_collide(movement,true,true,true)
	if not collision:
		translation += movement
		return
	if collision.collider.has_method('receive_damage'):
		collision.collider.receive_damage(damage)
	queue_free()

func _ready():
	$Timer.start()

func _on_Timer_timeout():
	queue_free()
