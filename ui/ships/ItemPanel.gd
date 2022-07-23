extends Panel

export var show_ships: bool = false # false = items, true = ships
export var test_mode: bool = false
export var min_aabb_scale: float = 4.0
export var ship_border: float = 0.00
export var initial_scale: float = 2.0
export var hover_check_ticks: int = 100
export var enabled_font: Font
export var enabled_color: Color = Color(0.7,0.9,1.0,1.0)
export var disabled_font: Font
export var disabled_color: Color = Color(1.0,0.8,0.8,1.0)

const InventorySlot: GDScript = preload('res://ui/ships/InventorySlot.gd')
const InventoryArray: GDScript = preload('res://ui/ships/InventoryArray.gd')
const y500: Vector3 = Vector3(0,500,0)
const cell_span: float = 0.25
const cell_pad: float = cell_span/2.0

signal select_item
signal deselect_item
signal drag_selection
signal add_design
signal change_design
signal remove_design
signal edit_design
signal hover_over_InventorySlot

var ship_zspan = 1.0 + 2.0*ship_border # must be >1.0
var ship_xspan = ship_zspan
var last_click_tick = -9999999
var scenes = {} # key is resource_path, used to detect duplicate objects
var item_count = {} # key is resource path, value is item count; missing means infinite
var item_cost = {} # key is resource path, value is cost per item
var item_xspan = {}
var design_names = {}
var scroll_rate = 0.0
var last_used_x_index: int = 0
var camera_xspan

var max_purchase_value = null
var items_mutex: Mutex = Mutex.new()
var items_updated: bool = false
var resized: bool = true
var selection: NodePath = NodePath()
var selection_click: Vector2
var selection_dragging: bool = false
var viewport: Viewport
var items: Spatial
var camera: Camera
var scrollbar: VScrollBar
var scale: float = initial_scale
var last_hover: NodePath
var last_location_check_tick: int = -9999999

var regular_layer: int = 0
var disabled_layer: int = 0
var highlight_layer: int = 0

func update_hover(what):
	var what_path = what.get_path() if what else NodePath()
	if what_path!=last_hover:
		last_hover=what_path
		emit_signal('hover_over_InventorySlot',what)

func clear_items():
	var _discard = deselect(false)
	for child in $All/Top/View/Port/Items.get_children():
		$All/Top/View/Port/Items.remove_child(child)
		child.queue_free()
	design_names.clear()
	scenes.clear()

func _ready():
	$All/Buttons/Zoom.value = initial_scale
	viewport = $All/Top/View/Port
	items = $All/Top/View/Port/Items
	camera = $All/Top/View/Port/Camera
	scrollbar = $All/Top/Scroll
	viewport.transparent_bg = true
	regular_layer = $All/Top/View/Port/Sun.layers
	disabled_layer = $All/Top/View/Port/Red.layers
	highlight_layer = $All/Top/View/Port/SelectBack.layers
	$All/Top/View/Port/Sun.light_cull_mask = regular_layer
	$All/Top/View/Port/Red.light_cull_mask = disabled_layer
	$All/Top/View/Port/SelectBack.light_cull_mask = highlight_layer
	$All/Top/View/Port/SelectFront.light_cull_mask = highlight_layer
	if not show_ships:
		forbid_edits(true)
		$All/Top/View.hint_tooltip = 'Select a design to view it.'
	else:
		update_buttons()
		$All/Top/View.hint_tooltip = 'Select an item to see stats; drag to install.'

func forbid_edits(forbid_open=false):
	var forbid_me = ['Add','Change','Remove']
	if forbid_open:
		forbid_me.append('Open')
	for button_name in forbid_me:
		var child = $All/Buttons.get_node_or_null(button_name)
		if child:
			$All/Buttons.remove_child(child)
			child.queue_free()
	$All/Buttons.columns = len($All/Buttons.get_children())

func update_buttons():
	for button_name in ['Change','Remove','Open']:
		var child = $All/Buttons.get_node_or_null(button_name)
		if child:
			child.disabled = not selection

