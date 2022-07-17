extends simple_tree.SimpleNode

const SpaceObjectData = preload('res://places/SpaceObjectData.gd')
const SystemData = preload('res://places/SystemData.gd')

var player_ship_design_name = 'player_ship_design'
var systems: simple_tree.SimpleNode
var ship_designs: simple_tree.SimpleNode
var fleets: simple_tree.SimpleNode
var factions: Factions.FactionList
var ui: simple_tree.SimpleNode
var flotsam: simple_tree.SimpleNode
var asteroids: simple_tree.SimpleNode
var links: Dictionary = {}
var data_mutex: Mutex = Mutex.new() # control access to children, links, selection, last_id
var cached_parts: Dictionary
var allow_caching: bool = true

signal reset_system
signal added_system
signal erased_system
signal added_link
signal erased_link
signal system_display_name_changed
signal system_position_changed
signal link_position_changed

func mandatory_add_child(child, child_name: String):
	assert(child.has_method('is_SimpleNode')) # type checking breaks here
	child.name=child_name
	if not add_child(child):
		push_error('Could not add '+child_name+' child to universe.')

func _exit_tree():
	free_all_resources()

func free_all_resources():
	allow_caching = false
	for v in cached_parts.values():
		v.queue_free()
	cached_parts.clear()

func _init():
	systems = simple_tree.SimpleNode.new()
	mandatory_add_child(systems,'systems')
	
	ship_designs = simple_tree.SimpleNode.new()
	mandatory_add_child(ship_designs,'ship_designs')
	
	fleets = simple_tree.SimpleNode.new()
	mandatory_add_child(fleets,'fleets')
	
	ui = simple_tree.SimpleNode.new()
	mandatory_add_child(ui,'ui')
	
	factions = Factions.FactionList.new()
	mandatory_add_child(factions,'factions')
	
	flotsam = simple_tree.SimpleNode.new()
	mandatory_add_child(flotsam,'flotsam')
	
	asteroids = simple_tree.SimpleNode.new()
	mandatory_add_child(asteroids,'asteroids')

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

static func decode_children(parent, children):
	if not children is Dictionary:
		push_error("encoded parent's children are not stored in a Dictionary")
		return
	for child_name in children:
		var decoded = decode_helper(children[child_name])
		if not decoded:
			push_error('null child "'+str(child_name)+'"')
		elif not decoded.has_method('set_name'):
			push_error('invalid child')
		else:
			decoded.set_name(child_name)
			if not parent.add_child(decoded):
				push_error('decode_children failed to add child')

static func encode_children(parent) -> Dictionary:
	var result = {}
	for child_name in parent.get_child_names():
		result[child_name] = encode_helper(parent.get_child_with_name(child_name))
	return result

static func encode_ProductsNode(p: Commodities.ProductsNode):
	return [ 'ProductsNode', str(p.update_time),
		encode_helper(p.products.encode() if p.products else {}),
		encode_children(p) ]

static func decode_ProductsNode(v):
	var result = Commodities.ProductsNode.new()
	if len(v)<4:
		push_error('Expected two arguments in encoded ProductsNode, not '+str(len(v)))
	if len(v)>1:
		if v[1] is String and v[1].is_valid_integer():
			result.update_time = int(v[1])
		else:
			push_error('Invalid value for encoded ProductsNode.update_time: '+str(v[1]))
	if len(v)>2:
		var two = decode_helper(v[2])
		if two is Dictionary:
			result.decode_products(two)
		elif two:
			push_error('Invalid value for encoded ProductsNode.products: '+str(two).substr(0,100))
	if len(v)>3:
		decode_children(result,v[3])
	return result

class Mounted extends simple_tree.SimpleNode:
	var scene: PackedScene
	func is_Mounted(): pass # for type detection; never called
	func list_ship_parts(parts,from):
		parts.add_quantity_from(from,scene.resource_path,1,Commodities.ship_parts)
		for child_name in get_child_names():
			var child = get_child_with_name(child_name)
			if child and child.has_method('list_ship_parts'):
				child.list_ship_parts(parts,from)
