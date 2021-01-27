extends ViewportContainer

const InventoryArray: Script = preload('res://ui/ships/InventoryArray.gd')
const InventoryContent: Script = preload('res://ui/ships/InventoryContent.gd')
const InventorySlot: Script = preload('res://ui/ships/InventorySlot.gd')

const SHIP_LAYER_MASK: int = 1
const INSTALLED_LAYER_MASK: int = 2
const MOUNT_POINT_LAYER_MASK: int = 4

const ITEM_LIGHT_CULL_LAYER: int = 1
const SHIP_LIGHT_CULL_LAYER: int = 2
const RED_LIGHT_CULL_LAYER: int = 8

signal update_coloring

var ship_aabb: AABB
var root: simple_tree.SimpleNode
var mounts: simple_tree.SimpleNode
var tree: simple_tree.SimpleTree

class MountData extends simple_tree.SimpleNode:
	var nx: int
	var ny: int
	var mount_type: String
	var transform: Transform
	var box: NodePath
	var box_translation: Vector3
	var multimount: bool
	var content: NodePath = NodePath()
	var scene: PackedScene # Note: not initialized
	
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
			print('make multimount at '+child.name)
			mp = ship_design_view.multimount_point(nx,ny,loc,child.mount_type,child.name)
		else:
			mp = ship_design_view.mount_point(nx,ny,loc,child.name,child.mount_type)
		box_translation = mp.translation
		box = mp.get_path()

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
	box.place_near(loc,$Viewport.world.direct_space_state, \
		MOUNT_POINT_LAYER_MASK | SHIP_LAYER_MASK)
	box.translation.y = loc.y
	box.name=box_name
	box.collision_layer = MOUNT_POINT_LAYER_MASK
	var _discard=connect('update_coloring',box,'update_coloring')
	$Viewport/MountPoints.add_child(box)
	return box

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
		print('no x_y insert at grid range for '+mount.get_name())
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

func make_ship(design):
	clear_ship()
	
	var encoded = game_state.universe.encode_helper(design)
	var decoded = game_state.universe.decode_helper(encoded)
	decoded.set_name('Ship')
	var _discard = root.add_child(decoded)

	#var ship = decoded.assemble_ship(false)
	var ship = design.hull.instance()
	ship.name='Ship'
	ship.collision_layer = SHIP_LAYER_MASK
	ship.collision_mask = 0
	ship.random_height = false
	ship.retain_hidden_mounts = true
	
	set_layer_recursively(ship,SHIP_LIGHT_CULL_LAYER)
	var existing = $Viewport.get_node_or_null('Ship')
	if existing:
		$Viewport.remove_child(existing)
		existing.queue_free()
	ship.pack_stats(true)
	$Viewport.add_child(ship)
	ship.name = 'Ship'
	
	for child in sorted_ship_children(ship):
		if child.get('mount_type')!=null:
			_discard = mounts.add_child(MountData.new(child,self))

	for mount_name in design.get_child_names():
		var mount = design.get_child_with_name(mount_name)
		if mount and mounts.has_child(mount_name):
			if mount.has_method('is_MultiMount'):
				add_multimount_contents(mount_name,design)
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
	var contents: simple_tree.SimpleNode = design.get_node_or_null(mount_name)
	if not contents:
		print('no node for multimount '+mount_name)
		return
	var seen = false
	for item in contents.get_children():
		if not item.has_method('is_MultiMounted'):
			print('not multimounted')
			continue
		var scene: PackedScene = item.scene
		assert(scene)
		var area: Area = Area.new()
		area.set_script(InventorySlot)
		area.create_item(scene,false,Vector2(item.x, item.y))
		area.my_x = item.x
		area.my_y = item.y
		if not try_to_mount(area,mount_name,true):
			print('failed to mount')
			area.queue_free()
		seen = true
	if not seen:
		print('no contents in '+mount_name)
	
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
		print('content has no scene '+mount_name)
		return false
	
	if mount.multimount:
		print('place in multimount')
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
	$Viewport/SpaceBackground.update_from(game_state.system)
	$Viewport/Red.layers = RED_LIGHT_CULL_LAYER
	$Viewport/Red.light_cull_mask = RED_LIGHT_CULL_LAYER
	$Viewport/SpaceBackground.center_view(130,90,0,120,0)
	make_ship(game_state.player_ship_design)

func _on_ViewportContainer_resized():
	$Viewport.size = rect_size
