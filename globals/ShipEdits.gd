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

class ChangeSpawnCount extends undo_tool.Action:
	var fleet_path: NodePath
	var design_path: NodePath
	var old_count: int
	var new_count: int
	func as_string():
		return 'ChangeSpawnCount(' \
			+'fleet_path='+str(fleet_path)+', design_path='+str(design_path) \
			+'old_count='+str(old_count)+', new_count='+str(new_count)+')'
	func _init(fleet_path_: NodePath, design_path_: NodePath, new_count_: int):
		fleet_path=fleet_path_
		design_path=design_path_
		new_count=new_count_
	func run() -> bool:
		var fleet = game_state.fleets.get_node_or_null(fleet_path)
		var design_name = design_path.get_name(design_path.get_name_count()-1)
		if not fleet:
			return false
		old_count = fleet.spawn_count_for(design_name)
		return true
	func undo() -> bool:
		return game_state.fleet_editor.change_spawn_count(
			fleet_path,design_path,old_count)
	func redo() -> bool:
		return game_state.fleet_editor.change_spawn_count(
			fleet_path,design_path,new_count)

class ChangeFleetSelection extends undo_tool.Action:
	var old_path: NodePath
	var old_index: int
	var old_column: int
	var new_path: NodePath
	var new_index: int
	var new_column: int
	func as_string():
		return 'ChangeFleetSelection(' \
			+ 'old='+str(old_path)+'@'+str(old_index)+':'+str(old_column) \
			+ ',new='+str(new_path)+'@'+str(new_index)+':'+str(new_column)+')'
	func _init(old_path_: NodePath, old_index_: int, old_column_: int, \
			new_path_: NodePath, new_index_: int, new_column_: int):
		old_path = old_path_
		old_index = old_index_
		old_column = old_column_
		new_path = new_path_
		new_index = new_index_
		new_column = new_column_
	func undo() -> bool:
		return game_state.fleet_editor.select_fleet(old_path,old_index,old_column)
	func redo() -> bool:
		return game_state.fleet_editor.select_fleet(new_path,new_index,old_column)

class RemoveFleet extends undo_tool.Action:
	var old_path: NodePath
	var old_column: int
	var old_fleet
	func as_string():
		return 'RemoveFleet(old='+str(old_path)+':'+str(old_column)+',...)'
	func _init(old_path_: NodePath, old_column_: int):
		old_path = old_path_
		old_column = old_column_
	func run():
		old_fleet = game_state.fleets.get_node_or_null(old_path)
		if not old_fleet:
			return false
		return game_state.fleets.remove_child(old_fleet)
	func undo():
		return game_state.fleets.add_child(old_fleet) and \
			game_state.fleet_editor.add_fleet(old_path,old_column,old_fleet)
	func redo():
		return game_state.fleets.remove_child(old_fleet) and \
			game_state.fleet_editor.remove_fleet(old_path,old_column,old_fleet)
