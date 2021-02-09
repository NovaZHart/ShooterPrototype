extends Node2D

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func _process(_delta):
	var thrust: int = int(Input.is_action_pressed('ui_up'))-int(Input.is_action_pressed('ui_down'))
	var rotate: int = int(Input.is_action_pressed('ui_left'))-int(Input.is_action_pressed('ui_right'))
	var land: bool = Input.is_action_just_pressed('ui_land')
	var next_planet: bool = Input.is_action_just_pressed('ui_next_planet')
