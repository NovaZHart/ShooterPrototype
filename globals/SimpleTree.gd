extends Node

class NoRef:
	func get_ref():
		return null

class SimpleNode extends Reference:
	var name_: String
	var name=null setget set_name, get_name
	var parent_ = NoRef.new()
	
	var tree_ = NoRef.new()
	var children_: Dictionary = {}
	var path_array_ = null
	var node_path_ = null
	var path_string_ = null
	var is_root_ = false
	var called_ready_ = false

	func is_SimpleNode(): pass # for type checking; never called

	func is_root():
		return is_root_

	func get_child_count() -> int:
		return len(children_)
	
	func has_children() -> bool:
		return len(children_)>0

	func has_child(id) -> bool:
		return children_.has(id)
	
	func _impl_ready(force: bool=false):
		for child_name in children_:
			var child = children_.get(child_name,null)
			if child:
				child._impl_ready(force)
		if (force or not called_ready_) and has_method('_ready'):
			call('_ready',[])
		called_ready_ = true

	func set_name(n: String):
		var p = parent_.get_ref()
		if p:
			p.set_child_name(self,n)
		else:
			name_=n

	func get_name() -> String:
		return name_

	func set_tree(tree):
		tree_=tree
		called_ready_=false
		for child in children_.values():
			child.set_tree(tree)

	func set_child_name(child: SimpleNode,new_name: String):
		var old_name = child.name_
		if old_name==new_name:
			return
		var has_name = children_.get(new_name,null)
		if not has_name:
			var _discard = children_.erase(old_name)
			child.name_=new_name
			children_[new_name]=child

	func unparent():
		var p = parent_.get_ref()
		if p:
			p.remove_child(self)
		parent_ = NoRef.new()
		set_tree(NoRef.new())

	func make_root_of(tree: WeakRef):
		unparent()
		is_root_ = true
		set_tree(tree)
		path_array_ = null
		node_path_ = null
		path_string_ = null

	func set_parent(parent: WeakRef):
		unparent()
		parent_=parent
		var p = parent.get_ref()
		if p:
			set_tree(p.tree_)
			is_root_=false
		path_array_ = null
		node_path_ = null
		path_string_ = null

	func get_tree():
		return tree_.get_ref()

	func clear_parent_():
		parent_ = NoRef.new()
		set_tree(NoRef.new())

	func get_parent():
		var p = parent_.get_ref()
