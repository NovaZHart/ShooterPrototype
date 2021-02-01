extends Node

class FleetTreeSelection extends Object:
	var path: NodePath = NodePath()
	var ship_index: int = -1
	var column: int = 0
	func _init(tree,editor):
		if not tree or not editor:
			return # null,null => deselected settings
		if not tree:
			tree = editor.get_node_or_null('H/Tree')
		if not tree:
			return null
		var item = tree.get_selected()
		column = tree.get_selected_column()
		if not item:
			return
		var fleet_path = item.get_metadata(0)
		path = item.get_metadata(1)
		if not fleet_path:
			return
		var fleet = editor.tree_find_meta(tree.get_root(),1,fleet_path)
		if not fleet:
			path=NodePath()
			return
		ship_index = editor.tree_find_meta_index(fleet,1,path)

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
	var old: FleetTreeSelection
	var new: FleetTreeSelection
	func as_string():
		return 'ChangeFleetSelection(...)'
	func _init(old_: FleetTreeSelection, new_: FleetTreeSelection):
		old = old_
		new = new_
	func undo() -> bool:
		return game_state.fleet_editor.select_fleet(old)
	func redo() -> bool:
		return game_state.fleet_editor.select_fleet(new)

class ChangeFleetDisplayName extends undo_tool.Action:
	var fleet_path: NodePath
	var old_name
	var new_name
	func as_string():
		return 'ChangeFleetDisplayName(path='+str(fleet_path)+',old='+\
			old_name+'new='+new_name+')'
	func _init(fleet_path_,new_name_):
		fleet_path=fleet_path_
		new_name=new_name_
	func set_name(value: String, save=false) -> bool:
		var fleet = game_state.fleets.get_node_or_null(fleet_path)
		if not fleet:
			return false
		if save:
			old_name = fleet.display_name
			return true
		fleet.display_name = value
		return game_state.fleet_editor.set_fleet_display_name(fleet_path,value)
	func run() -> bool:
		return set_name(new_name,true)
	func undo() -> bool:
		return set_name(old_name)
	func redo() -> bool:
		return set_name(new_name)

class ChangeFleetSpawnCount extends undo_tool.Action:
	var fleet_path: NodePath
	var design_path: NodePath
	var old_count
	var new_count
	var send_event_in_run: bool
	func as_string():
		return 'ChangeFleetSpawnCount(fleet='+str(fleet_path)+ \
			',design='+str(design_path)+',old='+\
			str(old_count)+'new='+str(new_count)+ \
			'send_event_in_run='+str(send_event_in_run)+')'
	func _init(fleet_path_,design_path_,new_count_,send_event_in_run_):
		fleet_path=fleet_path_
		design_path=design_path_
		new_count=new_count_
		send_event_in_run=send_event_in_run_
	func set_count(value: int, save=false) -> bool:
		var fleet = game_state.fleets.get_node_or_null(fleet_path)
		if not fleet:
			push_error('There is no fleet at path '+str(fleet_path))
			return false
		var design_name = design_path.get_name(design_path.get_name_count()-1)
		if save:
			old_count = fleet.spawn_count_for(design_name)
		fleet.set_spawn(design_name,value)
		return not send_event_in_run or \
			game_state.fleet_editor.set_spawn_count(fleet_path,design_path,value)
	func run() -> bool:
		return set_count(new_count,true)
	func undo() -> bool:
		return set_count(old_count)
	func redo() -> bool:
		return set_count(new_count)

class AddFleet extends undo_tool.Action:
	var new_path: NodePath
	var new_fleet
	var old_selection
	func as_string():
		return 'AddFleet(old='+str(new_path)+',...)'
	func _init(new_fleet_):
		new_fleet = new_fleet_
	func run() -> bool:
		old_selection = FleetTreeSelection.new(null,game_state.fleet_editor)
		var success: bool = game_state.fleets.add_child(new_fleet) and \
			game_state.fleet_editor.add_fleet(new_fleet)
		new_path = new_fleet.get_path()
		return success
	func undo() -> bool:
		return game_state.fleets.remove_child(new_fleet) and \
			game_state.fleet_editor.remove_fleet(new_fleet.get_path()) and \
			game_state.fleet_editor.select_fleet(old_selection)
	func redo() -> bool:
		return game_state.fleets.add_child(new_fleet) and \
			game_state.fleet_editor.add_fleet(new_fleet)

class RemoveFleet extends undo_tool.Action:
	var old_path: NodePath
	var old_index: int
	var old_column: int
	var old_fleet
	var old_selection
	func as_string():
		return 'RemoveFleet(old='+str(old_path)+':'+str(old_column)+',...)'
	func _init(old_path_: NodePath, old_index_: int):
		old_path = old_path_
		old_index = old_index_
	func run() -> bool:
		old_selection = FleetTreeSelection.new(null,game_state.fleet_editor)
		old_fleet = game_state.fleets.get_node_or_null(old_path)
		if not old_fleet:
			return false
		return game_state.fleets.remove_child(old_fleet) and \
			game_state.fleet_editor.remove_fleet(old_path) and \
			game_state.fleet_editor.select_fleet(old_selection)
	func undo() -> bool:
		return game_state.fleets.add_child(old_fleet) and \
			game_state.fleet_editor.add_fleet(old_fleet) and \
			game_state.fleet_editor.select_fleet(old_selection)
	func redo() -> bool:
		return game_state.fleets.remove_child(old_fleet) and \
			game_state.fleet_editor.remove_fleet(old_path) and \
			game_state.fleet_editor.select_fleet(old_selection)
