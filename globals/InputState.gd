extends Node

const action_text: Dictionary = {
	'ui_depart': 'Depart/Deorbit',
	'ui_land': 'Orbit/Land',
	'ui_pause': 'Pause',
	'ui_next_enemy': 'Next Enemy',
	'ui_next_planet': 'Next Planet/Star',
	'ui_select': 'Fire/Select',
	'ui_intercept': 'Intercept',
	'ui_evade': 'Evade',
	'ui_toggle_auto_targeting': 'Toggle Auto-Targetting',
	'ui_deselect_target': 'Deselect Target',
}
var input_path = 'user://config/input.json'

var default_actions
var loaded_actions

func encode_actions():
	var action_events: Dictionary = {}
	var action_names = action_text.keys()
	for action_name in action_names:
		action_events[action_name] = InputMap.get_action_list(action_name)
	return game_state.universe.encode_helper(action_events)

func save():
	var encoded = encode_actions()
	save_actions(encoded)
	loaded_actions = encoded

func save_actions(encoded,path=input_path):
	var json_string = JSON.print(encoded,'  ')
	var file: File = File.new()
	if OK!=file.open(path,File.WRITE):
		return false
	file.store_string(json_string)
	file.close()

func load_actions(path=input_path):
	var file: File = File.new()
	if OK!=file.open(path,File.READ):
		return false
	var json_string = file.get_as_text()
	file.close()
	var parsed: JSONParseResult = JSON.parse(json_string)
	if parsed.error:
		push_error(path+':'+str(parsed.error_line)+': '+parsed.error_string)
		return false

func _init():
	default_actions = encode_actions()
	loaded_actions = load_actions()
	if not loaded_actions:
		loaded_actions = encode_actions()