#	func is_available(ship_parts):
#		return ship_parts.by_name.has(scene.resource_path)
	func _init(scene_: PackedScene):
		scene=scene_

static func encode_Mounted(m: Mounted):
	return [ 'Mounted', encode_helper(m.scene) ]

static func decode_Mounted(v):
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

static func encode_MultiMounted(m: MultiMounted):
	return [ 'MultiMounted', encode_helper(m.scene), m.x, m.y ]

static func decode_MultiMounted(v):
	if not v is Array or not len(v)>3 or not v[0]=='MultiMounted':
		push_error('Invalid input to decode_MultiMounted: '+str(v))
		return null
	var result = MultiMounted.new(decode_helper(v[1]),int(v[2]),int(v[3]))
	if not result.scene:
		push_error('Cannot decode multimount scene from: '+str(v))
	return result


class MultiMount extends simple_tree.SimpleNode:
	func is_MultiMount(): pass # for type detection; never called
	func list_ship_parts(parts,from):
		for child_name in get_child_names():
			var child = get_child_with_name(child_name)
			if child and child.has_method('list_ship_parts'):
				child.list_ship_parts(parts,from)
#	func is_available(ship_parts):
#		for child_name in get_child_names():
#			var child = get_child_with_name(child_name)
#			if child and child.has_method('is_available'):
#				if not child.is_available(ship_parts):
#					return false
#		return true

static func decode_MultiMount(v):
	if not v is Array or not len(v)>0 or not v[0]=='MultiMount':
		push_error('Invalid input to decode_MultiMount')
		return null
	var result = MultiMount.new()
	if len(v)>1:
		decode_children(result,v[1])
	return result

static func encode_MultiMount(m: MultiMount):
	return [ 'MultiMount', encode_children(m) ]

class AsteroidPalette extends simple_tree.SimpleNode:
	var contents: Array = []
	var palettes = null
	func _init(content_in: Array):
		for c in content_in:
			if c is Array and len(c)==2 and c[0]>0 and c[1] is Dictionary:
				contents.append(c)
			else:
				push_error('Invalid item in AsteroidPalette: '+str(c))
	func get_palettes(flotsam) -> Array:
		if palettes:
			return palettes
		var asteroids: Array = []
		var salvage: Dictionary = {}
		for weight_asteroid in contents:
			var asteroid = weight_asteroid[1]
			var asteroid_salvage = asteroid.get('salvage',null)
			if not asteroid_salvage:
				push_warning('Ignoring asteroid without a salvage name: '+str(asteroid))
				continue
			if not salvage.has(asteroid_salvage):
				var flot = flotsam.get_child_with_name(asteroid_salvage)
				if not flot:
					push_warning('Ignoring asteroid with invalid salvage name "'+str(asteroid_salvage)+'"')
					continue
				salvage[asteroid_salvage] = flot.encode_for_native(null,0,0,null,false)
			asteroids.append(weight_asteroid)
		palettes = [asteroids, salvage]
		return palettes
	func encode_for_native() -> Array:
		return contents

static func encode_AsteroidPalette(m: AsteroidPalette):
	var result: Array = [ "AsteroidPalette" ]
	result.append_array(m.contents)
	return result

static func decode_AsteroidPalette(v):
	if not v is Array or not len(v)>0 or not v[0]=='AsteroidPalette':
		push_error('Invalid input to decode_AsteroidPalette')
		return null
	var entries = []
	for i in range(1,len(v)):
		entries.append(decode_helper(v[i]))
	var ap = AsteroidPalette.new(entries)
	assert(ap.contents)
	return ap

