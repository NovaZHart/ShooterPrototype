extends PopupPanel

signal cancel_pressed
signal button_pressed

var result = null

func get_cancel_button():
	return $Top/Buttons.get_node_or_null('Cancel')

func set_cancel_text(text: String):
	var cancel = get_cancel_button()
	if cancel:
		cancel.text = text

func get_button(index: int):
	return $Top/Buttons.get_child(index)

func get_button_count():
	return $Top/Buttons.get_child_count()

func remove_cancel():
	var cancel = get_cancel_button()
	if cancel:
		$Top/Buttons.remove_child(cancel)

func set_label_text(text: String):
	$Top/Label.text = text

func add_button(text,metadata,index=-1):
	$Top/Buttons.columns+=1
	var button = Button.new()
	button.text = text
	$Top/Buttons.add_child(button)
	button.connect('pressed',self,'_on_Button_pressed',[metadata,false])
	button.theme=theme
	if index>=0:
		$Top/Buttons.move_child(button,index)

func _on_Button_pressed(metadata, is_cancel):
	if is_cancel:
		emit_signal('cancel_pressed')
		result = null
	else:
		emit_signal('button_pressed',metadata)
		result = metadata
	set_visible(false)
