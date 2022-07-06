extends Node

func _enter_tree():
	get_tree().paused = false

func _ready():
	call_deferred('free_all_resources')

func free_all_resources():
	print('ExitScene is freeing all resources')
	PreloadResources.free_all_resources()
	combat_engine.free_all_resources()
	game_state.universe.free_all_resources()
	call_deferred('exit_program')

func exit_program():
	print('ExitScene is exiting')
	get_tree().quit()
