extends Reference

var links: Dictionary = {}
var systems: Dictionary = {}
var data_mutex: Mutex = Mutex.new() # control access to systems, links, selection, last_id

signal added_system
signal erased_system
signal added_link
signal erased_link
signal system_display_name_changed
signal system_position_changed
signal link_position_changed

func has_links() -> bool:
	return not not links

func has_systems() -> bool:
	return not not systems

func has_system(id) -> bool:
	return systems.has(id)

func has_link(arg1,arg2 = null) -> bool:
	if arg2:
		var link_key = [arg1,arg2] if arg1<arg2 else [arg2,arg1]
		return links.has(link_key)
	return links.has(arg1)

func encode() -> String:
	return JSON.print(encode_helper(systems),'  ')

func decode(json_string,context: String) -> bool:
	var parsed: JSONParseResult = JSON.parse(json_string)
	if parsed.error:
		push_error(context+':'+str(parsed.line)+': cannot parse')
		return false
	var content = decode_helper(parsed.result)
	print(content)
	if not content is Dictionary:
		printerr('Can only load systems from a Dictionary!')
		return false
	systems.clear()
	links.clear()
	for system_id in content:
		if not system_id is String or not system_id:
			printerr('error: ignoring invalid system id: ',system_id)
			continue
		var system = content[system_id]
		system['id']=system_id
		system['type'] = 'system'
		if not system.has('links'):
			printerr('warning: system with id ',system_id,' has no links Dictionary')
			system['links']={}
		var system_links = system['links']
		if not system_links is Dictionary:
			printerr('warning: system with id ',system_id,' links is not a Dictionary')
			system_links={}
			system['links']=system_links
		var bad_links = false
		for to in system_links.keys():
			if not to is String or not to or to==system_id:
				bad_links = false
				var _discard = system_links.erase(to)
			var link_key = make_key(system_id,to)
			links[link_key]={ 'type':'link', 'link_key':link_key }
		if bad_links:
			printerr('warning: system with id ',system_id,' has invalid objects for destination systems in its links')
		systems[system_id] = system
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
	elif what==null:
		return []
	elif [TYPE_INT,TYPE_REAL,TYPE_STRING].has(typeof(what)):
		return what
	else:
		printerr('encode_helper: do not know how to handle object ',str(what))
		return []

func decode_helper(what):
	if what is Dictionary:
		var result = {}
		for key in what:
			result[decode_helper(key)] = decode_helper(what[key])
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
	elif [TYPE_INT,TYPE_REAL,TYPE_STRING].has(typeof(what)):
		return what

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
	var from_id = from['id'] if from is Dictionary else from
	var to_id = to['id'] if to is Dictionary else to
	var link_key = [to_id,from_id] if to_id<from_id else [from_id,to_id]
	return links.get(link_key,null)

func get_system(system_id: String): # -> Dictionary or null
	return systems.get(system_id,null)

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
	var from = systems.get(link_key[0],null)
	if not from:
		printerr('link_vectors: system ',link_key[0],' does not exist')
		return null
	var to = systems.get(link_key[1],null)
	if not to:
		printerr('link_vectors: system ',link_key[1],' does not exist')
		return null

	var from_position: Vector3 = from['position']
	var to_position: Vector3 = to['position']
	var along: Vector3 = to_position-from_position

	return {
		'link_key':link_key, 'type':'link', 'from_position':from_position,
		'to_position':to_position, 'along':along,
		'distance_squared': along.length_squared()
	}

func link_sin_cos(arg): # -> Dictionary or null
	var link_key = arg
	if arg is Dictionary:
		link_key=link_key['link_key']
	var from = systems.get(link_key[0],null)
	if not from:
		printerr('link_sin_cos: system ',link_key[0],' does not exist')
		return null
	var to = systems.get(link_key[1],null)
	if not to:
		printerr('link_sin_cos: system ',link_key[1],' does not exist')
		return null
	
	var diff: Vector3 = to['position']-from['position']
	var distsq: float = diff.length_squared()
	var dist: float = sqrt(distsq)
	
	return {
		'from':from, 'to':to, 'position':(from['position']+to['position'])/2.0,
		'sin':(-diff.z/dist if abs(dist)>0.0 else 0.0),
		'cos':(diff.x/dist if abs(dist)>0.0 else 0.0),
		'distance':(dist if abs(dist)>0.0 else 1e-6),
		'distance_squared':(distsq if abs(dist)>0.0 else 1e-12),
		'link_key':link_key, 'type':'link',
	}

# warning-ignore:shadowed_variable
func string_for(selection) -> String:
	if selection is Dictionary:
		var type = str(selection.get('type',''))
		if type=='system':
			return selection['id']
		elif type=='link':
			return selection['link_key'][0]+'->'+selection['link_key'][1]
	return str(selection)

