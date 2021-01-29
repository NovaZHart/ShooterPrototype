extends Node

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
