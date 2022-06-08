extends Node

export var resource_path_list="res://data/resources_to_preload.json"
var GDNativePreloadResources = preload("res://bin/PreloadResources.gdns")

var preloader
var die: bool = false

func _ready():
	preloader=GDNativePreloadResources.new()

func _process(_delta):
	var resource_list: Array = get_resource_path_list()
	preloader.add_resources(resource_list)
	# fixme: split this across multiple frames.
	var loaded = preloader.load_resources()
	print("Preloaded "+str(loaded)+" resources.")
	set_process(false)

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

