extends Spatial

var design_path: NodePath
var page: String = 'weapons'
var item_aabb: AABB
var item_collision_layer: int = 0
var width: float = 1

const x_axis: Vector3 = Vector3(1,0,0)
const y_axis: Vector3 = Vector3(0,1,0)

func copy_only_item() -> Area:
	var new: Area = Area.new()
	new.set_script(get_script())
	new.create_item(game_state.ship_designs.get_node(design_path))
	return new

func combined_aabb(node: Node):
	var result: AABB = AABB()
	if node is VisualInstance:
		result = node.get_aabb()
	for child in node.get_children():
		result=result.merge(combined_aabb(child))
	if node is Spatial:
		result = node.transform.xform(result)
	return result

func set_collision_layer(layer: int):
	item_collision_layer = layer
	var item = get_node_or_null('item')
	if item!=null:
		item.collision_layer = item_collision_layer

func create_item(design: simple_tree.SimpleNode):
	design_path = design.get_path()
	
	var item: RigidBody = design.assemble_ship()
	page=item.help_page
	item.random_height = false
	item_aabb=combined_aabb(item)
	item.collision_mask = 0
	item.collision_layer = item_collision_layer
	item.name='item'
	item.transform = Transform()
	var scale: float = 1.0/clamp(item_aabb.size.x,1.0,15.0)
	item.scale = Vector3(scale,scale,scale)
	width = item_aabb.size.z*scale
	add_child(item)
