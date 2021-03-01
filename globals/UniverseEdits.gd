extends Node

var state = undo_tool.UndoStack.new(false)
const SpaceObjectData = preload('res://places/SpaceObjectData.gd')

class AddSystem extends undo_tool.Action:
	var system
	var was_selected: bool
	func as_string() -> String:
		return 'AddSystem('+str(system.get_name())+')'
	func _init(system_):
		system=system_
		was_selected = game_state.sector_editor.selection is simple_tree.SimpleNode and game_state.sector_editor.selection==system
	func undo() -> bool:
		game_state.sector_editor.deselect(system)
		return game_state.sector_editor.process_if(game_state.universe.erase_system(system))
	func redo() -> bool:
		if game_state.sector_editor.process_if(game_state.universe.restore_system(system)):
			return not was_selected or game_state.sector_editor.change_selection_to(system)
		return false

class EraseSystem extends undo_tool.Action:
	var system
	var was_selected: bool
	func as_string() -> String:
		return 'Erase('+str(system.get_name())+')'
	func _init(system_):
		system=system_
		was_selected=game_state.sector_editor.selection is simple_tree.SimpleNode and game_state.sector_editor.selection==system
	func run() -> bool:
		game_state.sector_editor.deselect(system)
		return game_state.sector_editor.process_if(game_state.universe.erase_system(system))
	func undo() -> bool:
		return game_state.sector_editor.process_if(game_state.universe.restore_system(system)) \
			and game_state.sector_editor.change_selection_to(system)
	func redo() -> bool:
		game_state.sector_editor.deselect(system)
		return game_state.sector_editor.process_if(game_state.universe.erase_system(system))

class EraseLink extends undo_tool.Action:
	var link: Dictionary
	var was_selected: bool
	func as_string() -> String:
		return 'EraseLink('+link['link_key'][0]+'->'+link['link_key'][1]+')'
	func _init(link_: Dictionary):
		self.link=link_
		was_selected = game_state.sector_editor.selection is Dictionary and game_state.sector_editor.selection==link
	func run() -> bool:
		game_state.sector_editor.deselect(link)
		return game_state.sector_editor.process_if(game_state.universe.erase_link(link))
	func undo() -> bool:
		if game_state.sector_editor.process_if(game_state.universe.restore_link(link)):
			return not was_selected or game_state.sector_editor.change_selection_to(link)
		return false
	func redo() -> bool:
		game_state.sector_editor.deselect(link)
		return game_state.sector_editor.process_if(game_state.universe.erase_link(link))

class AddLink extends undo_tool.Action:
	var link: Dictionary
	func as_string() -> String:
		return 'AddLink('+link['link_key'][0]+'->'+link['link_key'][1]+')'
	func _init(link_: Dictionary):
		self.link=link_
	func undo() -> bool:
		game_state.sector_editor.deselect(link)
		return game_state.sector_editor.process_if(game_state.universe.erase_link(link))
	func redo() -> bool:
		return game_state.sector_editor.process_if(game_state.universe.restore_link(link))

class ChangeSelection extends undo_tool.Action:
	var old_selection
	var new_selection
	var system_editor: bool
	var center_view: bool
	func as_string() -> String:
		return 'ChangeSelection(old=['+ \
			game_state.universe.string_for(old_selection)+ \
			'],to=['+game_state.universe.string_for(new_selection)+'])'
	func _init(old,new,system_editor_: bool = false, center_view_: bool = false):
		old_selection=old
		new_selection=new
		system_editor=system_editor_
		center_view=center_view_
	func cancel_drag(_from,_to) -> bool:
		if system_editor:
			return game_state.system_editor.cancel_drag()
		return game_state.sector_editor.cancel_drag()
	func set_selection(_from,to) -> bool:
		if system_editor:
			return game_state.system_editor.change_selection_to(to,center_view)
		assert(game_state.hyperspace!=null)
		return game_state.hyperspace.change_selection_to(to,center_view) and \
			game_state.sector_editor.change_selection_to(to,center_view)
	func run() -> bool:
		return set_selection(old_selection,new_selection)
	func undo() -> bool:
		return set_selection(new_selection,old_selection) and cancel_drag(new_selection,old_selection)
	func redo() -> bool:
		return set_selection(old_selection,new_selection) and cancel_drag(old_selection,new_selection)

