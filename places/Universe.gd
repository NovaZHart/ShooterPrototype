extends simple_tree.SimpleNode

const SpaceObjectData = preload('res://places/SpaceObjectData.gd')
const SystemData = preload('res://places/SystemData.gd')

var player_ship_design_name = 'player_ship_design'
var systems: simple_tree.SimpleNode
var ship_designs: simple_tree.SimpleNode
var fleets: simple_tree.SimpleNode
var ui: simple_tree.SimpleNode
var links: Dictionary = {}
var data_mutex: Mutex = Mutex.new() # control access to children, links, selection, last_id

signal reset_system
signal added_system
signal erased_system
signal added_link
signal erased_link
signal system_display_name_changed
signal system_position_changed
signal link_position_changed

func mandatory_add_child(child: simple_tree.SimpleNode, child_name: String):
	child.name=child_name
	if not add_child(child):
		push_error('Could not add '+child_name+' child to universe.')

func _init():
	systems = simple_tree.SimpleNode.new()
	#systems.set_name('systems')
	mandatory_add_child(systems,'systems')
	ship_designs = simple_tree.SimpleNode.new()
	#ship_designs.set_name('ship_designs')
	mandatory_add_child(ship_designs,'ship_designs')
	fleets = simple_tree.SimpleNode.new()
	#fleets.set_name('fleets')
	mandatory_add_child(fleets,'fleets')
	ui = simple_tree.SimpleNode.new()
	#ui.set_name('ui')
	mandatory_add_child(ui,'ui')

func is_a_system() -> bool: return false
func is_a_planet() -> bool: return false

func is_Universe(): pass # for type detection; never called

func lock():
	data_mutex.lock()

func unlock():
	data_mutex.unlock()

func has_links() -> bool:
	return not not links

func has_link(arg1,arg2 = null) -> bool:
	if arg2:
		var link_key = [arg1,arg2] if arg1<arg2 else [arg2,arg1]
		return links.has(link_key)
	return links.has(arg1)

func get_stellar_systems():
	var stellar_systems: Dictionary = {}
	for system_name in systems.get_child_names():
		var system = systems.get_child_with_name(system_name)
		if not system or not system.has_method('is_SystemData'):
			continue
		if system.show_on_map:
			stellar_systems[system_name]=system
			continue
	return stellar_systems

func get_interstellar_systems():
	var interstellar_systems: Dictionary = {}
	for system_name in systems.get_child_names():
		var system = systems.get_child_with_name(system_name)
		if not system or not system.has_method('is_SystemData'):
			continue
		if not system.show_on_map:
			if system_name.begins_with('interstellar'):
				interstellar_systems[system_name]=system
			continue
	return interstellar_systems

func decode_children(parent: simple_tree.SimpleNode, children):
	if not children is Dictionary:
		push_error("encoded parent's children are not stored in a Dictionary")
		return
	for child_name in children:
		var decoded = decode_helper(children[child_name])
		if not decoded.has_method('set_name'):
			push_error('invalid child')
		else:
			decoded.set_name(child_name)
			if not parent.add_child(decoded):
				push_error('decode_children failed to add child')

func encode_children(parent: simple_tree.SimpleNode) -> Dictionary:
	var result = {}
	for child_name in parent.get_child_names():
		result[child_name] = encode_helper(parent.get_child_with_name(child_name))
	return result



class Mounted extends simple_tree.SimpleNode:
	var scene: PackedScene
	func is_Mounted(): pass # for type detection; never called
	func _init(scene_: PackedScene):
		scene=scene_

func encode_Mounted(m: Mounted):
	return [ 'Mounted', encode_helper(m.scene) ]

func decode_Mounted(v):
	if not v is Array or not len(v)>1 or v[0]!='Mounted':
		push_error('Invalid input to decode_Mounted')
		return null
	return Mounted.new(decode_helper(v[1]))



class MultiMounted extends Mounted:
	var x: int
	var y: int
	func is_MultiMounted(): pass # for type detection; never called
	func _init(scene_: PackedScene,x_: int,y_: int).(scene_):
		x=x_
		y=y_
	func set_name_with_prefix(prefix: String):
		set_name(prefix+'_at_x'+str(x)+'_y'+str(y))

func encode_MultiMounted(m: MultiMounted):
	return [ 'MultiMounted', encode_helper(m.scene), m.x, m.y ]

