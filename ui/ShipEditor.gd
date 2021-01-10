extends Spatial

const InventorySlot: Script = preload('res://ui/InventorySlot.gd')
const InventoryArray: Script = preload('res://ui/InventoryArray.gd')
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
const RED_LIGHT_CULL_LAYER: int = 8

signal update_coloring

func multimount_point(width: int,height: int,loc: Vector3,mount_type: String,box_name: String) -> Spatial:
	# Create an area that allows multiple non-overlapping items to be mounted
	var box: Spatial = Spatial.new()
	box.set_script(InventoryArray)
	box.create(width,height,mount_type)
	# Note: equipment box is not displaced, unlike regular mounts.
	box.translation = loc
	box.name=box_name
	var _discard=connect('update_coloring',box,'update_coloring')
	$MountPoints.add_child(box)
	return box

func mount_point(width: int,height: int,loc: Vector3,box_name: String) -> Area:
	# Create an area that allows only one item to be mounted
	var box: Area = Area.new()
	box.set_script(InventorySlot)
	box.create_only_box(width,height)
	box.place_near(loc,get_viewport().world.direct_space_state, \
		MOUNT_POINT_LAYER_MASK | SHIP_LAYER_MASK)
	box.name=box_name
	box.collision_layer = MOUNT_POINT_LAYER_MASK
	var _discard=connect('update_coloring',box,'update_coloring')
	$MountPoints.add_child(box)
	return box

func copy_to_installed(installed_name: String,child: Node,display_location: Vector3) -> NodePath:
	var area = child.copy_only_item()
	area.collision_layer = INSTALLED_LAYER_MASK
	area.translation = Vector3(display_location.x,13,display_location.z)
	area.name = installed_name
	$Installed.add_child(area)
	area.name = installed_name
	return area.get_path()

class CompareMountLocations:
	static func cmp(a: Spatial,b: Spatial) -> bool:
		# Sort function to beautify the locations of mount points on the screen.
		if sign(a.translation.z)<sign(b.translation.z):
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
	for x_y_scene in contents:
		var scene: PackedScene = contents[2]
		var area: Area = Area.new()
		area.set_script(InventorySlot)
		area.create_item(scene,false,Vector2(contents[0],contents[1]))
		if not try_to_mount(area,mount_name):
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
			var loc: Vector3 = Vector3(child.translation.x,10,child.translation.z)
			var nx: int = child.mount_size_x
			var ny: int = child.mount_size_y
			var multimount: bool = child.mount_type=='equipment'
			var mp
			if multimount:
				mp = multimount_point(nx,ny,loc,child.mount_type,child.name)
			else:
				mp = mount_point(nx,ny,loc,child.name)
			mounts[child.name]={'name':child.name, 'transform':child.transform, 
				'mount_type':child.mount_type,'scene':'','content':NodePath(),
				'box':mp.get_path(),'nx':nx,'ny':ny,'box_translation':mp.translation,
				'multimount':multimount,
			}
	for mount_name in design:
		if mounts.has(mount_name):
			if mounts[mount_name]['multimount']:
				add_multimount_contents(mount_name,ship)
				continue
			var area: Area = Area.new()
			area.set_script(InventorySlot)
			area.create_item(design[mount_name],false)
			if not try_to_mount(area,mount_name):
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

func add_available_design(design: Dictionary):
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

func place_in_multimount(area: Area, mount_name: String, mount: Dictionary) -> bool:
	# Install a component (area) in the multimount in mounts[mount_name].
	# The location is based on the area location and item size.
	var inventory_array = get_node_or_null(mount['box'])
	if inventory_array==null:
		printerr('Inventory array missing for mount "',mount_name,'"')
		return false
	return inventory_array.insert_at_grid_range(area,area.scene)

func place_in_single_mount(area: Area, mount_name: String, mount: Dictionary) -> bool:
	# Install a component (area) in the mount in mounts[mount_name]
	if area.nx>mount['nx']:
		printerr('mount failed: x size too small (',area.nx,'>',mount['nx'],') in ',mount_name)
		return false
	if area.ny>mount['ny']:
		printerr('mount failed: y size too small (',area.ny,'>',mount['ny'],') in ',mount_name)
		return false
	var content = get_node_or_null(mount['content'])
	if content!=null:
		content.queue_free()
	mounts[mount_name]['content'] = copy_to_installed(mount['name'],area,mount['box_translation'])
	mounts[mount_name]['scene'] = area.scene
	
	if mount['mount_type']!='gun' and mount['mount_type']!='turret':
		return false
	
	var install = area.scene.instance()
	install.transform = mount['transform']
	install.name = mount['name']
	install.mount_size_x = mount['nx']
	install.mount_size_y = mount['ny']
	var child = $Ship.get_node_or_null(mount['name'])
	if child!=null:
		child.replace_by(install)
	else:
		$Ship.add_child(install)
	install.owner=$Ship
	install.name = mount['name']
	return true

func try_to_mount(area: Area, mount_name: String):
	# Install the item (area) in the specified mount, which may be a single
	# or multimount.
	if not mounts.has(mount_name):
		printerr('mount failed: no mount ',mount_name)
		return false
	var mount: Dictionary = mounts[mount_name]
	if area.mount_type!=mount['mount_type']:
		printerr('mount failed: type ',area.mount_type,' does not match mount type ',mount['mount_type'])
		return false
	if not area.scene:
		printerr('mount failed: no scene in mount ',mount_name)
		return false
	
	if mount['multimount']:
		if not place_in_multimount(area,mount_name,mount):
			return false
	elif not place_in_single_mount(area,mount_name,mount):
		return false
	
	update_ship_info()
	return true