func decide_layers(node,highlight) -> int:
	var layers = highlight_layer if highlight else regular_layer
	if node.scene:
		var resource_path=node.scene.resource_path
		var count=item_count.get(resource_path,null)
		if count!=null and count<1:
			layers |= disabled_layer
		elif max_purchase_value!=null:
			var cost=item_cost.get(resource_path,null)
			if cost!=null and cost>max_purchase_value:
				layers |= disabled_layer
	else:
		push_warning('Node at path "'+str(node.get_path())+'" has no scene')
	return layers

func deselect(send_event=false) -> bool:
	if not selection:
		return true
	var node = get_node_or_null(selection)
	if send_event:
		emit_signal('deselect_item',node)
	selection=NodePath()
	if node:
		set_layers(node,decide_layers(node,false))
	update_buttons()
	return true

func select(var node: Node,send_event=true) -> bool:
	if selection:
		var _discard = deselect(send_event)
	selection=node.get_path()
	set_layers(node,decide_layers(node,true))
	update_buttons()
	return true

func set_layers(node: Node, layers: int):
	if node is VisualInstance:
		node.layers = layers
	for child in node.get_children():
		set_layers(child,layers)

func add_ship_design(design) -> bool:
	if not show_ships:
		push_error('Cannot load ships into this ItemPanel.')
		return false
	if not design.has_method('is_ShipDesign'):
		push_warning('Tried to add a ship design that was not a ShipDesign')
		return false
	if design_names.has(design.get_name()):
		push_warning('Already added ship design "'+design.get_name()+'".')
		return false
	var ship = design.assemble_ship()
	if not ship is RigidBody:
		push_error('Ship design "'+design.get_name()+'" is not a RigidBody.')
		ship.queue_free()
		return false
	ship.name = design.get_name()
	var old = items.get_node_or_null(design.get_name())
	if old:
		items.remove_child(old)
		old.queue_free()
	items.add_child(ship)
	var aabb: AABB = ship.get_combined_aabb()
# warning-ignore:shadowed_variable
	var scale: float = max(aabb.size.x,aabb.size.z)
	scale = 1.0 / max(2.0,scale + 2.0/sqrt(max(scale,0.6)))
	ship.scale = Vector3(scale,scale,scale)
	design_names[ship.name] = design.get_path()
	set_layers(ship,decide_layers(ship,false))
	if selection and selection.get_name(selection.get_name_count()-1)==ship.name:
		var _discard = deselect()
	return true

func remove_ship_design(design_name: String) -> bool:
	var success = false
	var old = items.get_node_or_null(design_name)
	if old:
		items.remove_child(old)
		old.queue_free()
		success = true
	success = design_names.erase(design_name) or success
	if selection and selection.get_name(selection.get_name_count()-1)==design_name:
		var _discard = deselect()
	return success

func add_mountable_part(scene: PackedScene) -> bool:
	if not scene:
		push_error('Null scene in ItemPanel.')
		return false
	if show_ships:
		push_error('Cannot load items into this ItemPanel')
	if scenes.has(scene.resource_path):
		return false
	var item = scene.instance()
	if not item is MeshInstance:
		push_error('Tried to add an item that was not a MeshInstance.')
		return false
	if not item.has_method('is_mountable'):
		push_error('Tried to add an item of an invalid type.')
		return false
	var area: Area = Area.new()
	area.set_script(InventorySlot)
	area.create_item(scene,true,null,item)
	#area.name = scene.resource_path.validate_node_name()
	items_mutex.lock()
	items.add_child(area)
	items_updated = true
	items_mutex.unlock()
	scenes[scene.resource_path] = area.get_path()
	set_layers(area,decide_layers(area,false))
	return true

func _on_available_count_updated(counts,money,_ship_value):
	max_purchase_value = money
	set_item_counts(counts)

func set_item_counts(counts):
	var new_item_count: Dictionary = {}
	var new_item_costs: Dictionary = {}
	for resource_path in scenes:
		var product = counts.by_name.get(resource_path,null)
		if product:
			new_item_count[resource_path] = product.quantity
			new_item_costs[resource_path] = product.value
		else:
			new_item_count[resource_path] = 0
			new_item_costs[resource_path] = 0
	item_count = new_item_count
	item_cost = new_item_costs
	update_item_colors()

