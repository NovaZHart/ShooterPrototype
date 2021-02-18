extends Node

var commodities: ManyProducts
var trading: Dictionary
var selected_commodity_index: int = -1

const no_commodity: Array = [ 'nothing', 0, 0, 0, 0 ]

func get_selected_commodity() -> Array:
	if commodities:
		return commodities.all.get(selected_commodity_index,no_commodity)
	return no_commodity

class Products extends Reference:
	var all: Dictionary = {} # mapping from ID to data for one product
	var by_name: Dictionary = {} # lookup table of product_name -> list of IDs
	var by_tag: Dictionary = {} # lookup table of tag -> list of IDs
	const NAME_INDEX: int = 0 # Index in all[id] of the product name
	const VALUE_INDEX: int = 1 # Index in all[id] of value
	const FINE_INDEX: int = 2 # Index in all[id] of fine
	const QUANTITY_INDEX: int = 3 # Index in all[id] of quantity
	const MASS_INDEX: int = 4 # Index in all[id] of mass
	const FIRST_TAG_INDEX: int = MASS_INDEX+1 # First index in all[id] of tags
	const index_type: Array = [ 'name', 'value', 'fine', 'quantity', 'mass' ]
	
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
	
	# Return a new Products object that contains only the specified IDs.
	# Intended to be used with ids_for_tags.
	func make_subset(_ids: PoolIntArray):
		return Products.new()
	
	# Given the output of encode(), replace all data in this Product.
	func decode(_from: Dictionary) -> bool:
		return false
	
	func add_products(_all_products, 
			_quantity_multiplier = null, _value_multiplier = null, _fine_multiplier = 0, 
			_skip_checks: bool = true, _keys_to_add = null):
		return false

class OneProduct extends Products:
	const zero_pool: PoolIntArray = PoolIntArray([0])
	var product_name: String
	
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
		
		if not all:
			# No product yet.
			var key
			if keys_to_add==null:
				key = all_products.last_id
			else:
				key = keys_to_add[0]
			set_product(all_products.all[key])
		elif not all_products.by_name.has(product_name):
			push_warning('Product named "'+product_name+'" not in all_products')
			return false
		elif keys_to_add!=null:
			var has: bool = false
			for key in keys_to_add:
				if all_products[key][0]==product_name:
					has=true
					break
			if not has:
				push_warning('Product named "'+product_name+'" not in keys')
		if value_multiplier!=null:
			if abs(value_multiplier)<1e-5:
				all[0][VALUE_INDEX] = 0
			elif value_multiplier<0:
				all[0][VALUE_INDEX] = max(all[0][VALUE_INDEX],
					-all[0][VALUE_INDEX]*value_multiplier)
			else:
				all[0][VALUE_INDEX] = max(all[0][VALUE_INDEX],
					all[0][VALUE_INDEX]*value_multiplier)
		if fine_multiplier!=null:
			if abs(fine_multiplier)<1e-5:
				all[0][FINE_INDEX] = 0
			elif fine_multiplier<0:
				all[0][FINE_INDEX] = min(all[0][FINE_INDEX],
					-all[0][FINE_INDEX]*fine_multiplier)
			else:
				all[0][FINE_INDEX] = max(all[0][FINE_INDEX],
					all[0][FINE_INDEX]*fine_multiplier)
		if quantity_multiplier!=null:
			if abs(quantity_multiplier)<1e-5:
				all[0][QUANTITY_INDEX] = 0
			elif quantity_multiplier<0:
				all[0][QUANTITY_INDEX] = min(all[0][QUANTITY_INDEX],
					-all[0][QUANTITY_INDEX]*quantity_multiplier)
			else:
				all[0][QUANTITY_INDEX] = max(all[0][QUANTITY_INDEX],
					all[0][QUANTITY_INDEX]*quantity_multiplier)
		return true

