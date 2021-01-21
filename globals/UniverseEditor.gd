extends Node

var state = undo_tool.UndoStack.new(false)

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
	# warning-ignore:shadowed_variable
	# warning-ignore:shadowed_variable
	func as_string() -> String:
		return 'EraseLink('+link['link_key'][0]+'->'+link['link_key'][1]+')'
# warning-ignore:shadowed_variable
# warning-ignore:shadowed_variable
	func _init(link: Dictionary):
		self.link=link
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
	# warning-ignore:shadowed_variable
	# warning-ignore:shadowed_variable
	func as_string() -> String:
		return 'AddLink('+link['link_key'][0]+'->'+link['link_key'][1]+')'
# warning-ignore:shadowed_variable
	func _init(link: Dictionary):
		self.link=link
	func undo() -> bool:
		game_state.sector_editor.deselect(link)
		return game_state.sector_editor.process_if(game_state.universe.erase_link(link))
	func redo() -> bool:
		return game_state.sector_editor.process_if(game_state.universe.restore_link(link))

class ChangeSelection extends undo_tool.Action:
	var old_selection
	var new_selection
	# warning-ignore:shadowed_variable
	func as_string() -> String:
		return 'ChangeSelection(old=['+ \
			game_state.universe.string_for(old_selection)+ \
			'],to=['+game_state.universe.string_for(new_selection)+'])'
# warning-ignore:shadowed_variable
	func _init(old,new):
		old_selection=old
		new_selection=new
	func run() -> bool:
		return game_state.sector_editor.change_selection_to(new_selection)
	func undo() -> bool:
		return game_state.sector_editor.change_selection_to(old_selection) and game_state.sector_editor.cancel_drag()
	func redo() -> bool:
		return game_state.sector_editor.change_selection_to(new_selection) and game_state.sector_editor.cancel_drag()

class ChangeDisplayName extends undo_tool.Action: # change name from sector editor
	var editor: Node
	var system_id: String
	var old_name: String
	var new_name: String
	func as_string() -> String:
		return 'ChangeDisplayName(system_id='+str(system_id)+',old_name='+ \
			str(old_name)+',new_name='+str(new_name)+')'
# warning-ignore:shadowed_variable
# warning-ignore:shadowed_variable
# warning-ignore:shadowed_variable
# warning-ignore:shadowed_variable
	func _init(system_id: String,old_name: String,new_name: String):
		self.system_id=system_id
		self.old_name=old_name
		self.new_name=new_name
	func undo() -> bool:
		return game_state.sector_editor.process_if(game_state.universe.set_display_name(system_id,old_name))
	func redo() -> bool:
		return game_state.sector_editor.process_if(game_state.universe.set_display_name(system_id,new_name))

class MoveObject extends undo_tool.Action:
	var object
	var delta: Vector3
	var function: String
	func as_string() -> String:
		return 'MoveObject(object='+game_state.universe.string_for(object)+',delta='+str(delta)+')'
# warning-ignore:shadowed_variable
# warning-ignore:shadowed_variable
# warning-ignore:shadowed_variable
	func _init(var object,function: String):
		self.object=object
		self.delta = Vector3()
		self.function = function
# warning-ignore:shadowed_variable
	func amend(delta: Vector3) -> bool:
		self.delta += delta
		return true
	func undo() -> bool:
		return game_state.sector_editor.process_if(game_state.universe.call(function,object,-delta)) \
			and game_state.sector_editor.cancel_drag()
	func redo() -> bool:
		return game_state.sector_editor.process_if(game_state.universe.call(function,object,delta)) \
			and game_state.sector_editor.cancel_drag()

class SystemDataChange extends undo_tool.Action:
	var old: Dictionary = {}
	var new: Dictionary
	var system_path: NodePath
	var background_update: bool
	var metadata_update: bool
	func as_string() -> String:
		return 'SystemDataChange('+str(system_path)+','+str(new)+','+ \
			str(background_update)+','+str(metadata_update)+')'
# warning-ignore:shadowed_variable
	func _init(system_path: NodePath,changes: Dictionary,
			background_update: bool,metadata_update:bool):
		#assert(system)
		self.new = changes
		self.system_path=system_path
		self.background_update=background_update
		self.metadata_update=metadata_update
	func run() -> bool:
		var system = game_state.universe.get_node_or_null(system_path)
		if not system:
			push_error('No system to edit in SystemDataChange')
			return false
		for key in new:
			old[key]=system.get(key)
			system.set(key,new[key])
		return game_state.system_editor.update_system_data(system.get_path(),
				background_update,metadata_update)
	func undo() -> bool:
		var system = game_state.universe.get_node_or_null(system_path)
		if not system or not old:
			push_error('No system to edit in SystemDataChange')
			return false
		for key in old:
			system.set(key,old[key])
		return game_state.system_editor.update_system_data(system.get_path(),
				background_update,metadata_update)
	func redo() -> bool:
		var system = game_state.universe.get_node_or_null(system_path)
		if not system or not old:
			push_error('No system to edit in SystemDataChange')
			return false
		for key in new:
			system.set(key,new[key])
		return game_state.system_editor.update_system_data(system.get_path(),
				background_update,metadata_update)

class DescriptionChange extends undo_tool.Action:
	var old_description: String
	var new_description: String
	var object_path: NodePath
	func as_string() -> String:
		return 'DescriptionChange('+str(object_path)+',...)'
# warning-ignore:shadowed_variable
	func _init(object_path: NodePath,new_description: String,old_description: String):
		self.new_description = new_description
		self.old_description = old_description
		self.object_path=object_path
	func amend(description: String) -> bool:
		new_description = description
		return true
	func undo() -> bool:
		var object = game_state.universe.get_node_or_null(object_path)
		if not object:
			push_error('No space object to edit in SystemDataChange at '+str(object_path))
			return false
		object.description = old_description
		return game_state.system_editor.update_space_object_data(object.get_path(),
				false,false,true,false)
	func redo() -> bool:
		var object = game_state.universe.get_node_or_null(object_path)
		if not object:
			push_error('No space object to edit in SystemDataChange at '+str(object_path))
			return false
		object.description = new_description
		return game_state.system_editor.update_space_object_data(object.get_path(),
				false,false,true,false)

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
# warning-ignore:shadowed_variable
	func _init(object_path: NodePath,changes: Dictionary,
			basic: bool, visual: bool, help: bool, location: bool):
		self.new = changes
		self.object_path=object_path
		self.basic=basic
		self.visual=visual
		self.help=help
		self.location=location
	func run() -> bool:
		var object = game_state.universe.get_node_or_null(object_path)
		if not object:
			push_error('No space object to edit in SystemDataChange at '+str(object_path))
			return false
		for key in new:
			old[key]=object.get(key)
			object.set(key,new[key])
		return game_state.system_editor.update_space_object_data(object.get_path(),
				basic,visual,help,location)
	func undo() -> bool:
		var object = game_state.universe.get_node_or_null(object_path)
		if not object or not old:
			push_error('No space object to edit in SystemDataChange at '+str(object_path))
			return false
		for key in old:
			object.set(key,old[key])
		return game_state.system_editor.update_space_object_data(object.get_path(),
				basic,visual,help,location)
	func redo() -> bool:
		var object = game_state.universe.get_node_or_null(object_path)
		if not object or not old:
			push_error('No space object to edit in SystemDataChange at '+str(object_path))
			return false
		for key in new:
			object.set(key,new[key])
		return game_state.system_editor.update_space_object_data(object.get_path(),
				basic,visual,help,location)
