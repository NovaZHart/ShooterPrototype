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
	'ui_next_enemy': 'Select Enemy',
	'ui_next_planet': 'Select Planet/Star',
	'ui_select': 'Fire/Select',
	'ui_intercept': 'Intercept',
	'ui_toggle_auto_targeting': 'Toggle Auto-Targetting',
	'ui_deselect_target': 'Deselect Target',
}

var undo_stack_top_at_last_save = null
var picker_path: NodePath = NodePath()
var content = {}

signal page_selected

class SwapState extends undo_tool.Action:
	var old_actions: Dictionary
	var new_actions: Dictionary
	func _init(new_actions_):
		new_actions=new_actions_
	func run() -> bool:
		old_actions = input_state.encode_actions()
		return redo()
	func undo() -> bool:
		input_state.set_actions(old_actions)
		game_state.key_editor.reread_input_map()
		return true
	func redo() -> bool:
		input_state.set_actions(new_actions)
		game_state.key_editor.reread_input_map()
		return true

class AddOrRemoveActionEvent extends undo_tool.Action:
	var action: String
	var event: InputEvent
	var add: bool
	var index: int
	func _init(action_: String,event_: InputEvent,add_: bool,index_: int):
		action=action_
		event=event_
		add=add_
		index=index_
		assert(event is InputEvent)
	func run() -> bool:
		assert(event is InputEvent)
		print('run ',add)
		if add:
			InputMap.action_add_event(action,event)
			game_state.key_editor.add_ui_for_action_event(action,event,index)
		else:
			game_state.key_editor.remove_ui_for_action_event(action,event,index)
			InputMap.action_erase_event(action,event)
		return true
	func undo() -> bool:
		print('undo ',add)
		if add:
			InputMap.action_erase_event(action,event)
			game_state.key_editor.remove_ui_for_action_event(action,event,index)
		else:
			InputMap.action_add_event(action,event)
			game_state.key_editor.add_ui_for_action_event(action,event,index)
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
		print('run')
		InputMap.action_erase_event(action,old_event)
		InputMap.action_add_event(action,new_event)
		game_state.key_editor.change_ui_for_action_event(action,old_event,new_event)
		return true
	func undo() -> bool:
		InputMap.action_erase_event(action,new_event)
		InputMap.action_add_event(action,old_event)
		game_state.key_editor.change_ui_for_action_event(action,new_event,old_event)
		return true

func _exit_tree():
	game_state.input_edit_state.disconnect('undo_stack_changed',self,'update_buttons')
	game_state.input_edit_state.disconnect('redo_stack_changed',self,'update_buttons')
	game_state.set_key_editor(null)
	input_state.save()

func _ready():
	game_state.input_edit_state.connect('undo_stack_changed',self,'update_buttons')
	game_state.input_edit_state.connect('redo_stack_changed',self,'update_buttons')
	game_state.set_key_editor(self)
	fill_keys()
	update_disabled_flags()
	update_buttons()
	$All/Right/Scroll.rect_min_size.x = $All/Right/Scroll/Panel.rect_size.x

func update_buttons():
	$All/Right/Buttons/Redo.disabled = game_state.input_edit_state.redo_stack.empty()
	$All/Right/Buttons/Undo.disabled = game_state.input_edit_state.undo_stack.empty()
#	$All/Right/Buttons/Save.disabled = undo_stack_top_at_last_save==null \
#		or not game_state.input_edit_state.top() \
#		or game_state.input_edit_state.top().get_instance_id() != \
#		undo_stack_top_at_last_save

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

func add_button(text, callback, mode, action, event = null, prior = null):
	var button = Button.new()
	button.text = text
	if mode==ALIGN_LEFT:
		button.size_flags_horizontal = 0
		button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	elif mode==ALIGN_RIGHT:
		button.size_flags_horizontal = 0
		button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child_maybe_after($All/Right/Scroll/Panel,button,prior)
	var _discard = button.connect('mouse_entered',self,'show_help_for',[action])
	button.connect('pressed', self, callback, [
		action, event, button.get_path()
	])
	return button.get_path()

func add_child_maybe_after(parent,child, prior):
	if prior:
		parent.add_child_below_node(prior,child)
	else:
		parent.add_child(child)

func add_texture(texture, callback, mode, action, event = null, prior = null):
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
	add_child_maybe_after($All/Right/Scroll/Panel,button,prior)
	button.connect('pressed', self, callback, [
		action, event, button.get_path()
	])
	return button.get_path()

func add_label(text,prior=null,action=null):
	var label = Label.new()
	label.text = text
	add_child_maybe_after($All/Right/Scroll/Panel,label,prior)
	if action:
		var _discard = label.connect('mouse_entered',self,'show_help_for',[action])
		label.mouse_filter = Control.MOUSE_FILTER_PASS
	return label.get_path()

func show_help_for(action):
	$All/Left/Consoles/Info.process_command('help controls/'+action)

class SortByValue extends Reference:
	var dict
	func _init(dict_):
		dict = dict_
	func cmp(a,b):
		return dict[a]<dict[b]

