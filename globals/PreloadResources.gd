extends Node

export var resource_path_list="res://data/resources_to_preload.json"
var GDNativePreloadResources = preload("res://bin/PreloadResources.gdns")

var preloader
var got_resources: bool = false
var designs_to_load: Array = []
var ship_count=0

func _ready():
	preloader=GDNativePreloadResources.new()

func free_all_resources():
	if not preloader:
		return
	preloader.free_all_resources()
	preloader = null

func _exit_tree():
	free_all_resources()

func _process(_delta):
	if not preloader:
		set_process(false)
		return
	if not got_resources:
		var resource_list: Array = get_resource_path_list()
		preloader.add_resources(resource_list)
		# fixme: split this across multiple frames.
		var loaded = preloader.load_resources()
		print("Preloaded "+str(loaded)+" resources.")

		got_resources=true
	
		designs_to_load = game_state.ship_designs.get_child_names()
	elif not designs_to_load:
		set_process(false)
		print("Preloaded "+str(ship_count)+" ship designs.")
	else:
		var child_name = designs_to_load.pop_back()
		var design = game_state.ship_designs.get_child_with_name(child_name)
		if design:
			var _stats = design.get_stats()
			ship_count += 1
	

func get_resource_path_list() -> Array:
	if not preloader:
		return []
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