class SystemEditorToSectorEditor extends undo_tool.Action:
	var from_system: NodePath
	func as_string() -> String:
		return 'SystemEditorToSectorEditor(from_system='+str(from_system)+')'
	func _init():
		from_system = Player.system.get_path()
	func run():
		if OK!=Engine.get_main_loop().change_scene('res://ui/edit/SectorEditor.tscn'):
			push_error('cannot change scene to SectorEditor')
			return false
		return true
	func undo():
		Player.system = from_system
		if OK!=Engine.get_main_loop().change_scene('res://ui/edit/SystemEditor.tscn'):
			push_error('cannot change scene to SystemEditor')
			return false
		return true

class EnterSystemFromSector extends undo_tool.Action:
	var from_system: NodePath
	var to_system: NodePath
	func as_string() -> String:
		return 'EnterSystemFromSector(system_path='+str(to_system)+')'
	func _init(to_system_: NodePath):
		from_system = Player.system.get_path()
		to_system = game_state.systems.get_node(to_system_).get_path()
	func run():
		Player.set_system(game_state.systems.get_node(to_system))
		assert(Player.system.get_path()==to_system)
		if OK!=Engine.get_main_loop().change_scene('res://ui/edit/SystemEditor.tscn'):
			push_error('cannot change scene to SystemEditor')
			return false
		return true
	func undo():
		Player.system = from_system
		if OK!=Engine.get_main_loop().change_scene('res://ui/edit/SectorEditor.tscn'):
			push_error('cannot change scene to SectorEditor')
			return false
		return true

class MoveObject extends undo_tool.Action:
	var object
	var delta: Vector3
	var function: String
	func as_string() -> String:
		return 'MoveObject(object='+game_state.universe.string_for(object)+',delta='+str(delta)+')'
	func _init(object_,function_: String):
		self.object=object_
		self.delta = Vector3()
		self.function = function_
	func amend(delta_: Vector3) -> bool:
		self.delta += delta_
		return true
	func undo() -> bool:
		return game_state.sector_editor.process_if(game_state.universe.call(function,object,-delta)) \
			and game_state.sector_editor.cancel_drag()
	func redo() -> bool:
		return game_state.sector_editor.process_if(game_state.universe.call(function,object,delta)) \
			and game_state.sector_editor.cancel_drag()


class SystemRemoveFleet extends undo_tool.Action:
	var system_path: NodePath
	var fleet_index: int
	var old_value
	func as_string() -> String:
		return 'SystemRemoveFleet(system_path='+str(system_path)+ \
			',fleet_index='+str(fleet_index)+',old_value='+str(old_value)+')'
	func _init(system_path_: NodePath, fleet_index_: int):
		system_path=system_path_
		fleet_index=fleet_index_
	func validate_system(system,validate_index) -> bool:
		if not system:
			push_error('No system to edit in SystemDataChange')
			return false
		if validate_index and len(system.fleets)-1<fleet_index:
			push_error('System '+str(system_path)+' has no fleet '+str(fleet_index))
			return false
		return true
	func run() -> bool:
		var system = game_state.systems.get_node_or_null(system_path)
		if not validate_system(system,true):
			return false
		old_value = system.fleets[fleet_index]
		system.fleets.remove(fleet_index)
		return game_state.system_editor.remove_spawned_fleet(fleet_index)
	func undo() -> bool:
		var system = game_state.systems.get_node_or_null(system_path)
		if not validate_system(system,false):
			return false
		system.fleets.insert(fleet_index,old_value)
		return game_state.system_editor.add_spawned_fleet(fleet_index,old_value)
	func redo() -> bool:
		var system = game_state.systems.get_node_or_null(system_path)
		if not validate_system(system,true):
			return false
		system.fleets.remove(fleet_index)
		return game_state.system_editor.remove_spawned_fleet(fleet_index)


class SystemAddFleet extends undo_tool.Action:
	var system_path: NodePath
	var data
	func as_string() -> String:
		return 'SystemAddFleet(system_path='+str(system_path)+','+str(data)+')'
	func _init(system_path_: NodePath, data_: Dictionary):
		system_path=system_path_
		data=data_
	func run() -> bool:
		var system = game_state.systems.get_node_or_null(system_path)
		if not system:
			push_error('No system to edit in SystemDataChange')
			return false
		system.fleets.append(data)
		return game_state.system_editor.add_spawned_fleet(len(system.fleets)-1,data)
	func undo() -> bool:
		var system = game_state.systems.get_node_or_null(system_path)
		if not system:
			push_error('No system to edit in SystemDataChange')
			return false
		var _discard = system.fleets.pop_back()
		return game_state.system_editor.remove_spawned_fleet(len(system.fleets))