class ManyProducts extends Products:
	var last_id: int = -1 # last ID assigned to a product in `all`
	
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
	
	func add_products(all_products, 
			quantity_multiplier = null, value_multiplier = null, fine_multiplier = 0, 
			skip_checks: bool = true, keys_to_add = null):
		if keys_to_add==null:
			if all_products is Products:
				keys_to_add = all_products.all.keys()
			elif all_products is Dictionary:
				keys_to_add = all_products.keys()
			elif all_products is Array:
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
			if value_multiplier!=null:
				if abs(value_multiplier)<1e-5:
					all[id][VALUE_INDEX] = 0
				elif value_multiplier<0:
					all[id][VALUE_INDEX] = max(all[id][VALUE_INDEX],
						-all[id][VALUE_INDEX]*value_multiplier)
				else:
					all[id][VALUE_INDEX] = max(all[id][VALUE_INDEX],
						all[id][VALUE_INDEX]*value_multiplier)
			if fine_multiplier!=null:
				if abs(fine_multiplier)<1e-5:
					all[id][FINE_INDEX] = 0
				elif fine_multiplier<0:
					all[id][FINE_INDEX] = min(all[id][FINE_INDEX],
						-all[id][FINE_INDEX]*fine_multiplier)
				else:
					all[id][FINE_INDEX] = max(all[id][FINE_INDEX],
						all[id][FINE_INDEX]*fine_multiplier)
			if quantity_multiplier!=null:
				if abs(quantity_multiplier)<1e-5:
					all[id][QUANTITY_INDEX] = 0
				elif quantity_multiplier<0:
					all[id][QUANTITY_INDEX] = min(all[id][QUANTITY_INDEX],
						-all[id][QUANTITY_INDEX]*quantity_multiplier)
				else:
					all[id][QUANTITY_INDEX] = max(all[id][QUANTITY_INDEX],
						all[id][QUANTITY_INDEX]*quantity_multiplier)
		return false
	
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
				_discard = by_tag[tag].erase(product_name)
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
					universal_set.append(by_tag[tag])
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
						var _discard = as_set.remove(tag_id)
				elif tag is int:
					var _discard = as_set.remove(tag)
		# Store the result in a pool:
		return PoolIntArray(as_set.keys())
	
	# Return a new Products object that contains only the specified IDs.
	# Intended to be used with ids_for_tags.
	func make_subset(ids: PoolIntArray):
		var result = Products.new()
		for id in ids:
			if not all.has(id) or result.all.has(id):
				continue
			result.all.append(all[id])
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
		var m = pow(population.get('races/suvar',0),0.333333)
		if not m: return
		result.add_products(products.ids_for_tags(['religous/terran/buddhism']),m*2,0.8,null)
		result.add_products(products.ids_for_tags(['religous/terran']),m,0.8,null)
		result.add_products(products.ids_for_tags(['consumables/terran']),m)
		result.add_products(products.ids_for_tags(['luxury/terran']),m,0.8)
		result.add_products(products.ids_for_tags(['intoxicant/terran']),m,null,1.4)
		result.add_products(products.ids_for_tags(['intoxicant/terran/suvar']),m,1.4,1.7)
		result.add_products(products.ids_for_tags(['dead/thinking']),m,1.2,1.5)
		result.add_products(products.ids_for_tags(['dead/sentient','live_sentient']),null,null,10)

class HumanConsumers extends ProducerConsumer:
	func population(products: Products, result: Products, population: Dictionary):
		var m = pow(population.get('races/human',0),0.333333)
		if not m: return
		result.add_products(products.ids_for_tags(
			['religious/terran','consumables/terran','luxury/terran']),m)
		result.add_products(products.ids_for_tags(['intoxicant/terran']),m,null,1.4)
		result.add_products(products.ids_for_tags(['intoxicant/terran/human']),m,1.4,1.4)
		result.add_products(products.ids_for_tags(['dead/sentient']),0,null,8)
		result.add_products(products.ids_for_tags(['live/sentient']),0,null,8)

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
		result.add_products(products.ids_for_tags(consumes_tags,exclude_tags),0.5*m,1.2,0)
		result.add_products(products.ids_for_tags(produces_tags,exclude_tags),3*m,-0.8,0)

class TerranIllegalTradeCenter extends ProducerConsumer:
	func population(products: Products, result: Products, population: Dictionary):
		var m = pow(population.get('races/suvar',0)+population.get('races/human',0),0.333333)
		result.add_products(products.ids_for_tags([
			'intoxicant/terran','live/sentient/human','live/sentient/suvar']),m)

class TerranTradeCenter extends ProducerConsumer:
	func population(products: Products, result: Products, population: Dictionary):
		var m = pow(population.get('races/suvar',0)+population.get('races/human',0),0.333333)
		result.add_products(products.ids_for_tags([
			'religious/terran','consumables/terran','luxury/terran',
			'intoxicant/terran','manufactured/terran','raw_materials/metal',
			'raw_materials/gems'],['live/sentient','dead/sentient']),m)

func make_test_products() -> ManyProducts:
	var result = ManyProducts.new()
	var data = [
		[ 'catnip', 100, 100, 10, 1, 'intoxicant/terran', 'intoxicant/terran/suvar' ],
		[ 'heroin', 300, 900, 10, 1, 'intoxicant/terran', 'intoxicant/terran/human',
			'intoxicant/terran/suvar' ],
		[ 'iron', 1, 1, 10000, 5, 'raw_materials/metal' ],
		[ 'titanium', 8, 8, 3000, 5, 'raw_materials/metal' ],
		[ 'diamonds', 50000, 50000, 3, 1, 'raw_materials/gems', 'luxury/terran' ],
		[ 'rubies', 20000, 20000, 3, 1, 'raw_materials/gems', 'luxury/terran' ],
		[ 'weapon_parts', 800, 800, 10, 50, 'manufactured/defense', 'manufactured/terran' ],
		[ 'woodworking_tools', 500, 500, 10, 50, 'manufactured/industrial', 'manufactured/terran' ],
		[ 'tractors', 4000, 4000, 25, 1500, 'manufactured/farming', 'manufactured/terran' ],
		[ 'deep_core_drill', 18000, 18000, 10, 15000, 'manufactured/mining', 'manufactured/terran' ],
		[ 'jewelry', 10000, 10000, 7, 1, 'luxury/terran' ],
		[ 'hamburgers', 5, 100, 100, 1, 'consumables/terran', 'consumables/terran/food', 'dead/thinking' ],
		[ 'human_slaves', 10000, 1000, 10, 100, 'slaves/terran', 'live/sentient', 'live/sentient/human' ],
		[ 'humanburgers', 1000, 10000, 10, 1, 'dead/sentient', 'dead/sentient/human' ],
		[ 'suvar_pelts', 3000, 10000, 10, 3, 'dead/sentient', 'dead/sentient/suvar' ],
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
