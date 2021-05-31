extends ViewportContainer

export var hover_check_ticks: int = 100

const InventoryArray: Script = preload('res://ui/ships/InventoryArray.gd')
const InventoryContent: Script = preload('res://ui/ships/InventoryContent.gd')
const InventorySlot: Script = preload('res://ui/ships/InventorySlot.gd')

const SHIP_LAYER_MASK: int = 1
const INSTALLED_LAYER_MASK: int = 2
const MOUNT_POINT_LAYER_MASK: int = 4
const MULTIMOUNT_LAYER_MASK: int = 32

const ITEM_LIGHT_CULL_LAYER: int = 1
const SHIP_LIGHT_CULL_LAYER: int = 2
const RED_LIGHT_CULL_LAYER: int = 8

signal update_coloring
signal pixel_height_changed
signal select_item
signal deselect_item
signal drag_selection
signal design_changed
signal hover_over_InventorySlot
signal hover_over_MultiSlotItem

const y500: Vector3 = Vector3(0,500,0)
var ship_aabb: AABB
var root: simple_tree.SimpleNode
var mounts: simple_tree.SimpleNode
var tree: simple_tree.SimpleTree
var selection_click
var selection_dragging = false
var selected_scene
var selection: NodePath = NodePath()
var old_collider_path: NodePath = NodePath()
var old_drag_location: Vector3 = Vector3(-9999,-9999,-9999)
var last_hover: NodePath
var last_location_check_tick: int = -9999999

func update_hover(what):
	if not what:
		emit_signal('hover_over_InventorySlot',null)
		return
	if what.my_x>=0 and what.my_y>=0:
		var parent = what.get_parent()
		if parent and parent.has_method("is_InventoryArray"):
			var item = parent.item_at(what.my_x,what.my_y)
			var item_path = item.get_path() if item else NodePath()
			var scene = parent.scene_at(what.my_x,what.my_y)
			if item_path!=last_hover:
				last_hover=item_path
				emit_signal('hover_over_MultiSlotItem',item,scene)
			return
	var what_path = what.get_path() if what else NodePath()
	if what_path!=last_hover:
		last_hover=what_path
		emit_signal('hover_over_InventorySlot',what)

class MountData extends simple_tree.SimpleNode:
	var nx: int
	var ny: int
	var mount_type: String
	var transform: Transform
	var box: NodePath
	var box_translation: Vector3
	var multimount: bool
	var content: NodePath = NodePath()
	var scene = null # : PackedScene or null
	
	func _init(child,ship_design_view: ViewportContainer):
		var loc: Vector3 = Vector3(child.translation.x,0,child.translation.z)
		nx = child.mount_size_x
		ny = child.mount_size_y
		set_name(child.name)
		mount_type = child.mount_type
		transform = child.transform
		
		multimount = child.mount_type=='equipment'
		var mp
		if multimount:
			mp = ship_design_view.multimount_point(nx,ny,loc,child.mount_type,child.name)
		else:
			mp = ship_design_view.mount_point(nx,ny,loc,child.name,child.mount_type)
		box_translation = mp.translation
		box = mp.get_path()

func ship_world():
	var ship = $Viewport.get_node_or_null('Ship')
	if ship:
		return ship.get_world()
	push_error('Tried to get ship world with no ship')
	return $Viewport.get_world()

func deselect():
	selection=NodePath()
	selection_click=null
	selection_dragging=false
	selected_scene=null
	emit_signal('update_coloring',-1,-1,null,'')

func get_cell_pixel_height() -> float:
	var view_size: Vector2 = $Viewport.size
	var ul_corner: Vector3 = $Viewport/Camera.project_position(Vector2(0,0),-10)
	var lr_corner: Vector3 = $Viewport/Camera.project_position(view_size,-10)
	return view_size.y * 0.135*2.0/max(abs(ul_corner.x-lr_corner.x),0.01)

func at_position(pos,mask: int) -> Dictionary:
	# Helper function to do an intersect_ray at a particular screen location.
	if pos==null:
		return {}
	var space: PhysicsDirectSpaceState = ship_world().direct_space_state
	var from = $Viewport/Camera.project_ray_origin(pos)
	from.y = $Viewport/Camera.translation.y+500
	var to = from + $Viewport/Camera.project_ray_normal(pos)
	to.y = $Viewport/Camera.translation.y-500
	return space.intersect_ray(from,to,[],mask,true,true)

