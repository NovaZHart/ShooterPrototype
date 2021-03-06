extends PopupPanel

var replace_action: String = 'ui_depart'
var known_actions: Dictionary = {}
var action_text: Dictionary = {}
var selected_event = null

func _ready():
	if get_tree().current_scene==self:
		call_deferred('popup')
	$All/Instructions.text = 'Press a keyboard or joypad button.'
	$All/Info.text = ''

func _process(_delta):
	if visible and not has_focus():
		grab_focus()
	if visible:
		raise()
		set_process_input(true)

func _input(event):
	if not is_visible_in_tree():
		return
	if event is InputEventMouseMotion:
		return
	if not (event is InputEventKey or event is InputEventJoypadButton):
#		$All/Info.text = 'Must be a keyboard or joypad button.'
		return
	if not event.is_action_type():
#		$All/Info.text = 'Must be a keyboard or joypad button.'
		return
	for action in known_actions:
		if action == replace_action:
			continue
		var action_content = known_actions[action]
		for event_content in action_content['events']:
			if event_content['event'] == event:
				$All/Info.text = 'Already used by '+action_text[action]+'.'
				return
	selected_event = event
	hide()
