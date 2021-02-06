extends Panel

# Called when the node enters the scene tree for the first time.
func _ready():
	$Message.text = ''
	$Center/Grid/PlayerName.grab_focus()

func _input(event):
	if event.is_action_pressed('ui_cancel'):
		game_state.call_deferred('change_scene','res://ui/MainScreen/MainScreen.tscn')

func maybe_start_game(player_name: String):
	var clipped = player_name.strip_edges()
	if not clipped:
		$Message.text = 'Enter a name first!'
		return
	Player.player_name = clipped
	game_state.call_deferred('change_scene','res://ui/OrbitalScreen.tscn')

func _on_PlayerName_text_entered(new_text):
	maybe_start_game(new_text)

func _on_Button_pressed():
	maybe_start_game($Center/Grid/PlayerName.text)

func _on_Cancel_pressed():
	game_state.call_deferred('change_scene','res://ui/MainScreen/MainScreen.tscn')
