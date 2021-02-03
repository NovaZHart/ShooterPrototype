extends Node

export var MainDialog: PackedScene

var dialog_path: NodePath = NodePath()

signal dialog_shown
signal dialog_hidden

func _exit_tree():
	if not dialog_path.is_empty():
		var node = get_node_or_null(dialog_path)
		if node:
			node.queue_free()

func _input(event):
	if dialog_path:
		return
	if not event.is_action_pressed('ui_cancel'):
		return
	var viewport: Viewport = get_viewport()
	if viewport.get_modal_stack_top()!=null:
		return
	get_tree().set_input_as_handled()
	var dialog = MainDialog.instance()
	if OK!=dialog.connect('hide',self,'_on_MainDialog_hide'):
		push_error('cannot connect to MainDialog hide signal')
		return
	viewport.add_child(dialog)
	dialog_path = dialog.get_path()
	emit_signal('dialog_shown')
	dialog.popup()
	yield(get_tree(),'idle_frame')
	
func _on_MainDialog_hide():
	emit_signal('dialog_hidden')
	var dialog = get_node_or_null(dialog_path)
	if dialog:
		dialog.queue_free()
	dialog_path = NodePath()
