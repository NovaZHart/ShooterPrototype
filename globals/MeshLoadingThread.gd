extends Thread

var meshes: Dictionary = {}
var terminate: bool = false setget set_terminate,get_terminate
const max_dirs: int = 500   # safeguard against symlink loops
var scanned_dirs: int = 0
var was_started: bool = false
var has_ended: bool = false
var start_mutex: Mutex = Mutex.new()
var subdirs: Array = [ 'ships', 'weapons', 'places' ]

func set_terminate(term: bool):
	var had_ended: bool = has_ended
	terminate=term
	if terminate and not had_ended:
		print('MeshLoadingThread: requesting premature termination')

func get_terminate() -> bool:
	return terminate

func load_meshes() -> int: # returns an Error enum
	var result: int = OK
	start_mutex.lock()
	if not was_started:
		result = start(self,'thread_main',null,Thread.PRIORITY_LOW)
		if result!=OK:
			printerr('MeshLoadingThread: Could not start thread for self.thread_main(). Error #',result)
	was_started = result==OK
	start_mutex.unlock()
	return result

func count_meshes() -> int:
	var count: int = 0
	for mesh in meshes.values():
		if mesh!=null:
			count+=1
	return count

func thread_main(_userdata):
	was_started = true
	var success: bool = true
	for subdir in subdirs:
		success=process_dir('res://'+subdir)
		if not success:
			break
	if not success:
		printerr('MeshLoadingThread: aborting. Loaded ',count_meshes(),' of ',
			len(meshes),' meshes.')
	else:
		print('MeshLoadingThread: success. Loaded ',count_meshes(),' of ',
			len(meshes),' meshes.')
	mesh_loader.receive_meshes(meshes)
	has_ended=true

func process_dir(dir_path) -> bool:
	scanned_dirs += 1
	if scanned_dirs>max_dirs:
		printerr('MeshLoadingThread: hit maximum allowed directories to scan (',max_dirs,'). Aborting!')
		return false
	var dir: Directory = Directory.new()
	if dir.open(dir_path) != OK:
		printerr('MeshLoadingThread: ',dir_path,': cannot open directory')
		return false
	if dir.list_dir_begin(true,true)!=OK:
		printerr('MeshLoadingThread: ',dir_path,': cannot list directory')
		return false
	var file_name: String = dir.get_next()
	while file_name!='':
		if terminate:
			print('MeshLoadingThread: terminating prematurely on request')
			return false
		var full_path: String = dir_path+'/'+file_name
		if dir.current_is_dir():
			if not process_dir(full_path):
				printerr('MeshLoadingThread: ',dir_path,' aborting because subdir failed: ',file_name)
				return false
		elif file_name.ends_with('.mesh') and not meshes.has(full_path):
#				and ResourceLoader.exists(full_path):
			meshes[full_path] = ResourceLoader.load(full_path)
		file_name=dir.get_next()
	return true