func select_multimount(mouse_pos: Vector2, space_pos: Vector3, 
		collider: CollisionObject, is_location_select, is_hover_check) -> bool:
	var parent = collider.get_parent()
	if parent==null:
		printerr('Orphaned node found in select_multimount.')
		return false
	elif not parent.has_method('remove_child_or_null'):
		printerr('Multimount slot does not have a multimount parent.')
		return false
	
	var ship_mount = $Viewport/Ship.get_node_or_null(parent.name)
	if ship_mount==null:
		printerr('Cannot find ship mount "',parent.name,'"')
		return false
	
	var xy = parent.slot_xy_for(space_pos,1,1)
	var scene = parent.scene_at(xy[0],xy[1])
	if scene:
		if is_location_select:
			emit_signal('select_item',collider,scene)
			selection_click = mouse_pos
			selection = collider.get_path()
			selected_scene = scene
		if is_hover_check:
			update_hover(collider)
		return true
	return false
#
#
#func in_top_dialog(node,top) -> bool:
#	if node==null:
#		return false
#	if node==top:
#		return true
#	return in_top_dialog(node.get_parent(),top)

func _input(event):
	var scene = get_tree().current_scene
	if scene and scene.has_method('popup_has_focus'):
		if get_tree().current_scene.popup_has_focus():
			return
	elif not is_visible_in_tree():
		return
	var view_pos = rect_global_position
	var view_rect: Rect2 = Rect2(view_pos, rect_size)
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	if view_rect.has_point(mouse_pos):
		var is_location_select = event.is_action_pressed('ui_location_select')
		var click_tick = OS.get_ticks_msec()
		var is_hover_check = click_tick-last_location_check_tick>hover_check_ticks
		if is_location_select or is_hover_check:
			if is_hover_check:
				last_location_check_tick=OS.get_ticks_msec()
			var space_pos: Vector3 = $Viewport/Camera.project_position(mouse_pos-view_pos,-30)
			var space: PhysicsDirectSpaceState = ship_world().direct_space_state
			var result: Dictionary = space.intersect_ray(
				space_pos-y500,space_pos+y500,[],INSTALLED_LAYER_MASK|MULTIMOUNT_LAYER_MASK,true,true)
			var collider = result.get('collider',null)
			if collider and collider.has_method('is_InventorySlot'):
				if collider.my_x<0:
					if is_location_select:
						emit_signal('select_item',collider,collider.scene)
						selection_click = mouse_pos
						selection = collider.get_path()
						selected_scene = collider.scene
					if is_hover_check:
						update_hover(collider)
				elif not select_multimount(mouse_pos, space_pos, collider,
						is_location_select, is_hover_check):
					if is_location_select:
						emit_signal('deselect_item')
					if is_hover_check:
						update_hover(null)
			else:
				if is_location_select:
					emit_signal('deselect_item')
				if is_hover_check:
					update_hover(null)
			selection_dragging=false
		elif selection:
			if Input.is_action_pressed('ui_location_select'):
				if not selection_dragging and mouse_pos.distance_to(selection_click)>3:
					selection_dragging=true
					var _discard = remove_selected_item()
					emit_signal('drag_selection',selected_scene)
			else:
				selection_dragging=false

func dragging_item(item: MeshInstance):
	var pos2 = get_viewport().get_mouse_position() - rect_global_position
	var pos3 = $Viewport/Camera.project_position(pos2,-10)
	var space: PhysicsDirectSpaceState = ship_world().direct_space_state
	var there: Dictionary = space.intersect_ray(
		Vector3(pos3.x,-500,pos3.z),Vector3(pos3.x,500,pos3.z),[],36,false,true)
	var collider = there.get('collider',null)
	var path = collider.get_path() if collider!=null else NodePath()
	if old_collider_path!=path or old_drag_location.distance_to(pos3)>0.05:
		if collider:
			collider.update_coloring(item.item_size_x,item.item_size_y,pos3,item.mount_type)
		else:
			emit_signal('update_coloring',item.item_size_x,item.item_size_y,pos3,item.mount_type)
	old_collider_path=path
	old_drag_location=pos3

