extends simple_tree.SimpleNode

const SpaceObjectData = preload('res://places/SpaceObjectData.gd')
const SystemData = preload('res://places/SystemData.gd')

var links: Dictionary = {}
var data_mutex: Mutex = Mutex.new() # control access to children, links, selection, last_id

signal added_system
signal erased_system
signal added_link
signal erased_link
signal system_display_name_changed
signal system_position_changed
signal link_position_changed

func is_a_system() -> bool: return false
func is_a_planet() -> bool: return false

func is_Universe(): pass # never called; must only exist

func has_links() -> bool:
	return not not links

func has_systems() -> bool:
	return has_children()

func has_system(id) -> bool:
	return has_child(id)

func has_link(arg1,arg2 = null) -> bool:
	if arg2:
		var link_key = [arg1,arg2] if arg1<arg2 else [arg2,arg1]
		return links.has(link_key)
	return links.has(arg1)

func save_as_json(filename: String) -> bool:
	print('save to file "',filename,'"')
	var encoded: String = encode()
	var file: File = File.new()
	if file.open(filename, File.WRITE):
		push_error('Cannot open file '+filename+'!!')
		return false
	file.store_string(encoded)
	file.close()
	return true

func load_from_json(filename: String) -> bool:
	print('load from file "',filename,'"')
	var file: File = File.new()
	if file.open(filename, File.READ):
		printerr('Cannot open file '+filename+'!!')
		return false
	var encoded: String = file.get_as_text()
	file.close()
	return decode(encoded,filename)

func encode() -> String:
	return JSON.print(encode_helper(children_),'  ')

func decode(json_string,context: String) -> bool:
	var parsed: JSONParseResult = JSON.parse(json_string)
	if parsed.error:
		push_error(context+':'+str(parsed.error_line)+': '+parsed.error_string)
		return false
	var content = decode_helper(parsed.result)
	if not content is Dictionary:
		printerr('Can only load systems from a Dictionary!')
		return false
	var _discard = remove_all_children()
	links.clear()
	for system_id in content:
		if not system_id is String or not system_id:
			printerr('error: ignoring invalid system id: ',system_id)
			continue
		var system = content[system_id]
		if not system is simple_tree.SimpleNode or not system.has_method('is_SystemData'):
			printerr('warning: system with id ',system_id,' is not a SystemData')
		system.set_name(system_id)
		var bad_links = false
		for to in system.links.keys():
			if not to is String or not to or to==system_id:
				bad_links = false
				_discard = system.links.erase(to)
			var link_key = make_key(system_id,to)
			links[link_key]={ 'type':'link', 'link_key':link_key }
		if bad_links:
			printerr('warning: system with id ',system_id,' has invalid objects for destination systems in its links')
		add_child(system)
	return true

func encode_helper(what):
	if what is Dictionary:
		var result = {}
		for key in what:
			result[encode_helper(key)] = encode_helper(what[key])
		return result
	elif what is Array:
		var result = ['Array']
		for value in what:
			result.append(encode_helper(value))
		return result
	elif what is Resource:
		return [ 'Resource', what.resource_path ]
	elif what is Vector2:
		return [ 'Vector2', what.x, what.y ]
	elif what is Vector3:
		return [ 'Vector3', what.x, what.y, what.z ]
	elif what is Color:
		return [ 'Color', what.r, what.g, what.b, what.a ]
	elif what is simple_tree.SimpleNode and what.has_method('encode'):
		var encoded = encode_helper(what.encode())
		var type = 'SpaceObjectData' if what.has_method('is_SpaceObjectData') else 'SystemData'
		var children = {}
		var what_children = what.get_children()
#		if what.astral_gate_path():
#			assert(what_children)
		for child in what_children:
			assert(child is simple_tree.SimpleNode)
			children[encode_helper(child.get_name())]=encode_helper(child)
		encoded['objects'] = children
		return [ type, encoded ]
	elif what is simple_tree.SimpleNode and what.has_method('is_SystemData'):
		return [ 'SystemData', what.encode() ]
	elif what==null:
		return []
	elif [TYPE_INT,TYPE_REAL,TYPE_STRING,TYPE_BOOL].has(typeof(what)):
		return what
	else:
		printerr('encode_helper: do not know how to handle object ',str(what))
		return []