func decode_MultiMounted(v):
	if not v is Array or not len(v)>3 or not v[0]=='MultiMounted':
		push_error('Invalid input to decode_MultiMounted: '+str(v))
		return null
	var result = MultiMounted.new(decode_helper(v[1]),int(v[2]),int(v[3]))
	if not result.scene:
		push_error('Cannot decode multimount scene from: '+str(v))
	return result


class MultiMount extends simple_tree.SimpleNode:
	func is_MultiMount(): pass # for type detection; never called

func decode_MultiMount(v):
	if not v is Array or not len(v)>0 or not v[0]=='MultiMount':
		push_error('Invalid input to decode_MultiMount')
		return null
	var result = MultiMount.new()
	if len(v)>1:
		decode_children(result,v[1])
	return result

func encode_MultiMount(m: MultiMount):
	return [ 'MultiMount', encode_children(m) ]



class ShipDesign extends simple_tree.SimpleNode:
	var display_name: String
	var hull: PackedScene
	var cached_stats = null
	var cargo = null
	
	func is_ShipDesign(): pass # for type detection; never called
	
	func _init(display_name_: String, hull_: PackedScene):
		display_name=display_name_
		hull=hull_
		assert(display_name)
		assert(hull)
		assert(hull is PackedScene)
	
	func get_stats() -> Dictionary:
		if not cached_stats:
			var _discard = assemble_ship()
		return cached_stats
	
	func clear_cached_stats():
		cached_stats=null
	
	func cache_remove_instance_info():
		cached_stats.erase('rid')
		for i in range(len(cached_stats['weapons'])):
			cached_stats['weapons'][i]['node_path']=NodePath()
	
	func assemble_part(body: Node, child: Node) -> bool:
		var part = get_child_with_name(child.name)
		if not part:
			return false
		elif part is MultiMount:
#			if not part.get_child_names():
#				push_warning('multimount has no contents')
			var found = false
			for part_name in part.get_child_names():
				var content = part.get_child_with_name(part_name)
				assert(content is MultiMounted)
				var new_child: Node = content.scene.instance()
				if new_child!=null:
					new_child.item_offset_x = content.x
					new_child.item_offset_y = content.y
					new_child.transform = child.transform
					new_child.name = child.name+'_at_'+str(content.x)+'_'+str(content.y)
					body.add_child(new_child)
					found = true
			return found
		elif part is Mounted:
			var new_child = part.scene.instance()
			new_child.transform = child.transform
			new_child.name = child.name
			body.remove_child(child)
			child.queue_free()
			body.add_child(new_child)
			return true
		return false

	func assemble_ship() -> Node:
		var body = hull.instance()
		body.ship_display_name = display_name
		if body == null:
			push_error('assemble_ship: cannot instance scene: '+body)
			return Node.new()
		body.save_transforms()
		var found = false
		for child in body.get_children():
			if child is CollisionShape and child.scale.y<10:
				child.scale.y=10
			found = assemble_part(body,child) or found
		if not found:
			push_warning('No parts found in ship')
		var stats = body.pack_stats(true)
		for child in body.get_children():
			if child.has_method('is_not_mounted'):
				# Unused slots are removed to save space in the scene tree
				body.remove_child(child)
				child.queue_free()
		if not cached_stats:
			cached_stats = stats.duplicate(true)
			cache_remove_instance_info()
		if cargo:
			body.set_cargo(cargo)
		return body

func encode_ShipDesign(d: ShipDesign):
	return [ 'ShipDesign', d.display_name, encode_helper(d.hull), encode_children(d),
		( encode_helper(d.cargo.all) if d.cargo is Commodities.Products else null ) ]

func decode_ShipDesign(v):
	if not v is Array or len(v)<3 or not v[0] is String or v[0]!='ShipDesign':
		return null
	var result = ShipDesign.new(str(v[1]), decode_helper(v[2]))
	if len(v)>3:
		decode_children(result,v[3])
	if len(v)>4:
		var cargo_data = decode_helper(v[4])
		if cargo_data is Dictionary:
			v.cargo = Commodities.ManyProducts.new()
			v.cargo.add_products(cargo_data)
	return result



class UIState extends simple_tree.SimpleNode:
	var ui_state
	
	func is_UIState(): pass # for type detection; never called
	
	func _init(state):
		ui_state = state

func encode_UIState(u: UIState):
	return [ 'UIState', u.ui_state ]

func decode_UIState(v):
	if not v is Array or len(v)<2 or not v[0] is String or v[0]!='UIState':
		return null
	return UIState.new(decode_helper(v[1]))