class Flotsam extends simple_tree.SimpleNode:
	var display_name: String
	var products: Array = []
	var armor_repair: float = 0.0
	var structure_repair: float = 0.0
	var fuel: float = 0.0
	var cargo: float = 0.0
	const default_grab_radius: float = 0.25
	var grab_radius: float = default_grab_radius
	var mesh_path: String = ''
	var loaded_mesh: Mesh = null
	var tried_to_load_mesh: bool =false
	
	func _init(content: Dictionary):
		display_name=content.get('display_name','(Unnamed)')
		armor_repair=content.get('armor_repair',0.0)
		structure_repair=content.get('structure_repair',0.0)
		fuel=content.get('fuel',0.0)
		grab_radius=content.get('grab_radius',default_grab_radius)
		cargo = content.get('cargo',0.0)
		mesh_path = content.get('mesh_path','')
		loaded_mesh = null
		#flotsam_scale=content.get('flotsam_scale',default_flotsam_scale)
		#var flotsam_mesh_path=content.get('flotsam_mesh_path')
		#if flotsam_mesh_path:
		#	flotsam_mesh = load(flotsam_mesh_path)
		var prod = content.get('products')
		if prod is Dictionary:
			for product_name in prod:
				var count = prod[product_name]
				if not count or count<0:
					continue
				var id = Commodities.commodities.by_name.get(product_name,-1)
				if id>=0:
					var product = Array(Commodities.commodities.all[id])
					product[Commodities.Products.QUANTITY_INDEX] = count
					products.append(product)
					continue
				id = Commodities.ship_parts.by_name.get(product_name,-1)
				if id>=0:
					var product = Array(Commodities.ship_parts.all[id])
					product[Commodities.Products.QUANTITY_INDEX] = count
					products.append(product)
					continue
	
	func load_mesh():
		if tried_to_load_mesh:
			return loaded_mesh
		var loaded = null
		if mesh_path:
			loaded = load(mesh_path)
		if not loaded:
			loaded_mesh = null
		elif not ( loaded is Mesh ):
			push_warning('Non-mesh at flotsam mesh resource path '+str(mesh_path))
			loaded_mesh = null
		else:
			loaded_mesh = loaded
		tried_to_load_mesh = true
	
	func uses_ship_cargo():
		return not not cargo
		
	func encode_for_native(mesh: Mesh = null, max_armor: float = 2000.0,
			max_fuel: float = 20, ship_cargo=null,
			random_fraction: bool=true) -> Dictionary:
		var product = random_product(ship_cargo,random_fraction)
		if not product:
			product = [ '',0,0,0,0 ]
		if not mesh:
			mesh = load_mesh()
		return {
			'flotsam_mesh': mesh,
			'flotsam_scale': 1.0,
			'cargo_name': product[Commodities.Products.NAME_INDEX],
			'cargo_count': product[Commodities.Products.QUANTITY_INDEX],
			'cargo_unit_mass': product[Commodities.Products.MASS_INDEX],
			'cargo_unit_value': product[Commodities.Products.VALUE_INDEX],
			'armor_repair': armor_repair*max_armor,
			'structure_repair': structure_repair,
			'fuel': fuel*max_fuel,
			"spawn_duration": combat_engine.SALVAGE_TIME_LIMIT,
			'grab_radius': utils.mesh_radius(mesh),
		}
	
	func random_product(ship_cargo = null, random_fraction: bool = true):
		if cargo and ship_cargo: # and randf()<cargo:
			var keys = ship_cargo.all.keys()
			if keys:
				var id = keys[randi()%keys.size()]
				var product = ship_cargo.all.get(id,null)
				if product:
					var quantity =  product[Commodities.Products.QUANTITY_INDEX]
					if quantity:
						product = Array(product)
						if random_fraction:
							quantity = int(max(1,ceil(randf()*quantity)))
						product[Commodities.Products.QUANTITY_INDEX] = quantity
						return product
		if not products:
			return null
		else:
			var index = randi()%products.size()
			var product: Array = products[index].duplicate(true)
			var count: int = int(max(1,ceil(product[Commodities.Products.QUANTITY_INDEX])))
			var original = products[index][Commodities.Products.QUANTITY_INDEX]
			if random_fraction:
				var selected = 1+randi()%count
				#print("Randomly selecting "+str(selected)+" of "+str(count)+" "+str(product[Commodities.Products.NAME_INDEX]));
				count = selected
			product[Commodities.Products.QUANTITY_INDEX] = count
			assert(products[index][Commodities.Products.QUANTITY_INDEX] == original)
			return product
	
	func is_flotsam(): pass # For type detection. Never called, just needs to exist.

