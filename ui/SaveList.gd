extends Tree

export var allow_saving = true setget set_allow_saving
export var new_saves_string = '+ new save +'
export var save_dir = 'user://saves'

var root: TreeItem
var new_save: TreeItem
var read_data: bool = false
var first_file_index: int = 1

signal no_save_selected
signal new_save
signal save_selected

func set_allow_saving(flag: bool):
	if flag and first_file_index==0:
		insert_new_slot_item()
		allow_saving = flag
	elif not flag and first_file_index==1:
		root.remove_child(root.get_children())
		allow_saving = flag

# Called when the node enters the scene tree for the first time.
func _ready():
	root = create_item()
	set_column_title(0,'File')
	set_column_title(1,'Player')
	set_column_title(2,'Location')
	set_column_titles_visible(true)

func _on_SaveList_visibility_changed():
	if visible and not read_data:
		fill_tree()
		read_data = true

func refill_tree():
	clear()
	new_save = null
	root = create_item()
	fill_tree()

func remake_new_slot_item():
	if allow_saving:
		if new_save:
			root.remove_child(new_save)
		insert_new_slot_item()

func insert_new_slot_item():
	var item = create_item(root,0)
	item.set_text(0,new_saves_string)
	item.set_text_align(0,TreeItem.ALIGN_CENTER)
	item.set_editable(0,true)
	item.set_selectable(1,false)
	item.set_metadata(1,'new save')
	item.set_selectable(2,false)
	new_save = item

func insert_save_data(savefile: String, data: Dictionary, index: int = 1):
	var item = create_item(root,index)
	write_save_data(item,savefile,data)

func basename(savefile: String) -> String:
	var split = savefile.split('/',false)
	return split[len(split)-1]

func write_save_data(item: TreeItem, savefile: String, data: Dictionary):
	var location_text = 'Unknown Location'
	var location = game_state.systems.get_node_or_null(data['player_location'])
	if location:
		location_text = location.full_display_name()
	item.set_text(0,basename(savefile))
	item.set_metadata(0,data)
	item.set_text(1,data['player_name'])
	item.set_metadata(1,'existing save')
	item.set_text(2,location_text)

func delete_save_data(savefile: String):
	var text = basename(savefile)
	var scan = root.get_children()
	while scan:
		if scan and scan.get_text(0)==text:
			print('remove ',text)
			var dir = Directory.new()
			dir.remove(savefile)
			root.remove_child(scan)
			return
		scan = scan.get_next()
	push_warning(text+': could not find this in the list of saves')

func replace_save_data(savefile: String,data: Dictionary):
	var text = basename(savefile)
	var scan = root.get_children()
	while scan:
		if scan and scan.get_text(0)==text:
			root.remove_child(scan)
			insert_save_data(text,data,0)
			return
		scan = scan.get_next()
	push_warning(text+': could not find this in the list of saves')
	insert_save_data(text,data,first_file_index)

class SortByModificationTime extends Reference:
	func cmp(a,b):
		return b[1]<a[1]

func fill_tree():
	if allow_saving:
		insert_new_slot_item()
	var dir: Directory = Directory.new()
	if not dir.dir_exists(save_dir):
		print('make saves directory')
		if OK!=dir.make_dir(save_dir):
			push_error('Cannot make saves directory')
			return
	if OK!=dir.open(save_dir) or OK!=dir.list_dir_begin(true,true):
		push_error('Cannot list user saves directory')
		return
	var files = []
	var savefile = dir.get_next()
	var file: File = File.new()
	while savefile:
		var full_name = save_dir+'/'+savefile
		var data = Player.read_save_file(full_name)
		files.append([savefile, file.get_modified_time(full_name), data])
		savefile = dir.get_next()
	if files:
		files.sort_custom(SortByModificationTime.new(),'cmp')
		for content in files:
			insert_save_data(content[0],content[2],-1)
	dir.list_dir_end()

func _on_SaveList_cell_selected():
	print('cell selected')
	var selected = get_selected()
	var meta = selected.get_metadata(0)
	if meta:
		print('meta, so save selected')
		emit_signal('save_selected',save_dir+'/'+selected.get_text(0),meta)
	elif allow_saving and selected.get_metadata(1)=='new save':
		print('no meta, but other stuff')
		new_save.set_text(0,'')
		new_save.set_text_align(0,TreeItem.ALIGN_LEFT)
		emit_signal('no_save_selected')
	else:
		emit_signal('no_save_selected')
		print('confused by cell selection')

func _on_SaveList_nothing_selected():
	if allow_saving:
		emit_signal('no_save_selected')
		remake_new_slot_item()

func _on_SaveList_focus_exited():
	if allow_saving:
		remake_new_slot_item()

func _on_SaveList_item_edited():
	print('item edited')
	var selected = get_selected()
	var selected_column = get_selected_column()
	if allow_saving and selected.get_metadata(1)=='new save':
		print('ready to save')
		var text = selected.get_text(selected_column)
		print('text is "'+text+'"')
		remake_new_slot_item()
		if text and text is String:
			print('emit signal')
			emit_signal('new_save',save_dir+'/'+text)
