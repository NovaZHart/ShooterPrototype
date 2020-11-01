extends RigidBody

var team: int = 1 setget set_team,get_team
var enemy: int = 0 setget ,get_enemy

func get_damage() -> int: return 50
func is_a_ship() -> bool: return false
func is_a_planet() -> bool: return false
func is_a_projectile() -> bool: return true
func is_immobile() -> bool: return false
func get_velocity() -> Vector3: return linear_velocity
func threat_at_time(var _t: float) -> float: return 9.0
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

func set_lifetime(var seconds: float):
	$Timer.wait_time=seconds

func _init():
	custom_integrator = true

func _ready():
	$Timer.start()

func _on_Timer_timeout():
	queue_free()
