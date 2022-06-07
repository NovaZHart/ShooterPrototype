extends game_state.SectorEditorStub

export var show_space_objects: bool = false
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
export var min_font_size = 8
export var target_font_size = 10

const NAVIGATIONAL: int = 0
const MIN_PRICE: int = 1
const AVG_PRICE: int = 2
const MAX_PRICE: int = 3
export var mode: int = NAVIGATIONAL

const MapItemShader: Shader = preload('res://shaders/MapItem.shader')
const StarmapSystemShader: Shader = preload('res://shaders/StarmapSystem.shader')
const StarmapLibrary = preload('res://bin/Starmap.gdns')
const SELECT_EPSILON: float = 0.007
const fake_system_name: String = '\t'

var starmap
var starmap_mutex: Mutex = Mutex.new()
var link_material: ShaderMaterial
var system_material: ShaderMaterial
var buy: bool = true setget set_buy
var system_metadata: Array = []
var name_pool: PoolStringArray = PoolStringArray()
var display_name_pool: PoolStringArray = PoolStringArray()
var pos_pool: PoolVector3Array = PoolVector3Array()
var gate_pool: PoolIntArray = PoolIntArray()
var link_pool: PoolIntArray = PoolIntArray()
var system_index: Dictionary = {}
var system_scale: float
var link_scale: float
var ui_scroll: float = 0
var last_position = null
var last_screen_position = null
var camera_start = null
var hover_index = -1
var first_show: bool = true

signal select
signal deselect
signal hover_over_player_location
signal hover_over_system
signal hover_no_system
signal activate_space_object
signal deselect_space_object
signal select_space_object

func _init():
	selection = game_state.systems.get_node_or_null(Player.destination_system)
	starmap = StarmapLibrary.new()

func set_buy(b: bool):
	buy=not not b
	update_starmap_visuals()

func cancel_drag() -> bool:
	last_position=null
	last_screen_position=null
	camera_start=null
	return true

func maybe_show_window():
	var show = show_space_objects and is_visible_in_tree()
	
	$Window.visible=show
	$Window.set_process_input(show)
	$Window/Tree.set_process_input(show)
	if first_show:
		set_window_location(true)
		first_show = false

func set_window_location(_set_initial_rect):
	var root_size: Vector2 = get_tree().root.size
	var window_size: Vector2 = root_size/7
	var me: Rect2 = get_global_rect()
	#var window_top_pad = M_size.y + M_size.x
	#var window_right_pad = M_size.x/2
	var window_position: Vector2 = Vector2(
		me.end.x-window_size.x, # -window_right_pad,
		me.position.y) # +window_top_pad)
	print('my position: '+str(me))
	print('window size: '+str(window_size))
	print('window position: '+str(window_position))
	print('old position: '+str($Window.get_global_rect()))
	$Window.set_initial_rect(window_position,window_size)
	print('new position: '+str($Window.get_global_rect()))

func _exit_tree():
	get_tree().root.disconnect('size_changed',self,'_on_root_viewport_size_changed')
	if allow_selection:
		universe_edits.pop_editors()

func _enter_tree():
	if allow_selection:
		universe_edits.push_editors(self)

func _ready():
	var _discard = get_tree().root.connect('size_changed',self,'_on_root_viewport_size_changed')
	
	$Window.get_close_button().visible=false
	maybe_show_window()
	
	$MapColorbar.set_title('Prices')
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
	
	system_scale = label_font.get_char_size(ord('M')).y-label_font.get_descent()
	link_scale = system_scale/2.0
	starmap.set_reference_size(system_scale, link_scale)
	starmap.set_max_scale(3.0, 3.0, rect_global_position)
	assert(label_font)
	starmap.set_default_visuals(system_color,link_color,system_name_color,label_font,1.0,1.0)
	
	starmap.set_show_links(false)
	send_systems_to_starmap()
	update_starmap_visuals()

func _on_root_viewport_size_changed():
	if $Window.visible:
		set_window_location(false)

