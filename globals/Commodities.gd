extends Node

var commodities: ManyProducts
var trading: Dictionary
var selected_commodity_index: int = -1

# Maybwe move this to game data files?
const population_names: Array = [ 'suvar', 'human' ]

const no_commodity: Array = [ 'nothing', 0, 0, 0, 0 ]

func select_no_commodity():
	selected_commodity_index=-1

func get_selected_commodity() -> Array:
	if commodities:
		return commodities.all.get(selected_commodity_index,no_commodity)
	return no_commodity

func select_commodity_with_name(product_name: String):
	selected_commodity_index=commodities.by_name.get(product_name,-1)

class Products extends Reference:
	var all: Dictionary = {} # mapping from ID to data for one product
	var by_name: Dictionary = {} # lookup table of product_name -> list of IDs
	var by_tag: Dictionary = {} # lookup table of tag -> list of IDs
	const NAME_INDEX: int = 0 # Index in all[id] of the product name
	const QUANTITY_INDEX: int = 1 # Index in all[id] of quantity
	const VALUE_INDEX: int = 2 # Index in all[id] of value
	const FINE_INDEX: int = 3 # Index in all[id] of fine
	const MASS_INDEX: int = 4 # Index in all[id] of mass
	const FIRST_TAG_INDEX: int = MASS_INDEX+1 # First index in all[id] of tags
	const index_type: Array = [ 'name', 'value', 'fine', 'quantity', 'mass' ]
	
	func clear():
		all={}
		by_name={}
		by_tag={}
	
	func dump() -> String:
		return 'Products[]'
	
	# Duplicate the `all` array, for storing the products in compressed form:
	func encode() -> Dictionary:
		return all.duplicate(true)
	
	# Return all IDs in the `include` set that are not in the `exclude` set
	# The `include` and `exclude` can have string tag names or int IDs.
	# The `include` and `exclude` can be anything that returns tags during
	# iteration. If they evaluate to false, they're unused.
	# If include is false, include all IDs, except those in `exclude`
	func ids_for_tags(_include, _exclude=null) -> PoolIntArray:
		return PoolIntArray()
	
	# Total mass of all specified products. Takes a list of ids or null.
	func get_mass(ids=null) -> float:
		var mass: float = 0.0
		if ids==null:
			ids=all.keys()
		for id in ids:
			var product = all[id]
			var product_mass = product[QUANTITY_INDEX]*product[MASS_INDEX]
			mass += max(0.0,product_mass)
		return mass
	
	# Return a new Products object that contains only the specified IDs.
	# Intended to be used with ids_for_tags.
	func make_subset(_ids: PoolIntArray):
		return Products.new()
	
	# Given the output of encode(), replace all data in this Product.
	func decode(_from: Dictionary) -> bool:
		return false
	
	func add_products_from(from,include,exclude,quantity_multiplier=null,
			value_multiplier=null,fine_multiplier=0):
		add_products(from,quantity_multiplier,value_multiplier,fine_multiplier,
			true,from.ids_for_tags(include,exclude))
	
	func add_products(_all_products, 
			_quantity_multiplier = null, _value_multiplier = null, _fine_multiplier = 0, 
			_skip_checks: bool = true, _keys_to_add = null):
		return false
	
	func randomize_costs(randseed: int,time: float):
		var ids=all.keys()
		ids.sort()
		for id in ids:
			seed(randseed+hash(all[id][NAME_INDEX]))
			var f = 0.0
			var w = 0.0
			var p = 1.0
			for i in range(3):
				p *= 0.75
				var w1 = (2.0*randf()-1.0)*p
				var w2 = (2.0*randf()-1.0)*p
				f += w1*sin(2*PI*time*(i+1)) + w2*(cos(2*PI*time*(i+1)))
				w += abs(w1)+abs(w2)
			all[id][VALUE_INDEX] = ceil(all[id][VALUE_INDEX]*(1.0 + 0.3*f/w))
	
	func apply_multiplier_list(multipliers: Dictionary):
		for tag in multipliers:
			if by_tag.has(tag):
				var quantity_value_fine = multipliers[tag]
				for id in by_tag[tag]:
					var product = all[id]
					if quantity_value_fine[0]>=0:
						product[QUANTITY_INDEX] *= quantity_value_fine[0]
					if quantity_value_fine[1]>=0:
						product[VALUE_INDEX] *= quantity_value_fine[1]
					if quantity_value_fine[2]>=0:
						product[FINE_INDEX] *= quantity_value_fine[2]
	
	func _apply_multipliers(old,new,quantity_multiplier,value_multiplier,
			fine_multiplier):
		if quantity_multiplier==null and value_multiplier==null and \
				fine_multiplier==null:
			return
		if value_multiplier!=null:
			if abs(value_multiplier)<1e-5:
				old[VALUE_INDEX] = 0
			elif value_multiplier<0:
				old[VALUE_INDEX] = min(old[VALUE_INDEX],
					-new[VALUE_INDEX]*value_multiplier)
			else:
				old[VALUE_INDEX] = max(old[VALUE_INDEX],
					new[VALUE_INDEX]*value_multiplier)
		if fine_multiplier!=null:
			if abs(fine_multiplier)<1e-5:
				old[FINE_INDEX] = 0
			elif fine_multiplier<0:
				old[FINE_INDEX] = min(old[FINE_INDEX],
					-new[FINE_INDEX]*fine_multiplier)
			else:
				old[FINE_INDEX] = max(old[FINE_INDEX],
					new[FINE_INDEX]*fine_multiplier)
		if quantity_multiplier!=null:
			if abs(quantity_multiplier)<1e-5:
				old[QUANTITY_INDEX] = 0
			elif quantity_multiplier<0:
				old[QUANTITY_INDEX] = min(old[QUANTITY_INDEX],
					-new[QUANTITY_INDEX]*quantity_multiplier)
			else:
				old[QUANTITY_INDEX] = max(old[QUANTITY_INDEX],
					new[QUANTITY_INDEX]*quantity_multiplier)