func deselect(there: Dictionary):
	# If something is being dragged, try to install it if possible, and then
	# delete the dragging version.
	var area: Area = get_node_or_null('Selected')
	if area!=null:
		if there.has('collider'):
			var target: CollisionObject = there['collider']
			try_to_mount(area,target.get_mount_name())
		area.queue_free()
	selected=false
	emit_signal('update_coloring',0,0,null,'')

func update_ship_info():
	$ShipInfo.process_command('ship info')

#func update_coloring(nx: int,ny: int,type: String):
#	for mount_info in mounts.values():
#		var box_area = get_node_or_null(mount_info['box'])
#		if box_area==null:
#			continue
#		if type and (type != mount_info['mount_type'] or nx>mount_info['nx'] or ny>mount_info['ny']):
#			for child in box_area.get_children():
#				if child is VisualInstance:
#					child.layers = child.layers | RED_LIGHT_CULL_LAYER
#		else:
#			for child in box_area.get_children():
#				if child is VisualInstance:
#					child.layers = child.layers & ~RED_LIGHT_CULL_LAYER

func select_collider(pos: Vector2, collider: Area):
	# Given an item (collider) from a collision check at screen position pos,
	# start dragging that item.
	var dup: CollisionObject = collider.copy_only_item()
	var pos3: Vector3 = $Camera.project_position(pos,-10)
	dup.translation = Vector3(pos3.x,16,pos3.z)
	dup.name = 'Selected'
	add_child(dup)
	selected=true
	$ConsolePanel.process_command('help '+dup.page)
	var item = collider.get_node_or_null('item')
	emit_signal('update_coloring',item.mount_size_x,item.mount_size_y,pos3,
		'' if item==null else item.mount_type)

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
	
	var pos3: Vector3 = $Camera.project_position(pos,-10)
	var scene = parent.remove_child_or_null(pos3)
	if scene==null:
		return false
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

func select_installed(pos: Vector2, there: Dictionary):
	# Pull something off of the single mount at screen position pos, identified
	# by the collision check information in "there"
	if there.empty():
		return false
	var collider = there['collider']
	if there!=null:
		select_collider(pos,collider)
		
		# Unmount the item from the ship
		var path = collider.get_path()
		for mount_name in mounts:
			var mount: Dictionary = mounts[mount_name]
			if mount['content'] == path:
				var child = $Ship.get_node_or_null(mount_name)
				if child!=null:
					$Ship.remove_child(child)
					child.queue_free()
				mount['scene'] = ''
				mount['content'] = NodePath()

		# Unmount the item from $Installed
		$Installed.remove_child(collider)
		collider.queue_free()
		
		update_ship_info()
		return true
	return false

func select_available(pos: Vector2, there: Dictionary):
	# Start dragging the item at screen position "pos" identified by the 
	# collision check information in "there"
	if there.empty():
		return false
	var collider = there['collider']
	if collider!=null:
		select_collider(pos,collider)
		return true
	return false

func select_hull(_pos: Vector2, there: Dictionary):
	# Switch to the hull identified by the collision check information "there"
	var collider = there['collider']
	var parent = collider.get_parent()
	var design = parent.design
	for child in $Installed.get_children():
		child.queue_free()
	for child in $MountPoints.get_children():
		child.queue_free()
	mounts={}
	$Ship.queue_free()
	yield(get_tree(),'idle_frame')
	make_ship(design)
	move_Available_for_scene()
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

func _input(event: InputEvent):
	if event.is_action_released('ui_location_select'):
		if selected:
			var there = at_position(event_position(event),36)
			deselect(there)
	elif event.is_action_pressed('ui_location_select'):
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
	elif event.is_action_released('ui_cancel'):
		game_state.player_ship_design = make_design()
		print(string_design(game_state.player_ship_design))
		var _discard = get_tree().change_scene('res://ui/OrbitalScreen.tscn')
	elif selected:
		var n = get_node_or_null('Selected')
		if n!=null:
			var pos2 = event_position(event)
			if pos2!=null:
				var pos3 = $Camera.project_position(pos2,-10)
				n.translation = Vector3(pos3.x,16,pos3.z)
				var space: PhysicsDirectSpaceState = get_viewport().world.direct_space_state
				var there: Dictionary = space.intersect_ray(
					pos3+Vector3(0,500,0),pos3-Vector3(0,500,0),[],36,true,true)
				var collider = there.get('collider',null)
				var path = collider.get_path() if collider!=null else NodePath()
				if path!=old_collider_path:
					emit_signal('update_coloring',n.nx,n.ny,pos3,n.mount_type)
				else:
					collider.update_coloring(n.nx,n.ny,pos3,n.mount_type)
				old_collider_path=path

func string_design(design: Dictionary) -> String:
	var s = '\t\t{\n'
	for key in design:
		s += '\t\t\t"'+key+'": preload("'+design[key].resource_path+'"),\n'
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

func run(console,argv:PoolStringArray):
	# Entry point for console commands.
	if argv[0]=='ship' and len(argv)>1:
		if argv[1]=='info' and $Ship.has_method('get_bbcode'):
			$Ship.repack_stats()
			console.insert_bbcode(console.rewrite_tags($Ship.get_bbcode()))
		if argv[1]=='dump':
			console.append_raw_text(string_design(make_design()))

func _ready():
	$ConsolePanel.add_command('ship',self)
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
			_discard=add_available_design(game_state.ship_designs[design_name])
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