func _on_StarmapPanel_resized():
	starmap.set_max_scale(3.0, 3.0, rect_global_position)
	var scale: Vector2 = utils.get_viewport_scale()
	label_font.size = max(min_font_size,target_font_size*min(scale[0],scale[1]))
	highlighted_font.size = max(min_font_size,target_font_size*min(scale[0],scale[1]))
#	if $Window.visible:

func get_viewport_scale() -> float:
	var scale: Vector2 = utils.get_viewport_scale()
	return min(scale[0],scale[1])

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

func get_location_index():
	if system_index.has(fake_system_name):
		return 0
	else:
		return system_index.get(Player.system.name,-1)

func update_starmap_visuals():
	starmap.clear_visuals()
	starmap.clear_extra_lines()
	
	var selection_index = -1
	var location_index = get_location_index()
	
	if selection and selection.has_method('is_SystemData'):
		selection_index = system_index.get(selection.name,-1)
	
	if mode==NAVIGATIONAL:
		navigational_visuals(selection_index,location_index)
		$MapColorbar.visible=false
		if not system_metadata.empty():
			system_metadata.resize(0)
	else:
		pricing_visuals(selection_index,location_index)
	
	if location_index>=0 and selection_index>=0 and location_index!=selection_index:
		starmap.add_extra_line(pos_pool[location_index],
			pos_pool[selection_index],path_color,2.0)
	
	starmap.update()

func price_stats_recurse(commodity: Commodities.OneProduct, node: simple_tree.SimpleNode, result: Array, method: String):
	if node.has_method(method):
		var price = Commodities.OneProduct.new()
		node.call(method,commodity,price)
		if price.all:
			var product = price.all[0]
			var value = product[Commodities.Products.VALUE_INDEX]
			var quantity = product[Commodities.Products.QUANTITY_INDEX]
			if value and quantity:
				result[1] += 1
				if mode==MAX_PRICE:
					result[0] = max(result[0],value)
				elif mode==MIN_PRICE:
					result[0] = min(result[0],value)
				else:
					result[0] += value
	for child_name in node.get_child_names():
		var child = node.get_child_with_name(child_name)
		if child:
			price_stats_recurse(commodity,child,result,method)

func price_stats(node: simple_tree.SimpleNode): # -> float or null
	var commodity_data: Array = Commodities.get_selected_commodity()
	var commodity = Commodities.OneProduct.new(commodity_data)
	if not buy:
		if Commodities.selected_commodity_type==Commodities.MARKET_TYPE_SHIP_PARTS:
			node.price_ship_parts(commodity)
		else:
			node.price_products(commodity)
		var value = commodity.all[0][Commodities.Products.VALUE_INDEX]
		return value if value else null
	var result = [ 0.0, 0 ]
	if mode==MIN_PRICE:
		result[0] = INF
	elif mode==MAX_PRICE:
		result[0] = -INF
	if Commodities.selected_commodity_type==Commodities.MARKET_TYPE_SHIP_PARTS:
		price_stats_recurse(commodity,node,result,'list_ship_parts')
	else:
		price_stats_recurse(commodity,node,result,'list_products')
	if result[0] + 1e6 == result[0]:
		result[0]=0
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
		step = round((max_stat-min_stat)/float(ncolors))
		var colorbar_labels = []
		for i in range(ncolors+1):
			colorbar_labels.append(str(round(min_stat+i*step)))
		$MapColorbar.visible=false
		$MapColorbar.set_labels(PoolStringArray(colorbar_labels))
		$MapColorbar.set_colors(PoolColorArray(colors.slice(1,len(colors))))
		$MapColorbar.visible=true
		step=max(1.0,step)
	else:
		$MapColorbar.visible=false
	system_metadata.resize(len(pos_pool))
	for index in range(len(pos_pool)):
		var flags: int = 0
		var price = null
		if min_stat!=INF:
			price = price_at_index.get(index,-1)
			if price and price>0:
# warning-ignore:narrowing_conversion
				flags = clamp(int(floor((price-min_stat)/step)),1,ncolors)
		system_metadata[index] = price
		if location_index==index:
			flags |= at_location
		if selection_index==index:
			flags |= at_selection
		if draw.has(flags):
			draw[flags].append(index)
		else:
			draw[flags] = [index]
		
	for flags in draw:
# warning-ignore:shadowed_variable
		var system_color = colors[flags&color_mask]
		var label_color = system_color
		var font = label_font
# warning-ignore:shadowed_variable
		var system_scale = 1.0
		if flags&at_location or flags&at_selection:
			font = highlighted_font
		if flags&at_location:
			system_scale *= 1.5
		starmap.add_system_visuals(PoolIntArray(draw[flags]),
			system_color, label_color, font, system_scale)

func navigational_visuals(selection_index: int, location_index: int):
	if location_index==selection_index and location_index>=0:
		starmap.add_system_visuals(PoolIntArray([selection_index]),
			highlight_color, system_name_color, highlighted_font, 1.2)
		starmap.add_adjacent_link_visuals(PoolIntArray([selection_index]),
			connected_color, 1.5)
	else:
		if location_index>=0:
			starmap.add_system_visuals(PoolIntArray([location_index]),
				system_location_color, system_name_color, highlighted_font, 1.2)
			starmap.add_adjacent_link_visuals(PoolIntArray([location_index]),
				connected_location_color, 1.5)
		
		if selection_index>=0:
			starmap.add_system_visuals(PoolIntArray([selection_index]),
				highlight_color, system_name_color, highlighted_font, 1.0)
			starmap.add_adjacent_link_visuals(PoolIntArray([selection_index]),
				connected_color, 1.0)

func index_at_position(screen_position: Vector2):
	var epsilon = SELECT_EPSILON*$View/Port/Camera.size
	var pos3 = $View/Port/Camera.project_position(
		screen_position-$View.rect_global_position,-10)
	return starmap.system_at_location(pos3, epsilon)

func find_at_position(screen_position: Vector2):
	var result = index_at_position(screen_position)
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
		if $Window.visible:
			$Window/Tree.clear()
		emit_signal('deselect')
		update_starmap_visuals()
		return true
	return false

func change_selection_to(new_selection,_center: bool = false) -> bool:
	game_state.universe.lock()
	selection=new_selection
	if selection is simple_tree.SimpleNode:
		if $Window.visible:
			if selection is simple_tree.SimpleNode and selection.has_method('is_SystemData'):
				$Window/Tree.set_system(selection)
			else:
				$Window/Tree.clear()
		emit_signal('select',selection)
		Player.destination_system = selection.get_path()
	elif selection==null:
		if $Window.visible:
			$Window/Tree.clear()
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
	var pos2: Vector2 = utils.event_position(event)
	if not get_global_rect().has_point(pos2):
		return
	if not is_visible_in_tree():
		return
	if $Window.visible:
		var rect: Rect2 = $Window.get_global_rect().grow_individual(10,30,10,10)
		if rect.has_point(pos2):
			return # event is inside window
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
	if event is InputEventMouseMotion and not system_metadata.empty():
		var index = index_at_position(pos2)
		if index!=hover_index:
			hover_index=index
			if hover_index>=0 and hover_index<len(name_pool):
				if hover_index==get_location_index():
					emit_signal('hover_over_player_location',name_pool[index],
						display_name_pool[index],system_metadata[index])
				else:
					emit_signal('hover_over_system',name_pool[index],
						display_name_pool[index],system_metadata[index])
			else:
				emit_signal('hover_no_system')
	
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



func _on_Tree_center_on_node(path):
	emit_signal('activate_space_object',path)


func _on_Tree_deselect_node():
	emit_signal('deselect_space_object')


func _on_Tree_select_node(path):
	emit_signal('select_space_object',path)


func _on_StarmapPanel_visibility_changed():
	maybe_show_window()