class OneProduct extends Products:
	const zero_pool: PoolIntArray = PoolIntArray([0])
	var product_name: String
	
	func clear():
		all={}
		by_name={}
		by_tag={}
		product_name=''
	
	func _init(product=null):
		if product!=null:
			set_product(product)
	
	func ids_for_tags(include, exclude=null) -> PoolIntArray:
		if include:
			for tag in include:
				if not by_tag.has(tag):
					return PoolIntArray()
		if exclude:
			for tag in exclude:
				if by_tag.has(tag):
					return PoolIntArray()
		return zero_pool
	
	func dump() -> String:
		return 'OneProduct['+str(all[0])+']'
	
	func set_product(product: Array):
		all = { 0:product.duplicate(true) }
		product_name = product[0]
		by_name = { product_name:0 }
		for itag in range(FIRST_TAG_INDEX,len(product)):
			by_tag[product[itag]] = [ 0 ]
	
	func add_products(all_products, 
			quantity_multiplier = null, value_multiplier = null, fine_multiplier = 0, 
			_skip_checks: bool = true, keys_to_add = null):
		# Checks are never skipped because we must ensure that only the
		# selected product is processed
		if keys_to_add!=null and not keys_to_add:
			return
		if not all_products.all:
			return
		if not all:
			# No product yet.
			var key
			if keys_to_add==null:
				key = all_products.last_id
			else:
				key = keys_to_add[0]
			set_product(all_products.all[key])
			_apply_multipliers(all[key],all_products.all[key],
				quantity_multiplier, value_multiplier, fine_multiplier)
		elif not all_products.by_name.has(product_name):
			push_warning('Product named "'+product_name+'" not in all_products')
			return false
		elif keys_to_add!=null:
			var has: bool = false
			for key in keys_to_add:
				if all_products.all.has(key) and all_products.all[key][0]==product_name:
					_apply_multipliers(all[key],all_products.all[key],
						quantity_multiplier, value_multiplier, fine_multiplier)
					has=true
					break
			if not has:
				push_warning('Product named "'+product_name+'" not in keys')
		return true

