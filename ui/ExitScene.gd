extends Node

var stage = 0

func _enter_tree():
	get_tree().paused = false

func _process(delta):
	stage += 1
	print('stage '+str(stage))
	if stage == 1:
		PreloadResources.free_all_resources()
	if stage == 3:
		combat_engine.free_all_resources()
	if stage == 5:
		game_state.universe.free_all_resources()
	if stage == 7:
		set_process(false)
		get_tree().quit()