func add_system(id: String,display_name: String,projected_position: Vector3) -> Dictionary:
	data_mutex.lock()
	var system = systems.get(id,null)
	if system!=null:
		var _discard = erase_system(system)
	system = {
		'position':projected_position, 'id':id, 'links':{},
		'distance':projected_position.length(), 'type':'system',
		'display_name':display_name, 'events': [], 'objects': {}
	}
	systems[id]=system
#	if not selection:
#		selection=system
	data_mutex.unlock()
	emit_signal('added_system',system)
	
	return system

func restore_system(system: Dictionary) -> bool:
	data_mutex.lock()
	var system_id: String = system['id']
	systems[system_id]=system
	data_mutex.unlock()
	for to_id in system['links']:
		var to = systems.get(to_id,null)
		if to:
			add_link(system,to)
	emit_signal('added_system',system)
	return true

func erase_system(system: Dictionary) -> bool:
	if system['type']!='system':
		printerr('tried to erase a system that was not a system')
		return false
	var system_id = system['id']
	
	data_mutex.lock()
	for to_id in system['links']:
		var to = systems.get(to_id,null)
		if not to:
			printerr('missing system for link to ',to_id)
			continue
		var link_key = [system_id,to_id] if system_id<to_id else [to_id,system_id]
		var link = links.get(link_key,null)
		if not link:
			printerr('missing link from ',systems['id'],' to ',to_id)
			continue
		if not links.erase(link_key):
			printerr('cannot erase link from ',systems['id'],' to ',to_id)
		var _discard = to['links'].erase(system_id)
		if links.has(link_key):
			printerr('links dictionary did not erase link key ',link_key)
	for link_key in links:
		assert(link_key[0]!=system['id'])
		assert(link_key[1]!=system['id'])
	var _discard = systems.erase(system_id)
#	if selection and selection['type']=='system' and selection['id']==system_id:
#		selection=null
	data_mutex.unlock()
	emit_signal('erased_system',system)
	
	return true

func erase_link(link: Dictionary) -> bool:
	var from_id = link['link_key'][0]
	var to_id = link['link_key'][1]
	
	data_mutex.lock()
	var from = systems.get(from_id,null)
	var to = systems.get(to_id,null)
	var link_key = link['link_key']
	var _discard = links.erase(link_key)
	if from:
		_discard = from['links'].erase(to_id)
	if to:
		_discard = to['links'].erase(from_id)
#	if selection and selection['type']=='link' and selection['link_key']==link_key:
#		selection=null
	data_mutex.unlock()
	emit_signal('erased_link',link)
	
	return true

func restore_link(link: Dictionary) -> bool:
	data_mutex.lock()
	var link_key = link['link_key']
	var from = systems.get(link_key[0],null)
	if not from:
		data_mutex.unlock()
		return false
	var to = systems.get(link_key[1],null)
	if not to:
		data_mutex.unlock()
		return false
	from['links'][to['id']]=link
	to['links'][from['id']]=link
	links[link_key]=link
	data_mutex.unlock()
	emit_signal('added_link',link)
	return true

func add_link(from: Dictionary,to: Dictionary): # -> Dictionary or null
	assert(from!=to)
	if from['type']!='system' or to['type']!='system':
		return null
	var from_id = from['id']
	var to_id = to['id']
	var link_key = [from_id,to_id] if from_id<to_id else [to_id,from_id]

	data_mutex.lock()
	var link = links.get(link_key,null)
	if link:
		data_mutex.unlock()
		return link
	
	link = { 'link_key':link_key, 'type':'link' }
	links[link_key]=link
	from['links'][to_id]=link_key
	to['links'][from_id]=link_key
	data_mutex.unlock()
	emit_signal('added_link',link)
	return link

func find_link(from: Dictionary,to: Dictionary):
	var link_key = [from['id'],to['id']] if from['id']<to['id'] else [to['id'],from['id']]
	return links.get(link_key,null)

func set_display_name(system_id,display_name) -> bool:
	data_mutex.lock()
	var system = systems.get(system_id,null)
	if not system:
		data_mutex.unlock()
		return false
	system['display_name']=display_name
	emit_signal('system_display_name_changed',system)
	data_mutex.unlock()
	return true

func move_system(system: Dictionary,delta: Vector3) -> bool:
	data_mutex.lock()
	system['position'] += Vector3(delta.x,0.0,delta.z)
	data_mutex.unlock()
	emit_signal('system_position_changed',system)
	return true

func set_system_position(system: Dictionary,pos: Vector3) -> bool:
	data_mutex.lock()
	system['position']=pos
	data_mutex.unlock()
	emit_signal('system_position_changed',system)
	return true

func move_link(link,delta) -> bool:
	data_mutex.lock()
	for system_id in link['link_key']:
		var system = systems.get(system_id,null)
		if system:
			system['position'] += delta
			emit_signal('system_position_changed',system)
	data_mutex.unlock()
	emit_signal('link_position_changed',link)
	return true