class SystemFleetDataChange extends undo_tool.Action:
	var system_path: NodePath
	var fleet_index: int
	var key: String
	var old_value
	var new_value
	func as_string() -> String:
		return 'SystemFleetDataChange(system_path='+str(system_path)+ \
			',fleet_index='+str(fleet_index)+',key='+str(key)+ \
			',old_value='+str(old_value)+',new_value='+str(new_value)+')'
	func _init(system_path_: NodePath, fleet_index_: int, key_: String, new_value_):
		system_path=system_path_
		fleet_index=fleet_index_
		key=key_
		new_value=new_value_
	func validate_system(system) -> bool:
		if not system:
			push_error('No system to edit in SystemDataChange')
			return false
		if len(system.fleets)-1<fleet_index:
			push_error('System '+str(system_path)+' has no fleet '+str(fleet_index))
			return false
		return true
	func run() -> bool:
		var system = game_state.systems.get_node_or_null(system_path)
		if not validate_system(system):
			return false
		old_value = system.fleets[fleet_index][key]
		system.fleets[fleet_index][key]=new_value
		return game_state.system_editor.change_fleet_data(fleet_index,key,new_value)
	func undo() -> bool:
		var system = game_state.systems.get_node_or_null(system_path)
		if not validate_system(system):
			return false
		system.fleets[fleet_index][key]=old_value
		return game_state.system_editor.change_fleet_data(fleet_index,key,old_value)
	func redo() -> bool:
		var system = game_state.systems.get_node_or_null(system_path)
		if not validate_system(system):
			return false
		system.fleets[fleet_index][key]=new_value
		return game_state.system_editor.change_fleet_data(fleet_index,key,new_value)



class SystemDataKeyUpdate extends undo_tool.Action:
	var object_path: NodePath
	var property: String
	var key
	var old_value
	var new_value
	func as_string():
		return 'SystemDataKeyUpdate(path='+str(object_path) \
			+',property='+str(property)+',key='+str(key)+',new_value=' \
			+str(new_value)+',old_value='+str(old_value)+')'
	func _init(object_path_: NodePath, property_: String, key_, new_value_):
		object_path=object_path_
		property=property_
		key=key_
		new_value=new_value_
	func apply(old: bool,store: bool) -> bool:
		var object = game_state.systems.get_node_or_null(object_path)
		if not object:
			push_error('No space object to edit in SystemDataKeyUpdate at '+str(object_path))
			return false
		var container = object.get(property)
		if store and not old:
			old_value = container[key]
		var value = old_value if old else new_value
		container[key] = value
		return game_state.system_editor.update_key_system_data(
			object.get_path(),property,key,value)
	func run() -> bool:
		return apply(false,true)
	func undo() -> bool:
		return apply(true,false)
	func redo() -> bool:
		return apply(false,false)


class SystemDataAddRemove extends undo_tool.Action:
	var object_path: NodePath
	var property: String
	var key
	var value
	var add: bool
	func as_string():
		return 'SystemDataAddRemove(path='+str(object_path) \
			+',property='+str(property)+',key='+str(key)+',value=' \
			+str(value)+',add='+str(add)+')'
	func _init(object_path_: NodePath, property_: String, key_, value_, add_: bool):
		object_path=object_path_
		property=property_
		key=key_
		add=add_
		value=value_
	func apply(is_add: bool,store: bool) -> bool:
		var object = game_state.systems.get_node_or_null(object_path)
		if not object:
			push_error('No space object to edit in SystemDataAddRemove at '+str(object_path))
			return false
		var container = object.get(property)
		if not is_add:
			if store:
				value=container[key]
			container.erase(key)
		elif container is Dictionary:
			container[key]=value
		else:
			container.insert(key,value)
		if is_add:
			return game_state.system_editor.insert_system_data(
				object.get_path(),property,key,value)
		else:
			return game_state.system_editor.remove_system_data(
				object.get_path(),property,key)
	func run() -> bool:
		return apply(add,true)
	func undo() -> bool:
		return apply(not add,false)
	func redo() -> bool:
		return apply(add,false)

