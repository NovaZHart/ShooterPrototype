extends Spatial

const InventoryArray: Script = preload('res://ui/InventoryArray.gd')
const InventoryContent: Script = preload('res://ui/InventoryContent.gd')
const InventorySlot: Script = preload('res://ui/InventorySlot.gd')
const HullIcon: Script = preload('res://ui/HullIcon.gd')

const available_items: Array = [
	preload('res://weapons/BlueLaserGun.tscn'),
	preload('res://weapons/GreenLaserGun.tscn'),
	preload('res://weapons/OrangeSpikeGun.tscn'),
	preload('res://weapons/PurpleHomingGun.tscn'),
	preload('res://weapons/OrangeSpikeTurret.tscn'),
	preload('res://weapons/BlueLaserTurret.tscn'),
	preload('res://equipment/BigEngineTest.tscn'),
	preload('res://equipment/EquipmentTest.tscn'),
	preload('res://equipment/BigEquipmentTest.tscn'),
]
const allowed_designs: PoolStringArray = PoolStringArray([
	'warship_lasers', 'warship_cyclotrons', 'curvy_cyclotrons', 
	'interceptor_cyclotrons', 'interceptor_lasers',
	'heavy_cyclotrons', 'heavy_lasers'
])
const x_axis: Vector3 = Vector3(1,0,0)
const y_axis: Vector3 = Vector3(0,1,0)

var available_by_page: Dictionary = {}
var designs_by_name: Dictionary = {}
var ship_aabb: AABB = AABB()
var mounts: Dictionary = {}
var used_width: float = 0
var selected: bool = false
var hull_scene: PackedScene
var scroll_active: bool = false
var page_size: float = 0
var old_collider_path: NodePath = NodePath()

const SHIP_LAYER_MASK: int = 1
const INSTALLED_LAYER_MASK: int = 2
const MOUNT_POINT_LAYER_MASK: int = 4
const AVAILABLE_ITEM_LAYER_MASK: int = 8
const AVAILABLE_HULL_LAYER_MASK: int = 16

const ITEM_LIGHT_CULL_LAYER: int = 1
const SHIP_LIGHT_CULL_LAYER: int = 2
const RED_LIGHT_CULL_LAYER: int = 8

signal update_coloring

func set_layer_recursively(node: Node,layer: int):
	if node is VisualInstance:
		node.layers=layer
	for child in node.get_children():
		set_layer_recursively(child,layer)

func multimount_point(width: int,height: int,loc: Vector3,mount_type: String,box_name: String) -> Spatial:
	# Create an area that allows multiple non-overlapping items to be mounted
	var box: Spatial = Spatial.new()
	box.set_script(InventoryArray)
	box.create(width,height,mount_type)
	# Note: equipment box is not displaced, unlike regular mounts.
	box.translation = Vector3(loc.x,0,loc.z)
	box.name=box_name
	var _discard=connect('update_coloring',box,'update_coloring')
	$MountPoints.add_child(box)
	return box

func mount_point(width: int,height: int,loc: Vector3,box_name: String,mount_type: String) -> Area:
	# Create an area that allows only one item to be mounted
	var box: Area = Area.new()
	box.set_script(InventorySlot)
	box.create_only_box(width,height,mount_type)
	box.place_near(loc,get_viewport().world.direct_space_state, \
		MOUNT_POINT_LAYER_MASK | SHIP_LAYER_MASK)
	box.translation.y = loc.y
	box.name=box_name
	box.collision_layer = MOUNT_POINT_LAYER_MASK
	var _discard=connect('update_coloring',box,'update_coloring')
	$MountPoints.add_child(box)
	return box

func copy_to_installed(installed_name: String,child,display_location: Vector3) -> NodePath:
	var area = child.copy_only_item()
	area.collision_layer = INSTALLED_LAYER_MASK
	area.translation = Vector3(display_location.x,7,display_location.z)
	area.name = installed_name
	$Installed.add_child(area)
	area.name = installed_name
	return area.get_path()

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

