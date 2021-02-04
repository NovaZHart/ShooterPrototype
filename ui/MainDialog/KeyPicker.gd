extends PopupPanel

var replace_action: String = 'ui_depart'
var known_actions: Dictionary = {}
var action_text: Dictionary = {}
var selected_event = null

func _ready():
	print('picker ready')
	$All/Instructions.text = 'Press a keyboard or joypad button.'
	$All/Info.text = ''

func _input(event):
	print('picker event '+str(event))
	if not is_visible_in_tree():
		print('skip - not visible in tree')
		return
	if event is InputEventMouseMotion:
		print('skip - is mouse motion')
	if not (event is InputEventKey or event is InputEventJoypadButton):
		print('skip - not right event type')
		$All/Info.text = 'Must be a keyboard or joypad button.'
		return
	if not event.is_action_type():
		print('skip - is not action type')
		$All/Info.text = 'Must be a keyboard or joypad button.'
		return
	for action in known_actions:
		if action == replace_action:
			continue
		var action_content = known_actions[action]
		for event_content in action_content['events']:
			if event_content['event'] == event:
				$All/Info.text = 'Already used by '+action_text[action]+'.'
				print('already used')
				return
	print('selected event')
	selected_event = event
	hide()