class Fleet extends simple_tree.SimpleNode:
	var spawn_info: Dictionary = {}
	var display_name: String = 'Unnamed'
	
	func is_Fleet(): pass # for type detection; never called
	
	func _init(display_name_, spawn_info_ = {}):
		display_name = display_name_
		set_spawn_info(spawn_info_)
	func set_spawn_info(dict: Dictionary):
		spawn_info.clear()
		for key in dict:
			if not key is String or not key:
				push_warning('Ignoring invalid design name '+str(key))
				continue
			var value = dict[key]
			var type = typeof(value)
			if type!=TYPE_INT and type!=TYPE_REAL:
				push_warning('Ignoring non-numeric count '+str(value)+' for design name '+key)
				continue
			var as_int = int(value)
			if as_int>0:
				spawn_info[key] = as_int
			else:
				push_warning('Design '+key+' has no ships: int(count)=int('+str(value)+')='+str(as_int))
				continue
	func add_spawn(design_name: String,count: int):
		if count==0:
			push_warning('Ignoring request to add no ships of type '+display_name)
			return
# warning-ignore:narrowing_conversion
		var new_count: int = max(0, count + spawn_info.get(design_name,0))
		if new_count:
			spawn_info[design_name] = new_count
		else:
			remove_spawn(design_name)
	func set_spawn(design_name: String,count: int):
		if count>0:
			spawn_info[design_name] = count
		else:
			remove_spawn(design_name)
	func remove_spawn(design_name: String):
		var _discard = spawn_info.erase(design_name)
	func get_designs() -> Array:
		return spawn_info.keys()
	func spawn_count_for(design_name: String) -> int:
		return spawn_info.get(design_name,0)
	func as_dict() -> Dictionary:
		return spawn_info.duplicate(true)

func encode_Fleet(f: Fleet):
	return [ 'Fleet', str(f.display_name), encode_helper(f.spawn_info) ]

func decode_Fleet(v):
	if not v is Array or len(v)<3 or not v[0] is String or v[0]!='Fleet':
		return null
	var display_name = decode_helper(v[1])
	if not display_name is String:
		push_warning('Encoded fleet display name is not a String.')
		display_name = str(display_name)
	var spawn_info = decode_helper(v[2])
	if not spawn_info is Dictionary:
		push_error('Encoded fleet spawn info is not a Dictionary.')
		return null
	return Fleet.new(display_name,spawn_info)



func decode_InputEvent(data):
	if not data is Array or not len(data)==2:
		push_warning('Unable to decode an input event from '+str(data))
		return null
	var v = decode_helper(data[1])
	var event = null
	if data[0] == 'InputEventKey':
		event = InputEventKey.new()
		event.scancode = v['scancode']
		event.unicode = v['unicode']
		event.alt = v['alt']
		event.command = v['command']
		event.control = v['control']
		event.meta = v['meta']
		event.shift = v['shift']
	elif data[0] == 'InputEventJoypadButton':
		event = InputEventJoypadButton.new()
		event.button_index = v['button_index']
		event.pressure = v['pressure']
	
	if event:
		event.pressed = v['pressed']
		event.device = v['device']
	assert(event==null or event is InputEvent)
	return event

func encode_InputEvent(event: InputEvent):
	if event is InputEventKey:
		return [ 'InputEventKey', { 
			'pressed': event.pressed,
			'scancode': event.scancode,
			'unicode': event.unicode,
			'alt': event.alt,
			'command': event.command,
			'control': event.control,
			'meta': event.meta,
			'shift': event.shift,
			'device': event.device
		} ]
	elif event is InputEventJoypadButton:
		return [ 'InputEventJoypadButton', { 
			'pressed': event.pressed,
			'pressure': event.pressure,
			'button_index': event.button_index,
			'device': event.device
		} ]
	else:
		push_error('Cannot encode unrecognized object '+str(event))


func save_places_as_json(filename: String) -> bool:
	var encoded: String = encode_places()
	var file: File = File.new()
	if file.open(filename, File.WRITE):
		push_error('Cannot open file '+filename+'!!')
		return false
	file.store_string(encoded)
	file.close()
	return true

func load_places_from_json(filename: String) -> bool:
	assert(children_.has('systems'))
	assert(children_.has('ship_designs'))
	assert(children_.has('fleets'))
	var file: File = File.new()
	if file.open(filename, File.READ):
		printerr('Cannot open file '+filename+'!!')
		return false
	var encoded: String = file.get_as_text()
	file.close()
	var system_name = null
	if Player and Player.system:
		system_name = Player.system.get_name()
	var success = decode_places(encoded,filename)
	emit_signal('reset_system')
	if system_name:
		var system = game_state.systems.get_node_or_null(system_name)
		if system:
			Player.system = system
	return success