func add_multimount_contents(mount_name: String,design: Dictionary):
	# Load contents of a multimount from a design dictionary.
	var contents: Array = design[mount_name]
	for item in contents:
		var scene: PackedScene = item[2]
		var area: Area = Area.new()
		area.set_script(InventorySlot)
		area.create_item(scene,false,Vector2(item[0],item[1]))
		area.my_x = item[0]
		area.my_y = item[1]
		if not try_to_mount(area,mount_name,true):
			area.queue_free()

func make_ship(design: Dictionary):
	# Fills the screen with a ship hull and whatever was mounted inside it
	var scene: PackedScene = design['hull']
	hull_scene = scene
	var ship = scene.instance()
	ship.name='Ship'
	ship.collision_layer = SHIP_LAYER_MASK
	ship.collision_mask = 0
	ship.random_height = false
	ship.retain_hidden_mounts = true
	set_layer_recursively(ship,SHIP_LIGHT_CULL_LAYER)
	var existing = get_node_or_null('Ship')
	if existing:
		remove_child(existing)
		existing.queue_free()
	add_child(ship)
	ship.name = 'Ship'
	assert(ship.get_parent())
	assert(get_node_or_null('Ship'))
	for child in sorted_ship_children(ship):
		if child.get('mount_type')!=null:
			var loc: Vector3 = Vector3(child.translation.x,0,child.translation.z)
			var nx: int = child.mount_size_x
			var ny: int = child.mount_size_y
			var multimount: bool = child.mount_type=='equipment'
			var mp
			if multimount:
				mp = multimount_point(nx,ny,loc,child.mount_type,child.name)
			else:
				mp = mount_point(nx,ny,loc,child.name,child.mount_type)
			mounts[child.name]={'name':child.name, 'transform':child.transform, 
				'mount_type':child.mount_type,'scene':'','content':NodePath(),
				'box':mp.get_path(),'nx':nx,'ny':ny,'box_translation':mp.translation,
				'multimount':multimount,
			}
	for mount_name in design:
		if mounts.has(mount_name):
			if mounts[mount_name]['multimount']:
				add_multimount_contents(mount_name,design)
				continue
			var area: Area = Area.new()
			area.set_script(InventorySlot)
			area.create_item(design[mount_name],false)
			if not try_to_mount(area,mount_name,true):
				area.queue_free()
		elif mount_name!='hull':
			printerr('ShipEditor: mount "',mount_name,'" does not exist.')
	$ShipInfo.process_command('ship info')
	ship_aabb = combined_aabb(ship)
	ship_aabb = ship_aabb.merge(combined_aabb($MountPoints))
	move_Camera_for_scene()
	return ship

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

func add_available_item(scene: PackedScene):
	# Adds the scene to the list of installable items.
	var area: Area = Area.new()
	area.set_script(InventorySlot)
	area.create_item(scene,true)
	area.collision_layer = AVAILABLE_ITEM_LAYER_MASK
	var width: float = max(2,area.nx+1)*0.25
	area.translation.z = width/2.0+used_width
	area.translation.x = (3.0-area.ny)/8.0
	used_width += width
#	area.name = item_name
	$Available.add_child(area)
	available_by_page[area.page]=area.get_path()

func add_available_design(design_name: String, design: Dictionary):
	# Adds a design to the list of ship designs.
	var icon: Spatial = Spatial.new()
	icon.set_script(HullIcon)
	icon.create_item(design)
	icon.set_collision_layer(AVAILABLE_HULL_LAYER_MASK)
	var width: float = abs(icon.width)
	icon.translation.z = width/2.0+used_width
	used_width += width
#	area.name = item_name
	$Available.add_child(icon)
	designs_by_name[design_name]=design

func move_Camera_for_scene():
	# Move the camera to fit the ship design, plus some space at the bottom
	# for the scrollbar and items.
	var size_x = clamp(abs(ship_aabb.size.x),8.0,18.0)
	size_x += 2.0 * 10.0/size_x
	$Camera.size = size_x
	var pos = ship_aabb.position + ship_aabb.size*0.5
	$Camera.translation.x = pos.x-1
	$Camera.translation.z = pos.z

