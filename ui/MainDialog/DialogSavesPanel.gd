extends Panel

export var ConfirmDialog: PackedScene

signal page_selected

var dialog_path: NodePath = NodePath()
var cancel: bool
var last_selected: String = ''
var tree = simple_tree.SimpleTree.new(simple_tree.SimpleNode.new())

func _on_DialogPageSelector_page_selected(page):
	emit_signal('page_selected',page)

func _on_Info_url_clicked(meta):
	$Split/Left/Split/Help.process_command(meta)

func update_buttons(save_selected):
	for child in $Split/Right/Center/Buttons.get_children():
		if child.has_method('set_disabled'):
			child.set_disabled(not save_selected)

func _on_SaveList_new_save(filename):
	print('save list new save')
	var encoded = Player.store_state()
	if not Player.write_save_file(Player.store_state(),filename):
		push_error('Could not write the save file')
	else:
		print('insert new save')
		$Split/Right/SaveList.insert_save_data(filename,encoded)
	last_selected = ''
	update_buttons(false)

func _on_SaveList_save_selected(filename,data):
	print('save list save selected')
	tree.get_root().remove_all_children()
	var node = data.get('player_ship_design',null)
	if node!=null and node.has_method('is_ShipDesign'):
		node.clear_cached_stats()
		var stats = node.get_stats()
		var text = text_gen.make_ship_bbcode(stats,true)
		$Split/Left/Split/Info.clear()
		$Split/Left/Split/Info.insert_bbcode(text,true)
		$Split/Left/Split/Info.scroll_to_line(0)
	else:
		print('no ship')
	last_selected = filename
	update_buttons(true)

func _on_DialogSavesPanel_page_selected(page):
	emit_signal('page_selected',page)

func _on_Cancel_pressed():
	cancel = true

func confirm(what) -> bool:
	var dialog = get_node_or_null(dialog_path)
	if dialog:
		cancel = true
		dialog.visible = false
		return false
	dialog = ConfirmationDialog.new()
	var label = Label.new()
	label.text = what+' '+filename+'?'
	cancel = false
	if OK!=dialog.get_cancel().connect("pressed", self, "_on_Cancel_pressed"):
		push_error('Could not connect to cancel button.')
		return false
	label.name = 'Label'
	dialog.add_child(label)
	get_tree().get_root().add_child(dialog)
	dialog_path = dialog.get_path()
	dialog.popup_centered()
	while dialog.visible:
		var view_size = get_viewport().size
		var pos = (view_size-dialog.rect_size)/2
		if dialog.rect_global_position != pos:
			dialog.rect_global_position = pos
		yield(get_tree(),'idle_frame')
	dialog.queue_free()
	dialog_path = NodePath()
	return not cancel

func basename(filename: String) -> String:
	var split = filename.split('/',false)
	return split[len(split)-1]

func _on_Load_pressed():
	if last_selected:
		var confirmed = confirm('Load '+basename(last_selected)+'?')
		while confirmed is GDScriptFunctionState and confirmed.is_valid():
			confirmed = yield(confirmed,'completed')
		if not confirmed:
			return
		var read = Player.read_save_file(last_selected)
		if read:
			Player.restore_state(read)
			$Split/Left/Split/Info.insert_bbcode('[h2]Game Loaded.[/h2]',true)

func _on_Delete_pressed():
	if last_selected:
		var confirmed = confirm('Delete '+basename(last_selected)+'?')
		while confirmed is GDScriptFunctionState and confirmed.is_valid():
			confirmed = yield(confirmed,'completed')
		if not confirmed:
			return
		print('remove save')
		$Split/Right/SaveList.remove_save_data(filename)

func _on_Replace_pressed():
	if last_selected:
		var confirmed = confirm('Delete '+basename(last_selected)+'?')
		while confirmed is GDScriptFunctionState and confirmed.is_valid():
			confirmed = yield(confirmed,'completed')
		if not confirmed:
			return
		var encoded = Player.store_state()
		if not Player.write_save_file(Player.store_state(),filename):
			push_error('Could not write the save file')
		else:
			print('replace save')
			$Split/Right/SaveList.replace_save_data(filename,encoded)

func _on_SaveList_no_save_selected():
	last_selected = ''
	update_buttons(false)

func _on_Refresh_pressed():
	last_selected = ''
	update_buttons(false)
	$Split/Right/SaveList.refill_tree()
