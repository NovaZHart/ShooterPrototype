extends Node

export var resource_path_list="res://data/resources_to_preload.json"
var GDNativePreloadResources = preload("res://bin/PreloadResources.gdns")

var preloader
var preloader_thread
var die: bool = false

func _ready():
	preloader=GDNativePreloadResources.new()
	preloader_thread=Thread.new()
	var result = preloader_thread.start(self,'thread_main',null,Thread.PRIORITY_LOW)
	if result!=OK:
		printerr('PreloadResources: Could not start thread for self.thread_main(). Error #',result)

func _exit_tree():
	print("Killing preloader thread.")
	die=true
	preloader_thread.wait_to_finish()
	print("Preloader thread has finished.")

func get_resource_path_list() -> Array:
	var file: File = File.new()
	if file.open(resource_path_list, File.READ):
		printerr('Cannot open file '+filename+'!!')
		return []
	var encoded: String = file.get_as_text()
	file.close()
	var parsed: JSONParseResult = JSON.parse(encoded)
	if parsed.error:
		push_error(resource_path_list+':'+str(parsed.error_line)+': '+parsed.error_string)
		return []
	if not parsed.result is Array:
		printerr(resource_path_list+': error: can only load systems from a Dictionary!')
		return []
	return parsed.result

# Called when the node enters the scene tree for the first time.
func thread_main(_userdata):
	if preloader == null:
		printerr("No preloader available to PreloadResources.thread_main. Will not preload any resources.")
		return
	var resource_list: Array = get_resource_path_list()
	if not resource_list:
		printerr("PreloadResources resource list is empty. Will not preload any resources.")
		return
	preloader.add_resources(resource_list)
	while not die:
		var count = preloader.load_resources()
		if count:
			print("Loaded "+str(count)+" resources in the background.")
		yield(get_tree().create_timer(1/60.0),"timeout")

func timeout():
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