func move_Available_for_scene():
	# Put the available items at the bottom left part of the screen.
	var scene_size = $Camera.size
	var middle_x = $Camera.translation.x
	var scale = 10.0/scene_size
	$Available.scale = Vector3(scale,scale,scale)
	$Available.translation.x = middle_x -scene_size/2.0 + 0.135*7*scale
	$Available.translation.z = -used_width/2.0

func place_in_multimount(content, mount_name: String, mount: Dictionary, use_item_offset: bool, console=null) -> bool:
	# Install a component (area) in the multimount in mounts[mount_name].
	# The location is based on the area location and item size.
	var inventory_array = get_node_or_null(mount['box'])
	if inventory_array==null:
		if console:
			console.append_raw_text('Inventory array missing for mount "',mount_name,'"')
		return false
	var ship_mount = $Ship.get_node_or_null(mount_name)
	if ship_mount==null:
		if console:
			console.append_raw_text('Missing ship mount "',mount_name,'"')
		return false
	var x_y = inventory_array.insert_at_grid_range(content,use_item_offset,console)
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
		if console:
			console.append_raw_text('installing item failed because Godot renamed node from '+cell_name+' to '+install.name)
		install.queue_free()
		return false
	return true

func place_in_single_mount(content, mount_name: String, mount: Dictionary, console=null) -> bool:
	# Install a component (content) in the mount in mounts[mount_name]
	if content.nx>mount['nx']:
		if console:
			console.append_raw_text('mount failed: x size too small (',content.nx,'>',mount['nx'],') in ',mount_name)
		return false
	if content.ny>mount['ny']:
		if console:
			console.append_raw_text('mount failed: y size too small (',content.ny,'>',mount['ny'],') in ',mount_name)
		return false
	var mount_content = get_node_or_null(mount['content'])
	if mount_content!=null:
		mount_content.queue_free()
	mounts[mount_name]['content'] = copy_to_installed(mount['name'],content,mount['box_translation'])
	mounts[mount_name]['scene'] = content.scene
	
	var make_visible = mount['mount_type']=='gun' or mount['mount_type']=='turret'
	
	var install = content.scene.instance()
	install.visible = make_visible
	install.transform = mount['transform']
	install.name = mount['name']
	install.mount_size_x = mount['nx']
	install.mount_size_y = mount['ny']
	var child = $Ship.get_node_or_null(mount['name'])
	if child!=null:
		child.replace_by(install)
	else:
		$Ship.add_child(install)
	set_layer_recursively(install,SHIP_LIGHT_CULL_LAYER)
	install.owner=$Ship
	install.name = mount['name']
	return true

func try_to_mount(content, mount_name: String, use_item_offset: bool, console=null):
	# Install the item (area) in the specified mount, which may be a single
	# or multimount.
	if not mounts.has(mount_name):
		if console:
			console.append_raw_text('mount failed: no mount '+mount_name)
		return false
	var mount: Dictionary = mounts[mount_name]
	if content.mount_type!=mount['mount_type']:
		if console:
			console.append_raw_text('mount failed: type "'+content.mount_type+'" does not match mount type "'+mount['mount_type']+'"')
		return false
	if not content.scene:
		if console:
			console.append_raw_text('mount failed: no scene in mount '+mount_name)
		return false
	
#	var content = InventoryContent.new()
#	content.fill_with(area)
	
	if mount['multimount']:
		if not place_in_multimount(content,mount_name,mount,use_item_offset,console):
			return false
	elif not place_in_single_mount(content,mount_name,mount,console):
		return false
	
	$ShipInfo.process_command('ship info')
	return true