class SystemDataChange extends undo_tool.Action:
	var old: Dictionary = {}
	var new: Dictionary
	var system_path: NodePath
	var background_update: bool
	var metadata_update: bool
	func as_string() -> String:
		return 'SystemDataChange('+str(system_path)+','+str(new)+','+ \
			str(background_update)+','+str(metadata_update)+')'
	func _init(system_path_: NodePath,changes_: Dictionary,
			background_update_: bool,metadata_update_:bool):
		self.new = changes_
		self.system_path=system_path_
		self.background_update=background_update_
		self.metadata_update=metadata_update_
	func run() -> bool:
		var system = game_state.systems.get_node_or_null(system_path)
		if not system:
			push_error('No system to edit in SystemDataChange')
			return false
		for key in new:
			old[key]=system.get(key)
			system.set(key,new[key])
		return game_state.sector_editor.process_if(
			game_state.system_editor.update_system_data(system.get_path(),
				background_update,metadata_update))
	func undo() -> bool:
		var system = game_state.systems.get_node_or_null(system_path)
		if not system or not old:
			push_error('No system to edit in SystemDataChange')
			return false
		for key in old:
			system.set(key,old[key])
		return game_state.sector_editor.process_if(
			game_state.system_editor.update_system_data(system.get_path(),
				background_update,metadata_update))
	func redo() -> bool:
		var system = game_state.systems.get_node_or_null(system_path)
		if not system or not old:
			push_error('No system to edit in SystemDataChange')
			return false
		for key in new:
			system.set(key,new[key])
		return game_state.sector_editor.process_if(
			game_state.system_editor.update_system_data(system.get_path(),
				background_update,metadata_update))
#return game_state.sector_editor.process_if(game_state.universe.set_display_name(system_id,old_name))
class AddSpaceObject extends undo_tool.Action:
	var parent_path: NodePath
	var child: simple_tree.SimpleNode
	func as_string() -> String:
		return 'AddSpaceObject('+str(parent_path)+','+child.get_name()+'{...})'
	func _init(parent_path_: NodePath, child_: simple_tree.SimpleNode):
		parent_path=parent_path_
		child=child_
	func run() -> bool:
		var node: simple_tree.SimpleNode = game_state.systems.get_node_or_null(parent_path)
		if not node:
			push_error('Cannot add space object because parent '+str(parent_path)+' does not exist.')
			return false
		if not node.add_child(child):
			push_error('Unable to add child to '+str(parent_path))
			return false
		return game_state.system_editor.add_space_object(parent_path,child)
	func undo() -> bool:
		var node: simple_tree.SimpleNode = game_state.systems.get_node_or_null(parent_path)
		if not node:
			push_error('Cannot remove space object because parent '+str(parent_path)+' does not exist.')
			return false
		if not node.remove_child(child):
			push_error('Unable to remove child from '+str(parent_path))
			return false
		return game_state.system_editor.remove_space_object(parent_path,child)

class RemoveSpaceObject extends undo_tool.Action:
	var parent_path: NodePath
	var child: simple_tree.SimpleNode
	var child_name
	var was_selected: bool
	func as_string() -> String:
		return 'RemoveSpaceObject('+str(parent_path)+'/'+str(child.get_name())+')'
	func _init(child_: simple_tree.SimpleNode, was_selected_: bool):
		child=child_
		child_name=child.get_name()
		was_selected=was_selected_
		var parent = child.get_parent()
		var parent_path_: NodePath = parent.get_path() if parent else NodePath()
		if not parent_path_ or not child_name:
			push_error('Cannot remove a child that was already removed. Operation will fail.')
		parent_path=parent_path_
	func run() -> bool:
		var node: simple_tree.SimpleNode = game_state.systems.get_node_or_null(parent_path)
		if not node:
			push_error('Cannot remove space object because parent '+str(parent_path)+' does not exist.')
			return false
		if not node.remove_child(child):
			push_error('Unable to remove child from '+str(parent_path))
			return false
		return game_state.system_editor.remove_space_object(parent_path,child)
	func undo() -> bool:
		var node: simple_tree.SimpleNode = game_state.systems.get_node_or_null(parent_path)
		if not node:
			push_error('Cannot add space object because parent '+str(parent_path)+' does not exist.')
			return false
		if not node.add_child(child):
			push_error('Unable to add child to '+str(parent_path))
			return false
		if not game_state.system_editor.add_space_object(parent_path,child):
			push_error('SystemEditor failed to add child to '+str(parent_path))
			return false
		return game_state.system_editor.change_selection_to(child)

class DescriptionChange extends undo_tool.Action:
	var old_description: String
	var new_description: String
	var object_path: NodePath
	func as_string() -> String:
		return 'DescriptionChange('+str(object_path)+',...)'
	func _init(object_path_: NodePath,new_description_: String,old_description_: String):
		self.new_description = new_description_
		self.old_description = old_description_
		self.object_path=object_path_
	func amend(description: String) -> bool:
		new_description = description
		return true
	func undo() -> bool:
		var object = game_state.systems.get_node_or_null(object_path)
		if not object:
			push_error('No space object to edit in SystemDataChange at '+str(object_path))
			return false
		object.description = old_description
		return game_state.system_editor.update_space_object_data(object.get_path(),
				false,false,true,false)
	func redo() -> bool:
		var object = game_state.systems.get_node_or_null(object_path)
		if not object:
			push_error('No space object to edit in SystemDataChange at '+str(object_path))
			return false
		object.description = new_description
		return game_state.system_editor.update_space_object_data(object.get_path(),
				false,false,true,false)