func remove_selected_item() -> bool:
	var selected_node = get_node_or_null(selection)
	if not selected_node or not selected_node.has_method('is_InventorySlot'):
		# push_warning('Tried to remove a selected item when none was selected (selection='+str(selection)+')')
		return false
	elif selected_node.my_x<0 or selected_node.my_y<0:
		return universe_edits.state.push(ship_edits.RemoveItem.new(selected_scene,
			selected_node.mount_name, selected_node.my_x, selected_node.my_y))
	var parent = selected_node.get_parent()
	if not parent or not parent.has_method('is_InventoryArray'):
		push_error('Multimount slot has no InventoryArray parent')
		return false
	
	var item = parent.item_at(selected_node.my_x,selected_node.my_y)
	if not item:
		pass # push_warning('Multimount slot has no item (selection='+str(selection)+')')
		return false
	return universe_edits.state.push(ship_edits.RemoveItem.new(selected_scene,
		parent.name, item.item_offset_x, item.item_offset_y))

func _init():
	root = simple_tree.SimpleNode.new()
	tree = simple_tree.SimpleTree.new(root)
	mounts = simple_tree.SimpleNode.new()
	mounts.set_name('MountPoints')
	var _discard = root.add_child(mounts)

func clear_ship():
	var _discard = mounts.remove_all_children()
	var ship_node = root.get_child_with_name('Ship')
	if ship_node:
		_discard = root.remove_child(ship_node)
	
	for child_name in [ 'Ship', 'Hull' ]:
		var ship = get_node_or_null(child_name)
		if ship:
			remove_child(ship)
			ship.queue_free()
	
	for child in $Viewport/Installed.get_children():
		$Viewport/Installed.remove_child(child)
		child.queue_free()
	
	for child in $Viewport/MountPoints.get_children():
		$Viewport/MountPoints.remove_child(child)
		child.queue_free()

func multimount_point(width: int,height: int,loc: Vector3,mount_type: String,box_name: String) -> Spatial:
	# Create an area that allows multiple non-overlapping items to be mounted
	var box: Spatial = Spatial.new()
	box.set_script(InventoryArray)
	box.create(width,height,mount_type)
	# Note: equipment box is not displaced, unlike regular mounts.
	box.translation = Vector3(loc.x,0,loc.z)
	box.name=box_name
	var _discard=connect('update_coloring',box,'update_coloring')
	$Viewport/MountPoints.add_child(box)
	return box

func mount_point(width: int,height: int,loc: Vector3,box_name: String,mount_type: String) -> Area:
	# Create an area that allows only one item to be mounted
	var box: Area = Area.new()
	box.set_script(InventorySlot)
	box.create_only_box(width,height,mount_type)
	box.place_near(loc,ship_world().direct_space_state, \
		MOUNT_POINT_LAYER_MASK | SHIP_LAYER_MASK)
	box.translation.y = loc.y
	box.name=box_name
	box.collision_layer = MOUNT_POINT_LAYER_MASK
	var _discard=connect('update_coloring',box,'update_coloring')
	$Viewport/MountPoints.add_child(box)
	return box

func release_dragged_item(item: MeshInstance, scene: PackedScene) -> bool:
	deselect()
	var pos2 = get_viewport().get_mouse_position() - rect_global_position
	var pos3 = $Viewport/Camera.project_position(pos2,-10)
	var space: PhysicsDirectSpaceState = ship_world().direct_space_state
	var there: Dictionary = space.intersect_ray(
		Vector3(pos3.x,-500,pos3.z),Vector3(pos3.x,500,pos3.z),[],36,false,true)
	var target: CollisionObject = there.get('collider',null)
	if not target:
		print('No mount under that location.')
		return false
	var mount_name: String = target.get_mount_name()
	var mount = mounts.get_child_with_name(mount_name)
	if not mount_name:
		push_warning('Tried to drag into mount "'+mount_name+'" which does not exist.')
		return false
	if mount.mount_type != item.mount_type:
		print('Mount type mismatch: item='+item.mount_type+' mount='+mount.mount_type)
		return false
	var x = -1
	var y = -1
	if mount.multimount:
		var inventory_array = get_node_or_null(mount.box)
		var slot_xy = inventory_array.slot_xy_for(pos3,item.item_size_x,item.item_size_y)
		x=slot_xy[0]
		y=slot_xy[1]
	var installed = $Viewport/Installed.get_node_or_null(mount_name)
	if installed!=null and not universe_edits.state.push(
			ship_edits.RemoveItem.new(installed.scene,mount_name,x,y)):
		push_error('Could not remove item from '+mount_name)
		return false
	return universe_edits.state.push(ship_edits.AddItem.new(scene,mount_name,x,y))

