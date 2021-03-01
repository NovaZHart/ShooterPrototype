extends game_state.SectorEditorStub

export var connected_location_color = Color(0.6,0.5,0.9)
export var system_location_color = Color(0.7,0.6,1.0)
export var allow_selection: bool = true
export var path_color = Color(0.6,0.5,0.9)
export var connected_color = Color(0.4,0.8,1.0)
export var highlight_color = Color(1.0,0.9,0.5)
export var system_color = Color(0.1,0.2,0.6)
export var link_color = Color(0.3,0.3,0.5)
export var system_name_color = Color(1.0,1.0,1.0,1.0)
export var min_camera_size: float = 20
export var max_camera_size: float = 400
export var label_font: Font
export var highlighted_font: Font
export var bar1_color = Color('#8343a5')
export var bar2_color = Color('#00A0E9')
export var bar3_color = Color('#009944')
export var bar4_color = Color('#FFF100')
export var bar5_color = Color('#EB6100')
export var bar6_color = Color('#F63332')
export var no_sale = Color('#999999')

const NAVIGATIONAL: int = 0
const MIN_PRICE: int = 1
const AVG_PRICE: int = 2
const MAX_PRICE: int = 3
export var mode: int = NAVIGATIONAL

const MapItemShader: Shader = preload('res://ui/edit/MapItem.shader')
const StarmapSystemShader: Shader = preload('res://ui/StarmapSystem.shader')
const StarmapLibrary = preload('res://bin/Starmap.gdns')
const SYSTEM_SCALE: float = 0.007
const LINK_SCALE: float = 0.004
const SELECT_EPSILON: float = 0.02
const fake_system_name: String = '\t'

var starmap
var starmap_mutex: Mutex = Mutex.new()
var link_material: ShaderMaterial
var system_material: ShaderMaterial

var name_pool: PoolStringArray = PoolStringArray()
var display_name_pool: PoolStringArray = PoolStringArray()
var pos_pool: PoolVector3Array = PoolVector3Array()
var gate_pool: PoolIntArray = PoolIntArray()
var link_pool: PoolIntArray = PoolIntArray()
var system_index: Dictionary = {}

var ui_scroll: float = 0
var last_position = null
var last_screen_position = null
var camera_start = null

signal select
signal deselect

func _init():
	selection = game_state.systems.get_node_or_null(Player.destination_system)
	starmap = StarmapLibrary.new()

func cancel_drag() -> bool:
	last_position=null
	last_screen_position=null
	camera_start=null
	return true

func _ready():
	if allow_selection:
		game_state.switch_editors(self)
	
	starmap.name = 'Starmap'
	starmap.set_camera_path(NodePath('../Camera'))
	$View/Port.add_child(starmap)
	
	var syspos = Player.hyperspace_position
	$View/Port/Camera.translation = Vector3(syspos.x,$View/Port/Camera.translation.y,syspos.z)
	
	link_material = ShaderMaterial.new()
	link_material.shader = MapItemShader
	link_material.set_shader_param('poly',2)
	starmap.set_line_material(link_material)
	
	system_material = ShaderMaterial.new()
	system_material.shader = StarmapSystemShader
	system_material.set_shader_param('poly',4)
	starmap.set_circle_material(system_material)
	
	starmap.set_max_scale(SYSTEM_SCALE*2.0, LINK_SCALE*2.0, rect_global_position)
	assert(label_font)
	starmap.set_default_visuals(system_color,link_color,system_name_color,label_font,
		SYSTEM_SCALE,LINK_SCALE)
	
	starmap.set_show_links(false)
	send_systems_to_starmap()
	update_starmap_visuals()

func _on_StarmapPanel_resized():
	starmap.set_max_scale(SYSTEM_SCALE*2.0, LINK_SCALE*2.0, rect_global_position)

func process_if(flag):
	if flag:
		update()
	return true