func deselect(there: Dictionary):
	# If something is being dragged, try to install it if possible, and then
	# delete the dragging version.
	var area: Area = get_node_or_null('Selected')
	if area!=null:
		if there.has('collider'):
			var target: CollisionObject = there['collider']
			var mount_name: String = target.get_mount_name()
			var command: String = 'install '+mount_name+' '+area.page
			var mount = mounts[mount_name]
			if mount['multimount']:
				var inventory_array = get_node_or_null(mount['box'])
				var slot_xy = inventory_array.slot_xy_for(area.translation,area.nx,area.ny)
				command += ' '+str(slot_xy[0])+' '+str(slot_xy[1])
			$ConsolePanel.process_command(command)
#			var content: Reference = InventoryContent.new()
#			content.fill_with(area)
#			try_to_mount(content,target.get_mount_name(),false)
		area.queue_free()
	selected=false
	emit_signal('update_coloring',0,0,null,'')

func select_collider(pos: Vector2, collider: Area, help: bool = true) -> CollisionObject:
	# Given an item (collider) from a collision check at screen position pos,
	# start dragging that item.
	var dup: CollisionObject = collider.copy_only_item()
	var pos3: Vector3 = $Camera.project_position(pos,-10)
	dup.translation = Vector3(pos3.x,16,pos3.z)
	dup.name = 'Selected'
	add_child(dup)
	selected=true
	if help:
		$ConsolePanel.process_command('help '+dup.page)
	var item = collider.get_node_or_null('item')
	assert(item)
	emit_signal('update_coloring',item.mount_size_x,item.mount_size_y,pos3,
		item.mount_type)
	return dup

func select_multimount(pos: Vector2, there: Dictionary):
	# Start dragging something from a multimount. The pos is the screen position
	# and "there" is the result of a collision check.
	var collider = there.get('collider',null)
	if collider==null:
		return false
	
	var parent = collider.get_parent()
	if parent==null:
		printerr('Orphaned node found in select_multimount.')
		return false
	elif not parent.has_method('remove_child_or_null'):
		printerr('Multimount slot does not have a multimount parent.')
		return false
	
	var ship_mount = $Ship.get_node_or_null(parent.name)
	if ship_mount==null:
		printerr('Cannot find ship mount "',parent.name,'"')
		return false
	
	var pos3: Vector3 = $Camera.project_position(pos,-10)
	var xy = parent.slot_xy_for(pos3,1,1)
	var scene = parent.scene_at(xy[0],xy[1])
	$ConsolePanel.process_command('uninstall '+parent.name+' '+str(xy[0])+' '+str(xy[1]))
	
	var area: Area = Area.new()
	area.name='Selected'
	area.set_script(InventorySlot)
	area.create_item(scene,false)
	area.translation=pos3
	add_child(area)
	area.name='Selected'
	selected=true
	$ConsolePanel.process_command('help '+area.page)
	emit_signal('update_coloring',area.nx,area.ny,pos3,area.mount_type)
	return true

func unmount_all(multimount_name: String):
	var mount: Dictionary = mounts[multimount_name]
	if not mount['multimount']:
		unmount(multimount_name,0,0)
		return
	var parent = get_node_or_null(mount['box'])
	if parent==null:
		return
	var ship_mount = $Ship.get_node_or_null(parent.name)
	if ship_mount==null:
		printerr('Cannot find ship mount "',parent.name,'"')
		return
	var all = parent.all_children_xy()
	for sxy in all:
		var scene_x_y = parent.remove_child_or_null(sxy[1],sxy[2])
		var child_name = 'cell_'+str(scene_x_y[1])+'_'+str(scene_x_y[2])
		var old_child = ship_mount.get_node_or_null(child_name)
		if old_child==null:
			printerr('Cannot find unmounted item "',child_name,'" in ship. Will ignore this error.')
		else:
			ship_mount.remove_child(old_child) # make the node name available again
			old_child.queue_free()