func add_ui_for_action_event(action: String, event: InputEvent, index: int) -> bool:
	print('add ui for '+action+' event '+str(event))
	if not action in content:
		content[action] = {
			'label': add_label(action_text[action],null,action),
			'texture': add_texture(AddTexture, 'add_action_event', ALIGN_RIGHT, action),
			'empty': add_label(''),
			'events': []
		}
	
	var prior = null
	if index>=0:
		var prior_path = null
		if index==0:
			prior_path = content[action]['empty']
		else:
			prior_path = content[action]['events'][index-1]['button']
		prior = get_node_or_null(prior_path)
		if not prior:
			push_error('Node missing at path '+str(prior)+' when trying to add an event for '+action+' at index '+str(index))
			return false
	else:
		index = len(content[action]['events'])
	
	var empty
	var remove
	var button
	if prior:
		button = add_button(describe_event(event),'change_action_event',FILL,action,event,prior)
		remove = add_texture(RemoveTexture,'remove_action_event',ALIGN_LEFT,action,event,prior)
		empty = add_label('',prior)
	else:
		empty = add_label('',prior)
		remove = add_texture(RemoveTexture,'remove_action_event',ALIGN_LEFT,action,event,prior)
		button = add_button(describe_event(event),'change_action_event',FILL,action,event,prior)
		
	content[action]['events'].insert(index,{
		'event': event, 'empty':empty, 'remove':remove, 'button':button
	})
	
	update_disabled_flags()
	return true

func index_of_action_event(action: String, event: InputEvent) -> int:
	if not action in content:
		push_warning('Tried to get index of an action "'+action+'" that was never added.')
		return -1
	var num_events = len(content[action]['events'])
	for i in range(num_events):
		if content[action]['events'][i]['event'] == event:
			return i
	push_warning('Could not find '+str(event)+' in action "'+action+'".')
	return -1

func remove_children_for_event(dict: Dictionary):
	for key in dict:
		var path = dict.get(key,null)
		if path!=null and path is NodePath:
			var node = get_node_or_null(path)
			if node:
				node.queue_free()

func remove_ui_for_action_event(action: String, event: InputEvent, index: int) -> bool:
	print('remove ui for '+action)
	var action_content = content.get(action,null)
	if not action_content:
		return false
	if len(action_content['events']) <= index:
		push_warning('Tried to remove event at index '+str(index) \
			+' which is past the end of the action '+action \
			+' array, length '+str(len(action_content['events'])))
		return false
	if action_content['events'][index]['event']!=event:
		push_warning('Tried to move a mismatched event from index '+str(index) \
			+' in action '+str(action)+'. Expected "'+str(event) \
			+'", found "'+str(action_content['events'][index]['event']))
		return false
	remove_children_for_event(action_content['events'][index])
	action_content['events'].remove(index)
	update_disabled_flags()
	return true

func change_ui_for_action_event(action: String, old_event: InputEvent,
		new_event: InputEvent) -> bool:
	print('change ui for action event')
	var action_content = content.get(action,null)
	if not action_content:
		print('action ',action,' has no content')
		return false
	for index in range(len(action_content['events'])):
		print('index ',index)
		if action_content['events'][index]['event'] == old_event:
			print('match at index '+str(index))
			action_content['events'][index]['event'] = new_event
			var button = get_node_or_null(action_content['events'][index]['button'])
			if button:
				button.text = describe_event(new_event)
			return true
		else:
			print('no match')
	return false

func reread_input_map():
	while $All/Right/Scroll/Panel.get_child_count() > 3:
		var child = $All/Right/Scroll/Panel.get_child(3)
		if child:
			$All/Right/Scroll/Panel.remove_child(child)
			child.queue_free()
		else:
			break # should never get here
	fill_keys()

func fill_keys():
	content = {}
	var actions = action_text.keys()
	actions.sort_custom(SortByValue.new(action_text),'cmp')
	for action in actions:
		var events = InputMap.get_action_list(action)
		for n in range(len(events)):
			var _discard = add_ui_for_action_event(action,events[n],-1)

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

func pick_event(action: String):
	var picker = get_node_or_null(picker_path)
	if picker:
		picker.visible=false
		return null
	picker = KeyPicker.instance()
	picker.replace_action = action
	picker.action_text = action_text
	picker.known_actions = content
	get_tree().root.add_child(picker)
	picker_path = picker.get_path()
	print('picker popup')
	picker.popup()
	assert(picker.visible)
	while picker.visible:
		yield(get_tree(),'idle_frame')
	var result = picker.selected_event
	print('picker returned '+str(result))
	if picker:
		get_tree().root.remove_child(picker)
	picker_path=NodePath()
	return result

func add_action_event(action,_event,_path):
	print("pick event")
	var picked = pick_event(action)
	while picked is GDScriptFunctionState and picked.is_valid():
		picked = yield(picked, 'completed')
	print('returned from pick event')
	if picked:
		assert(picked is InputEvent)
		game_state.input_edit_state.push(AddOrRemoveActionEvent.new(action,picked,true,0))

func remove_action_event(action,event,_path):
	assert(event is InputEvent)
	game_state.input_edit_state.push(AddOrRemoveActionEvent.new(action,event,false,
		index_of_action_event(action,event)))

func change_action_event(action,event,_path):
	assert(event is InputEvent)
	var picked = pick_event(action)
	while picked is GDScriptFunctionState and picked.is_valid():
		picked = yield(picked, 'completed')
	if picked:
		print('event selected')
		game_state.input_edit_state.push(ChangeActionEvent.new(action,event,picked))
	else:
		print('no event picked')

func _on_DialogPageSelector_page_selected(page):
	emit_signal('page_selected',page)

func _input(event):
	if is_visible_in_tree() and not picker_path:
		if event.is_action_pressed('ui_undo'):
			game_state.input_edit_state.undo()
		elif event.is_action_pressed('ui_redo'):
			game_state.input_edit_state.redo()

func _on_Undo_pressed():
	game_state.input_edit_state.undo()

func _on_Redo_pressed():
	game_state.input_edit_state.redo()

func _on_Save_pressed():
	input_state.save()
#	undo_stack_top_at_last_save = game_state.input_edit_state.top().get_instance_id()
#	update_buttons()

func _on_Revert_pressed():
	game_state.input_edit_state.push(SwapState.new(input_state.loaded_actions))

func _on_Default_pressed():
	game_state.input_edit_state.push(SwapState.new(input_state.default_actions))