static func decode_Flotsam(var p,var _key=null):
	if not p is Array or p.size()<2 or not p[1] is Dictionary:
		push_error('Invalid flotsam data '+str(p))
		return null
	return Flotsam.new(p[1])

# warning-ignore:shadowed_variable
static func encode_Flotsam(flotsam: Flotsam):
	var result = {}
	if flotsam.display_name:
		result['display_name']=flotsam.display_name
	if flotsam.armor_repair:
		result['armor_repair']=flotsam.armor_repair
	if flotsam.structure_repair:
		result['structure_repair']=flotsam.structure_repair
	if flotsam.fuel:
		result['fuel']=flotsam.fuel
	#if flotsam.flotsam_mesh:
	#	result['flotsam_mesh_path']=flotsam.flotsam_mesh.resource_path
	if flotsam.grab_radius!=flotsam.default_grab_radius:
		result['grab_radius']=flotsam.grab_radius
	#if flotsam.flotsam_scale!=flotsam.default_flotsam_scale:
	#	result['flotsam_scale']=flotsam.flotsam_scale
	return ['Flotsam',result]

func get_part(scene: PackedScene):
	if not allow_caching:
		return scene.instance()
	var start = OS.get_ticks_msec()
	var part = cached_parts.get(scene,null)
	var instanced = false
	if not part:
		instanced = true
		#print('Instancing scene '+str(scene.resource_path)+' in get_part')
		var start1 = OS.get_ticks_msec()
		part = scene.instance()
		cached_parts[scene]=part
		var duration1 = OS.get_ticks_msec()-start1
		if duration1>4:
			print('get_part took '+str(duration1)+'ms to instance instance='+str(instanced)+' scene='+str(scene.resource_path))
	var result = part.duplicate(4)
	var duration = OS.get_ticks_msec()-start
	if duration>4:
		print('get_part took '+str(duration)+'ms instance='+str(instanced)+' scene='+str(scene.resource_path))
	return result


class ShipDesign extends simple_tree.SimpleNode:
	var display_name: String
	var hull: PackedScene
	var cached_stats = null setget ,get_stats
	var cargo setget set_cargo
	var cached_cost = -1.0
	var not_visible: Dictionary = {} # names of children that should not be in scene tree
	
	func set_cargo(new_cargo):
		# Update cargo stats. This MUST match ShipStats.pack_cargo_stats
		assert(new_cargo==null or new_cargo is Commodities.ManyProducts)
		cargo = new_cargo
		if cached_stats:
			cached_stats['cargo_mass'] = float(cargo.get_mass()/1000) if cargo else 0.0

	func get_cost(from=null):
		if cached_cost<0:
			var parts = Commodities.ManyProducts.new()
			if from==null:
				from = Commodities.ship_parts
			list_ship_parts(parts,from)
			cached_cost = parts.get_value()
		return cached_cost
	
	func is_ShipDesign(): pass # for type detection; never called
	
	func list_ship_parts(parts,from):
		parts.add_quantity_from(from,hull.resource_path,1,Commodities.ship_parts)
		for child_name in get_child_names():
			var child = get_child_with_name(child_name)
			if child and child.has_method('list_ship_parts'):
				child.list_ship_parts(parts,from)
		return parts
	
	func has_sufficient_parts(my_parts, all_parts) -> bool:
		# my_parts = return value from list_ship_parts
		# all_parts = second argument to list_ship_parts
		for part_name in my_parts.by_name:
			var product = all_parts.all.get(all_parts.by_name.get(part_name,-1),null)
			if not product:
				return false
			var my_product = my_parts.all.get(my_parts.by_name.get(part_name,-1),null)
			if not my_product:
				return false
			if my_product[Commodities.Products.QUANTITY_INDEX]>product[Commodities.Products.QUANTITY_INDEX]:
				return false
		return true
	
	func is_available(ship_parts) -> bool:
		var my_parts = Commodities.ManyProducts.new()
		list_ship_parts(my_parts,ship_parts)
		return has_sufficient_parts(my_parts,ship_parts)