class ManyProducts extends Products:
	var last_id: int = -1 # last ID assigned to a product in `all`
	
	func clear():
		all={}
		by_name={}
		by_tag={}
		last_id=-1
	
	# Add a product the given information to `all`, `by_name`, and `by_tag`
	# Returns the new id or -1 on failure
	func add_product(product_name: String, intrinsic_value: float, 
			intrinsic_fine: float, typical_quantity: float, 
			mass_per_quantity: float, tags: Array) -> int:
		last_id += 1
		var id: int = last_id
		all[id] = [product_name,intrinsic_value,intrinsic_fine,typical_quantity,
			mass_per_quantity]+tags
		by_name[product_name] = id
		for tag in tags:
			if not tag is String or not tag:
				push_warning('In add_product, tags must be non-empty strings '
					+'(bad tag "'+str(tag)+'")')
			elif not by_tag.has(tag):
				by_tag[tag] = [ id ]
			else:
				by_tag[tag].append(id)
		return id
	
	func add_products(all_products,  # : Dictionary or Products
			quantity_multiplier = null, value_multiplier = null, fine_multiplier = 0, 
			skip_checks: bool = true, keys_to_add = null, zero_quantity_if_missing = false):
		var have_multipliers = (quantity_multiplier!=null or \
			value_multiplier!=null or fine_multiplier!=null)
		if keys_to_add==null:
			if all_products is Products:
				keys_to_add = all_products.all.keys()
			elif all_products is Dictionary:
				keys_to_add = all_products.keys()
			elif all_products is Array or all_products is PoolIntArray:
				keys_to_add = range(len(all_products))
			if all_products is Dictionary:
				keys_to_add = all_products
			else:
				keys_to_add = all_products.all
		for key in keys_to_add:
			var product
			if all_products is Products:
				product = all_products.all[key]
			else:
				product = all_products[key]
			if not skip_checks:
				# Discard invalid products.
				var bad: bool = false
				if not product is Array or len(product)<FIRST_TAG_INDEX:
					push_warning('In add_products, each array element must be an '
						+'Array with at least '+str(FIRST_TAG_INDEX)+' elements.')
					bad=true
				if not product[0] is String or not product[0]:
					push_warning('In add_products, names must be non-empty strings '
						+'(bad name "'+str(product[0])+'")')
					bad=true
				for i in range(1,FIRST_TAG_INDEX):
					if not product[i] is int and not product[i] is float:
						push_warning('In add_products, '+index_type[i]+' must be '
							+'int or float (bad "'+str(product[i])+'" at index '+str(i)+')')
						bad=true
				if bad:
					push_error('In add_products, ignoring product with key "'+str(key)+'"')
					continue
			
			# Do we already have this product?
			var id: int = by_name.get(product[0],-1)
			var qm = quantity_multiplier
			if id>=0:
				# Add information to existing product
				var have_tags: Array = all[id].slice(FIRST_TAG_INDEX,len(all[id]))
				for itag in range(FIRST_TAG_INDEX,len(product)):
					var tag=product[itag]
					if not skip_checks and (not tag is String or not tag):
						push_warning('In add_products, tags must be non-empty '
							+'strings (Ignoring bad tag "'+str(tag)+'".)')
					elif have_tags.find(tag)>=0:
						pass # tag already added
					elif not by_tag.has(tag):
						by_tag[tag] = [ id ]
					else:
						by_tag[tag].append(id)
			else:
				# Add a new product
				last_id += 1
				id = last_id
				all[id] = product.duplicate(true)
				if zero_quantity_if_missing:
					qm=0
				by_name[product[0]] = id
				for itag in range(FIRST_TAG_INDEX,len(product)):
					var tag = product[itag]
					if not skip_checks and (not tag is String or not tag):
						push_warning('In add_products, tags must be non-empty '
							+'strings (Ignoring bad tag "'+str(tag)+'".)')
					elif not by_tag.has(tag):
						by_tag[tag] = [ id ]
					else:
						by_tag[tag].append(id)
			if have_multipliers or qm!=null:
				_apply_multipliers(all[id],product,qm,value_multiplier,fine_multiplier)

		return false
	
	func remove_absent_products():
		for id in all.keys():
			var product=all.get(id,null)
			if product and product[QUANTITY_INDEX]<=0:
				var _discard = by_name.erase(product[NAME_INDEX])
				for itag in range(FIRST_TAG_INDEX,len(product)):
					var tag = product[itag]
					_discard = by_tag[tag].erase(id)
					if by_tag[tag].empty():
						_discard = by_tag.erase(tag)
				_discard = all.erase(id)
	
	# Remove the ID'd product from `all`, `by_name`, and `by_tag`
	func remove_product_id(id: int) -> bool:
		var entry = all.get(id,null)
		var _discard = all.erase(id)
		if not entry:
			return false
		var product_name = entry[0]
		_discard = by_name.erase(product_name)
		for itag in range(FIRST_TAG_INDEX,len(entry)):
			var tag = entry[itag]
			if by_tag.has(tag):
				_discard = by_tag[tag].erase(id)
				if by_tag[tag].empty():
					_discard = by_tag.erase(tag)
		return true
	
	func dump() -> String:
		var result = 'ManyProducts[\n'
		for key in all:
			result += ' '+str(key)+' => '+str(all[key])+'\n'
		return result + ']'
	
	# Duplicate the `all` array, for storing the products in compressed form:
	func encode() -> Dictionary:
		return all.duplicate(true)
	
	# Return all IDs in the `include` set that are not in the `exclude` set
	# The `include` and `exclude` can have string tag names or int IDs.
	# The `include` and `exclude` can be anything that returns tags during
	# iteration. If they evaluate to false, they're unused.
	# If include is false, include all IDs, except those in `exclude`
	func ids_for_tags(include, exclude=null) -> PoolIntArray:
		var universal_set: Array
		# Get the list of IDs to include in results:
		if not include:
			universal_set = all.keys()
		else:
			universal_set = []
			for tag in include: # Tag may be an int ID or String tag name
				if tag is String and by_tag.has(tag):
					universal_set += (by_tag[tag])
				elif tag is int:
					universal_set.append(tag)
		# Convert to a set for speed, and remove duplicates:
		var as_set = {}
		for id in universal_set:
			as_set[id] = 1
		# Remove IDs we were told to exclude:
		if exclude:
			for tag in exclude: # tag may be an int ID or String tag name
				if tag is String and by_tag.has(tag):
					for tag_id in by_tag[tag]:
						var _discard = as_set.erase(tag_id)
				elif tag is int:
					var _discard = as_set.erase(tag)
		# Store the result in a pool:
		return PoolIntArray(as_set.keys())
	
	# Return a new Products object that contains only the specified IDs.
	# Intended to be used with ids_for_tags.
	func make_subset(ids: PoolIntArray):
		var result = ManyProducts.new()
		for id in ids:
			if not all.has(id) or result.all.has(id):
				continue
			result.all[id]=all[id]
			result.by_name[all[id][0]] = id
			for itag in range(FIRST_TAG_INDEX,len(all[id])):
				var tag = all[id][itag]
				if not result.by_tag.has(tag):
					result.by_tag[tag] = [ id ]
				else:
					result.by_tag[tag].append(tag)
		return result
	
	# Given the output of encode(), replace all data in this Product.
	func decode(from: Dictionary):
		all = from.duplicate(true)
		by_name.clear()
		by_tag.clear()
		last_id = -1
		var all_ids: Array = all.keys()
		for id in all_ids:
			if id>last_id:
				last_id = id
			if len(all[id])<FIRST_TAG_INDEX:
				var _discard = all.erase(id)
			else:
				by_name[all[id][0]] = id
				for itag in range(FIRST_TAG_INDEX,len(all[id])):
					var tag = all[id][itag]
					if not by_tag.has(tag):
						by_tag[tag] = [ id ]
					else:
						by_tag[tag].append(id)
		return true