func decode_places(json_string,context: String) -> bool:
	assert(children_.has('systems'))
	assert(children_.has('fleets'))
	assert(children_.has('ship_designs'))
	var parsed: JSONParseResult = JSON.parse(json_string)
	if parsed.error:
		push_error(context+':'+str(parsed.error_line)+': '+parsed.error_string)
		return false
	var content = decode_helper(parsed.result)
	if not content is Dictionary:
		printerr(context+': error: can only load systems from a Dictionary!')
		return false
	links.clear()

	var content_designs = content['ship_designs']
	if content_designs or not content_designs is simple_tree.SimpleNode:
		for design_name in ship_designs.get_child_names():
			var design = ship_designs.get_child_with_name(design_name)
			if design_name != player_ship_design_name:
				var _discard = ship_designs.remove_child(design)
		for design_name in content_designs.get_child_names():
			var design = content_designs.get_child_with_name(design_name)
			if design_name != player_ship_design_name:
				content_designs.remove_child(design)
				if not ship_designs.add_child(design):
					push_error('Unable to add ship design with name '+design_name)
	else:
		push_error(context+': no ship_designs to load')
		return false
	
	var content_fleets = content['fleets']
	if content_fleets:
		var _discard = fleets.remove_all_children()
		for fleet_name in content_fleets.get_child_names():
			var fleet = content_fleets.get_child_with_name(fleet_name)
			if not fleet or not fleet is Fleet:
				push_error('Invalid fleet with name '+fleet_name)
			elif not content_fleets.remove_child(fleet):
				push_error('Unable to remove fleet '+fleet_name+' from internal data')
			elif not fleets.add_child(fleet):
				push_error('Unable to add fleet with name '+fleet_name)

	var content_systems = content['systems']
	if not content_systems or not content_systems is simple_tree.SimpleNode:
		push_error(context+': no systems to load')
		return false
	for system_id in content_systems.get_child_names():
		if not system_id is String or not system_id:
			printerr(context+': error: ignoring invalid system id: ',system_id)
			continue
		var system = content_systems.get_child_with_name(system_id)
		if not system:
			push_error(context+': error: system with id '+system_id+' is null')
			continue
		if not system is simple_tree.SimpleNode or not system.has_method('is_SystemData'):
			printerr(context+': warning: system with id ',system_id,' is not a SystemData')
			continue
		content_systems.remove_child(system)
		var _discard = systems.add_child(system)
		var bad_links = false
		for to in system.links.keys():
			if not to is String or not to or to==system_id:
				bad_links = false
				_discard = system.links.erase(to)
			var link_key = make_key(system_id,to)
			links[link_key]={ 'type':'link', 'link_key':link_key }
		if bad_links:
			printerr('warning: system with id ',system_id,' has invalid objects for destination systems in its links')
	return true

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
		if not what[0] is String:
			push_warning('Found an array that did not begin with a string when decoding. Returning null.')
			return null
		if what[0]=='Vector2' and len(what)>=3:
			return Vector2(float(what[1]),float(what[2]))
		elif what[0]=='Array':
			var result = []
			result.resize(len(what)-1)
			for n in range(1,len(what)):
				result[n-1] = decode_helper(what[n])
			return result
		elif what[0]=='Vector3' and len(what)>=4:
			return Vector3(float(what[1]),float(what[2]),float(what[3]))
		elif what[0]=='Color' and len(what)>=5:
			return Color(float(what[1]),float(what[2]),float(what[3]),float(what[4]))
		elif what[0].begins_with('InputEvent'):
			return decode_InputEvent(what)
		elif what[0] == 'NodePath' and len(what)>1:
			return NodePath(what[1])
		elif what[0] == 'Fleet':
			return decode_Fleet(what)
		elif what[0] == 'UIState':
			return decode_UIState(what)
		elif what[0] == 'MultiMounted':
			return decode_MultiMounted(what)
		elif what[0] == 'MultiMount':
			return decode_MultiMount(what)
		elif what[0] == 'Mounted':
			return decode_Mounted(what)
		elif what[0] == 'ShipDesign':
			return decode_ShipDesign(what)
		elif what[0] == 'SpaceObjectData' and len(what)>=2:
			return SpaceObjectData.new(key,decode_helper(what[1]))
		elif what[0] == 'SystemData' and len(what)>=2:
			return SystemData.new(key,decode_helper(what[1]))
		elif what[0] == 'SimpleNode' and len(what)>1:
			var result = simple_tree.SimpleNode.new()
			result.set_name(key)
			decode_children(result,what[1])
			return result
		elif what[0]=='Resource' and len(what)>1:
			return ResourceLoader.load(str(what[1]))
	elif [TYPE_INT,TYPE_REAL,TYPE_STRING,TYPE_BOOL].has(typeof(what)):
		return what
	push_warning('Unrecognized type encountered in decode_helper; returning null.')
	return null