func decode_helper(what,key=null):
	if what is Dictionary:
		var result = {}
		for encoded_key in what:
			var decoded_key = decode_helper(encoded_key)
			result[decoded_key] = decode_helper(what[encoded_key],decoded_key)
		return result
	elif what is Array:
		if not what:
			return null
		if what[0]=='Resource' and len(what)>1:
			return ResourceLoader.load(str(what[1]))
		elif what[0]=='Vector2' and len(what)>=3:
			return Vector2(float(what[1]),float(what[2]))
		elif what[0]=='Array':
			return what.slice(1,len(what))
		elif what[0]=='Vector3' and len(what)>=4:
			return Vector3(float(what[1]),float(what[2]),float(what[3]))
		elif what[0]=='Vector3' and len(what)>=5:
			return Color(float(what[1]),float(what[2]),float(what[3]),float(what[4]))
		elif what[0]=='SpaceObjectData' and len(what)>=2:
			return SpaceObjectData.new(key,decode_helper(what[1]))
		elif what[0]=='SystemData' and len(what)>=2:
			return SystemData.new(key,decode_helper(what[1]))
	elif [TYPE_INT,TYPE_REAL,TYPE_STRING,TYPE_BOOL].has(typeof(what)):
		return what
	return null

func lock():
	data_mutex.lock()

func unlock():
	data_mutex.unlock()

func make_key(id1: String, id2: String) -> Array:
	return [id1,id2] if id1<id2 else [id2,id1]

func get_link_by_key(key): # -> Dictionary or null
	var link_key = key['link_key'] if key is Dictionary else key
	return links.get(link_key,null)

func get_link_between(from,to): # -> Dictionary or null
	var from_id = from.get_name() if from is simple_tree.SimpleNode else from
	var to_id = to.get_name() if to is simple_tree.SimpleNode else to
	var link_key = [to_id,from_id] if to_id<from_id else [from_id,to_id]
	return links.get(link_key,null)

func get_system(system_id: String): # -> Dictionary or null
	return get_child_with_name(system_id)

func link_distsq(p: Vector3,link: Dictionary) -> float:
	# modified from http://geomalgorithms.com/a02-_lines.html#Distance-to-Ray-or-Segment
	var link_data: Dictionary = link if link.has('along') else link_vectors(link)
	var p0: Vector3 = link_data['from_position']
	var c2: float = link_data['distance_squared']
	var w: Vector3 = p-p0
	if abs(c2)<1e-5: # "line segment" is actually a point
		return w.length_squared()
	var v: Vector3 = link_data['along']
	var c1: float = w.dot(v)
	if c1<=0:
		return v.length_squared()
	var p1: Vector3 = link_data['to_position']
	if c2<=c1:
		return p.distance_squared_to(p1)
	return p.distance_squared_to(p0+(c1/c2)*v)

func link_vectors(arg): # -> Dictionary or null
	var link_key = arg
	if arg is Dictionary:
		link_key = link_key['link_key']
	var from = get_child_with_name(link_key[0])
	if not from:
		printerr('link_vectors: system ',link_key[0],' does not exist')
		return null
	var to = get_child_with_name(link_key[1])
	if not to:
		printerr('link_vectors: system ',link_key[1],' does not exist')
		return null

	var along: Vector3 = to.position-from.position

	return {
		'link_key':link_key, 'type':'link', 'from_position':from.position,
		'to_position':to.position, 'along':along,
		'distance_squared': along.length_squared()
	}

func link_sin_cos(arg): # -> Dictionary or null
	var link_key = arg
	if arg is Dictionary:
		link_key=link_key['link_key']
	var from = get_child_with_name(link_key[0])
	if not from:
		printerr('link_sin_cos: system ',link_key[0],' does not exist')
		return null
	var to = get_child_with_name(link_key[1])
	if not to:
		printerr('link_sin_cos: system ',link_key[1],' does not exist')
		return null
	
	var diff: Vector3 = to.position-from.position
	var distsq: float = diff.length_squared()
	var dist: float = sqrt(distsq)
	
	return {
		'from':from, 'to':to, 'position':(from.position+to.position)/2.0,
		'sin':(-diff.z/dist if abs(dist)>0.0 else 0.0),
		'cos':(diff.x/dist if abs(dist)>0.0 else 0.0),
		'distance':(dist if abs(dist)>0.0 else 1e-6),
		'distance_squared':(distsq if abs(dist)>0.0 else 1e-12),
		'link_key':link_key, 'type':'link',
	}

# warning-ignore:shadowed_variable
func string_for(selection) -> String:
	if selection is Dictionary:
		return selection['link_key'][0]+'->'+selection['link_key'][1]
	return str(selection)

