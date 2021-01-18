extends Node

class NoRef:
	func get_ref():
		return null

class SimpleNode extends Reference:
	var name_: String
	var parent_ = NoRef.new()
	
	var tree_ = NoRef.new()
	var children_: Dictionary = {}
	var path_array_ = null
	var node_path_ = null
	var path_string_ = null
	var is_root_ = false

	func is_root():
		return is_root_

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

	# warning-ignore:shadowed_variable
	func set_parent(parent: WeakRef):
		unparent()
		parent_=parent
		path_array_ = null
		node_path_ = null
		path_string_ = null
		var p = parent.get_ref()
		assert(p)
		if p:
			set_tree(p.tree_)
			is_root_=false

	func get_tree():
		return tree_.get_ref()

	func clear_parent_():
		parent_ = NoRef.new()
		set_tree(NoRef.new())

	func get_parent():
		var p = parent_.get_ref()
		if not p:
			push_error('tried to get parent of orphaned node')
		return p

	func get_children():
		return children_.values()

	func queue_free():
		var parent_node = parent_.get_ref()
		if parent_node:
			parent_node.remove_child(self)

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

	func add_child(child: SimpleNode, child_name = null):
		if child.parent_.get_ref():
			push_error('child already has a parent: '+str(child))
			return
		if child_name==null:
			child_name=child.get_name()
		if not child_name or not child_name is String:
			push_error('tried to add a child with no name: '+str(child))
			return
		var _discard = remove_child_with_name(child_name)
		child.name_=child_name
		child.set_parent(weakref(self))
		children_[child_name]=child

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
			if not parent_.get_ref():
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
		return get_node_or_null(path)

	func get_path_to(other) -> NodePath:
		var a: Array = get_path_array()
		var b: Array = other.get_path_array()
		var i: int = 0
		while i<len(a) and i<len(b) and a[i]==b[i]:
			i+=1
		print(i,' ',a,' ',b,' ',b.slice(i,len(b)))
		if i==len(a):
			return NodePath(slash_join(b.slice(i,len(b)),false))
		return NodePath()
	
	func _to_string() -> String:
		return '[SimpleNode@'+get_path_str()+']'

class SimpleTree extends Reference:
	var root_: SimpleNode
	func _init(root=null):
		if root_==null:
			root_ = SimpleNode.new()
		else:
			root_ = root
		root_.tree_=weakref(self)
		root_.is_root_=true
	func get_root():
		return root_
	func get_node_or_null(path: NodePath,start=null):
		if path.is_empty():
			return null
		var obj = root_ if (start==null or path.is_absolute()) else start
		for i in range(path.get_name_count()):
			if obj==null:
				return obj
			var name = path.get_name(i)
			print('index ',i,' has ',name)
			if i==0 and name=='root' and path.is_absolute():
				continue
			obj = obj.children_.get(name,null)
		return obj