func send_systems_to_starmap():
	game_state.universe.lock()
	var system_names: Array = []
	system_index = {}
	
	if not Player.system or not Player.system.show_on_map or \
			Player.system.position.distance_to(Player.hyperspace_position)>0.1:
		system_names.append(fake_system_name)
		system_index[fake_system_name]=0
	
	for system_name in game_state.systems.get_child_names():
		var system = game_state.systems.get_child_with_name(system_name)
		if system and system.has_method('is_SystemData') and system.show_on_map:
			system_names.append(system_name)
			system_index[system_name] = len(system_names)-1
	var nsystems: int = len(system_names)
	
	name_pool.resize(nsystems)
	display_name_pool.resize(nsystems)
	pos_pool.resize(nsystems)
	
	var links: Array = []
	var gates: Array = []
	
	for i in range(nsystems):
		var system_name = system_names[i]
		name_pool[i] = system_name
		display_name_pool[i] = name_pool[i]
		if system_name == fake_system_name:
			pos_pool[i] = Player.hyperspace_position
			continue
		var system = game_state.systems.get_child_with_name(system_name)
		if not system or not system.has_method('is_SystemData'):
			push_error('System "'+system_name+'" is in child list, but has no SystemData')
		display_name_pool[i] = system.display_name
		pos_pool[i] = system.position
		for link_name in system.links:
			var link_index = system_index.get(link_name,-1)
			if link_index<0:
				push_error('System "'+system_name+'" has a link to an undefined system "'+system_name+'"')
				continue
			links.append(i)
			links.append(link_index)
		if not system.astral_gate_path().is_empty():
			gates.append(i)
	
	gate_pool = PoolIntArray(gates)
	link_pool = PoolIntArray(links)
	
	starmap.set_systems(display_name_pool, pos_pool, link_pool, gate_pool)

func alpha(c: Color, a: float) -> Color:
	return Color(c.r,c.g,c.b,a)

func update_starmap_visuals():
	starmap.clear_visuals()
	starmap.clear_extra_lines()
	
	var selection_index = -1
	var location_index = -1
	if system_index.has(fake_system_name):
		location_index = 0
	else:
		location_index = system_index.get(Player.system.name,-1)
	
	if selection and selection.has_method('is_SystemData'):
		selection_index = system_index.get(selection.name,-1)
	
	if mode==NAVIGATIONAL:
		navigational_visuals(selection_index,location_index)
	else:
		pricing_visuals(selection_index,location_index)
	
	if location_index>=0 and selection_index>=0 and location_index!=selection_index:
		starmap.add_extra_line(pos_pool[location_index],
			pos_pool[selection_index],path_color,LINK_SCALE*2.0)
	
	starmap.update()

func price_stats_recurse(commodity: Commodities.OneProduct, node: simple_tree.SimpleNode, result: Array):
	var price = Commodities.OneProduct.new()
	if node.has_method('list_products'):
		node.list_products(commodity,price)
		if price.all:
			print('node ',node.get_path(),' price ',price.all)
			var value = price.all[0][Commodities.Products.VALUE_INDEX]
			if mode==MAX_PRICE:
				result[0] = max(result[0],value)
			elif mode==MIN_PRICE:
				result[0] = min(result[0],value)
			else:
				result[0] += value
			result[1] += 1
	for child_name in node.get_child_names():
		var child = node.get_child_with_name(child_name)
		if child:
			price_stats_recurse(commodity,child,result)
	print('result now ',result)

func price_stats(node: simple_tree.SimpleNode): # -> float or null
	var commodity_data: Array = Commodities.get_selected_commodity()
	var commodity = Commodities.OneProduct.new(commodity_data)
	var result = [ 0.0, 0 ]
	if mode==MIN_PRICE:
		result[0] = INF
	elif mode==MAX_PRICE:
		result[0] = -INF
	price_stats_recurse(commodity,node,result)
	if result[0] + 1e6 == result[0]:
		result[0]=0
	print('final result ',result)
	if not result[1]:
		return null
	elif mode==AVG_PRICE:
		return result[0]/result[1]
	else:
		return result[0]

