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
const input_dir: String = 'user://config'
const input_path: String = input_dir+'/input.json'

var default_actions = null
var loaded_actions = null

func encode_actions():
	var action_events: Dictionary = {}
	var action_names = action_text.keys()
	for action_name in action_names:
		action_events[action_name] = InputMap.get_action_list(action_name)
		assert(action_events[action_name][0] is InputEvent)
	return game_state.universe.encode_helper(action_events)

func save():
	var encoded = encode_actions()
	save_actions(encoded)
	loaded_actions = encoded

func set_actions(encoded):
	var decoded = game_state.universe.decode_helper(encoded)
	if not decoded:
		push_error('Could not decode actions in set_actions')
		return
	for action in decoded:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		else:
			InputMap.action_erase_events(action)
		for event in decoded[action]:
			InputMap.action_add_event(action,event)

func save_actions(encoded,path=input_path):
	var json_string = JSON.print(encoded,'  ')
	var file: File = File.new()
	if OK!=file.open(path,File.WRITE):
		push_error('Could not open "'+path+'" for writing.')
		return false
	file.store_string(json_string)
	file.close()

func load_actions(path=input_path):
	var file: File = File.new()
	if OK!=file.open(path,File.READ):
		push_error('Could not open "'+path+'" for reading.')
		return null
	var json_string = file.get_as_text()
	file.close()
	var parsed: JSONParseResult = JSON.parse(json_string)
	if parsed.error:
		push_error(path+':'+str(parsed.error_line)+': '+parsed.error_string)
		return null
	return parsed.result
#	var decoded = game_state.universe.decode_helper(parsed.result)
#	if not decoded or not decoded is Dictionary:
#		push_error('Could not understand input key data in "'+path+'"')
#		return null
#	return decoded

func _init():
	default_actions = encode_actions()
	
	var dir: Directory = Directory.new()
# warning-ignore:return_value_discarded
	dir.make_dir(input_dir)
	
	var file: File = File.new()
	if file.file_exists(input_path):
		loaded_actions = load_actions()
	if not loaded_actions:
		loaded_actions = encode_actions()
	else:
		set_actions(loaded_actions)
