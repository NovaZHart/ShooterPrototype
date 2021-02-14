extends Node

func Tree_depth_first(item: TreeItem,object: Object,method: String):
	var scan = item.get_children()
	while scan:
		if object.call(method,item,scan):
			return true
		scan = scan.get_next()

func Tree_remove_subtree(parent: TreeItem,child: TreeItem):
	Tree_depth_first(child,self,'_remove_tree_item')
	_TreeItem_remove_child(parent,child)

func Tree_clear(tree: Tree):
	var root = tree.get_root()
	Tree_depth_first(root,self,'_remove_tree_item')
	tree.clear()
	root.free()

func _TreeItem_remove_child(parent: TreeItem,child: TreeItem):
	parent.remove_child(child)
	child.free()

func TreeItem_child_count_at_least(item: TreeItem,min_children: int):
	var count = 0
	var scan = item.get_children()
	while scan:
		count += 1
		if count >= min_children:
			return true
		scan = scan.get_next()
	return false

func ship_max_speed(ship_stats,mass=null) -> float:
	if mass==null:
		mass = ship_stats.get('mass',null)
	if mass==null:
		mass = ship_mass(ship_stats)
	var max_thrust = max(max(ship_stats['reverse_thrust'],ship_stats['thrust']),0)
	return max_thrust/max(1e-9,ship_stats['drag']*mass)

func ship_mass(ship_stats):
	return ship_stats['empty_mass']+ship_stats.get('cargo_mass',0)+ \
		ship_stats['max_fuel']*ship_stats['fuel_density']/1000.0+ \
		ship_stats['max_armor']*ship_stats['armor_density']/1000.0