#
#	func is_available(ship_parts):
#		if not ship_parts.by_name.has(hull.resource_path):
#			return false
#		for child_name in get_child_names():
#			var child = get_child_with_name(child_name)
#			if child and child.has_method('is_available'):
#				if not child.is_available(ship_parts):
#					return false
#		return true
	
	func _init(display_name_: String, hull_: PackedScene):
		display_name=display_name_
		hull=hull_
		assert(display_name)
		assert(hull)
		assert(hull is PackedScene)
	
	func get_stats() -> Dictionary:
		if not cached_stats:
			assemble_ship().queue_free()
		return cached_stats
	
	func clear_cached_stats():
		push_warning("ShipDesign "+str(display_name)+" clear_cached_stats")
		cached_stats=null
		cached_cost=-1.0
		not_visible = {}
	
	func cache_remove_instance_info():
		cached_stats.erase('rid')
		for i in range(len(cached_stats['weapons'])):
			cached_stats['weapons'][i]['node_path']=NodePath()
	
	func cost_of(scene: PackedScene) -> float:
		var resource_path = scene.resource_path
		var id = Commodities.ship_parts.by_name.get(resource_path,-1)
		if id<0:
			push_warning('No product for scene "'+str(resource_path)+'"')
			return 0.0
		var product = Commodities.ship_parts.all.get(id,null)
		return float(product[Commodities.Products.VALUE_INDEX] if product else 0.0)
	
	func assemble_part(body: Node, child: Node, skip_hidden: bool) -> bool:
#		var start = OS.get_ticks_msec()
		var part = get_child_with_name(child.name)
		if not part:
#			var duration = OS.get_ticks_msec()-start
#			if duration>1:
#				print("ShipDesign.assemble_part(skip_hidden="+str(skip_hidden)+") took "+str(duration)+"ms to do nothing (1)")
			return false
		elif part is MultiMount:
			if skip_hidden:
#				var duration = OS.get_ticks_msec()-start
#				if duration>1:
#					print("ShipDesign.assemble_part(skip_hidden="+str(skip_hidden)+") took "+str(duration)+"ms to skip a multimount")
				return false # multimount contents should never be shown
			var found = false
			for part_name in part.get_child_names():
				var content = part.get_child_with_name(part_name)
				assert(content is MultiMounted)
				var new_child_name = child.name+'_at_'+str(content.x)+'_'+str(content.y)
				var new_child: Node = game_state.universe.get_part(content.scene)
				if new_child!=null:
					new_child.item_offset_x = content.x
					new_child.item_offset_y = content.y
					new_child.transform = child.transform
					new_child.name = new_child_name
					var old_child = body.get_node_or_null(new_child_name)
					if old_child:
						body.remove_child(old_child)
						old_child.queue_free()
					body.add_child(new_child)
					found = true
#			var duration = OS.get_ticks_msec()-start
#			if duration>1:
#				print("ShipDesign.assemble_part(skip_hidden="+str(skip_hidden)+") took "+str(duration)+"ms to fill multimount "+str(child.name))
			return found
		elif part is Mounted:
			if skip_hidden and not_visible.has(child.name):
				return false # this part should not be shown, so don't instance it
			var new_child = game_state.universe.get_part(part.scene)
			new_child.transform = child.transform
			new_child.name = child.name
			child.replace_by(new_child)
			#body.remove_child(child)
			child.queue_free()
			#body.add_child(new_child)
#			var duration = OS.get_ticks_msec()-start
#			if duration>1:
#				print("ShipDesign.assemble_part(skip_hidden="+str(skip_hidden)+") took "+str(duration)+"ms to create part "+str(part.scene.resource_path))
			return true
