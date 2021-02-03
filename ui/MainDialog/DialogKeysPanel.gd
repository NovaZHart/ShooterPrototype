extends game_state.KeyEditorStub

export var KeyPicker: PackedScene
export var RemoveTexture: Texture
export var AddTexture: Texture
export var EmptyTexture: Texture

const ALIGN_LEFT = 1
const ALIGN_RIGHT = 2
const FILL = 3
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

var picker_path: NodePath = NodePath()

class AddOrRemoveActionEvent extends undo_tool.Action:
	var action: String
	var event: InputEvent
	var add: bool
	func _init(action_: String,event_: InputEvent,add_: bool):
		action=action_
		event=event_
		add=add_
	func run() -> bool:
		if add:
			InputMap.action_add_event(action,event)
		else:
			InputMap.action_erase_event(action,event)
		return true
	func undo() -> bool:
		if add:
			InputMap.action_erase_event(action,event)
		else:
			InputMap.action_add_event(action,event)
		return true

class ChangeActionEvent extends undo_tool.Action:
	var action: String
	var old_event: InputEvent
	var new_event: InputEvent
	func _init(action_: String, old_event_: InputEvent, new_event_: InputEvent):
		action=action_
		old_event=old_event_
		new_event=new_event_
	func run() -> bool:
		InputMap.action_erase_event(action,old_event)
		InputMap.action_add_event(action,new_event)
		return true
	func undo() -> bool:
		InputMap.action_erase_event(action,new_event)
		InputMap.action_add_event(action,old_event)
		return true

var content = {}

signal page_selected

# Called when the node enters the scene tree for the first time.
func _ready():
	fill_keys()
	update_disabled_flags()
	$Scroll.rect_min_size.x = $Scroll/Panel.rect_size.x

func describe_event(event):
	if event is InputEventKey:
		return 'Key '+event.as_text()
	elif event is InputEventJoypadButton:
		var device = Input.get_joy_name(event.device)
		if not device:
			device = 'Joypad '+str(event.device)
		var button = Input.get_joy_button_string(event.button_index)
		return device+' '+button
	else:
		return event.as_text()

func add_button(text, callback, mode, action, event = null):
	var button = Button.new()
	button.text = text
	if mode==ALIGN_LEFT:
		button.size_flags_horizontal = 0
		button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	elif mode==ALIGN_RIGHT:
		button.size_flags_horizontal = 0
		button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	$Scroll/Panel.add_child(button)
	button.connect('pressed', self, callback, [
		action, event, button.get_path()
	])
	return button.get_path()

func add_texture(texture, callback, mode, action, event = null):
	var button = TextureButton.new()
	button.texture_normal = texture
	button.texture_disabled = EmptyTexture
	if texture==AddTexture:
		button.hint_tooltip = 'Add a shortcut'
	if mode==ALIGN_LEFT:
		button.size_flags_horizontal = 0
		button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	elif mode==ALIGN_RIGHT:
		button.size_flags_horizontal = 0
		button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	$Scroll/Panel.add_child(button)
	button.connect('pressed', self, callback, [
		action, event, button.get_path()
	])
	return button.get_path()

func add_label(text):
	var label = Label.new()
	label.text = text
	$Scroll/Panel.add_child(label)
	return label.get_path()

class SortByValue extends Reference:
	var dict
	func _init(dict_):
		dict = dict_
	func cmp(a,b):
		return dict[a]<dict[b]

func add_ui_for_action_event(action: String, event: InputEvent) -> bool:
	if not action in content:
		content[action] = {
			'label': add_label(action_text[action]),
			'texture': add_texture(AddTexture, 'add_action_event', ALIGN_RIGHT, action),
			'empty': add_label(''),
			'events': []
		}
	content[action]['events'].append({
				'event': event,
				'empty': add_label(''),
				'remove': add_texture(RemoveTexture,'remove_action_event',ALIGN_LEFT,action,event),
				'button': add_button(describe_event(event),'change_action_event',FILL,action,event),
			})
	update_disabled_flags()
	return true

func remove_children_for_event(dict: Dictionary):
	for key in dict:
		var path = dict.get(key,null)
		if path!=null and path is NodePath:
			var node = get_node_or_null(path)
			if node:
				node.queue_free()

func remove_ui_for_action_event(action: String, event: InputEvent) -> bool:
	var action_content = content.get(action,null)
	if not action_content:
		return false
	for index in range(len(action_content['events'])):
		if action_content['events'][index]['event'] == event:
			print('match at index '+str(index))
			remove_children_for_event(action_content['events'][index])
			action_content['events'].remove(index)
			update_disabled_flags()
			return true
	return false

func change_ui_for_action_event(action: String, old_event: InputEvent,
		new_event: InputEvent) -> bool:
	var action_content = content.get(action,null)
	if not action_content:
		return false
	for index in range(len(action_content['events'])):
		if action_content['events'][index]['event'] == old_event:
			print('match at index '+str(index))
			action_content['events'][index]['event'] = new_event
			var button = get_node_or_null(action_content['events'][index]['button'])
			if button:
				button.text = describe_event(new_event)
			return true
	return false

func fill_keys():
	var actions = action_text.keys()
	actions.sort_custom(SortByValue.new(action_text),'cmp')
	for action in actions:
		var events = InputMap.get_action_list(action)
		for event in events:
			var _discard = add_ui_for_action_event(action,event)

func update_disabled_flags():
	for action in content:
		if len(content[action]['events']) == 1:
			var remove_path = content[action]['events'][0]['remove']
			var remove = get_node_or_null(remove_path)
			if remove:
				remove.disabled = true
				remove.hint_tooltip = 'Cannot remove the last key.'
		elif len(content[action]['events']) > 1:
			var events = content[action]['events']
			for event in events:
				var remove = get_node_or_null(event['remove'])
				if remove:
					remove.disabled = false
					remove.hint_tooltip = 'Remove this key.'

func add_action_event(action,event,_path):
	game_state.input_edit_state.push(AddOrRemoveActionEvent.new(action,event,true))

func remove_action_event(action,event,_path):
	game_state.input_edit_state.push(AddOrRemoveActionEvent.new(action,event,false))

func change_action_event(action,event,_path):
	var picker = get_node_or_null(picker_path)
	if picker_path:
		picker.visible=false
		return
	picker = KeyPicker.instance()
	picker.replace_action = action
	picker.action_text = action_text
	picker.known_actions = content
	get_viewport().add_child(picker)
	picker_path = picker.get_path()
	picker.popup()
	while picker.visible:
		yield(get_tree(),'idle_frame')
	picker_path=NodePath()
	if picker.selected_event:
		game_state.input_edit_state.push(ChangeActionEvent.new(
			action,event,picker.selected_event))

func _on_DialogPageSelector_page_selected(page):
	emit_signal('page_selected',page)