func add_item(scene: PackedScene,mount_name: String,x: int,y: int) -> bool:
	var item = scene.instance()
	var mount = mounts.get_node_or_null(mount_name)
	if not mount or not mount is MountData:
		push_error('tried to mount on a non-existent mount "'+mount_name+'"')
		return false
	var content = InventoryContent.new()
	content.create(mount.transform.origin,item.item_size_x,item.item_size_y,item.mount_type,scene,x,y)
	return try_to_mount(content, mount_name, true)

func remove_item(_scene: PackedScene,mount_name: String,x: int,y: int) -> bool:
	return unmount(mount_name,x,y)

func unmount(mount_name: String,x: int,y: int) -> bool:
	var mount = mounts.get_node_or_null(mount_name)
	if mount.multimount and (x<0 or y<0):
		push_error('Tried to mount from an unspecified location in a multimount')
		return false
	elif mount['multimount']:
		var parent = get_node_or_null(mount.box)
		if parent==null:
			return false
		var ship_mount = $Viewport/Ship.get_node_or_null(parent.name)
		if ship_mount==null:
			push_error('Cannot find ship mount "'+parent.name+'"')
			return false
		var scene_x_y = parent.remove_child_or_null(x,y)
		var scene = scene_x_y[0]
		if not scene:
			return false
		var child_name = 'cell_'+str(scene_x_y[1])+'_'+str(scene_x_y[2])
		var old_child = ship_mount.get_node_or_null(child_name)
		if old_child==null:
			print('Cannot find unmounted item "'+child_name+'" in ship.')
		else:
			ship_mount.remove_child(old_child) # make the node name available again
			old_child.queue_free()
		return true
	else:
		var child = $Viewport/Ship.get_node_or_null(mount_name)
		if child!=null:
			$Viewport/Ship.remove_child(child)
			child.queue_free()
		child = $Viewport/Installed.get_node_or_null(mount_name)
		if child!=null:
			$Viewport/Installed.remove_child(child)
			child.queue_free()
		mount.content = NodePath()
		mount.scene = null
		return true

func place_in_multimount(content, mount: MountData, use_item_offset: bool) -> bool:
	# Install a component (area) in the multimount.
	# The location is based on the area location and item size.
	var inventory_array = $Viewport.get_node_or_null(mount.box)
	if inventory_array==null:
		print('no inventory array for '+mount.get_name()+' at path '+str(mount.box))
		return false
	var ship_mount = $Viewport/Ship.get_node_or_null(mount.get_name())
	if ship_mount==null:
		print('no ship mount for '+mount.get_name())
		return false
	var x_y = inventory_array.insert_at_grid_range(content,use_item_offset)
	if not x_y:
		return false
	
	var x: int = x_y[0]
	var y: int = x_y[1]
	var cell_name: String = 'cell_'+str(x)+'_'+str(y)
	var install = content.scene.instance()
	install.item_offset_x = x
	install.item_offset_y = y
	install.name=cell_name
	install.visible=false
	if install is CollisionObject:
		install.collision_mask=0
		install.collision_layer=0
	ship_mount.add_child(install)
	set_layer_recursively(install,SHIP_LIGHT_CULL_LAYER)
	if install.name!=cell_name:
		install.queue_free()
		return false
	return true

func place_in_single_mount(content, mount: MountData) -> bool:
	# Install a component (content) in the mount in mounts[mount_name]
	if content.nx>mount.nx or content.ny>mount.ny:
		return false
	var mount_content = get_node_or_null(mount.content)
	if mount_content!=null:
		mount_content.queue_free()
	mount.content = copy_to_installed(mount.get_name(),content,mount.box_translation)
	mount.scene = content.scene
	
	var make_visible = mount.mount_type=='gun' or mount.mount_type=='turret'
	
	var install = content.scene.instance()
	install.visible = make_visible
	install.transform = mount.transform
	install.name = mount.get_name()
	install.mount_size_x = mount.nx
	install.mount_size_y = mount.ny
	var child = $Viewport/Ship.get_node_or_null(mount.get_name())
	if child!=null:
		child.replace_by(install)
	else:
		$Viewport/Ship.add_child(install)
	set_layer_recursively(install,SHIP_LIGHT_CULL_LAYER)
	install.owner=$Viewport/Ship
	install.name = mount.get_name()
	return true