func unmount(mount_name: String,x: int,y: int): # -> PackedScene or something that evaluates to false
	var mount: Dictionary = mounts[mount_name]
	if mount['multimount'] and (x<0 or y<0):
		unmount_all(mount_name)
	elif mount['multimount']:
		var parent = get_node_or_null(mount['box'])
		if parent==null:
			return null
		var ship_mount = $Ship.get_node_or_null(parent.name)
		if ship_mount==null:
			printerr('Cannot find ship mount "',parent.name,'"')
			return null
		var scene_x_y = parent.remove_child_or_null(x,y)
		var scene = scene_x_y[0]
		if not scene:
			return null
		var child_name = 'cell_'+str(scene_x_y[1])+'_'+str(scene_x_y[2])
		var old_child = ship_mount.get_node_or_null(child_name)
		if old_child==null:
			printerr('Cannot find unmounted item "',child_name,'" in ship. Will ignore this error.')
		else:
			ship_mount.remove_child(old_child) # make the node name available again
			old_child.queue_free()
		return scene
	else:
		var child = $Ship.get_node_or_null(mount_name)
		if child!=null:
			$Ship.remove_child(child)
			child.queue_free()
		child = $Installed.get_node_or_null(mount_name)
		if child!=null:
			$Installed.remove_child(child)
			child.queue_free()
		mounts[mount_name]['content'] = NodePath()
		var scene = mounts[mount_name]['scene']
		mounts[mount_name]['scene'] = ''
		return scene

func select_installed(pos: Vector2, there: Dictionary):
	# Pull something off of the single mount at screen position pos, identified
	# by the collision check information in "there"
	if there.empty():
		return false
	var collider = there['collider']
	if there!=null:
		var new = select_collider(pos,collider,false)
		
		# Unmount the item from the ship
		var path = collider.get_path()
		for mount_name in mounts:
			var mount: Dictionary = mounts[mount_name]
			if mount['content'] == path:
				$ConsolePanel.process_command('uninstall '+mount_name)
#				unmount(mount_name,0,0)

		# Unmount the item from $Installed
#		$Installed.remove_child(collider)
#		collider.queue_free()
		
		$ConsolePanel.process_command('help '+new.page)
		$ShipInfo.process_command('ship info')
		return true
	return false

func select_available(pos: Vector2, there: Dictionary):
	# Start dragging the item at screen position "pos" identified by the 
	# collision check information in "there"
	if there.empty():
		return false
	var collider = there['collider']
	if collider!=null:
		var _discard = select_collider(pos,collider)
		return true
	return false

func load_design(design: Dictionary):
	for child in $Installed.get_children():
		child.queue_free()
	for child in $MountPoints.get_children():
		child.queue_free()
	mounts={}
	$Ship.queue_free()
	yield(get_tree(),'idle_frame')
	make_ship(design)
	move_Available_for_scene()

func select_hull(_pos: Vector2, there: Dictionary):
	# Switch to the hull identified by the collision check information "there"
	var collider = there.get('collider',null)
	if collider==null:
		return false
	var parent = collider.get_parent()
	load_design(parent.design)
	return true

func event_position(event: InputEvent):
	# Get the best guess of the mouse position for the event.
	if event is InputEventMouseButton:
		return event.position
	return get_viewport().get_mouse_position()

func at_position(pos,mask: int) -> Dictionary:
	# Helper function to do an intersect_ray at a particular screen location.
	if pos==null:
		return {}
	var space: PhysicsDirectSpaceState = get_viewport().world.direct_space_state
	var from = $Camera.project_ray_origin(pos)
	from.y = $Camera.translation.y+500
	var to = from + $Camera.project_ray_normal(pos)
	to.y = $Camera.translation.y-500
	return space.intersect_ray(from,to,[],mask,true,true)

