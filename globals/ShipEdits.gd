extends Node

class RemoveDesign extends undo_tool.Action:
	var old_design
	var design_name
	func as_string():
		return 'RemoveDesign('+old_design.name+')'
	func _init(design_name_):
		design_name = design_name_
		old_design = game_state.ship_designs.get_node_or_null(design_name)
	func run():
		var now = game_state.ship_designs.get_node_or_null(design_name)
		if now!=null:
			game_state.ship_editor.remove_design(now)
			game_state.ship_designs.remove_child(now)
		return true
	func undo():
		run()
		if old_design:
			game_state.ship_designs.add_child(old_design)
			game_state.ship_editor.add_design(old_design)
		return true

class AddOrChangeDesign extends undo_tool.Action:
	var new_design
	var old_design
	var design_name
	func as_string():
		return 'AddOrReplaceDesign(hull='+new_design.hull.resource_path+',name='+ \
			design_name+',display_name='+new_design.display_name+'...)'
	func _init(design):
		assert(design!=null)
		new_design = design
		old_design = game_state.ship_designs.get_node_or_null(design.get_name())
		design_name = design.name
	func set_design(design):
		var now = game_state.ship_designs.get_node_or_null(design_name)
		if now!=null:
			game_state.ship_editor.remove_design(now)
			game_state.ship_designs.remove_child(now)
		if design!=null:
			game_state.ship_designs.add_child(design)
			game_state.ship_editor.add_design(design)
	func run():
		set_design(new_design)
		return true
	func undo():
		set_design(old_design)
		return true

class RemoveItem extends undo_tool.Action:
	var scene
	var mount_name
	var x
	var y
	func as_string():
		return 'RemoveItem(scene='+scene.resource_path+', mount_name=' \
			+mount_name+', x='+str(x)+', y='+str(y)+')'
	func _init(scene_,mount_name_,x_,y_):
		scene=scene_
		mount_name=mount_name_
		x=x_
		y=y_
	func run():
		return game_state.ship_editor.remove_item(scene,mount_name,x,y)
	func undo():
		return game_state.ship_editor.add_item(scene,mount_name,x,y)

class AddItem extends undo_tool.Action:
	var scene
	var mount_name
	var x
	var y
	func as_string():
		return 'AddItem(scene='+scene.resource_path+', mount_name=' \
			+mount_name+', x='+str(x)+', y='+str(y)+')'
	func _init(scene_,mount_name_,x_,y_):
		scene=scene_
		mount_name=mount_name_
		x=x_
		y=y_
	func run():
		return game_state.ship_editor.add_item(scene,mount_name,x,y)
	func undo():
		return game_state.ship_editor.remove_item(scene,mount_name,x,y)

class SetEditedShipName extends undo_tool.Action:
	var old
	var new
	func as_string():
		return 'SetEditedShipName('+old+','+new+')'
	func _init(old_,new_):
		old=old_
		new=new_
	func run():
		return game_state.ship_editor.set_edited_ship_name(new)
	func undo():
		return game_state.ship_editor.set_edited_ship_name(old)

class SetEditedShipDisplayName extends undo_tool.Action:
	var old
	var new
	func as_string():
		return 'SetEditedShipDisplayName('+old+','+new+')'
	func _init(old_,new_):
		old=old_
		new=new_
	func run():
		return game_state.ship_editor.set_edited_ship_display_name(new)
	func undo():
		return game_state.ship_editor.set_edited_ship_display_name(old)

class SetEditedShipDesign extends undo_tool.Action:
	var old
	var new
	func as_string():
		return 'SetEditedShipDesign(...)'
	func _init(old_,new_):
		old=old_
		new=new_
	func run():
		return game_state.ship_editor.set_edited_ship_design(new)
	func undo():
		return game_state.ship_editor.set_edited_ship_design(old)
