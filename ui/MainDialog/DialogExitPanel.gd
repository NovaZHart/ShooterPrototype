extends Panel

export var exit_countdown_start = 0.1
export var cancel_button_text = 'Cancel'
export var countdown_label_format = 'Program shutdown in 0:%06.3f.'

var exit_countdown: float = INF
var initial_label: String
var initial_button: String

signal page_selected

func _ready():
	initial_label = $Grid/Label.text
	initial_button = $Grid/Button.text

func _process(delta):
	if not is_visible_in_tree():
		return
	
	if exit_countdown>0:
		exit_countdown -= delta
	if exit_countdown<INF:
		$Grid/Label.text = countdown_label_format % max(1e-9,exit_countdown)
	if exit_countdown<=0:
		game_state.call_deferred('change_scene','res://ui/ExitScene.tscn')
	
func _on_Button_pressed():
	if exit_countdown == INF:
		exit_countdown = clamp(exit_countdown_start,0.05,3)
		$Grid/Button.text = 'Cancel'
		set_process(true)
	else:
		exit_countdown = INF
		$Grid/Label.text = initial_label
		$Grid/Button.text = initial_button
		set_process(false)

func _on_DialogPageSelector_page_selected(page):
	emit_signal('page_selected',page)

func _on_MainMenu_pressed():
	get_tree().paused=false
	game_state.call_deferred('change_scene','res://ui/MainScreen/MainScreen.tscn')