func _unhandled_input(event: InputEvent):
	if event.is_action_released('ui_location_select'):
		old_collider_path=NodePath()
		if selected:
			var there = at_position(event_position(event),36)
			deselect(there)
		return
	elif event.is_action_pressed('ui_location_select'):
		old_collider_path=NodePath()
		var pos = event_position(event)
		if pos!=null:
			var found = \
				select_available(pos,at_position(pos,AVAILABLE_ITEM_LAYER_MASK)) \
				or select_installed(pos,at_position(pos,INSTALLED_LAYER_MASK)) \
				or select_multimount(pos,at_position(pos,InventoryArray.my_collision_mask))
			if not found:
				found = select_hull(pos,at_position(pos,AVAILABLE_HULL_LAYER_MASK))
				while found is GDScriptFunctionState and found.is_valid():
					found=yield(found,'completed')
		return
	elif event.is_action_released('ui_cancel'):
		exit_scene()
		return
	elif selected:
		var n = get_node_or_null('Selected')
		if n!=null:
			var pos2 = event_position(event)
			if pos2!=null:
				var pos3 = $Camera.project_position(pos2,-10)
				n.translation = Vector3(pos3.x,16,pos3.z)
				
				var space: PhysicsDirectSpaceState = get_viewport().world.direct_space_state
				var there: Dictionary = space.intersect_ray(
					Vector3(pos3.x,-500,pos3.z),Vector3(pos3.x,500,pos3.z),[],36,false,true)
				var collider = there.get('collider',null)
				var path = collider.get_path() if collider!=null else NodePath()
				if path!=old_collider_path:
					emit_signal('update_coloring',n.nx,n.ny,pos3,n.mount_type)
				elif collider:
					collider.update_coloring(n.nx,n.ny,pos3,n.mount_type)
				old_collider_path=path
	if event.is_action_released('wheel_up'):
		$HScrollBar.value-=0.5
	elif event.is_action_released('wheel_down'):
		$HScrollBar.value+=0.5

func exit_scene():
	game_state.player_ship_design = make_design()
	print(string_design(game_state.player_ship_design))
	var _discard = get_tree().change_scene('res://ui/OrbitalScreen.tscn')

func string_design(design: Dictionary) -> String:
	var s = '\t\t{\n'
	for key in design:
		var value = design[key]
		if value is Array:
			s += '\t\t\t"'+key+'": [\n'
			for item in value:
				s += '\t\t\t\t[ '+str(item[0])+', '+str(item[1])+', '+str(item[2])+' ],\n'
			s += '\t\t\t]\n'
		else:
			s += '\t\t\t"'+key+'": preload("'+value.resource_path+'"),\n'
	return s + '\t\t},\n'

func make_design() -> Dictionary:
	var design: Dictionary = {'hull':hull_scene}
	for mount_name in mounts:
		var mount = mounts[mount_name]
		if mount['multimount']:
			var node = get_node_or_null(mount['box'])
			if node==null:
				printerr('null node for mount ',mount_name,' path ',str(mount['box']))
			design[mount_name] = node.content_for_design()
		elif mount['scene']:
			design[mount_name] = mount['scene']
	return design

func force_child_size(c: Control,size: Vector2,pos: Vector2):
	c.anchor_left=0
	c.anchor_right=0
	c.anchor_top=0
	c.anchor_bottom=0
	
	c.margin_left=0
	c.margin_right=0
	c.margin_top=0
	c.margin_bottom=0
	
	c.size_flags_horizontal=0
	c.size_flags_vertical=0
	
	c.rect_global_position=pos
	c.rect_size=size

func child_fills_parent(c: Control):
	c.anchor_left=0
	c.anchor_right=1
	c.anchor_top=0
	c.anchor_bottom=1
	
	c.margin_left=0
	c.margin_right=0
	c.margin_top=0
	c.margin_bottom=0
	
	c.size_flags_horizontal=Control.SIZE_FILL|Control.SIZE_EXPAND
	c.size_flags_vertical=Control.SIZE_FILL|Control.SIZE_EXPAND

func usage_install(console,argv:PoolStringArray):
	console.append(argv[0]+': install items in a ship. Syntax:')
	console.append('\t[code]'+argv[0]+' install MountName item/path [/code]    = Mount an item')
	console.append('\t[code]'+argv[0]+' install MountName item/path x y[/code] = at location x,y')

