extends Node

const MeshLoadingThread = preload('res://globals/MeshLoadingThread.gd')
var mesh_loading_thread = null
var mesh_mutex: Mutex = Mutex.new()
var meshes: Dictionary

func receive_meshes(the_meshes: Dictionary):
	meshes = the_meshes

func load_meshes() -> int:
	mesh_mutex.lock()
	if mesh_loading_thread == null:
		mesh_loading_thread = MeshLoadingThread.new()
	var result: int = mesh_loading_thread.load_meshes()
	mesh_mutex.unlock()
	return result

func wait_for_thread():
	mesh_mutex.lock()
	if mesh_loading_thread!=null:
		mesh_loading_thread.terminate=true
		if mesh_loading_thread.is_active():
			mesh_loading_thread.wait_to_finish()
	mesh_mutex.unlock()