func copy_to_installed(installed_name: String,child,display_location: Vector3) -> NodePath:
	var area = child.copy_only_item()
	area.collision_layer = INSTALLED_LAYER_MASK
	area.translation = Vector3(display_location.x,7,display_location.z)
	area.name = installed_name
	var old = $Viewport/Installed.get_node_or_null(area.name)
	if old:
		$Viewport/Installed.remove_child(old)
		old.queue_free()
	$Viewport/Installed.add_child(area)
	area.name = installed_name
	if area.name != installed_name:
		printerr('Godot renamed installed item to '+area.name+' so I will not be able to remove it.')
	return area.get_path()

func make_design(design_id,display_name) -> Dictionary:
	var ship = tree.get_node_or_null('/root/Ship')
	if not ship:
		push_error("Cannot encode a ship's design until a ship is loaded.")
	var hull_scene = ship.hull
	assert(hull_scene)
	assert(hull_scene is PackedScene)
	var design = game_state.universe.ShipDesign.new(display_name,hull_scene)
	design.set_name(design_id)
	for mount_name in mounts.get_child_names():
		var mount = mounts.get_child_with_name(mount_name)
		if not mount:
			# Should never get here.
			push_error('Internal error: mount has no child with a name from get_child_names')
		elif mount.multimount:
			var node = get_node_or_null(mount.box)
			if node==null:
				printerr('null node for mount ',mount_name,' path ',str(mount.box))
			var content: simple_tree.SimpleNode = node.content_for_design(mount_name)
			design.add_child(content)
		elif mount.scene:
			var mounted = game_state.universe.Mounted.new(mount.scene)
			mounted.set_name(mount_name)
			design.add_child(mounted)
	design.cargo = ship.cargo
	return design

func list_ship_parts(parts,from):
	var ship = tree.get_node_or_null('/root/Ship')
	if not ship:
		push_error("Cannot list ship parts until a ship is loaded.")
		return parts
	parts.add_quantity_from(from,ship.hull.resource_path,1,Commodities.ship_parts)
	for mount_name in mounts.get_child_names():
		var mount = mounts.get_child_with_name(mount_name)
		if not mount:
			# Should never get here.
			push_error('Internal error: mount has no child with a name from get_child_names')
		elif mount.multimount:
			var node = get_node_or_null(mount.box)
			if node:
				node.list_ship_parts(parts,from)
			else:
				push_error('No box path for multimount "'+str(mount_name)+'"')
		elif mount.scene:
			#print('single add quantity from '+str(mount.scene.resource_path))
			parts.add_quantity_from(from,mount.scene.resource_path,1,Commodities.ship_parts)
	return parts

func make_ship(design):
	clear_ship()
	
	var encoded = game_state.universe.encode_helper(design)
	var decoded = game_state.universe.decode_helper(encoded)
	decoded.set_name('Ship')
	var _discard = root.add_child(decoded)

	#var ship = $Viewport.assemble_ship(decoded)
	var ship = design.hull.instance()
	ship.name='Ship'
	ship.collision_layer = SHIP_LAYER_MASK
	ship.collision_mask = SHIP_LAYER_MASK
	ship.random_height = false
	ship.retain_hidden_mounts = true
	ship.ship_display_name = design.display_name
	set_layer_recursively(ship,SHIP_LIGHT_CULL_LAYER)
	var existing = $Viewport.get_node_or_null('Ship')
	if existing:
		$Viewport.remove_child(existing)
		existing.queue_free()
	ship.pack_stats(true)
	$Viewport.add_child(ship)
	ship.name = 'Ship'
	if design.cargo:
		ship.set_cargo(design.cargo.copy())
	for child in sorted_ship_children(ship):
		if child.get('mount_type')!=null:
			_discard = mounts.add_child(MountData.new(child,self))

	for mount_name in decoded.get_child_names():
		var mount = decoded.get_child_with_name(mount_name)
		if mount and mounts.has_child(mount_name):
			if mount.has_method('is_MultiMount'):
				add_multimount_contents(mount_name,decoded)
				continue
			var area: Area = Area.new()
			area.set_script(InventorySlot)
			area.create_item(mount.scene,false)
			if not try_to_mount(area,mount_name,true):
				area.queue_free()
		elif mount_name!='hull':
			printerr('ShipEditor: mount "',mount_name,'" does not exist.')
	ship_aabb = combined_aabb(ship)
	ship_aabb = ship_aabb.merge(combined_aabb($Viewport/MountPoints))
	move_Camera_for_scene()
	emit_signal('design_changed',decoded)
	return ship

