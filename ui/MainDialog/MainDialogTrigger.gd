extends Node

export var MainDialog: PackedScene
export var allow_saving: bool = true

var dialog_path: NodePath = NodePath()

signal dialog_shown
signal dialog_hidden

func _ready():
	if game_state.restore_from_load_page:
		call_deferred('restore_from_load_page')

func restore_from_load_page():
	show_main_dialog()

func _exit_tree():
	if not dialog_path.is_empty():
		var node = get_node_or_null(dialog_path)
		if node:
			node.queue_free()

func _input(event):
	if not event.is_action_pressed('ui_cancel'):
		return
	var viewport: Viewport = get_viewport()
	if viewport.get_modal_stack_top()!=null:
		return
	get_tree().set_input_as_handled()
	show_main_dialog()

func show_main_dialog():
	if dialog_path:
		return
	var dialog = MainDialog.instance()
	if OK!=dialog.connect('hide',self,'_on_MainDialog_hide'):
		push_error('cannot connect to MainDialog hide signal')
		return
	var viewport: Viewport = get_viewport()
	viewport.add_child(dialog)
	dialog.allow_saving = allow_saving
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