func pricing_visuals(selection_index: int, location_index: int):
	var price_at_index: Dictionary = {}
	var min_stat: float = INF
	var max_stat: float = -INF
	for system_name in system_index:
		var data = game_state.systems.get_child_with_name(system_name)
		var index = system_index[system_name]
		if data==null or not data.has_method('is_SystemData') or index<0:
			push_warning('Invalid system "'+system_name+'"')
			continue
		var stat = price_stats(data)
		price_at_index[index] = stat
		if stat!=null and stat>0:
			min_stat = min(min_stat,stat)
			max_stat = max(max_stat,stat)
	print('price_at_index = ',price_at_index)
	var draw: Dictionary = {}
	var colors = [ no_sale, bar1_color, bar2_color, bar3_color, bar4_color,
		bar5_color, bar6_color ]
	var ncolors = len(colors)-1
	var at_location = 128
	var at_selection = 64
	var color_mask = 15
	assert(color_mask>=ncolors)
	assert(not (at_location&color_mask))
	assert(not (at_selection&color_mask))
	var step: float = 1.0
	if min_stat!=INF:
		step = max(round((max_stat-min_stat)/float(ncolors)),1.0)
	for index in range(len(pos_pool)):
		var flags: int = 0
		if min_stat!=INF:
			var price = price_at_index.get(index,-1)
			if price>0:
# warning-ignore:narrowing_conversion
				flags = clamp(int(floor((price-min_stat)/step)),1,ncolors)
		if location_index==index:
			flags |= at_location
		if selection_index==index:
			flags |= at_selection
		if draw.has(flags):
			draw[flags].append(index)
		else:
			draw[flags] = [index]
	print(draw)
	for flags in draw:
# warning-ignore:shadowed_variable
		var system_color = colors[flags&color_mask]
		var label_color = system_color
		var font = label_font
		var system_scale = SYSTEM_SCALE
		if flags&at_location or flags&at_selection:
			font = highlighted_font
		if flags&at_location:
			system_scale *= 1.5
		starmap.add_system_visuals(PoolIntArray(draw[flags]),
			system_color, label_color, font, system_scale)

func navigational_visuals(selection_index: int, location_index: int):
	if location_index==selection_index and location_index>=0:
		starmap.add_system_visuals(PoolIntArray([selection_index]),
			highlight_color, system_name_color, highlighted_font,
			SYSTEM_SCALE*1.2)
		starmap.add_adjacent_link_visuals(PoolIntArray([selection_index]),
			connected_color, LINK_SCALE*1.5)
	else:
		if location_index>=0:
			starmap.add_system_visuals(PoolIntArray([location_index]),
				system_location_color, system_name_color, highlighted_font,
				SYSTEM_SCALE*1.2)
			starmap.add_adjacent_link_visuals(PoolIntArray([location_index]),
				connected_location_color, LINK_SCALE*1.5)
		
		if selection_index>=0:
			starmap.add_system_visuals(PoolIntArray([selection_index]),
				highlight_color, system_name_color, highlighted_font,
				SYSTEM_SCALE)
			starmap.add_adjacent_link_visuals(PoolIntArray([selection_index]),
				connected_color, LINK_SCALE)

func event_position(event: InputEvent) -> Vector2:
	# Get the best guess of the mouse position for the event.
	if event is InputEventMouseButton:
		return event.position
	return get_viewport().get_mouse_position()

func find_at_position(screen_position: Vector2):
	var epsilon = SELECT_EPSILON*$View/Port/Camera.size
	var pos3 = $View/Port/Camera.project_position(
		screen_position-$View.rect_global_position,-10)
	var result = starmap.system_at_location(pos3, epsilon)
	if result<0 or result>=name_pool.size():
		return null
	var system_name: String = name_pool[result]
	return game_state.systems.get_node_or_null(system_name)

func deselect(what) -> bool:
	if (what is Dictionary and selection is Dictionary and what==selection) or \
		(what is simple_tree.SimpleNode and selection is simple_tree.SimpleNode \
		and what==selection):
		selection=null
		Player.destination_system = NodePath()
		emit_signal('deselect')
		update_starmap_visuals()
		return true
	return false