func add_ship_parts(parts: Commodities.ManyProducts,include_tags: Array, exclude_tags=null):
	for product in parts.products_for_tags(include_tags,exclude_tags):
		if product:
			var resource_path = product.name
			if not ResourceLoader.exists(resource_path):
				push_error('Ship part refers to invalid path "'+str(resource_path)+'"')
				continue
			var scene = load(resource_path)
			if not scene:
				push_error('Could not load ship part from path "'+str(resource_path)+'"')
				continue
			if add_mountable_part(scene):
				item_count[resource_path] = product.quantity
	update_item_colors()

# warning-ignore:shadowed_variable
func add_part_list(scenes: Array):
	for scene in scenes:
		var _discard = add_mountable_part(scene)
	update_item_colors()

func update_item_colors():
	for child in $All/Top/View/Port/Items.get_children():
		set_layers(child,decide_layers(child,child.get_path()==selection))
	$All/Top/View/Port/Annotations.update()

func arrange_mountable_items():
	var view_size: Vector2 = viewport.size
	if view_size.x<=0 or view_size.y<=0:
		return
	
	var screen_size: Vector2 = get_viewport().size
	assert(screen_size)
	var zoom: float = clamp($All/Buttons/Zoom.value,1.0,12.0)
	var ship_pixel_height: float = max(40,screen_size.y/zoom)
	camera_xspan = view_size.y/ship_pixel_height * ship_xspan
	camera.size = camera_xspan
	scrollbar.page = camera_xspan
	
	var view_start: Vector3 = camera.project_position(Vector2(0.0,0.0),-30.0)
	var view_end: Vector3 = camera.project_position(viewport.size,-30.0)
	#var view_height = abs(view_end.x-view_start.x)
	var view_zspan = abs(view_end.z-view_start.z)

# warning-ignore:narrowing_conversion
	var cells_across: int = max(1,int(floor(view_zspan/cell_span)))
	var z_start: float = -view_zspan/2.0
	var x_start: float = 0.0
	
	var child_names: Array = []
	for child in items.get_children():
		child_names.append(child.name)
	child_names.sort()
	var next_child = 0
	var row_max_zspan = max(6,cells_across-1)
	var row_x_start: float = x_start
	while next_child<len(child_names):
		# First pass: collect items that fit in this row:
		var row: Array = []
		var row_zspan: int = 0
		var row_height: int = 0
		while next_child<len(child_names) and row_zspan<row_max_zspan:
			var child_name = child_names[next_child]
			var item = items.get_node_or_null(child_name)
			if not item:
				next_child+=1
				continue
			var pad_span = ceil(cell_pad/cell_span*1.999)
			var item_zspan = int(ceil(item.nx))
			var full_zspan = item_zspan+pad_span
			if row_zspan+full_zspan>row_max_zspan:
				break
			row.append(item)
			row_zspan+=full_zspan
			next_child+=1
# warning-ignore:narrowing_conversion
			row_height = max(row_height,int(ceil(item.ny))+pad_span)
		
		if not row:
			break
		
		# Second pass: set translation and update height
		var row_xspan: float = row_height*cell_span
		var col_z: float = z_start
		for item in row:
			var item_zspan: float = int(ceil(item.nx))*cell_span+2*cell_pad
			item.translation = Vector3(row_x_start-row_xspan/2, 0.0, col_z + item_zspan/2.0)
			item_xspan[item.get_path()] = row_xspan
			col_z += item_zspan
		row_x_start -= row_xspan
	
	scrollbar.min_value=0
	scrollbar.max_value=-row_x_start # start of next row after the last
	
	camera.translation = Vector3(-camera_xspan/2-scrollbar.value, 50.0, 0.0)

