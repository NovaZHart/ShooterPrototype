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
	func create():
		return null
	func _init(title: String):
		service_title=title

class ChildInstanceService extends Service:
	var resource: PackedScene
	func create() -> Node:
		return resource.instance()
	func _init(title: String,resource_: PackedScene).(title):
		resource = resource_
