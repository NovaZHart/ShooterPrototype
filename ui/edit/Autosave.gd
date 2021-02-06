extends Node2D

export var save_frequency_seconds: int = 300
export var autosave_dir: String = 'user://editor_autosave'

const max_scan: int = 65536
const max_autosaves: int = 20

var selected_file
var file_dialog_path: NodePath = NodePath()
var save_frequency_msec
var last_update_tick
var last_save_tick

func state_updated():
	last_update_tick = OS.get_ticks_msec()

func _process(_delta):
	var tick: int = OS.get_ticks_msec()
	if last_update_tick>last_save_tick and tick-last_save_tick>save_frequency_msec:
		autosave()
		last_save_tick = tick # even if autosave fails, to avoid infinite autosave
	if tick<last_update_tick or tick<last_save_tick:
		push_warning('Time wrapped around. Will autosave.')
		last_update_tick=tick
		last_save_tick=tick
		autosave()

func _ready():
	save_frequency_msec = save_frequency_seconds * 1000
	last_update_tick = OS.get_ticks_msec()
	last_save_tick = last_update_tick
	universe_edits.state.connect('undo_stack_changed',self,'state_updated')
	universe_edits.state.connect('redo_stack_changed',self,'state_updated')

func _exit_tree():
	universe_edits.state.disconnect('undo_stack_changed',self,'state_updated')
	universe_edits.state.disconnect('redo_stack_changed',self,'state_updated')

func rotate_autosave_files(exclude: Array) -> bool:
	var dir: Directory = Directory.new()
	if OK!=dir.open(autosave_dir):
		push_error('Cannot open dir "'+autosave_dir+'"')
		return false
	if OK!=dir.list_dir_begin(true,true):
		push_error('Cannot list dir "'+autosave_dir+'"')
		return false
	var autosaves: Array = []
	
	var i = 0
	while i<max_scan:
		i += 1
		var file = dir.get_next()
		if not file:
			break
		autosaves.append(file)
	dir.list_dir_end()
	autosaves.sort()
	var success = true
	while len(autosaves)>max_autosaves:
		var savefile = autosaves.pop_front()
		if savefile and exclude.find(savefile)<0 and OK!=dir.remove(savefile):
			push_warning('Cannot remove old autosave "'+savefile+'"')
			success = false
	return success

func make_autosave_filename() -> String:
	var now: Dictionary = OS.get_datetime()
	return ( '%s/%04d-%02d-%02d_%02d-%02d-%02d.json' % [
		autosave_dir, now['year'], now['month'], now['day'], now['hour'],
		now['minute'], now['second'] ] )

func autosave():
	# NOTE: this does NOT update last_save_tick. The caller must do that.
	var dir: Directory = Directory.new()
	if not dir.dir_exists(autosave_dir) and OK!=dir.make_dir(autosave_dir):
		push_error('Could not make directory "'+autosave_dir+'"')
	var savefile: String = make_autosave_filename()
	printerr('Autosave to "'+savefile+'"')
	if not game_state.save_universe_as_json(savefile):
		push_error('Autosave failed!')
		if dir.file_exists(savefile) and OK!=dir.remove(savefile):
			push_warning('Could not delete incomplete autosave file "'+savefile+'"')
	if not rotate_autosave_files([savefile]):
		push_warning('Autosave file rotation failed.')

func _on_FileDialog_file_selected(path: String, node: FileDialog):
	selected_file=path
	node.visible=false

func save_load(save: bool) -> bool:
	var dialog = get_viewport().get_node_or_null(file_dialog_path)
	if dialog:
		selected_file=null
		dialog.visible=false
		get_viewport().remove_child(dialog)
		file_dialog_path=NodePath()
		return
	
	dialog = FileDialog.new()
	dialog.connect('file_selected',self,'_on_FileDialog_file_selected',[dialog])
	dialog.popup_exclusive = true
	dialog.mode = FileDialog.MODE_SAVE_FILE if save else FileDialog.MODE_OPEN_FILE
	get_viewport().add_child(dialog)
	dialog.rect_global_position=get_viewport().size*0.1
	dialog.rect_size=get_viewport().size*0.8
	selected_file=null
	file_dialog_path = dialog.get_path()
	
	dialog.popup()
	while dialog and dialog.visible:
		yield(get_tree(),'idle_frame')
	dialog.disconnect('file_selected',self,'_on_FileDialog_file_selected')
	get_viewport().remove_child(dialog)
	dialog.queue_free()
	file_dialog_path = NodePath()
	
	if not selected_file:
		return false # canceled
	elif save:
		return game_state.save_universe_as_json(selected_file)
	elif game_state.load_universe_from_json(selected_file):
		universe_edits.state.clear()
		set_process(true)
		return true
	return false
