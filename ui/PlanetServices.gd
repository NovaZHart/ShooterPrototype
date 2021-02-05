extends Object

class Service extends Reference:
	var service_title: String = "Undefined" setget set_service_title,get_service_title
	func is_available() -> bool:
		return true
	func will_change_scene() -> bool:
		return false
	func set_service_title(s: String):
		service_title=s
	func get_service_title() -> String:
		return service_title
	func create(_tree: SceneTree):
		return null
	func _init(title: String):
		service_title=title

class SceneChangeService extends Service:
	var resource: PackedScene
	func will_change_scene() -> bool:
		return true
	func create(_tree: SceneTree) -> int:
		return game_state.change_scene(resource)
	func _init(title: String,resource_: PackedScene).(title):
		resource = resource_

class ChildInstanceService extends Service:
	var resource: PackedScene
	func create(_tree: SceneTree) -> Node:
		return resource.instance()
	func _init(title: String,resource_: PackedScene).(title):
		resource = resource_

class PlanetDescription extends ChildInstanceService:
	func is_available() -> bool:
		var info = Player.get_space_object_or_null()
		return not info==null and not info.description.empty()
	func create(_tree: SceneTree) -> Node:
		var info = Player.get_space_object_or_null()
		var scene = resource.instance()
		var desc = '' if info==null else info.description
		if not desc.empty():
			scene.set_description(desc)
		return scene
	func _init(title: String,resource: PackedScene).(title,resource):
		pass

