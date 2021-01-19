extends Reference

var state = undo_tool.UndoStack.new(false)

class AddSystem extends undo_tool.Action:
	var system
	var editor: Node
	var was_selected: bool
	func as_string() -> String:
		return 'AddSystem('+str(system.get_name())+')'
	func _init(editor_: Node,system_):
		system=system_
		editor=editor_
		was_selected = editor.selection is simple_tree.SimpleNode and editor.selection==system
	func undo() -> bool:
		editor.deselect(system)
		return editor.process_if(game_state.universe.erase_system(system))
	func redo() -> bool:
		if editor.process_if(game_state.universe.restore_system(system)):
			return not was_selected or editor.change_selection_to(system)
		return false

class EraseSystem extends undo_tool.Action:
	var system
	var editor: Node
	var was_selected: bool
	func as_string() -> String:
		return 'Erase('+str(system.get_name())+')'
	func _init(editor_: Node,system_):
		system=system_
		editor=editor_
		was_selected=editor.selection is simple_tree.SimpleNode and editor.selection==system
	func run() -> bool:
		editor.deselect(system)
		return editor.process_if(game_state.universe.erase_system(system))
	func undo() -> bool:
		return editor.process_if(game_state.universe.restore_system(system)) \
			and editor.change_selection_to(system)
	func redo() -> bool:
		editor.deselect(system)
		return editor.process_if(game_state.universe.erase_system(system))

class EraseLink extends undo_tool.Action:
	var link: Dictionary
	var editor: Node
	var was_selected: bool
	# warning-ignore:shadowed_variable
	# warning-ignore:shadowed_variable
	func as_string() -> String:
		return 'EraseLink('+link['link_key'][0]+'->'+link['link_key'][1]+')'
	func _init(editor: Node,link: Dictionary):
		self.link=link
		self.editor=editor
		was_selected = editor.selection is Dictionary and editor.selection==link
	func run() -> bool:
		editor.deselect(link)
		return editor.process_if(game_state.universe.erase_link(link))
	func undo() -> bool:
		if editor.process_if(game_state.universe.restore_link(link)):
			return not was_selected or editor.change_selection_to(link)
		return false
	func redo() -> bool:
		editor.deselect(link)
		return editor.process_if(game_state.universe.erase_link(link))

class AddLink extends undo_tool.Action:
	var link: Dictionary
	var editor: Node
	# warning-ignore:shadowed_variable
	# warning-ignore:shadowed_variable
	func as_string() -> String:
		return 'AddLink('+link['link_key'][0]+'->'+link['link_key'][1]+')'
	func _init(editor: Node,link: Dictionary):
		self.link=link
		self.editor=editor
	func undo() -> bool:
		editor.deselect(link)
		return editor.process_if(game_state.universe.erase_link(link))
	func redo() -> bool:
		return editor.process_if(game_state.universe.restore_link(link))

class ChangeSelection extends undo_tool.Action:
	var old_selection
	var new_selection
	var editor
	# warning-ignore:shadowed_variable
	func as_string() -> String:
		return 'ChangeSelection(old=['+ \
			game_state.universe.string_for(old_selection)+ \
			'],to=['+game_state.universe.string_for(new_selection)+'])'
	func _init(editor: Node,old,new):
		old_selection=old
		new_selection=new
		self.editor=editor
	func run() -> bool:
		return editor.change_selection_to(new_selection)
	func undo() -> bool:
		return editor.change_selection_to(old_selection) and editor.cancel_drag()
	func redo() -> bool:
		return editor.change_selection_to(new_selection) and editor.cancel_drag()

class ChangeDisplayName extends undo_tool.Action:
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
	func _init(editor: Node,system_id: String,old_name: String,new_name: String):
		self.editor=editor
		self.system_id=system_id
		self.old_name=old_name
		self.new_name=new_name
	func undo() -> bool:
		return editor.process_if(game_state.universe.set_display_name(system_id,old_name))
	func redo() -> bool:
		return editor.process_if(game_state.universe.set_display_name(system_id,new_name))

class MoveObject extends undo_tool.Action:
	var editor: Node
	var object
	var delta: Vector3
	var function: String
	func as_string() -> String:
		return 'MoveObject(object='+game_state.universe.string_for(object)+',delta='+str(delta)+')'
# warning-ignore:shadowed_variable
# warning-ignore:shadowed_variable
# warning-ignore:shadowed_variable
	func _init(editor: Node,var object,function: String):
		self.editor=editor
		self.object=object
		self.delta = Vector3()
		self.function = function
# warning-ignore:shadowed_variable
	func amend(delta: Vector3) -> bool:
		self.delta += delta
		return true
	func undo() -> bool:
		return editor.process_if(game_state.universe.call(function,object,-delta)) \
			and editor.cancel_drag()
	func redo() -> bool:
		return editor.process_if(game_state.universe.call(function,object,delta)) \
			and editor.cancel_drag()