func arrange_ship_designs():
	var view_size: Vector2 = viewport.size
	if view_size.x<=0 or view_size.y<=0:
		return
	
	var screen_size: Vector2 = get_viewport().size
	assert(screen_size)
	var zoom: float = clamp($All/Buttons/Zoom.value,1.0,12.0)
	var ship_pixel_height: float = max(40,screen_size.y/zoom)
	camera_xspan = view_size.y/ship_pixel_height * ship_xspan
	camera.size = camera_xspan
	scrollbar.page = camera_xspan
	
	var view_start: Vector3 = camera.project_position(Vector2(0.0,0.0),-30.0)
	var view_end: Vector3 = camera.project_position(viewport.size,-30.0)
	#var view_height = abs(view_end.x-view_start.x)
	var view_zspan = abs(view_end.z-view_start.z)
	
# warning-ignore:narrowing_conversion
	var ships_across: int = max(1,int(floor(view_zspan/ship_zspan)))
	var z_start: float = -view_zspan/2.0 + ship_zspan/2.0
	var x_start: float = -ship_xspan/2.0
	
	var children: Array = items.get_children()
	var child_names: Array = []
	for child in children:
		child_names.append(child.name)
	child_names.sort()
	
	var x_index: int = 0
	var z_index: int = 0
	last_used_x_index= 0
	for child_name in child_names:
		var trans = Vector3(x_start - ship_xspan*x_index,
			1.0, z_start + ship_zspan*z_index)
		last_used_x_index = x_index
		var item_node = items.get_node_or_null(child_name)
		if not item_node:
			continue
		item_node.translation = trans
		if z_index == ships_across-1:
			z_index = 0
			x_index += 1
		else:
			z_index += 1
	#var x_end = x_start + ship_xspan*(last_used_x_index-1)
	scrollbar.min_value=0
	scrollbar.max_value=ship_xspan*(1+last_used_x_index)
	scrollbar.visible = scrollbar.page<scrollbar.max_value
	scrollbar.page=min(scrollbar.page,scrollbar.max_value-scrollbar.min_value)
	
	camera.translation = Vector3(-camera_xspan/2-scrollbar.value, 50.0, 0.0)

func arrange_items():
	if show_ships:
		arrange_ship_designs()
	else:
		arrange_mountable_items()
	
	if scrollbar.page<scrollbar.max_value:
		scrollbar.visible=true
		$All/Top.columns=2
	else:
		scrollbar.visible=false
		$All/Top.columns=1
	
	scrollbar.page=min(scrollbar.page,scrollbar.max_value-scrollbar.min_value)
	$All/Top/View/Port/Annotations.update()

func input():
	if get_tree().current_scene.popup_has_focus():
		return
	if not is_visible_in_tree():
		return
	var view_pos = $All/Top/View.rect_global_position
	var view_rect: Rect2 = Rect2(view_pos, $All/Top/View.rect_size)
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var result: Dictionary
	var collider = null
	if view_rect.has_point(mouse_pos):
		var click_tick = OS.get_ticks_msec()
		if click_tick-last_location_check_tick>hover_check_ticks:
			last_location_check_tick=OS.get_ticks_msec()
			var space_pos: Vector3 = camera.project_position(mouse_pos-view_pos,-30)
			var space: PhysicsDirectSpaceState = items.get_world().direct_space_state
			result = space.intersect_ray(
				space_pos-y500,space_pos+y500,[],2147483647,true,true)
			collider = result.get('collider',null)
			update_hover(collider)
		if Input.is_action_just_released('wheel_up'):
			scroll_rate = clamp(scroll_rate-0.2,-2.0,2.0)
		elif Input.is_action_just_released('wheel_down'):
			scroll_rate = clamp(scroll_rate+0.2,-2.0,2.0)
		elif Input.is_action_just_pressed('ui_location_select'):
			if not result:
				var space_pos: Vector3 = camera.project_position(mouse_pos-view_pos,-30)
				var space: PhysicsDirectSpaceState = items.get_world().direct_space_state
				result = space.intersect_ray(
					space_pos-y500,space_pos+y500,[],2147483647,true,true)
				collider = result.get('collider',null)
			if not collider:
				var _discard = deselect(true)
			else:
				if selection and selection == collider.get_path():
					if click_tick - last_click_tick<400 and show_ships:
						_on_Open_pressed()
				elif collider:
					last_click_tick = click_tick
					var _discard = select(collider)
					emit_signal('select_item',collider)
					selection_click = mouse_pos
				call_deferred('drag_selection')