#		var duration = OS.get_ticks_msec()-start
#		if duration>1:
#			print("ShipDesign.assemble_part(skip_hidden="+str(skip_hidden)+") took "+str(duration)+"ms to do nothing (2)")
		return false

	func assemble_body(): # -> Node or null
		var start = OS.get_ticks_msec()
		if not hull:
			push_error('assemble_ship: hull is null')
			return null
		var body = hull.instance()
		body.ship_display_name = display_name
		var _discard = body.get_item_slots()
		if body == null:
			push_error('assemble_ship: cannot instance scene: '+body)
			var duration = OS.get_ticks_msec()-start
			if duration>4:
				print("ShipDesign.assemble_body took "+str(duration)+"ms to fail")
			return null
		body.save_transforms()
		var duration = OS.get_ticks_msec()-start
		if duration>4:
			print("ShipDesign.assemble_body took "+str(duration)+"ms")
		return body

	func assemble_stats(body: Node, reassemble: bool):
		if reassemble and cached_stats:
			body.set_stats(cached_stats)
			body.update_stats()
			body.restore_combat_stats()
			return
		var stats = body.pack_stats(true)
		var _discard = body.set_cost(get_cost())
		if cargo:
			body.set_cargo(cargo)
		cached_stats = stats.duplicate(true)
		cache_remove_instance_info()

	func assemble_parts(body: Node, reassemble: bool,retain_hidden_mounts: bool) -> void:
#		var start = OS.get_ticks_msec()
		var skip_hidden: bool = reassemble and not retain_hidden_mounts
		for child in body.get_children():
			if assemble_part(body,child,skip_hidden) and skip_hidden and not_visible.has(child.name):
				body.remove_child(child)
				child.queue_free()
			#if not assemble_part(body,child,skip_hidden) and not retain_hidden_mounts:
#				var skip: bool = not_visible.has(child.name)
#				if not skip:
#					skip = not child is VisualInstance and not child is CollisionShape and \
#						not (child.has_method("keep_mount_in_space") and \
#						child.keep_mount_in_space() )
#				if skip:
#					not_visible[child.name]=1
#					body.remove_child(child)
#					child.queue_free()
#			elif child is CollisionShape and child.scale.y<10:
#				child.scale.y=10
#		var duration = OS.get_ticks_msec()-start
#		if duration>1:
#			print("ShipDesign.assemble_parts(skip_hidden="+str(skip_hidden)+") took "+str(duration)+"ms")

	func assemble_ship_setup_cargo_and_stats(body,reassemble):
#		var start = OS.get_ticks_msec()
		var stats = null
		if reassemble:
			body.set_stats(cached_stats)
		else:
			stats = body.pack_stats(true)
		var _discard = body.set_cost(get_cost())
		if cargo:
			body.set_cargo(cargo)
		#var duration = OS.get_ticks_msec()-start
#		if duration>1:
#			print("ShipDesign.assemble_parts took "+str(duration)+"ms")
		return stats
	
	func assemble_ship_remove_hidden_mounts(body,retain_hidden_mounts):
#		var start = OS.get_ticks_msec()
		for child in body.get_children():
			if child is VisualInstance and not child.get_script():
				continue # may be part of the ship, so keep it visible
			if child is CollisionShape:
				continue # need to collide
			if child.has_method('keep_mount_in_space') and child.keep_mount_in_space():
				continue # weapons stay visible if they want to
			# This is not visible in space, so remove it from the scene tree.
			not_visible[child.name]=1
			#print("Assemble Ship "+str(display_name)+": will remove "+str(child.name)+" from the scene tree.")
			if retain_hidden_mounts:
				body.remove_child(child)
				child.queue_free()
#		var duration = OS.get_ticks_msec()-start
#		if duration>1:
#			print("ShipDesign.assemble_ship took "+str(duration)+"ms")
	
	func assemble_ship(retain_hidden_mounts: bool = false) -> Spatial:
#		var start = OS.get_ticks_msec()
		var body = assemble_body()
		if not body:
			push_error("No body to assemble. Returning an empty Spatial")
#			var duration = OS.get_ticks_msec()-start
#			if duration>1:
#				print("ShipDesign.assemble_ship took "+str(duration)+"ms to fail")
			return Spatial.new()
		var reassemble = cached_stats!=null # true=already assembled design once
		assemble_parts(body,reassemble,retain_hidden_mounts)
		var stats = assemble_ship_setup_cargo_and_stats(body,reassemble)
		if not reassemble:
			assemble_ship_remove_hidden_mounts(body,retain_hidden_mounts)
		if not reassemble and not retain_hidden_mounts:
			cached_stats = stats.duplicate(true)
			cache_remove_instance_info()