func encode_places() -> String:
	return JSON.print(encode_helper(children_),'  ')

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
	elif what is Vector2:
		return [ 'Vector2', what.x, what.y ]
	elif what is Vector3:
		return [ 'Vector3', what.x, what.y, what.z ]
	elif what is Color:
		return [ 'Color', what.r, what.g, what.b, what.a ]
	elif what is InputEvent:
		return encode_InputEvent(what)
	elif what is NodePath:
		return [ 'NodePath', str(what) ]
	elif what is Fleet:
		return encode_Fleet(what)
	elif what is UIState:
		return encode_UIState(what)
	elif what is MultiMounted:
		return encode_MultiMounted(what)
	elif what is MultiMount:
		return encode_MultiMount(what)
	elif what is Mounted:
		return encode_Mounted(what)
	elif what is ShipDesign:
		return encode_ShipDesign(what)
	elif what is Resource:
		return [ 'Resource', what.resource_path ]
	elif what is simple_tree.SimpleNode and what.has_method('encode'):
		var encoded = encode_helper(what.encode())
		var type = 'SpaceObjectData' if what.has_method('is_SpaceObjectData') else 'SystemData'
		var children = {}
		var what_children = what.get_children()
		for child in what_children:
			assert(child is simple_tree.SimpleNode)
			children[encode_helper(child.get_name())]=encode_helper(child)
		encoded['objects'] = children
		return [ type, encoded ]
	elif what is simple_tree.SimpleNode and what.has_method('is_SystemData'):
		return [ 'SystemData', what.encode() ]
	elif what is simple_tree.SimpleNode:
		return [ 'SimpleNode', encode_children(what) ]
	elif what==null:
		return []
	elif [TYPE_INT,TYPE_REAL,TYPE_STRING,TYPE_BOOL].has(typeof(what)):
		return what
	else:
		printerr('encode_helper: do not know how to handle object ',str(what))
		return []



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
	return systems.get_child_with_name(system_id)

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
	var from = systems.get_child_with_name(link_key[0])
	if not from:
		printerr('link_vectors: system ',link_key[0],' does not exist')
		return null
	var to = systems.get_child_with_name(link_key[1])
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
	var from = systems.get_child_with_name(link_key[0])
	if not from:
		printerr('link_sin_cos: system ',link_key[0],' does not exist')
		return null
	var to = systems.get_child_with_name(link_key[1])
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
	systems.remove_child_with_name(id)
	var system = SystemData.new(id,{
		'display_name': display_name,
		'position': projected_position })
	var _discard = systems.add_child(system)
	data_mutex.unlock()
	emit_signal('added_system',system)
	return system

func restore_system(system) -> bool:
	data_mutex.lock()
	#var system_id: String = system.get_name()
	var _discard = systems.add_child(system)
	data_mutex.unlock()
	for to_id in system.links:
		var to = systems.get_child_with_name(to_id)
		if to:
			add_link(system,to)
	emit_signal('added_system',system)
	return true

func erase_system(system) -> bool:
# warning-ignore:return_value_discarded
	systems.remove_child(system)
	var system_id=system.get_name()
	data_mutex.lock()
	for to_id in system.links:
		var to = systems.get_child_with_name(to_id)
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
	var from = systems.get_child_with_name(from_id)
	var to = systems.get_child_with_name(to_id)
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
	var from = systems.get_child_with_name(link_key[0])
	if not from:
		data_mutex.unlock()
		return false
	var to = systems.get_child_with_name(link_key[1])
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
	var system = systems.get_child_with_name(system_id)
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
		var system = systems.get_child_with_name(system_id)
		if system:
			system['position'] += delta
			emit_signal('system_position_changed',system)
	data_mutex.unlock()
	emit_signal('link_position_changed',link)
	return true