class ProducerConsumer extends Reference:
	func industry(_all_products: Products, _result: Products, _industrial_capacity: float):
		pass # What the planet produces or consumes, scaled by industrial capacity
	func population(_all_products: Products, _result: Products, _population: Dictionary):
		pass # What the population produces and consumes, regardless of infrastructure:


class SuvarConsumers extends ProducerConsumer:
	func population(products: Products, result: Products, population: Dictionary):
		var m = pow(population.get('suvar',0),0.333333)
		if not m: return
		result.add_products_from(products,['religous/terran/buddhism'],[],m*2,0.8,null)
		result.add_products_from(products,['religous/terran'],[],m,0.8,null)
		result.add_products_from(products,['consumables/terran'],[],m)
		result.add_products_from(products,['luxury/terran'],[],m,0.8)
		result.add_products_from(products,['intoxicant/terran'],[],m,null,1.4)
		result.add_products_from(products,['intoxicant/terran/suvar'],[],m,1.4,1.7)
		result.add_products_from(products,['dead/thinking'],[],m,1.2,1.5)
		result.add_products_from(products,['dead/sentient','live_sentient'],[],null,null,10)

class HumanConsumers extends ProducerConsumer:
	func population(products: Products, result: Products, population: Dictionary):
		var m = pow(population.get('human',0),0.333333)
		if not m: return
		result.add_products_from(products,
			['religious/terran','consumables/terran','luxury/terran'],[],m)
		result.add_products_from(products,['intoxicant/terran'],[],m,null,1.4)
		result.add_products_from(products,['intoxicant/terran/human'],[],m,1.4,1.4)
		result.add_products_from(products,['dead/sentient'],[],0,null,8)
		result.add_products_from(products,['live/sentient'],[],0,null,8)