func drag_selection():
			if not show_ships:
				var selected_node = get_node_or_null(selection)
				if selected_node:
					if selected_node.scene:
						var count = item_count.get(selected_node.scene.resource_path,null)
						if count!=null and count<1:
							return
						if max_purchase_value!=null:
							var cost = item_cost.get(selected_node.scene.resource_path,null)
							if cost!=null and cost>max_purchase_value:
								return
					selection_dragging=true
					emit_signal('drag_selection',selected_node.scene)
					selection_dragging=true
					return
			selection_dragging=false

func _process(delta):
	items_mutex.lock()
	if items_updated or resized:
		items_updated = false
		resized = false
		arrange_items()
	items_mutex.unlock()
	
	if is_visible_in_tree():
		input()
	
	if abs(scroll_rate) > .001:
		scrollbar.value = clamp(scrollbar.value+scroll_rate,scrollbar.min_value,scrollbar.max_value)
		scroll_rate*=pow(0.7,60*delta)

func _on_View_resized():
	$All/Top/View/Port.size = $All/Top/View.rect_size
	resized = true
	$All/Top/View/Port/Annotations.update()

func _on_Zoom_value_changed(value):
	items_mutex.lock()
	scale = value
	resized = true
	items_mutex.unlock()
	$All/Top/View/Port/Annotations.update()

func _on_Scroll_value_changed(value):
	camera.translation = Vector3(-camera_xspan/2-value, 50.0, 0.0)
	$All/Top/View/Port/Annotations.update()

func _on_ItemPanel_visibility_changed():
	arrange_items()

func _on_Add_pressed():
	emit_signal('add_design',selection)

func _on_Change_pressed():
	if selection:
		emit_signal('change_design',selection)

func _on_Remove_pressed():
	if selection:
		emit_signal('remove_design',selection)

func _on_Open_pressed():
	if selection:
		var design_name = selection.get_name(selection.get_name_count()-1)
		var design_path = design_names.get(design_name,null)
		if design_path:
			var design = game_state.ship_designs.get_node_or_null(design_path)
			if design:
				emit_signal('edit_design',design)
			else:
				push_error('There is no design at path "'+str(design_path)+'" in game_state.ship_designs')
		else:
			push_error('Selection '+str(selection)+' has no design path.')

func set_edited_item_id(design_name: String):
	if not show_ships:
		return
	if game_state.ship_designs.get_child_with_name(design_name):
		$All/Buttons/Add.disabled=true
		$All/Buttons/Add.hint_tooltip='There is already a ship design with ID "'+design_name+'".'
	else:
		$All/Buttons/Add.disabled=false
		$All/Buttons/Add.hint_tooltip="Add the design you're currently editing as a new design with id "+'"'+design_name+'"'

func _on_Annotations_draw():
	var enabled_descent: float = enabled_font.get_descent()
	var disabled_descent: float = disabled_font.get_descent()
	var anne: CanvasItem = $All/Top/View/Port/Annotations
	var loc0: Vector2 = camera.unproject_position(Vector3(0,0,0))
	var loc1: Vector2 = camera.unproject_position(Vector3(InventoryArray.grid_cell_size,0,0))
	var cell_size: float = loc1.distance_to(loc0)
	for child in $All/Top/View/Port/Items.get_children():
		if not child.scene:
			push_warning('child '+str(child.get_path())+' has no scene')
		var resource_path = child.scene.resource_path
		var count = item_count.get(resource_path,null)
		if count==null:
			continue
		var string: String = str(max(count,0))
		
		var annotation_font = enabled_font if count>0 else disabled_font
		var annotation_color = enabled_color if count>0 else disabled_color
		var descent = enabled_descent if count>0 else disabled_descent
		
		var size: Vector2 = annotation_font.get_string_size(string)
		var pos2 = camera.unproject_position(child.translation)
		pos2.y -= descent
		var xspan = item_xspan.get(child.get_path(),0)
		pos2.y += cell_size*xspan*2
		pos2.x -= size.x/2.0
		anne.draw_string(annotation_font,pos2,string,annotation_color)