func change_selection_to(new_selection,_center: bool = false) -> bool:
	game_state.universe.lock()
	selection=new_selection
	if selection is simple_tree.SimpleNode:
		emit_signal('select',selection)
		Player.destination_system = selection.get_path()
	elif selection==null:
		emit_signal('deselect')
	game_state.universe.unlock()
	update_starmap_visuals()
	return true

func set_zoom(zoom: float,focus: Vector3) -> void:
	var from: float = $View/Port/Camera.size
	var new: float = clamp(zoom*from,min_camera_size,max_camera_size)
	
	if abs(new-from)<1e-5:
		return
	
	$View/Port/Camera.size = new
	var f = new/from
	var start: Vector3 = $View/Port/Camera.translation
	var center: Vector3 = Vector3(focus.x,start.y,focus.z)
	$View/Port/Camera.translation = f*start + center*(1-f)
	starmap.update()

func _input(event):
	var top = get_viewport().get_modal_stack_top()
	if top and not in_top_dialog(self,top):
		return
	var pos2: Vector2 = event_position(event)
	if not get_global_rect().has_point(pos2):
		return
	if not is_visible_in_tree():
		return
	if event is InputEventMouseMotion and last_position:
		if Input.is_action_pressed('ui_location_slide') or \
				Input.is_action_pressed('ui_location_select'):
			if last_screen_position:
				var pos3: Vector3 = $View/Port/Camera.project_position(pos2,-10)
				var pos3_start: Vector3 = $View/Port/Camera.project_position(last_screen_position,-10)
				var pos_diff = pos3_start-pos3
				pos_diff.y=0
				if pos_diff.length()>1e-3:
					$View/Port/Camera.translation = camera_start + pos_diff
					starmap.update()
		else:
			var _discard = cancel_drag()
	
	if event.is_action_pressed('ui_location_slide'):
		last_screen_position = pos2
		last_position = $View/Port/Camera.project_position(last_screen_position,-10)
		camera_start = $View/Port/Camera.translation
	elif event.is_action_released('ui_location_slide'):
		var _discard = cancel_drag()
	elif event.is_action_pressed('ui_location_select'):
		if allow_selection:
			var target = find_at_position(pos2)
			if (selection and not target) or target is simple_tree.SimpleNode:
				universe_edits.state.push(universe_edits.ChangeSelection.new(
					selection,target))
		last_screen_position = pos2
		last_position = $View/Port/Camera.project_position(last_screen_position,-10)
		camera_start = $View/Port/Camera.translation
		get_tree().set_input_as_handled()
	elif allow_selection and event.is_action_released('ui_undo'):
		universe_edits.state.undo()
		get_tree().set_input_as_handled()
	elif allow_selection and event.is_action_released('ui_redo'):
		universe_edits.state.redo()
		get_tree().set_input_as_handled()
	elif event.is_action_released("wheel_up"):
		ui_scroll=1.5
		if allow_selection:
			get_tree().set_input_as_handled()
	elif event.is_action_released("wheel_down"):
		ui_scroll=-1.5
		if allow_selection:
			get_tree().set_input_as_handled()

func in_top_dialog(node,top) -> bool:
	if node==null:
		return false
	if node==top:
		return true
	return in_top_dialog(node.get_parent(),top)

func _process(_delta):
	var top = get_viewport().get_modal_stack_top()
	if top and not in_top_dialog(self,top):
		return
	
	var ui_zoom: int = 0
	if Input.is_action_pressed("ui_page_up"):
		ui_zoom += 1
	if Input.is_action_pressed("ui_page_down"):
		ui_zoom -= 1
	var zoom: float = pow(0.9,ui_zoom)*pow(0.9,3*ui_scroll)
	ui_scroll*=0.7
	if abs(ui_scroll)<.05:
		ui_scroll=0
	
	var pos2: Vector2 = get_viewport().get_mouse_position()-rect_global_position
	var pos3: Vector3 = $View/Port/Camera.project_position(pos2,-10)
	set_zoom(zoom,pos3)