#		var duration = OS.get_ticks_msec()-start
#		if duration>1:
#			if not reassemble:
#				print("ShipDesign.assemble_ship "+str(display_name)+" took "+str(duration)+
#					"ms to assemble a ship the first time (retain_hidden_mounts="+str(retain_hidden_mounts)+")")
#			else:
#				print("ShipDesign.assemble_ship "+str(display_name)+" took "+str(duration)+
#					"ms (retain_hidden_mounts="+str(retain_hidden_mounts)+")")
		return body

static func encode_ShipDesign(d: ShipDesign):
	return [ 'ShipDesign', d.display_name, encode_helper(d.hull), encode_children(d),
		( encode_helper(d.cargo.all) if d.cargo is Commodities.Products else null ) ]

static func decode_ShipDesign(v):
	if not v is Array or len(v)<3 or not v[0] is String or v[0]!='ShipDesign':
		return null
	var hull = decode_helper(v[2])
	if not hull:
		push_error('Ignoring invalid ship design and returning null')
		return null
	var result = ShipDesign.new(str(v[1]), hull)
	if len(v)>3:
		decode_children(result,v[3])
	if len(v)>4:
		var cargo_data = decode_helper(v[4])
		if cargo_data is Dictionary:
			result.cargo = Commodities.ManyProducts.new()
			result.cargo.add_products(cargo_data)
	return result



class UIState extends simple_tree.SimpleNode:
	var ui_state
	
	func is_UIState(): pass # for type detection; never called
	
	func _init(state):
		ui_state = state

static func encode_UIState(u: UIState):
	return [ 'UIState', u.ui_state ]

static func decode_UIState(v):
	if not v is Array or len(v)<2 or not v[0] is String or v[0]!='UIState':
		return null
	return UIState.new(decode_helper(v[1]))

class Fleet extends simple_tree.SimpleNode:
	var spawn_info: Dictionary = {}
	var display_name: String = 'Unnamed'
	var cached_stats = null
	func is_Fleet(): pass # for type detection; never called
	
	func _init(display_name_, spawn_info_ = {}):
		display_name = display_name_
		set_spawn_info(spawn_info_)
	func get_stats():
		if cached_stats==null:
			var result = { 'threat':0.0, 'cost':0.0 }
			for design_name in spawn_info:
				var design = game_state.ship_designs.get_node_or_null(design_name)
				var count = int(spawn_info[design_name])
				if design and count>0:
					var design_stats = design.get_stats()
					result['cost'] += design.get_cost()*count
					result['threat'] += design_stats.get('threat',0.0)*count
			cached_stats = result
		return cached_stats
	func get_threat():
		return get_stats().get('threat',0.0)
	func get_cost():
		return get_stats().get('cost',0.0)
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
	func spawn_count() -> int:
		var result = 0
		for count in spawn_info.values():
			result += count
		return result
	func as_dict() -> Dictionary:
		return spawn_info.duplicate(true)

static func encode_Fleet(f: Fleet):
	return [ 'Fleet', str(f.display_name), encode_helper(f.spawn_info) ]

static func decode_Fleet(v):
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



static func decode_InputEvent(data):
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

static func encode_InputEvent(event: InputEvent):
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


func save_places_as_json(prefix: String) -> bool:
	var encoded: Dictionary = encode_places()
	for encode_key in encoded:
		var filename = prefix+str(encode_key)+".json"
		var file: File = File.new()
		if file.open(filename, File.WRITE):
			push_error('Cannot open file '+filename+'!!')
			return false
		file.store_string(encoded[encode_key])
		file.close()
	return true

func load_places_from_json(prefix: String) -> bool:
	assert(children_.has('systems'))
	assert(children_.has('ship_designs'))
	assert(children_.has('fleets'))
	var all_encoded: Array = []
	var input_keys: Array = [ "factions", "fleets", "ship_designs", "systems", "ui", "flotsam", 'asteroids' ]
	var context = prefix+"*.json"
	for input_key in input_keys:
		var filename: String = prefix+str(input_key)+".json"
		var file: File = File.new()
		if file.open(filename, File.READ):
			printerr('Cannot open file '+filename+'!!')
			return false
		var encoded: String = file.get_as_text()
		file.close()
		all_encoded.append([encoded,filename])
	var system_name = null
	if Player and Player.system:
		system_name = Player.system.get_name()
	var success = decode_places(all_encoded,context)
	emit_signal('reset_system')
	if system_name:
		var system = game_state.systems.get_node_or_null(system_name)
		if system:
			Player.system = system
	return success



