extends Control

export var ConfirmDialog: PackedScene
export var restore_from_load_page: bool = true

signal save_selected
signal game_loaded
signal save_deleted
signal save_replaced
signal save_created
signal saves_rescanned
signal no_save_selected

var allow_saving: bool = true setget set_allow_saving, get_allow_saving
var dialog_path: NodePath = NodePath()
var dialog_cancel_pressed: bool
var last_selected_savefile: String = ''

func get_allow_saving() -> bool:
	allow_saving = $SaveList.allow_saving
	return allow_saving

func set_allow_saving(flag: bool):
	$SaveList.allow_saving = flag
	allow_saving = flag

func _ready():
	$SaveList.allow_saving = allow_saving

func update_buttons(save_selected):
	for child_name in [ 'Load', 'Overwrite', 'Delete' ]:
		var child = $Center/Buttons.get_node_or_null(child_name)
		if child:
			child.set_disabled(not save_selected)

func _on_SaveList_new_save(savefile):
	print('save list new save')
	var encoded = Player.store_state()
	if not Player.write_save_file(Player.store_state(),savefile):
		push_error('Could not write the save file')
	else:
		print('insert new save')
		$SaveList.insert_save_data(savefile,encoded)
	last_selected_savefile = ''
	update_buttons(false)
	emit_signal('save_created',savefile,encoded)

func _on_SaveList_save_selected(savefile,data):
	print('save list save selected')
	last_selected_savefile = savefile
	update_buttons(true)
	emit_signal('save_selected',savefile,data)

func _on_Cancel_pressed_pressed():
	dialog_cancel_pressed = true

func confirm(what) -> bool:
	var dialog = get_node_or_null(dialog_path)
	if dialog:
		dialog_cancel_pressed = true
		dialog.visible = false
		return false
	dialog = ConfirmationDialog.new()
	var label = Label.new()
	label.text = what
	dialog_cancel_pressed = false
	if OK!=dialog.get_cancel().connect("pressed", self, "_on_Cancel_pressed"):
		push_error('Could not connect to cancel button.')
		return false
	label.name = 'Label'
	dialog.add_child(label)
	get_tree().get_root().add_child(dialog)
	dialog_path = dialog.get_path()
	dialog.popup_centered()
	print('enter loop')
	while dialog.visible:
		print('in loop')
		var view_size = get_viewport().size
		var pos = (view_size-dialog.rect_size)/2
		if dialog.rect_global_position != pos:
			dialog.rect_global_position = pos
		print('yield idle frame')
		yield(get_tree(),'idle_frame')
	print('past loop')
	get_tree().get_root().remove_child(dialog)
	dialog.queue_free()
	dialog_path = NodePath()
	print('return')
	return not dialog_cancel_pressed

func basename(savefile: String) -> String:
	var split = savefile.split('/',false)
	return split[len(split)-1]

func _on_Load_pressed():
	print('load')
	var fil = last_selected_savefile
	if fil:
#		var confirmed = confirm('Load '+basename(fil)+'?')
#		while confirmed is GDScriptFunctionState and confirmed.is_valid():
#			confirmed = yield(confirmed,'completed')
#		if not confirmed:
#			return
		var read = Player.read_save_file(fil)
		if read:
			Player.call_deferred('restore_state',read,restore_from_load_page)
			emit_signal('game_loaded',fil)

func _on_Delete_pressed():
	print('delete')
	if last_selected_savefile:
		var savefile: String = last_selected_savefile
		var confirmed = confirm('Delete '+basename(savefile)+'?')
		while confirmed is GDScriptFunctionState and confirmed.is_valid():
			confirmed = yield(confirmed,'completed')
			print('yield')
		print('returned')
		if not confirmed:
			print('not confirmed')
			return
		$SaveList.delete_save_data(savefile)
		emit_signal('save_deleted',savefile)

func has_save_files():
	return $SaveList.has_save_files()

func _on_Overwrite_pressed():
	if last_selected_savefile:
		var savefile: String = last_selected_savefile
		var confirmed = confirm('Ovewrite '+basename(last_selected_savefile)+'?')
		while confirmed is GDScriptFunctionState and confirmed.is_valid():
			confirmed = yield(confirmed,'completed')
		if not confirmed:
			return
		var encoded = Player.store_state()
		if not Player.write_save_file(Player.store_state(),savefile):
			push_error('Could not write the save file')
		else:
			$SaveList.replace_save_data(savefile,encoded)
			emit_signal('save_replaced',savefile,encoded)

func _on_SaveList_no_save_selected():
	print('deselect')
	last_selected_savefile = ''
	update_buttons(false)
	emit_signal('no_save_selected')

func _on_Rescan_pressed():
	print('rescan')
	last_selected_savefile = ''
	update_buttons(false)
	$SaveList.refill_tree()
	if last_selected_savefile:
		emit_signal('no_save_selected')
	emit_signal('saves_rescanned')

func _on_SaveList_save_double_clicked(savefile: String, _data=null):
	print('savelist save double clicked')
	last_selected_savefile = savefile
	_on_Load_pressed()