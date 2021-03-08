extends ItemList

var starting_left: float
var starting_right: float
var starting_top: float
var starting_bottom: float
var starting_font_size: float
const min_font_size: float = 9.0
var service_names: Array = []

signal service_activated
signal deorbit_selected

func _ready():
	starting_left=margin_left
	starting_right=margin_right
	starting_top=margin_top
	starting_bottom=margin_bottom
	anchor_left=0
	anchor_right=0
	anchor_top=0
	anchor_bottom=0
	update_service_list()

func update_service_list():
	clear()
	var planet_info = Player.get_space_object_or_null()
	service_names = [] if planet_info==null else planet_info.services
	if not service_names:
		service_names = []
	var i=0
	if planet_info and not service_names.has('market') and \
			(planet_info.trading or service_names.has('shipeditor')):
		service_names = service_names + ['market']
	for service_name in service_names:
		var service = game_state.services.get(service_name,null)
		if service == null:
			continue
		add_item(service.service_title)
		set_item_metadata(i,[service_name,service])
		i+=1
	add_item('De-orbit')
	set_item_metadata(i,[])
	i=i+1
	update_selectability()

func update_selectability():
	for i in range(get_item_count()):
		var name_and_object = get_item_metadata(i)
		var available = !len(name_and_object) or name_and_object[1].is_available()
		set_item_disabled(i,not available)
		set_item_selectable(i,available)

func _process(var _delta: float) -> void:
	var window_size: Vector2 = get_tree().root.size
	var project_height: int = ProjectSettings.get_setting("display/window/size/height")
	var project_width: int = ProjectSettings.get_setting("display/window/size/width")
	var scale: Vector2 = window_size / Vector2(project_width,project_height)
	
	margin_left = floor(starting_left*scale[0])
	margin_right = ceil(starting_right*scale[0])
	margin_top = floor(starting_top*scale[1])
	margin_bottom = ceil(starting_bottom*scale[1])
	
	theme.default_font.size=max(min_font_size,14*min(scale[0],scale[1]))

func _on_item_selected(index: int):
	if is_item_selectable(index):
		var name_and_object = get_item_metadata(index)
		if not len(name_and_object):
			emit_signal('deorbit_selected')
		else:
			emit_signal('service_activated',name_and_object[0],name_and_object[1])
