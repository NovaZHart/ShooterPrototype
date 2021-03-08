extends Node

var scene_path: NodePath = NodePath()
var scene_mutex: Mutex = Mutex.new()

func _ready():
	var _discard = change_scene(preload('res://ui/MainScreen/MainScreen.tscn'))
	var rid = get_viewport().get_viewport_rid()
	VisualServer.viewport_set_render_direct_to_screen(rid,true)

func popup_has_focus():
	var scene = get_scene()
	if scene and scene.has_method('popup_has_focus'):
		return not not scene.popup_has_focus()
	else:
		return not not get_viewport().get_modal_stack_top()

func change_scene(arg) -> bool:
	var was_paused = get_tree().paused
	scene_mutex.lock()
	var scene = arg
	if not arg is PackedScene:
		scene = load(arg)
	
	if scene:
		var instance = scene.instance()
		if instance:
			var old = get_node_or_null(scene_path)
			if old:
				remove_child(old)
				old.queue_free()
			add_child(instance)
			scene_path = instance.get_path()
			scene_mutex.unlock()
			get_tree().paused = false
			if was_paused:
				get_tree().call_deferred('set_paused',was_paused)
			return true
	
	scene_mutex.unlock()
	return false

func get_scene():
	return get_node_or_null(scene_path)