#		if not p:
#			# This is not really an error. Uncomment for debugging.
#			push_error('tried to get parent of orphaned node')
		return p

	func get_child_names():
		return children_.keys()
	
	func get_child_with_name(child_name: String):
		return children_.get(child_name,null)

	func get_children():
		return children_.values()

	func queue_free():
		var parent_node = parent_.get_ref()
		if parent_node:
			parent_node.remove_child(self)
		for child in children_.values():
			child.queue_free()

	func remove_all_children() -> bool:
		var names = children_.keys()
		if not names:
			return false
		for child_name in names:
			var child = children_.get(child_name,null)
			if child:
				child.clear_parent_()
			var _discard = children_.erase(child_name)
		return true

	func remove_child(child: SimpleNode) -> bool:
		var child_name = child.name_
		var child_parent = child.get_parent()
		if child_parent and child_parent==self:
			child.clear_parent_()
			return children_.erase(child_name)
		return false

	func remove_child_with_name(child_name: String) -> bool:
		var child = children_.get(child_name,null)
		if child:
			child.clear_parent_()
			return children_.erase(child_name)
		return false

	func make_child_name(base: String) -> String:
		if not base in children_:
			return base
		for _x in range(100):
			var check: String = ( '%s@%08x' % [ base, randi()%4294967296 ] )
			if not check in children_:
				return check
		var last_resort: String = '%s@%x'%[base,randi()] # hope for the best
		return last_resort

	func add_child(child: SimpleNode, child_name = null) -> bool:
		if child.parent_.get_ref():
			push_error('child already has a parent: '+str(child))
			return false
		if child_name==null:
			child_name=child.get_name()
		if not child_name or not child_name is String:
			push_error('tried to add a child with no name: '+str(child))
			return false
		var _discard = remove_child_with_name(child_name)
		child.name_=child_name
		child.set_parent(weakref(self))
		children_[child_name]=child
		return true

	func is_orphan() -> bool:
		return not parent_.get_ref()

	func get_path_array() -> Array:
		if path_array_==null:
			if not tree_.get_ref():
				push_error('Tried to get path of a node that is not in a tree')
				path_array_ = []
			elif is_root_:
				path_array_ = []
			else:
				var p = parent_.get_ref()
				var a = p.get_path_array().duplicate() if p else []
				if not p:
					push_error('Tried to get path to an orphaned SpaceObjectData.')
				else:
					a.append(name_)
				path_array_ = a
		return path_array_

	func slash_join(path: Array,root: bool) -> String:
		var s: String = '/root/' if root else ''
		var first: bool = true
		for p in path:
			if first:
				s+=p
				first=false
			else:
				s+='/'+p
		return s

	func get_path_str() -> String:
		if path_string_ == null:
			if is_root_:
				path_string_='/root'
			elif not parent_.get_ref():
				push_error('Tried to get path to an orphaned SpaceObjectData.')
				path_string_=''
			elif not tree_.get_ref():
				push_error('Tried to get path to a node that is not in a tree.')
				path_string_=''
			else:
				path_string_ = slash_join(get_path_array(),true)
		return path_string_

	func get_path() -> NodePath:
		if node_path_ == null:
			node_path_ = NodePath(get_path_str())
		return node_path_

	func get_node_or_null(path: NodePath): # -> SimpleNode or null
		var t = tree_.get_ref()
		return t.get_node_or_null(path,self) if t else null

	func get_node(path: NodePath) -> SimpleNode:
		var result = get_node_or_null(path)
		if not result or not result is SimpleNode:
			push_error(str(self)+' has no node at path '+str(path))
		assert(result)
		assert(result is SimpleNode)
		return result

	func get_path_to(other) -> NodePath:
		var a: Array = get_path_array()
		var b: Array = other.get_path_array()
		var i: int = 0
		while i<len(a) and i<len(b) and a[i]==b[i]:
			i+=1
		if i==len(a):
			return NodePath(slash_join(b.slice(i,len(b)),false))
		return NodePath()
	
	func _to_string() -> String:
		return '[SimpleNode@'+get_path_str()+']'

class SimpleTree extends Reference:
	var root: SimpleNode setget set_root, get_root
	func is_SimpleTree(): pass # for type checking; never called
	func _init(root_):
		root = root_
		root.make_root_of(weakref(self))
	func call_ready(force: bool = false):
		if root:
			root._impl_ready(force)
	func get_root():
		return root
	func set_root(root_: SimpleNode):
		assert(root_)
		if root:
			var _ignore = root.remove_all_children()
			root.queue_free()
		root=root_
		root.make_root_of(weakref(self))
	func get_node_or_null(path: NodePath,start=null):
		var obj = root if (start==null or path.is_absolute()) else start
		if path.is_empty():
			return null
		for i in range(path.get_name_count()):
			if obj==null:
				return obj
			var name = path.get_name(i)
			if i==0 and name=='root' and path.is_absolute():
				continue
			obj = obj.children_.get(name,null)
		return obj
	func make_absolute(a: NodePath) -> NodePath:
		if a.is_absolute():
			return a
		var node = get_node_or_null(a)
		return NodePath() if node==null else node.get_path()
	func same_path(a: NodePath, b: NodePath):
		if a.is_empty() and b.is_empty():
			return true
		return make_absolute(a) == make_absolute(b)
	func queue_free():
		root.queue_free()