func usage_design(console,argv:PoolStringArray):
	console.append(argv[0]+': load a different ship design. Syntax:')
	console.append('\t[code]'+argv[0]+' design load design_name [/code]')

func usage_ship(console,argv:PoolStringArray):
	console.append(argv[0]+': display ship info. Syntax:')
	console.append('\t[code]'+argv[0]+' info[/code]    = Show ship info on other panel')
	console.append('\t[code]'+argv[0]+' dump[/code]    = Dump JSON-encoded ship info')

func usage_list(console,argv:PoolStringArray):
	console.append(argv[0]+': list known mount points, items, or designs. Syntax:')
	console.append('\t[code]'+argv[0]+' mounts[/code]  = mount points on this ship')
	console.append('\t[code]'+argv[0]+' items[/code]   = guns, turrets, engines, equipment')
	console.append('\t[code]'+argv[0]+' designs[/code] = list ship designs')

func run(console,argv:PoolStringArray):
	# Entry point for console commands.
	if argv[0]=='ship':
		if len(argv)!=2:
			usage_ship(console,argv)
		elif argv[1]=='info' and $Ship.has_method('get_bbcode'):
			$Ship.repack_stats()
			console.insert_bbcode(console.rewrite_tags($Ship.get_bbcode()))
		elif argv[1]=='dump':
			console.append_raw_text(string_design(make_design()))
		else:
			usage_ship(console,argv)
	elif argv[0]=='exit':
		exit_scene()
	elif argv[0]=='design':
		if len(argv)==3 and argv[1]=='load':
			var design = designs_by_name.get(argv[2],null)
			if not design:
				return console.append_raw_text('error: no design named "'+design+'". Try "list designs"')
			load_design(design)
		else:
			usage_design(console,argv)
	elif argv[0]=='uninstall':
		if len(argv)==2 or len(argv)==4:
			var mount=mounts.get(argv[1],null)
			if not mount:
				return console.append('Error: there is no mount named "'+argv[1]+'". Try "list mounts"')
			if len(argv)==4:
				unmount(argv[1],convert(argv[2],TYPE_INT),convert(argv[3],TYPE_INT))
			else:
				unmount(argv[1],-1,-1)
	elif argv[0]=='install':
		if len(argv)==3 or len(argv)==5:
			var mount = mounts.get(argv[1],null)
			if not mount:
				return console.append('Error: there is no mount named "'+argv[1]+'". Try "list mounts"')
			var path = available_by_page.get(argv[2],NodePath())
			var node = get_node_or_null(path)
			if not node:
				return console.append('Error: there is no item named "'+argv[2]+'". Try "list items"')
			var content = InventoryContent.new()
			content.fill_with(node)
			if len(argv)==5:
				content.my_x = convert(argv[3],TYPE_INT)
				content.my_y = convert(argv[4],TYPE_INT)
				console.append_raw_text(str(content.my_x)+' '+str(content.my_y))
				assert(content.my_x>=0 and content.my_y>=0)
				try_to_mount(content,argv[1],true,console)
			elif mount['multimount']:
				return console.append('Error: you must specify a location for this mount')
			else:
				try_to_mount(content,argv[1],false,console)
		else:
			usage_install(console,argv)
	elif argv[0]=='list':
		if len(argv)!=2:
			usage_list(console,argv)
		elif argv[1]=='mounts':
			console.append('Mount points on this ship:\n[table=5]',false)
			var names = mounts.keys()
			names.sort()
			for mount_name in names:
				var mount: Dictionary = mounts[mount_name]
				console.append('[cell]%s[/cell][cell]%d[/cell][cell]x[/cell][cell]%d[/cell][cell]%s[/cell]'%[
					mount_name, mount['nx'],mount['ny'],mount['mount_type']],false)
			console.append('[/table]')
			console.append('[i]--[/i]') # Godot bug workaround: this line is discarded to end the table.
		elif argv[1]=='items':
			console.append('All available items:\n[table=5]',false)
			var pages = available_by_page.keys()
			pages.sort()
			for page in pages:
				var node = get_node_or_null(available_by_page[page])
				if node!=null:
					console.append('[cell][ref=%s]%s[/ref][/cell][cell]%d[/cell][cell]x[/cell][cell]%2d[/cell][cell]%s[/cell]'%[
						page,page,node.nx,node.ny,node.mount_type],false)
			console.append('[/table]')
			console.append('[i]--[/i]') # Godot bug workaround: this line is discarded to end the table.
		elif argv[1]=='designs':
			console.append('All available ship designs:')
			var names = designs_by_name.keys()
			names.sort()
			for name in names:
				console.append_raw_text('\t'+name)