func move_Camera_for_scene():
	# Move the camera to fit the ship design, plus some space at the bottom
	# for the scrollbar and items.
	var size_x = clamp(abs(ship_aabb.size.x),8.0,18.0)
	size_x += 2.0 * 10.0/size_x
	$Viewport/Camera.size = size_x
	var pos = ship_aabb.position + ship_aabb.size*0.5
	$Viewport/Camera.translation.x = pos.x
	$Viewport/Camera.translation.z = pos.z

func combined_aabb(node: Node):
	# Get an AABB large enough for all visual instances in this node and its
	# descendants, recursively.
	var result: AABB = AABB()
	if node is VisualInstance:
		result = node.get_aabb()
	for child in node.get_children():
		result=result.merge(combined_aabb(child))
	if node is Spatial:
		result = node.transform.xform(result)
	return result

func add_multimount_contents(mount_name: String,design: simple_tree.SimpleNode):
	# Load contents of a multimount from a design dictionary.
	var contents: simple_tree.SimpleNode = design.get_child_with_name(mount_name)
	assert(contents)
	if not contents:
		print('no node for multimount '+mount_name)
		return
	for item in contents.get_children():
		if not item.has_method('is_MultiMounted'):
			continue
		var scene: PackedScene = item.scene
		assert(scene)
		var area: Area = Area.new()
		area.set_script(InventorySlot)
		area.create_item(scene,false,Vector2(item.x, item.y))
		area.my_x = item.x
		area.my_y = item.y
		if not try_to_mount(area,mount_name,true):
			area.queue_free()

func try_to_mount(content, mount_name: String, use_item_offset: bool):
	# Install the item (area) in the specified mount, which may be a single
	# or multimount.
	var mount = mounts.get_node_or_null(mount_name)
	if not mount:
		print('no mounts for '+mount_name)
		return false
	if content.mount_type!=mount.mount_type:
		print('mount type mismatch: content '+content.mount_type+' vs. mount '+mount.mount_type)
		return false
	if not content.scene:
		push_warning('content has no scene '+mount_name)
		return false
	
	if mount.multimount:
		return place_in_multimount(content,mount,use_item_offset)
	return place_in_single_mount(content,mount)

class CompareMountLocations:
	static func cmp(a: Spatial,b: Spatial) -> bool:
		# Sort function to beautify the locations of mount points on the screen.
		var eq_a: bool = a.mount_type=='equipment'
		var eq_b: bool = b.mount_type=='equipment'
		if eq_a and not eq_b:
			return true
		elif eq_b and not eq_a:
			return true
		elif sign(a.translation.z)<sign(b.translation.z):
			return sign(a.translation.z)<sign(b.translation.z)
		var a_angle: float = atan2(abs(a.translation.z),a.translation.x)
		var b_angle: float = atan2(abs(b.translation.z),b.translation.x)
		return a_angle<b_angle

func sorted_ship_children(ship: Node) -> Array:
	# Return a sorted list of mount names, arranged to beautify the locations of mounts.
	var just_mounts: Array = []
	for child in ship.get_children():
		if child.get('mount_type')!=null:
			just_mounts.append(child)
	just_mounts.sort_custom(CompareMountLocations,'cmp')
	return just_mounts

func set_layer_recursively(node: Node,layer: int):
	if node is VisualInstance:
		node.layers=layer
	for child in node.get_children():
		set_layer_recursively(child,layer)

func _ready():
	$Viewport.size = rect_size
	$Viewport/SpaceBackground.update_from(Player.system)
	$Viewport/Red.layers = RED_LIGHT_CULL_LAYER
	$Viewport/Red.light_cull_mask = RED_LIGHT_CULL_LAYER
	$Viewport/SpaceBackground.center_view(130,90,0,120,0)
	make_ship(Player.player_ship_design)
	emit_signal('pixel_height_changed',get_cell_pixel_height())

func _on_ViewportContainer_resized():
	$Viewport.size = rect_size
	emit_signal('pixel_height_changed',get_cell_pixel_height())