class ManufacturingProcess extends ProducerConsumer:
	var consumes_tags: Array
	var produces_tags: Array
	var exclude_tags: Array
	func _init(consumes_tags_: Array,produces_tags_: Array,exclude_tags_):
		consumes_tags=consumes_tags_.duplicate()
		produces_tags=produces_tags_.duplicate()
		exclude_tags=exclude_tags_.duplicate()
	func industry(products: Products, result: Products, industry: float):
		var m = pow(industry,0.333333)
		if not m: return
		result.add_products_from(products,consumes_tags,exclude_tags,0.5*m,1.2,0)
		result.add_products_from(products,produces_tags,exclude_tags,3*m,-0.8,0)

class TerranIllegalTradeCenter extends ProducerConsumer:
	func population(products: Products, result: Products, population: Dictionary):
		var m = pow(population.get('suvar',0)+population.get('human',0),0.333333)
		result.add_products_from(products,[
			'intoxicant/terran','live/sentient/human','live/sentient/suvar'],['dead/sentient'],m)

class TerranTradeCenter extends ProducerConsumer:
	func population(products: Products, result: Products, population: Dictionary):
		var m = pow(population.get('suvar',0)+population.get('human',0),0.333333)
		result.add_products_from(products,[
			'religious/terran','consumables/terran','luxury/terran',
			'intoxicant/terran','manufactured/terran','raw_materials/metal',
			'raw_materials/gems'],['live/sentient','dead/sentient'],m)

func make_test_products() -> ManyProducts:
	var result = ManyProducts.new()
	var data = [
		# name, quantity, value, fine, density, tags
		[ 'catnip', 10, 100, 100, 1, 'intoxicant/terran', 'intoxicant/terran/suvar' ],
		[ 'heroin', 10, 300, 900, 1, 'intoxicant/terran', 'intoxicant/terran/human',
			'intoxicant/terran/suvar' ],
		[ 'iron', 10000, 1, 1, 5, 'raw_materials/metal' ],
		[ 'titanium', 3000, 8, 8, 5, 'raw_materials/metal' ],
		[ 'diamonds', 3, 50000, 50000, 1, 'raw_materials/gems', 'luxury/terran' ],
		[ 'rubies', 3, 20000, 20000, 1, 'raw_materials/gems', 'luxury/terran' ],
		[ 'weapon_parts', 10, 800, 800, 50, 'manufactured/defense', 'manufactured/terran' ],
		[ 'woodworking_tools', 10, 500, 500, 50, 'manufactured/industrial', 'manufactured/terran' ],
		[ 'tractors', 25, 4000, 4000, 1500, 'manufactured/farming', 'manufactured/terran' ],
		[ 'deep_core_drill', 10, 18000, 18000, 15000, 'manufactured/mining', 'manufactured/terran' ],
		[ 'jewelry', 7, 10000, 10000, 1, 'luxury/terran' ],
		[ 'hamburgers', 1000, 5, 100, 1, 'consumables/terran', 'consumables/terran/food', 'dead/thinking' ],
		[ 'human_slaves', 10, 10000, 1000, 100, 'slaves/terran', 'live/sentient', 'live/sentient/human' ],
		[ 'humanburgers', 10, 1000, 10000, 1, 'dead/sentient', 'dead/sentient/human' ],
		[ 'suvar_pelts', 10, 3000, 10000, 3, 'dead/sentient', 'dead/sentient/suvar' ],
	]
	result.add_products(data,null,null,null,false,range(len(data)))
	return result

func _init():
	commodities=make_test_products()
	trading={
		'terran_trade': TerranTradeCenter.new(),
		'terran_illegal': TerranIllegalTradeCenter.new(),
		'suvar': SuvarConsumers.new(),
		'human': HumanConsumers.new(),
		'terran_mining': ManufacturingProcess.new(
			['manufactured/mining'],
			['raw_materials/metal','raw_materials/gems'],
			['live/sentient','dead/sentient']),
		'terran_industrial': ManufacturingProcess.new(
			['raw_materials/metal','raw_materials/gems'],
			['manufactured/terran'],
			['live/sentient','dead/sentient']),
		'terran_food': ManufacturingProcess.new(
			['manufactured/farming'],
			['consumables/terran/food','intoxicant/terran'],
			['live/sentient','dead/sentient']),
	}