class SpaceObjectDataKeyUpdate extends undo_tool.Action:
	var object_path: NodePath
	var property: String
	var key
	var old_value
	var new_value
	func as_string():
		return 'SpaceObjectDataKeyUpdate(path='+str(object_path) \
			+',property='+str(property)+',key='+str(key)+',new_value=' \
			+str(new_value)+',old_value='+str(old_value)+')'
	func _init(object_path_: NodePath, property_: String, key_, new_value_):
		object_path=object_path_
		property=property_
		key=key_
		new_value=new_value_
	func apply(old: bool,store: bool) -> bool:
		var object = game_state.systems.get_node_or_null(object_path)
		if not object:
			push_error('No space object to edit in SpaceObjectDataKeyUpdate at '+str(object_path))
			return false
		var container = object.get(property)
		if store and not old:
			old_value = container[key]
		var value = old_value if old else new_value
		container[key] = value
		return game_state.system_editor.update_key_space_object_data(
			object.get_path(),property,key,value)
	func run() -> bool:
		return apply(false,true)
	func undo() -> bool:
		return apply(true,false)
	func redo() -> bool:
		return apply(false,false)


class SpaceObjectDataAddRemove extends undo_tool.Action:
	var object_path: NodePath
	var property: String
	var key
	var value
	var add: bool
	func as_string():
		return 'SpaceObjectDataAddRemove(path='+str(object_path) \
			+',property='+str(property)+',key='+str(key)+',value=' \
			+str(value)+',add='+str(add)+')'
	func _init(object_path_: NodePath, property_: String, key_, value_, add_: bool):
		object_path=object_path_
		property=property_
		key=key_
		add=add_
		value=value_
	func apply(is_add: bool,store: bool) -> bool:
		var object = game_state.systems.get_node_or_null(object_path)
		if not object:
			push_error('No space object to edit in SpaceObjectDataAddRemove at '+str(object_path))
			return false
		var container = object.get(property)
		if not is_add:
			if store:
				value=container[key]
			container.erase(key)
		elif container is Dictionary:
			container[key]=value
		else:
			container.insert(key,value)
		if is_add:
			return game_state.system_editor.insert_space_object_data(
				object.get_path(),property,key,value)
		else:
			return game_state.system_editor.remove_space_object_data(
				object.get_path(),property,key)
	func run() -> bool:
		return apply(add,true)
	func undo() -> bool:
		return apply(not add,false)
	func redo() -> bool:
		return apply(add,false)

class SpaceObjectDataChange extends undo_tool.Action:
	var old: Dictionary = {}
	var new: Dictionary
	var object_path: NodePath
	var basic: bool
	var visual: bool
	var help: bool
	var location: bool
	func as_string() -> String:
		return 'SpaceObjectDataChange('+str(object_path)+','+str(new)+','+ \
			str(basic)+','+str(visual)+','+str(help)+','+str(location)+')'
	func _init(object_path_: NodePath,changes_: Dictionary,
			basic_: bool, visual_: bool, help_: bool, location_: bool):
		self.new = changes_
		self.object_path=object_path_
		self.basic=basic_
		self.visual=visual_
		self.help=help_
		self.location=location_
	func run() -> bool:
		var object = game_state.systems.get_node_or_null(object_path)
		if not object:
			push_error('No space object to edit in SpaceObjectDataChange at '+str(object_path))
			return false
		for key in new:
			old[key]=object.get(key)
			object.set(key,new[key])
		return game_state.system_editor.update_space_object_data(object.get_path(),
				basic,visual,help,location)
	func undo() -> bool:
		var object = game_state.systems.get_node_or_null(object_path)
		if not object or not old:
			push_error('No space object to edit in SpaceObjectDataChange at '+str(object_path))
			return false
		for key in old:
			object.set(key,old[key])
		return game_state.system_editor.update_space_object_data(object.get_path(),
				basic,visual,help,location)
	func redo() -> bool:
		var object = game_state.systems.get_node_or_null(object_path)
		if not object or not old:
			push_error('No space object to edit in SpaceObjectDataChange at '+str(object_path))
			return false
		for key in new:
			object.set(key,new[key])
		return game_state.system_editor.update_space_object_data(object.get_path(),
				basic,visual,help,location)