func decode_places(json_strings,context) -> bool:
	assert(children_.has('systems'))
	assert(children_.has('fleets'))
	assert(children_.has('ship_designs'))
	assert(children_.has('flotsam'))
	assert(children_.has('asteroids'))
	var content: Dictionary = {}
	for json_string_context in json_strings:
		var json_string: String = json_string_context[0]
		var file_context: String = json_string_context[1]
		var parsed: JSONParseResult = JSON.parse(json_string)
		if parsed.error:
			push_error(file_context+':'+str(parsed.error_line)+': '+parsed.error_string)
			return false
		var entry = decode_helper(parsed.result)
		if not entry is Dictionary:
			printerr(file_context+': error: can only load game data from a Dictionary!')
			return false
		if not entry:
			push_warning(file_context+': error: nothing in this file!')
		for key in entry:
			if content.has(key):
				push_warning(file_context+': error: key "'+str(key)+'" was specified in two game data files!')
			content[key] = entry[key]
	links.clear()

	
	for x in [ 'flotsam', 'asteroids' ]:
		var content_x = content[x]
		if content_x:
			content_x.set_name(x)
			var a = add_child(content_x)
			assert(a)
	flotsam = get_child_with_name('flotsam')
	assert(flotsam)
	asteroids = get_child_with_name('asteroids')
	assert(asteroids)
	
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
	
	var content_factions = content['factions']
	if content_factions:
		for child_name in content_factions.get_child_names():
			var child = content_factions.get_child_with_name(child_name)
			if child:
				content_factions.remove_child(child)
				var _discard = factions.add_child(child)
	
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

static func decode_helper(what,key=null):
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
		elif what[0] == 'Faction' and len(what)>1:
			return Factions.decode_Faction(what)
		elif what[0] == 'FactionList' and len(what)>1:
			return Factions.decode_FactionList(what)
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
		elif what[0] == 'ProductsNode':
			return decode_ProductsNode(what)
		elif what[0] == 'Flotsam':
			return decode_Flotsam(what)
		elif what[0] == 'AsteroidPalette':
			return decode_AsteroidPalette(what)
		elif what[0] == 'SimpleNode':
			if len(what)>1:
				var result = simple_tree.SimpleNode.new()
				if key:
					result.set_name(key)
				decode_children(result,what[1])
				return result
			else:
				push_error('Empty SimpleNode declaration')
		elif what[0]=='Resource' and len(what)>1:
			var loadme = str(what[1])
			if ResourceLoader.exists(loadme):
				return ResourceLoader.load(loadme)
			else:
				push_warning('No such resource: "'+loadme+'"')
				return null
	elif [TYPE_INT,TYPE_REAL,TYPE_STRING,TYPE_BOOL].has(typeof(what)):
		return what
	elif what==null:
		return what
	push_error('Unrecognized type encountered in decode_helper; returning null.')
	assert(false)
	return null



func encode_places() -> Dictionary:
	var result: Dictionary = {}
	for child_name in get_child_names():
		result[child_name] = encode_helper({child_name:get_child_with_name(child_name)})
	return result

static func encode_helper(what):
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
	elif what is Flotsam:
		return encode_Flotsam(what)
	elif what is AsteroidPalette:
		return encode_AsteroidPalette(what)
	elif what is Commodities.ProductsNode:
		return encode_ProductsNode(what)
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
		return null
	elif [TYPE_INT,TYPE_REAL,TYPE_STRING,TYPE_BOOL].has(typeof(what)):
		return what
	else:
		printerr('encode_helper: do not know how to handle object ',str(what))
		return null



static func make_key(id1: String, id2: String) -> Array:
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
static func string_for(selection) -> String:
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