#				var design: Dictionary = designs_by_name[name]
#				if not design.has('hull'):
#					continue
#				var hull = design['hull'].instance()
#				if not hull:
#					continue
#				var weapon_space=0
#				var engine_space=0
#				var equipment_space=0
#				for child in hull.get_children():
#					if not child.has_method('is_mount_point'):
#						continue
#					if child.mount_type=='gun' or child.mount_type=='turret':
#						weapon_space += 
#				console.append('\t[ref=%s]%s[/ref] 
		else:
			usage_list(console,argv)

func _ready():
	for command in [ 'ship','list','exit','design','install','uninstall' ]:
		$ConsolePanel.add_command(command,self)
	$ShipInfo/Console/Output.scroll_following=false
	$ShipInfo.add_command('ship',self)
	$Red.layers = RED_LIGHT_CULL_LAYER
	$Red.light_cull_mask = RED_LIGHT_CULL_LAYER
	$SpaceBackground.center_view(130,90,0,120,0)
	make_ship(game_state.player_ship_design)
#	ship_aabb = combined_aabb(make_ship(game_state.player_ship_design))
#	ship_aabb = ship_aabb.merge(combined_aabb($MountPoints))
#	move_Camera_for_scene()
	var _discard
	for avail in available_items:
		_discard=add_available_item(avail)
	for design_name in allowed_designs:
		if game_state.ship_designs.has(design_name):
			_discard=add_available_design(design_name,game_state.ship_designs[design_name])
	move_Available_for_scene()

func _process(_delta):
	var view_size: Vector2 = get_viewport().get_size()
	var pos3_ul: Vector3 = $Camera.project_position(Vector2(0,0),-10)
	var pos3_lr: Vector3 = $Camera.project_position(view_size,-10)
	$Camera.translation.z = abs(pos3_ul.z-pos3_lr.z)/6
	$ShipInfo.rect_global_position=Vector2(view_size.x*2.0/3.0,0)
	$ShipInfo.rect_size=Vector2(view_size.x/3.0,view_size.y*0.4)
	$ConsolePanel.rect_global_position=Vector2(view_size.x*2.0/3,view_size.y*0.4)
	$ConsolePanel.rect_size=Vector2(view_size.x/3.0,view_size.y*0.6)
	$HScrollBar.rect_global_position=Vector2(0,view_size.y-12)
	$HScrollBar.rect_size=Vector2(view_size.x*2.0/3.0,12)
	var left3: Vector3 = $Camera.project_position(Vector2(0,view_size.y-12),-10)
	var right3: Vector3 = $Camera.project_position(Vector2(view_size.x*2.0/3.0,view_size.y-12),-10)
	var scroll_max: float = max(0,used_width)
	page_size = min(abs(right3.z-left3.z),scroll_max)
	scroll_active = scroll_max>0 and page_size<scroll_max
	$HScrollBar.visible=scroll_active
	if scroll_active:
		if $HScrollBar.max_value != scroll_max:
			$HScrollBar.max_value=scroll_max
		if $HScrollBar.page!=page_size:
			$HScrollBar.page=page_size

func _on_HScrollBar_changed():
	_on_HScrollBar_value_changed($HScrollBar.value)

func _on_HScrollBar_value_changed(value):
	if scroll_active:
		$Available.translation.z=-page_size/2-value