func add_system(id: String,display_name: String,projected_position: Vector3) -> Dictionary:
	data_mutex.lock()
# warning-ignore:return_value_discarded
	remove_child_with_name(id)
	var system = SystemData.new(id,{
		'display_name': display_name,
		'position': projected_position })
	add_child(system)
	data_mutex.unlock()
	emit_signal('added_system',system)
	return system

func restore_system(system) -> bool:
	data_mutex.lock()
	#var system_id: String = system.get_name()
	add_child(system)
	data_mutex.unlock()
	for to_id in system.links:
		var to = get_child_with_name(to_id)
		if to:
			add_link(system,to)
	emit_signal('added_system',system)
	return true

func erase_system(system) -> bool:
# warning-ignore:return_value_discarded
	remove_child(system)
	var system_id=system.get_name()
	data_mutex.lock()
	for to_id in system.links:
		var to = get_child_with_name(to_id)
		if not to:
			printerr('missing system for link to ',to_id)
			continue
		var link_key = [system_id,to_id] if system_id<to_id else [to_id,system_id]
		var link = links.get(link_key,null)
		if not link:
			printerr('missing link from ',system_id,' to ',to_id)
			continue
		if not links.erase(link_key):
			printerr('cannot erase link from ',system_id,' to ',to_id)
		var _discard = to.links.erase(system_id)
		if links.has(link_key):
			printerr('links dictionary did not erase link key ',link_key)
	for link_key in links:
		assert(link_key[0]!=system.get_name())
		assert(link_key[1]!=system.get_name())
	data_mutex.unlock()
	emit_signal('erased_system',system)
	return true

func erase_link(link: Dictionary) -> bool:
	var from_id = link['link_key'][0]
	var to_id = link['link_key'][1]
	
	data_mutex.lock()
	var from = get_child_with_name(from_id)
	var to = get_child_with_name(to_id)
	var link_key = link['link_key']
	var _discard = links.erase(link_key)
	if from:
		_discard = from.links.erase(to_id)
	if to:
		_discard = to.links.erase(from_id)
	data_mutex.unlock()
	emit_signal('erased_link',link)
	
	return true

func restore_link(link: Dictionary) -> bool:
	data_mutex.lock()
	var link_key = link['link_key']
	var from = get_child_with_name(link_key[0])
	if not from:
		data_mutex.unlock()
		return false
	var to = get_child_with_name(link_key[1])
	if not to:
		data_mutex.unlock()
		return false
	from.links[to.get_name()]=link
	to.links[from.get_name()]=link
	links[link_key]=link
	data_mutex.unlock()
	emit_signal('added_link',link)
	return true

func add_link(from,to): # -> Dictionary or null
	var from_id = from.get_name()
	var to_id = to.get_name()
	var link_key = [from_id,to_id] if from_id<to_id else [to_id,from_id]

	data_mutex.lock()
	var link = links.get(link_key,null)
	if link:
		data_mutex.unlock()
		return link
	
	link = { 'link_key':link_key, 'type':'link' }
	links[link_key]=link
	from.links[to_id]=1
	to.links[from_id]=1
	data_mutex.unlock()
	emit_signal('added_link',link)
	return link

func find_link(from,to):
	var from_id = from.get_name()
	var to_id = to.get_name()
	var link_key = [from_id,to_id] if from_id<to_id else [to_id,from_id]
	return links.get(link_key,null)

func set_display_name(system_id,display_name) -> bool:
	data_mutex.lock()
	var system = get_child_with_name(system_id)
	if not system:
		data_mutex.unlock()
		return false
	system['display_name']=display_name
	emit_signal('system_display_name_changed',system)
	data_mutex.unlock()
	return true

func move_system(system,delta: Vector3) -> bool:
	data_mutex.lock()
	system['position'] += Vector3(delta.x,0.0,delta.z)
	data_mutex.unlock()
	emit_signal('system_position_changed',system)
	return true

func set_system_position(system,pos: Vector3) -> bool:
	data_mutex.lock()
	system['position']=pos
	data_mutex.unlock()
	emit_signal('system_position_changed',system)
	return true

func move_link(link,delta) -> bool:
	data_mutex.lock()
	for system_id in link['link_key']:
		var system = get_child_with_name(system_id)
		if system:
			system['position'] += delta
			emit_signal('system_position_changed',system)
	data_mutex.unlock()
	emit_signal('link_position_changed',link)
	return true
