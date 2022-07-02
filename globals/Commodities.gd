extends Node

const MARKET_TYPE_COMMODITIES: int = 0
const MARKET_TYPE_SHIP_PARTS: int = 1
const MARKET_TYPE_UNKNOWN: int = 2

var commodities: ManyProducts
var trading: Dictionary
var ship_parts: ManyProducts
var shipyard: Dictionary
var selected_commodity_index: int = -1
var selected_commodity_type: int = MARKET_TYPE_COMMODITIES

# Maybwe move this to game data files?
const population_names: Array = [ 'suvar', 'human', 'spiders' ]

const no_commodity: Array = [ 'nothing', 0, 0, 0, 0 ]

func select_no_commodity():
	selected_commodity_index = -1
	selected_commodity_type = MARKET_TYPE_COMMODITIES

func get_selected_commodity() -> Array:
	if selected_commodity_type==MARKET_TYPE_COMMODITIES and commodities:
		return commodities.all.get(selected_commodity_index,no_commodity)
	if selected_commodity_type==MARKET_TYPE_SHIP_PARTS and ship_parts:
		return ship_parts.all.get(selected_commodity_index,no_commodity)
	return no_commodity

func select_commodity_with_name(product_name: String,market_type=MARKET_TYPE_COMMODITIES):
	if market_type==MARKET_TYPE_COMMODITIES:
		selected_commodity_index = commodities.by_name.get(product_name,-1)
		selected_commodity_type = MARKET_TYPE_COMMODITIES
	if market_type==MARKET_TYPE_SHIP_PARTS:
		selected_commodity_index = ship_parts.by_name.get(product_name,-1)
		selected_commodity_type = MARKET_TYPE_SHIP_PARTS

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
	
	func duplicate(_deep):
		push_error('Subclass forgot to override duplicate()')
	
	func clear():
		all={}
		by_name={}
		by_tag={}
	
	func dump() -> String:
		return 'Products[]'
	
	# Duplicate the `all` array, for storing the products in compressed form:
	func encode() -> Dictionary:
		return all.duplicate(true)
	
	func has_quantity() -> bool:
		for id in all:
			var product = all.get(id,null)
			if product and product[QUANTITY_INDEX]>0:
				return true
		return false
	
	# Return all IDs in the `include` set that are not in the `exclude` set
	# The `include` and `exclude` can have string tag names or int IDs.
	# The `include` and `exclude` can be anything that returns tags during
	# iteration. If they evaluate to false, they're unused.
	# If include is false, include all IDs, except those in `exclude`
	func ids_for_tags(_include, _exclude=null) -> PoolIntArray:
		return PoolIntArray()
	
	# Total value of all specified products. Takes a list of ids or null.
	func get_value(ids=null):
		var value: float = 0.0
		if ids==null:
			ids=all.keys()
		for id in ids:
			var product = all[id]
			var product_value = product[QUANTITY_INDEX]*product[VALUE_INDEX]
			value += max(0.0,product_value)
		return value
	
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
	
	func copy():
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
	
	func remove_empty_products():
		var ids = all.keys()
		for id in ids:
			var product = all[id]
			if product[QUANTITY_INDEX]<= 0:
				var _ignore = all.erase(id)
				_ignore = by_name.erase(product[NAME_INDEX])
				for itag in range(FIRST_TAG_INDEX,len(product)):
					_ignore = by_tag[product[itag]].erase(id)
	
	func randomize_costs(randseed: int,time: float):
		var ids=all.keys()
		for id in ids:
			var product = all.get(id,null)
			if not product:
				continue
			var prod_hash: int = hash(product[NAME_INDEX])
			var scale = max(1.0,product[VALUE_INDEX])/max(1.0,product[MASS_INDEX])
			scale = clamp(scale,3.0,30.0)
			for ivar in [ VALUE_INDEX, QUANTITY_INDEX ]:
				seed(randseed+ivar*31337+prod_hash)
				var f = 0.0
				var w = 0.0
				var p = 1.0
				for i in range(3):
					p *= 0.75
					var w1 = (2.0*randf()-1.0)*p
					var w2 = (2.0*randf()-1.0)*p
					f += w1*sin(2*PI*time*(i+1)) + w2*(cos(2*PI*time*(i+1)))
					w += abs(w1)+abs(w2)
				var w3 = randf()
				var s = 0.08*pow(0.7,sqrt(w3))+0.15*pow(0.98,sqrt(w3))+0.02
				var final = 1.0+s*f/w
				if ivar==VALUE_INDEX:
					final = final/(final+scale)+scale/(scale+1)
				product[ivar] = int(ceil(product[ivar]*final))
	
	func randomly_erase_products():
		var ids=all.keys()
		for id in ids:
			var product = all.get(id,null)
			if product:
				var present: float = max(0.1,1.0-pow(0.7,log(product[QUANTITY_INDEX])))
				if randf()>present:
					product[QUANTITY_INDEX] = 0

	func apply_multiplier_list(multipliers: Dictionary):
		var scan_products: Dictionary = {}
		for tag in multipliers:
			if by_tag.has(tag):
				for id in by_tag[tag]:
					scan_products[id]=1
		for id in scan_products:
			var product = all.get(id,null)
			if product:
				var f_quantity=1.0
				var f_value=1.0
				var f_fine=1.0
				for itag in range(FIRST_TAG_INDEX,len(product)):
					var tag = product[itag]
					var mul = multipliers.get(tag,null)
					if mul:
						if mul[0]>=0: f_quantity*=mul[0]
						if mul[1]>=0: f_value*=mul[1]
						if mul[2]>=0: f_fine*=mul[2]
				var scale = max(1.0,product[VALUE_INDEX])/max(1.0,product[MASS_INDEX])
				scale = clamp(scale,3.0,30.0)
				f_quantity = f_quantity/(f_quantity+1.0)+1.0/2.0
				f_value = f_value/(f_value+scale)+scale/(scale+1)
				f_fine = f_fine/(f_fine+scale)+scale/(scale+1)
				product[QUANTITY_INDEX] = ceil(product[QUANTITY_INDEX]*f_quantity)
				product[VALUE_INDEX] = ceil(product[VALUE_INDEX]*f_value)
				product[FINE_INDEX] = ceil(product[FINE_INDEX]*f_fine)
#		for tag in multipliers:
#			if by_tag.has(tag):
#				var quantity_value_fine = multipliers[tag]
#				for id in by_tag[tag]:
#					var product = all[id]
#					if quantity_value_fine[0]>=0:
#						product[QUANTITY_INDEX] = ceil(product[QUANTITY_INDEX]*quantity_value_fine[0])
#					if quantity_value_fine[1]>=0:
#						product[VALUE_INDEX] = ceil(product[VALUE_INDEX]*quantity_value_fine[1])
#					if quantity_value_fine[2]>=0:
#						product[FINE_INDEX] = ceil(product[FINE_INDEX]*quantity_value_fine[2])
	
	func apply_multipliers(quantity_multiplier,value_multiplier,fine_multiplier):
		for id in all:
			var product = all.get(id,null)
			if product:
				_apply_multipliers(product,product,quantity_multiplier,
					value_multiplier,fine_multiplier)
	
	func _apply_multipliers(old,new,quantity_multiplier,value_multiplier,
			fine_multiplier):
		if quantity_multiplier==null and value_multiplier==null and \
				fine_multiplier==null:
			return
		if value_multiplier!=null:
			if abs(value_multiplier)<1e-12:
				old[VALUE_INDEX] = 0
			elif value_multiplier<0:
				old[VALUE_INDEX] = min(old[VALUE_INDEX],
					-new[VALUE_INDEX]*value_multiplier)
			else:
				old[VALUE_INDEX] = max(old[VALUE_INDEX],
					new[VALUE_INDEX]*value_multiplier)
		if fine_multiplier!=null:
			if abs(fine_multiplier)<1e-12:
				old[FINE_INDEX] = 0
			elif fine_multiplier<0:
				old[FINE_INDEX] = min(old[FINE_INDEX],
					-new[FINE_INDEX]*fine_multiplier)
			else:
				old[FINE_INDEX] = max(old[FINE_INDEX],
					new[FINE_INDEX]*fine_multiplier)
		if quantity_multiplier!=null:
			if abs(quantity_multiplier)<1e-12:
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
	
	func duplicate(deep=true):
		var p=OneProduct.new()
		p.all=all.duplicate(deep)
		p.by_name=by_name.duplicate(deep)
		p.by_tag=by_tag.duplicate(deep)
		p.product_name=product_name
		return p
	
	func copy():
		var result = OneProduct.new()
		if all:
			result.all = all.duplicate(true)
			result.by_name = by_name.duplicate(true)
			result.by_tag = by_tag.duplicate(true)
		result.product_name = product_name
		return result
	
	func _init(product=null):
		if product!=null:
			set_product(product)
	
	func ids_for_tags(include, exclude=null) -> PoolIntArray:
		if include:
			var found = false
			for tag in include:
				if by_tag.has(tag):
					found = true
					break
			if not found:
				return PoolIntArray()
		if exclude:
			for tag in exclude:
				if by_tag.has(tag):
					return PoolIntArray()
		return zero_pool
	
	func remove_empty_products():
		if all and all[0][QUANTITY_INDEX]<=0:
			clear()
	
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
		if not all_products.all:
			return
		if keys_to_add==null:
			if all_products is Products:
				keys_to_add = all_products.all.keys()
			elif all_products is Dictionary:
				keys_to_add = all_products.keys()
			elif all_products is Array:
				keys_to_add = range(len(all_products))
			else:
				keys_to_add = all_products.all
		if not keys_to_add:
			return
		if not all:
			# No product yet.
			var key = keys_to_add[0]
			set_product(all_products.all[key])
			_apply_multipliers(all[key],all_products.all[key],
				quantity_multiplier, value_multiplier, fine_multiplier)
		elif not all_products.by_name.has(product_name):
			push_warning('Product named "'+product_name+'" not in all_products')
			return false
		elif keys_to_add!=null:
			var has: bool = false
			for key in keys_to_add:
				if all_products.all.has(key) and all_products.all[key][NAME_INDEX]==product_name:
					_apply_multipliers(all[key],all_products.all[key],
						quantity_multiplier, value_multiplier, fine_multiplier)
					has=true
					break
			if not has:
				push_warning('Product named "'+product_name+'" not in keys')
		return true

class ManyProducts extends Products:
	var last_id: int = -1 # last ID assigned to a product in `all`
	
	func duplicate(deep = true):
		var p=ManyProducts.new()
		p.all=all.duplicate(deep)
		p.by_name=by_name.duplicate(deep)
		p.by_tag=by_tag.duplicate(deep)
		p.last_id=last_id
		return p
	
	func clear():
		all={}
		by_name={}
		by_tag={}
		last_id=-1
	
	func copy():
		var result = ManyProducts.new()
		if all:
			result.all = all.duplicate(true)
			result.by_name = by_name.duplicate(true)
			result.by_tag = by_tag.duplicate(true)
		result.last_id = last_id
		return result
	
	# Add a product the given information to `all`, `by_name`, and `by_tag`
	# Returns the new id or -1 on failure
	func add_product(product_name: String, intrinsic_value: float, 
			intrinsic_fine: float, typical_quantity: float, 
			mass_per_quantity: float, tags: Array) -> int:
		last_id += 1
		var id: int = last_id
		var product = []
		product.resize(FIRST_TAG_INDEX)
		product[NAME_INDEX] = product_name
		product[QUANTITY_INDEX] = typical_quantity
		product[VALUE_INDEX] = intrinsic_value
		product[FINE_INDEX] = intrinsic_fine
		product[MASS_INDEX] = mass_per_quantity
		product += tags
		all[id]=product
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
	
	func add_quantity_from(all_products,product_name: String,count = null,fallback=null):
		assert(count==null or count is int)
		
		var my_id=by_name.get(product_name,-1)
		if count!=null and my_id>=0:
			all[my_id][QUANTITY_INDEX] = max(0,all[my_id][QUANTITY_INDEX]+count)
			return
		
		var from_id=all_products.by_name.get(product_name,-1)
		var from_product=all_products.all.get(from_id,null)
		if not from_product and fallback!=null:
			from_id=fallback.by_name.get(product_name,-1)
			from_product=fallback.all.get(from_id,null)
		elif not from_product:
			push_warning('Could not find product named "'+str(product_name)+'" in all_products and no fallback was provided')
			assert(false)
		
		if not from_product:
			push_warning('No product to add for name "'+str(product_name)+'"')
			assert(false)
		elif my_id>=0: # count is null at this point
			all[my_id][QUANTITY_INDEX] += from_product[QUANTITY_INDEX]
		elif from_id>=0:
			last_id += 1
			all[last_id] = from_product.duplicate(true)
			by_name[product_name]=last_id
			for itag in range(FIRST_TAG_INDEX,len(from_product)):
				var tag = from_product[itag]
				if by_tag.has(tag):
					by_tag[tag].append(last_id)
				else:
					by_tag[tag]=[last_id]
			if count!=null:
				all[last_id][QUANTITY_INDEX] = max(0,count)
		else:
			push_warning('Could not find product "'+str(product_name)+'" in all_products, self, or fallback.')
			assert(false)
	
	func add_products(all_products,  # : Dictionary or Products or Array
			quantity_multiplier = null, value_multiplier = null, fine_multiplier = 0, 
			skip_checks: bool = true, keys_to_add = null, zero_quantity_if_missing = false):
		var have_multipliers = (quantity_multiplier!=null or \
			value_multiplier!=null or fine_multiplier!=null)
		if keys_to_add==null:
			if all_products is Products:
				keys_to_add = all_products.all.keys()
			elif all_products is Dictionary:
				keys_to_add = all_products.keys()
			elif all_products is Array:
				keys_to_add = range(len(all_products))
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
	
	func reduce_quantity_by(this_much):
		for id in this_much.all:
			var product = this_much.all.get(id,null)
			if product:
				var remove_quantity=max(0,product[QUANTITY_INDEX])
				if remove_quantity:
					var my_id = by_name.get(product[NAME_INDEX],-1)
					if my_id>=0:
						var my_product = all.get(my_id,null)
						if my_product:
							var my_quantity=max(0,my_product[QUANTITY_INDEX])
							my_product[QUANTITY_INDEX] = max(0,my_quantity-remove_quantity)
	
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
		result.last_id = last_id
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
					result.by_tag[tag].append(id)
		return result
	
	func remove_named_products(names,negate: bool = false):
		var remove = names if names is Array else names.by_name.keys()
		if negate:
			var negated = by_name.keys()
			for name in remove:
				var _discard = negated.erase(name)
			remove = negated
		for product_name in remove:
			var id = by_name.get(product_name,-1)
			if id>0:
				var _ignore
				var product = all.get(id,null)
				if product:
					_ignore = by_name.erase(product[NAME_INDEX])
					for itag in range(FIRST_TAG_INDEX,len(product)):
						var tag = product[itag]
						if by_tag.has(tag):
							_ignore = by_tag[tag].erase(id)
							if not by_tag[tag]:
								_ignore = by_tag.erase(tag)
				_ignore = all.erase(id)
	
	func ids_within(prod: Products) -> PoolIntArray:
		var ids = []
		for product_name in prod.by_name:
			var id = by_name.get(product_name,-1)
			if id>=0:
				ids.append(id)
		return PoolIntArray(ids)
	
	func ids_not_within(prod: Products) -> PoolIntArray:
		var ids = []
		for product_name in by_name:
			if prod.by_name.get(product_name,-1)<0:
				var id = by_name.get(product_name,-1)
				if id>=0:
					ids.append(id)
		return PoolIntArray(ids)
	
	# Given the output of encode(), replace all data in this Product.
	func decode(from: Dictionary):
		clear()
		# Godot turns the keys into Strings, so we need to convert back here:
		for godot_json_is_broken in from:
			var id = int(godot_json_is_broken)
			all[id] = from[godot_json_is_broken].duplicate()
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

func products_for_market(all_known_products,market_products,ship_products,
		product_pricer: Object,pricer_method: String,
		include_zero_value: bool = false) -> ManyProducts:
	
	# Find all products for sale that exist in the known set:
	var priced_ids: PoolIntArray = PoolIntArray()
	var forbidden_ids: PoolIntArray = PoolIntArray()
	for product_name in market_products.by_name:
		var market_id = market_products.by_name[product_name]
		var market_product = market_products.all[market_id]
		var known_id = all_known_products.by_name.get(product_name,-1)
		if known_id<0:
			continue
		elif not include_zero_value and market_product[Products.VALUE_INDEX]<=0:
			forbidden_ids.append(market_id)
		elif not include_zero_value and market_product[Products.QUANTITY_INDEX]<=0:
			continue
		else:
			priced_ids.append(market_id)
	var priced_products: ManyProducts = market_products.make_subset(priced_ids)
	
	# Find all ship cargo that exists in the known set but is not for sale here:
	var unpriced_ids: PoolIntArray = PoolIntArray()
	for product_name in ship_products.by_name:
		var known_product_id = all_known_products.by_name.get(product_name,-1)
		if known_product_id>=0:
			var ship_product = ship_products.all.get(ship_products.by_name.get(product_name,-1),null)
			if ship_product and ship_product[Products.QUANTITY_INDEX]>0:
				unpriced_ids.append(known_product_id)
	
	# If there aren't any new products in the ship, we're done:
	if not unpriced_ids.size():
		print('NO UNPRICED IDS')
		return priced_products
	
	# Get prices for all sellable products in the ship that are not for sale in market:
	var unpriced_products: ManyProducts = all_known_products.make_subset(unpriced_ids)
	product_pricer.call(pricer_method,unpriced_products)
	
	# Find all products whose sale value is greater than zero.
	# Sale values of zero or less indicate the product cannot be sold here.
	var allowed_ids: PoolIntArray = PoolIntArray()
	for product_name in unpriced_products.by_name:
		var product = unpriced_products.all.get(unpriced_products.by_name.get(product_name,-1),null)
		if product and product[Products.VALUE_INDEX]>0:
			allowed_ids.append(unpriced_products.by_name[product_name])
	
	# Add the sellable products from the ship that were not in the marketplace:
	var allowed_products: ManyProducts = unpriced_products.make_subset(allowed_ids)
	priced_products.add_products(allowed_products,0,null,null,true,null,false)
	
	if include_zero_value:
		# We're told to include all products that are forbidden here.
		unpriced_products.remove_named_products(allowed_products)
		priced_products.add_products(unpriced_products,0,0,null,true)
	
	# Return the list of all products that can be sold at this planet, which have
	# non-zero quantity in total between market and ship:
	return priced_products

class ProducerConsumer extends Reference:
	func industry(_all_products: Products, _result: Products, _industrial_capacity: float):
		pass # What the planet produces or consumes, scaled by industrial capacity
	func population(_all_products: Products, _result: Products, _population: Dictionary):
		pass # What the population produces and consumes, regardless of infrastructure:

class TerranGovernment extends ProducerConsumer:
	func population(products: Products, result: Products, _population: Dictionary):
		result.add_products_from(products,['dead/sentient','live/sentient'],[],0,0,1)
		result.add_products_from(products,['taboo/house_cat'],[],0,0,1)
		result.add_products_from(products,['deadly_drug/terran'],[],0,0,1)

class ForbidIntoxicants extends ProducerConsumer:
	func population(products: Products, result: Products, _population: Dictionary):
		result.add_products_from(products,['intoxicant/terran'],[],0,0,1)

class AllowCats extends ProducerConsumer:
	func population(products: Products, result: Products, population: Dictionary):
		var m = pow(population.get('suvar',0)+population.get('human',0)+population.get('spider',0),0.333333)
		result.add_products_from(products,['taboo/house_cat'],[],m)

class SuvarConsumers extends ProducerConsumer:
	func population(products: Products, result: Products, population: Dictionary):
		var m = pow(population.get('suvar',0),0.333333)
		if not m: return
		result.add_products_from(products,['religous/terran/buddhism'],[],m*2)
		result.add_products_from(products,
			['religious/terran','consumables/terran','durable/terran','pets/terran',
			'manufactured/transport'],[],0)
		result.add_products_from(products,['luxury/terran'],[],0,0.8)
		result.add_products_from(products,['intoxicant/terran/suvar'],[],0)

class HumanConsumers extends ProducerConsumer:
	func population(products: Products, result: Products, population: Dictionary):
		var m = pow(population.get('human',0),0.333333)
		if not m: return
		result.add_products_from(products,
			['religious/terran','consumables/terran','luxury/terran','durable/terran',
			'manufactured/transport'],[],0)
		result.add_products_from(products,['intoxicant/terran/human'],[],0,1.2)

class SpiderConsumers extends ProducerConsumer:
	func population(products: Products, result: Products, population: Dictionary):
		var m = pow(population.get('spider',0),0.333333)
		if not m: return
		result.add_products_from(products,
			['religious/terran', 'consumables/food/terran/spider' ],[],0)

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
		result.add_products_from(products,consumes_tags,exclude_tags,0)
		result.add_products_from(products,produces_tags,exclude_tags,3*m)

class TerranEaterTradeCenter extends ProducerConsumer:
	func population(products: Products, result: Products, population: Dictionary):
		var m = pow(population.get('suvar',0)+population.get('human',0)+population.get('spider',0),0.333333)
		result.add_products_from(products,['dead/sentient/terran','live/sentient/terran'],['slaves/rare'],m)

class TerranIllegalTradeCenter extends ProducerConsumer:
	func population(products: Products, result: Products, population: Dictionary):
		var m = pow(population.get('suvar',0)+population.get('human',0)+population.get('spider',0),0.333333)
		result.add_products_from(products,
			['intoxicant/terran','slaves/terran','live/thinking/house_cat'],
			['slaves/rare','dead/sentient'],m)

class TerranSlaveTradeCenter extends ProducerConsumer:
	func population(products: Products, result: Products, population: Dictionary):
		var m = pow(population.get('suvar',0)+population.get('human',0)+population.get('spider',0),0.333333)
		result.add_products_from(products,['slaves/terran'],['dead/sentient'],m)

class TerranTradeCenter extends ProducerConsumer:
	func industry(products: Products, result: Products, industry: float):
		var m = pow(industry,0.333333)
		if not m: return
		result.add_products_from(products,[
			'religious/terran','consumables/terran','luxury/terran','durable/terran','pets/terran',
			'intoxicant/terran','manufactured/terran','raw_materials/metal','pets/terran',
			'raw_materials/gems'],['live/sentient','dead/sentient','danger/highly_radioactive','taboo/house_cat'],m)

class SmallLaserTerranShipyard extends ProducerConsumer:
	func industry(all_products: Products, result: Products, _industrial_capacity: float):
		result.add_products_from(all_products,['terran'],['particle','kinetic','large','capital'])

class SmallParticleTerranShipyard extends ProducerConsumer:
	func industry(all_products: Products, result: Products, _industrial_capacity: float):
		result.add_products_from(all_products,['terran'],['laser','explosive','large','capital'])

class LargeTerranShipyard extends ProducerConsumer:
	func industry(all_products: Products, result: Products, _industrial_capacity: float):
		result.add_products_from(all_products,['terran'],[])

class ProductsNode extends simple_tree.SimpleNode:
	var products setget ,get_products #: ManyProducts or null
	var update_time: int
	func is_ProductsNode(): pass # used for type checking; never called
	func _init(products_=null,update_time_=-99999999):
		if products_:
			products=products_
		update_time=update_time_
	func get_products():
		if not products:
			products = ManyProducts.new()
		return products
	func age(now: int, scale: float) -> float:
		return scale*(update_time-now)
	func update(update: ManyProducts, now: int, dropoff: float, scale: float) -> void:
		var weight = clamp(pow(dropoff,scale*float(now-update_time)),0.0,1.0)
		var invweight = 1.0-weight
		var all_names: Array = update.by_name.keys() + products.by_name.keys()
		var name_set: Dictionary = {}
		for product_name in all_names:
			name_set[product_name]=1
		all_names = name_set.keys()
		var to_add: Array = []
		for product_name in all_names:
			var old_product = products.all.get(products.by_name.get(product_name,-1),null)
			var new_product = update.all.get(update.by_name.get(product_name,-1),null)
			if new_product!=null:
				if old_product!=null:
					for i in [ Products.VALUE_INDEX, Products.MASS_INDEX, Products.FINE_INDEX ]:
						old_product[i] = int(ceil(weight*old_product[i] + invweight*new_product[i]))
					old_product[Products.QUANTITY_INDEX] = int(max(0,round(
						weight*old_product[Products.QUANTITY_INDEX] +
						invweight*new_product[Products.QUANTITY_INDEX])))
				else:
					to_add.append(new_product)
		if to_add:
			products.add_products(to_add,1,1,1,true)
		products.remove_empty_products()
		update_time = now
	func decode_products(p: Dictionary):
		if not products:
			products = ManyProducts.new()
		products.decode(p)

func delete_old_products_impl(parent: simple_tree.SimpleNode, child: simple_tree.SimpleNode, cutoff: int):
	# Helper function for delete_old_products. Do not call directly
	# Deletes all nodes from child on down where a node and all of its
	# descendants have update_time<=cutoff. Anything that is not a
	# ProductsNode is assumed to be older than the cutoff time.
	var delete_node: bool = not ( child.has_method('is_ProductsNode') and child.update_time>cutoff)
	for grandchild_name in child.get_child_names():
		var grandchild = child.get_child_with_name(grandchild_name)
		if grandchild:
			# Only delete child if all grandchildren were deleted.
			delete_node = delete_old_products_impl(child,grandchild,cutoff) and delete_node
	if delete_node and not child.has_children():
		var _ignore = parent.remove_child(child)

func delete_old_products(root, cutoff: int):
	# Delete all descendant nodes where the node and all of its descendants
	# have update_time>cutoff. Anything that is not a ProductsNode is assumed
	# to be older than the cutoff time. The root is not deleted.
	# root is a simple_tree.SimpleNode, but godot's type checking is too stupid
	# to handle call checks of user-defined types in calls between top-level modules
	for child_name in root.get_child_names():
		var child = root.get_child_with_name(child_name)
		if child:
			delete_old_products_impl(root,child,cutoff)

func expand_tags(product_data: Array) -> Array:
	var result: Array = []
	for product in product_data:
		var result_product: Array = product.duplicate()
		var tags: Dictionary = {}
		for iarg in range(Products.FIRST_TAG_INDEX,len(product)):
			var whole_tag: String = product[iarg]
			var split_tag: Array = whole_tag.split('/',false)
			var tag: String = ''
			for subtag in split_tag:
				tag += ('/'+subtag) if tag else subtag
				if not tags.has(tag):
					tags[tag]=1
					result_product.append(tag)
		result.append(result_product)
	return result			
				

func shipyard_data_tables() -> ManyProducts:
	var result = ManyProducts.new()
	var data = [ # name, quantity, value, fine, density, tags
		[ 'res://weapons/IACivilian/AntiMissile2x2.tscn', 40, 13000, 13000, 0, 'antimissile', 'weapon', 'terran' ],
		[ 'res://weapons/IACivilian/AntiMissile3x3.tscn', 40, 32000, 32000, 0, 'antimissile', 'weapon', 'terran' ],
		[ 'res://weapons/IACivilian/DuteriumFluorideLaser.tscn', 40, 9000, 9000, 0, 'laser', 'weapon', 'terran', 'license/alliance_civilian' ],
		[ 'res://weapons/IACivilian/DuteriumFluorideLaserTurret.tscn', 25, 16000, 16000, 0, 'laser', 'weapon', 'terran', 'license/alliance_civilian' ],
		[ 'res://weapons/IACivilian/BlueMissileLauncher.tscn', 40, 13000, 13000, 0, 'explosive', 'homing', 'weapon', 'terran', 'license/alliance_civilian' ],
		[ 'res://weapons/IACivilian/BlueRapidMissileLauncher.tscn', 40, 29000, 29000, 0, 'explosive', 'homing', 'weapon', 'terran', 'license/alliance_civilian' ],
		[ 'res://weapons/IACivilian/GammaRayLaser.tscn', 40, 22000, 22000, 0, 'laser', 'weapon', 'terran', 'license/alliance_civilian' ],
		[ 'res://weapons/IACivilian/GreenMissileLauncher.tscn', 40, 26000, 26000, 0, 'explosive', 'homing', 'weapon', 'terran', 'license/alliance_civilian' ],
		[ 'res://weapons/IACivilian/GammaRayLaserTurret.tscn', 40, 39000, 39000, 0, 'laser', 'weapon', 'terran', 'license/alliance_civilian' ],
		[ 'res://weapons/IACivilian/PlasmaTurret.tscn', 40, 36000, 36000, 0, 'plasma', 'weapon', 'terran', 'license/alliance_advanced' ],
		[ 'res://weapons/IACivilian/PlasmaGun2x3.tscn', 40, 31000, 31000, 0, 'plasma', 'weapon', 'terran', 'license/alliance_advanced' ],
		[ 'res://weapons/IACivilian/PlasmaGun1x4.tscn', 40, 26000, 26000, 0, 'plasma', 'weapon', 'terran', 'license/alliance_advanced' ],
		[ 'res://weapons/IACivilian/PlasmaBallLauncher.tscn', 40, 54000, 54000, 0, 'plasma', 'homing', 'weapon', 'terran', 'license/alliance_advanced' ],
		[ 'res://weapons/Old/BigRedMissileLauncher.tscn', 25, 136000, 136000, 0, 'explosive', 'homing', 'weapon', 'terran', 'capital', 'license/alliance_military' ],
		[ 'res://weapons/FrontierMilitia/SpikeLauncher1x3.tscn', 40, 17000, 17000, 0, 'pierce', 'weapon', 'terran', 'license/frontier_militia' ],
		[ 'res://weapons/FrontierMilitia/SpikeLauncher1x4.tscn', 40, 29000, 29000, 0, 'pierce', 'weapon', 'terran', 'license/frontier_militia' ],
		[ 'res://weapons/FrontierMilitia/SpikeLauncher2x4.tscn', 40, 48000, 48000, 0, 'pierce', 'weapon', 'terran', 'large', 'license/frontier_militia' ],
		[ 'res://weapons/FrontierMilitia/SpikeLauncher3x4.tscn', 40, 81000, 81000, 0, 'pierce', 'weapon', 'terran', 'capital', 'license/frontier_militia' ],
		[ 'res://weapons/FrontierMilitia/SpikeLauncherTurret3x3.tscn', 40, 50000, 50000, 0, 'pierce', 'weapon', 'terran', 'license/frontier_militia' ],
		[ 'res://weapons/FrontierMilitia/SpikeLauncherTurret4x4.tscn', 40, 91000, 91000, 0, 'pierce', 'weapon', 'terran', 'capital', 'license/frontier_militia' ],
		[ 'res://weapons/FrontierMilitia/ElectronGun1x3.tscn', 40, 29000, 29000, 0, 'charge', 'weapon', 'terran', 'license/frontier_militia' ],
		[ 'res://weapons/FrontierMilitia/ElectronGun1x4.tscn', 40, 41000, 41000, 0, 'charge', 'weapon', 'terran', 'license/frontier_militia' ],
		[ 'res://weapons/FrontierMilitia/ElectronGun2x4.tscn', 40, 58000, 58000, 0, 'charge', 'weapon', 'terran', 'license/frontier_militia' ],
		[ 'res://weapons/FrontierMilitia/ElectronGun3x4.tscn', 40, 11000, 110000, 0, 'charge', 'weapon', 'terran', 'license/frontier_militia' ],
		[ 'res://weapons/FrontierMilitia/ElectronTurret3x3.tscn', 40, 61000, 61000, 0, 'charge', 'weapon', 'terran', 'license/frontier_militia' ],
		[ 'res://weapons/FrontierMilitia/ElectronTurret4x4.tscn', 40, 101000, 101000, 0, 'charge', 'weapon', 'terran', 'license/frontier_militia' ],
		[ 'res://weapons/FrontierMilitia/MagneticRailGun2x4.tscn', 40, 51000, 51000, 0, 'impact', 'weapon', 'terran', 'large', 'license/frontier_militia' ],
		[ 'res://weapons/FrontierMilitia/MagneticRailTurret.tscn', 40, 56000, 56000, 0, 'impact', 'weapon', 'terran', 'license/frontier_militia' ],
		[ 'res://weapons/FrontierMilitia/MagneticRailGun1x4.tscn', 40, 36000, 36000, 0, 'impact', 'weapon', 'terran', 'license/frontier_militia' ],
		[ 'res://weapons/FrontierMilitia/MagneticRailGun1x3.tscn', 40, 29000, 29000, 0, 'impact', 'weapon', 'terran', 'license/frontier_militia' ],
		[ 'res://weapons/FrontierMilitia/MassDriver.tscn', 40, 95000, 95000, 0, 'impact', 'weapon', 'terran', 'capital', 'license/frontier_militia' ],
		[ 'res://weapons/FrontierMilitia/MassDriverTurret.tscn', 40, 99000, 99000, 0, 'impact', 'weapon', 'terran', 'capital', 'license/frontier_militia' ],
		[ 'res://weapons/IAPolice/GreyMissileLauncher.tscn', 40, 59000, 59000, 0, 'explosive', 'homing', 'weapon', 'terran', 'large', 'license/alliance_police' ],
		[ 'res://weapons/IAPolice/RetributionMissileLauncher.tscn', 25, 94000, 94000, 0, 'explosive', 'homing', 'weapon', 'terran', 'capital', 'license/alliance_police' ],
		[ 'res://weapons/IAPolice/JusticeMissileLauncher.tscn', 25, 41000, 41000, 0, 'explosive', 'homing', 'weapon', 'terran', 'license/alliance_police' ],
		[ 'res://weapons/IAPolice/CyclotronTurret4x4.tscn', 40, 103000, 103000, 0, 'particle', 'weapon', 'terran', 'capital', 'license/alliance_police' ],
		[ 'res://weapons/IAPolice/CyclotronTurret3x3.tscn', 40, 55000, 55000, 0, 'particle', 'weapon', 'terran', 'large', 'license/alliance_police' ],
		[ 'res://weapons/IAPolice/LinearAccelerator3x4.tscn', 40, 95000, 95000, 0, 'particle', 'weapon', 'terran', 'capital', 'license/alliance_police' ],
		[ 'res://weapons/IAPolice/LinearAccelerator2x4.tscn', 40, 61000, 61000, 0, 'particle', 'weapon', 'terran', 'large', 'license/alliance_police' ],
		[ 'res://weapons/IAPolice/LinearAccelerator1x4.tscn', 40, 39000, 38000, 0, 'particle', 'weapon', 'terran', 'license/alliance_police' ],
		[ 'res://weapons/IAPolice/NuclearPumpedLaser1x4.tscn', 40, 38000, 38000, 0, 'laser', 'weapon', 'terran', 'license/alliance_police' ],
		[ 'res://weapons/IAPolice/NuclearPumpedLaser3x4.tscn', 40, 87000, 87000, 0, 'laser', 'weapon', 'terran', 'capital', 'license/alliance_police' ],
		[ 'res://weapons/IAPolice/NuclearPumpedLaser2x4.tscn', 40, 71000, 71000, 0, 'laser', 'weapon', 'terran', 'large', 'license/alliance_police' ],
		[ 'res://weapons/IAPolice/NuclearPumpedLaserTurret4x4.tscn', 25, 94000, 94000, 0, 'laser', 'weapon', 'terran', 'capital', 'license/alliance_police' ],
		[ 'res://weapons/IAPolice/NuclearPumpedLaserTurret3x3.tscn', 25, 53000, 53000, 0, 'laser', 'weapon', 'terran', 'large', 'license/alliance_police' ],
		[ 'res://equipment/defense/DefensiveScatterer.tscn', 40, 35000, 35000, 0, 'equipment', 'terran' ],
		[ 'res://equipment/defense/ReactiveArmor.tscn', 40, 45000, 45000, 0, 'equipment', 'terran' ],
		[ 'res://equipment/defense/GravityControlSystem.tscn', 40, 41000, 41000, 0, 'equipment', 'terran', 'licence/alliance_civilian' ],
		[ 'res://equipment/defense/ElectroMagneticDampener.tscn', 40, 46000, 46000, 0, 'equipment', 'terran', 'license/alliance_advanced' ],
		[ 'res://equipment/defense/EnvironmentalControlSystem.tscn', 40, 39000, 39000, 0, 'equipment', 'terran', 'license/alliance_civilian' ],
		[ 'res://equipment/defense/EntertainmentNetwork.tscn', 40, 31000, 31000, 0, 'equipment', 'terran', 'license/alliance_civilian' ],
		[ 'res://equipment/defense/AblativeBiogelExcreter.tscn', 40, 51000, 51000, 0, 'equipment', 'terran', 'license/alliance_advanced' ],
		[ 'res://equipment/defense/AstralShieldingPanels.tscn', 40, 48000, 48000, 0, 'equipment', 'terran', 'license/frontier_militia' ],
		[ 'res://equipment/defense/SelfHealingFoam.tscn', 40, 45000, 45000, 0, 'equipment', 'terran', 'license/frontier_militia' ],
		[ 'res://equipment/engines/FrontierEngine2x2.tscn', 40, 18000, 18000, 0, 'engine', 'terran/frontier', 'license/frontier_militia' ],
		[ 'res://equipment/engines/FrontierEngine2x4.tscn', 40, 36000, 36000, 0, 'engine', 'terran/frontier', 'license/frontier_militia' ],
		[ 'res://equipment/engines/FrontierEngine4x4.tscn', 40, 79000, 79000, 0, 'engine', 'terran/frontier', 'license/frontier_militia' ],
		[ 'res://equipment/engines/Engine2x2.tscn', 40, 11000, 11000, 0, 'engine', 'terran', 'licence/alliance_civilian' ],
		[ 'res://equipment/engines/Engine2x4.tscn', 40, 23000, 23000, 0, 'engine', 'terran', 'licence/alliance_civilian' ],
		[ 'res://equipment/engines/Engine4x4.tscn', 40, 47000, 47000, 0, 'engine', 'terran', 'large', 'licence/alliance_civilian' ],
		[ 'res://equipment/engines/FissionEngine.tscn', 40, 36000, 36000, 0, 'engine', 'terran', 'large', 'license/alliance_advanced' ],
		[ 'res://equipment/engines/FusionEngine.tscn', 40, 73000, 73000, 0, 'engine', 'terran', 'large', 'license/alliance_advanced' ],
		[ 'res://equipment/divinity/DivinityDrive.tscn', 40, 1, 1, 0, 'engine', 'terran' ],
		[ 'res://equipment/divinity/DivinityOrb.tscn', 40, 1, 1, 0, 'equipment', 'terran' ],
		[ 'res://equipment/engines/Hyperdrive.tscn', 40, 25000, 25000, 0, 'engine', 'terran' ],
		[ 'res://equipment/engines/EscapePodEngine.tscn', 40, 7000, 7000, 0, 'engine', 'terran', 'licence/alliance_civilian' ],
		[ 'res://equipment/engines/SmallHyperdrive.tscn', 40, 14000, 14000, 0, 'engine', 'terran' ],
		[ 'res://equipment/engines/SmallMultisystem.tscn', 40, 19000, 19000, 0, 'engine', 'terran', 'licence/alliance_civilian' ],
		[ 'res://equipment/engines/LargeMultisystem.tscn', 40, 41000, 41000, 0, 'engine', 'terran', 'licence/alliance_civilian' ],
		[ 'res://equipment/repair/Structure2x2.tscn', 40, 16000, 16000, 0, 'equipment', 'structure', 'terran' ],
		[ 'res://equipment/repair/FrontierRepair2x2.tscn', 40, 35000, 35000, 0, 'equipment', 'power', 'structure', 'terran', 'license/frontier_militia' ],
		[ 'res://equipment/repair/Shield1x3.tscn', 40, 24500, 24500, 0, 'equipment', 'shield', 'terran', 'licence/alliance_civilian' ],
		[ 'res://equipment/repair/Shield2x1.tscn', 40, 16000, 16000, 0, 'equipment', 'shield', 'terran', 'licence/alliance_civilian' ],
		[ 'res://equipment/repair/Shield1x1.tscn', 40, 7500, 7500, 0, 'equipment', 'shield', 'terran', 'licence/alliance_civilian' ],
		[ 'res://equipment/repair/FrontierShield1x2.tscn', 40, 29000, 29000, 0, 'equipment', 'shield', 'terran', 'license/frontier_militia' ],
		[ 'res://equipment/repair/ShieldCapacitors1x2.tscn', 40, 21000, 29000, 0, 'equipment', 'shield', 'terran', 'license/alliance_police' ],
		[ 'res://equipment/repair/Shield2x2.tscn', 40, 35000, 35000, 0, 'equipment', 'shield', 'terran', 'licence/alliance_civilian' ],
		[ 'res://equipment/repair/FrontierShield2x3.tscn', 40, 85000, 85000, 0, 'equipment', 'shield', 'terran', 'license/frontier_militia' ],
		[ 'res://equipment/repair/ShieldCapacitors2x3.tscn', 40, 65000, 85000, 0, 'equipment', 'shield', 'terran', 'license/alliance_police' ],
		[ 'res://equipment/repair/Shield3x3.tscn', 40, 79000, 79000, 0, 'equipment', 'shield', 'terran', 'large', 'licence/alliance_civilian' ],
		[ 'res://equipment/cargo/CargoBay1x2.tscn', 40, 6000, 6000, 0, 'equipment', 'cargo_bay', 'terran' ],
		[ 'res://equipment/cargo/CargoBay2x3.tscn', 40, 19000, 19000, 0, 'equipment', 'cargo_bay', 'terran' ],
		[ 'res://equipment/cargo/CargoBay3x4.tscn', 40, 40000, 40000, 0, 'equipment', 'cargo_bay', 'terran', 'large' ],
		[ 'res://equipment/power/TinyBioelectricGenerator.tscn', 40, 10000, 10000, 0, 'terran', 'equipment', 'power', 'organic' ],
		[ 'res://equipment/power/SmallBioelectricGenerator.tscn', 40, 19000, 19000, 0, 'terran', 'equipment', 'power', 'organic' ],
		[ 'res://equipment/power/MediumBioelectricGenerator.tscn', 40, 35000, 35000, 0, 'terran', 'equipment', 'power', 'organic' ],
		[ 'res://equipment/power/LargeBioelectricGenerator.tscn', 40, 72000, 72000, 0, 'terran', 'equipment', 'power', 'organic', 'large' ],
		[ 'res://equipment/power/SmallReactor.tscn', 40, 31000, 31000, 0, 'equipment', 'terran', 'power', 'license/alliance_advanced' ],
		[ 'res://equipment/power/MediumReactor.tscn', 40, 58000, 58000, 0, 'equipment', 'terran', 'power', 'license/alliance_advanced' ],
		[ 'res://equipment/power/LargeReactor.tscn', 40, 119000, 119000, 0, 'equipment', 'terran', 'power', 'large', 'license/alliance_advanced' ],
		[ 'res://equipment/cooling/AdiabaticDemagnitizationCooler.tscn', 40, 41000, 41000, 0, 'equipment', 'terran', 'cooling', 'license/alliance_advanced' ],
		[ 'res://equipment/cooling/SmallOpticalCooler.tscn', 40, 6000, 6000, 0, 'equipment', 'terran', 'cooling' ],
		[ 'res://equipment/cooling/LargeOpticalCooler.tscn', 40, 11000, 11000, 0, 'equipment', 'terran', 'cooling' ],
		[ 'res://equipment/cooling/OrganicNanofluidCoolant.tscn', 40, 31000, 31000, 0, 'equipment', 'terran', 'cooling', 'licence/alliance_civilian' ],
		[ 'res://ships/BannerShip/BannerShipHull.tscn', 3, 394000, 394000, 0, 'hull/civilian/advertisment', 'terran', 'large', 'license/alliance_military' ],
		[ 'res://ships/Police/Popoto.tscn', 9, 82000, 82000, 0, 'hull/combat/interceptor', 'terran', 'license/alliance_police' ],
		[ 'res://ships/Police/Bufeo.tscn', 4, 168000, 168000, 0, 'hull/combat/warship', 'terran', 'license/alliance_police' ],
		[ 'res://ships/Police/Orca.tscn', 2, 421000, 421000, 0, 'hull/combat/warship', 'terran', 'large', 'license/alliance_police' ],
		[ 'res://ships/Police/Ankylorhiza.tscn', 1, 1080000, 1080000, 0, 'hull/combat/capital', 'terran', 'capital', 'license/alliance_police' ],
		[ 'res://ships/FrontierMilitia/Eagle.tscn', 3, 305000, 305000, 0, 'hull/combat/warship', 'terran', 'license/frontier_militia' ],
		[ 'res://ships/FrontierMilitia/Condor.tscn', 1, 985000, 985000, 0, 'hull/combat/capital', 'terran', 'capital', 'license/frontier_militia' ],
		[ 'res://ships/FrontierMilitia/Peregrine.tscn', 12, 79000, 79000, 0, 'hull/combat/interceptor', 'terran', 'license/frontier_militia' ],
		[ 'res://ships/FrontierMilitia/Raven.tscn', 3, 128000, 128000, 0, 'hull/combat/warship', 'terran', 'license/frontier_militia' ],
		[ 'res://ships/SmallCivilian/Husky.tscn', 2, 235000, 235000, 0, 'hull/cargo/cargo', 'terran', 'license/alliance_advanced' ],
		[ 'res://ships/SmallCivilian/Qimmeq.tscn', 2, 61000, 61000, 0, 'hull/cargo/cargo', 'terran', 'license/alliance_civilian' ],
		[ 'res://ships/Starliner/Thoroughbred.tscn', 2, 475000, 475000, 0, 'hull/cargo/cargo', 'terran', 'license/alliance_advanced' ],
		[ 'res://ships/SmallCivilian/Samoyed.tscn', 2, 61000, 61000, 0, 'hull/cargo/cargo', 'terran', 'license/alliance_civilian' ],
		[ 'res://ships/CargoPodShips/Monopod.tscn', 2, 273000, 273000, 0, 'hull/cargo/container', 'terran', 'license/alliance_civilian' ],
		[ 'res://ships/CargoPodShips/Bipod.tscn', 2, 652000, 652000, 0, 'hull/cargo/container', 'terran', 'large', 'license/alliance_civilian' ],
		[ 'res://ships/CargoPodShips/Hexapod.tscn', 2, 845000, 845000, 0, 'hull/cargo/container', 'terran', 'capital', 'license/alliance_advanced' ],
	]
	# FIXME: Pregenerate this somehow:
	for datum in data:
		var resource_path = datum[Products.NAME_INDEX]
		var scene = load(resource_path)
		if scene:
			var state = scene.get_state()
			for i in range(state.get_node_property_count(0)):
				var property_name = state.get_node_property_name(0,i)
				if ['base_mass','add_mass','weapon_mass'].has(property_name):
					var mass = state.get_node_property_value(0,i)
					if mass>0:
						datum[Products.MASS_INDEX] = int(round(mass*1000)) # convert to kg
	result.add_products(expand_tags(data),null,null,null,false,range(len(data)))
	return result

func commodity_data_tables() -> ManyProducts:
	var result = ManyProducts.new()
	
	var data = [ # name, quantity, value, fine, density, tags
		
		# Intoxicants
		[ 'catnip', 1, 100, 100, 1, 'intoxicant/terran/suvar' ],
		[ 'spider_glitter', 1, 110, 100, 1, 'intoxicant/terran/spider' ],
		[ 'fine_wine', 1, 140, 100, 1, 'intoxicant/terran/human', 'intoxicant/terran/suvar' ],
		[ 'beer', 1, 30, 100, 1, 'intoxicant/terran/human', 'intoxicant/terran/suvar' ],
		[ 'magic_crystals', 1, 400, 100, 1, 'intoxicant/terran/human', 'intoxicant/terran/spider' ],
		[ 'peppy_pints', 1, 500, 100, 10, 'intoxicant/terran/human', 'intoxicant/terran/suvar' ],
		[ 'happy_powder', 1, 600, 900, 1, 'intoxicant/terran/human',
		  'intoxicant/terran/suvar', 'deadly_drug/terran/human' ],
		[ 'rainbow_tears', 1, 900, 900, 1, 'intoxicant/terran/human',
		  'intoxicant/terran/suvar', 'deadly_drug/terran/suvar' ],
		
		# Material prices for 1kg are based on Feb/Mar 2020 prices:
		#    max(3,ceil(us$/kg / 4))
		# Material fines are always 100
		# Base metals: quantity 200, mass 10kg
		# Medium-rarity metals: quantity 100, mass 10kg
		# Rare metals: quantity 30, mass 1
		[ 'iron', 200, 3, 100, 10, 'raw_materials/metal' ],
		[ 'copper', 200, 22, 100, 10, 'raw_materials/metal', 'raw_materials/jewelry_materials' ],
		[ 'nickel', 200, 41, 100, 10, 'raw_materials/metal' ],
		[ 'aluminum', 200, 5, 100, 10, 'raw_materials/metal' ],
		[ 'zinc', 200, 22, 100, 10, 'raw_materials/metal' ],
		[ 'lead', 200, 5, 100, 10, 'raw_materials/metal' ],
		
		[ 'cobalt', 100, 132, 100, 10, 'raw_materials/metal' ],
		[ 'titanium', 100, 64, 100, 10, 'raw_materials/metal' ],
		[ 'silver', 100, 139, 100, 10, 'raw_materials/metal', 'raw_materials/jewelry_materials' ],
		
		[ 'gold', 30, 938, 100, 1, 'raw_materials/metal/rare', 'raw_materials/jewelry_materials' ],
		[ 'platinum', 30, 624, 100, 1, 'raw_materials/metal/rare', 'raw_materials/jewelry_materials' ],
		[ 'iridium', 30, 2181, 100, 1, 'raw_materials/metal/rare' ],
		[ 'rhodium', 30, 16093, 100, 1, 'raw_materials/metal/rare' ],
		[ 'palladium', 30, 1291, 100, 1, 'raw_materials/metal/rare' ],
		[ 'ruthenium', 30, 2020, 100, 1, 'raw_materials/metal/rare' ],

		[ 'refined_uranium', 30, 10254, 100, 1, 'raw_materials/metal/highly_radioactive', 'danger/highly_radioactive' ],
		[ 'plutonium', 30, 19504, 100, 1, 'raw_materials/metal/highly_radioactive', 'danger/highly_radioactive' ],
		
		# Gems: 1kg, 300 fine. 
		# Mass includes protective and security packaging.
		# Price: max(200,real-world $/carat * 5)
		
		[ 'diamonds', 1, 100000, 300, 1, 'raw_materials/gems', 'luxury/terran' ],
		[ 'rubies', 3, 60000, 300, 1, 'raw_materials/gems', 'luxury/terran' ],
		[ 'alexandrite gems', 5, 35000, 300, 1, 'raw_materials/gems', 'luxury/terran' ],
		[ 'emeralds', 5, 24000, 300, 1, 'raw_materials/gems', 'luxury/terran' ],
		[ 'sapphires', 5, 20000, 300, 1, 'raw_materials/gems', 'luxury/terran' ],
		
		[ 'tourmaline_gems', 12, 25000, 300, 1, 'raw_materials/gems' ],
		[ 'spinel_gems', 12, 17500, 300, 1, 'raw_materials/gems' ],
		[ 'garnet_gems', 12, 12500, 300, 1, 'raw_materials/gems' ],
		[ 'tanzanite_gems', 12, 5000, 300, 1, 'raw_materials/gems' ],
		[ 'beryl_gems', 12, 4000, 300, 1, 'raw_materials/gems' ],
		[ 'zircon_gems', 12, 7500, 300, 1, 'raw_materials/gems' ],
		[ 'topaz_gems', 12, 7500, 300, 1, 'raw_materials/gems' ],
		[ 'aquamarine_gems', 12, 4000, 300, 1, 'raw_materials/gems' ],
		[ 'chrysoberyl_gems', 30, 2500, 300, 1, 'raw_materials/gems' ],
		[ 'amethysts', 12, 300, 300, 1, 'raw_materials/gems' ],
		[ 'garnet_gems', 12, 4000, 300, 1, 'raw_materials/gems' ],
		
		
		# Manufacturing: parts or bulk tools
		[ 'weapon_parts', 40, 800, 800, 250, 'manufactured/defense/terran', 'manufactured/terran' ],
		[ 'woodworking_tools', 40, 500, 500, 250, 'manufactured/industrial/terran', 'manufactured/terran' ],
		[ 'metalworking_tools', 40, 500, 500, 250, 'manufactured/industrial/terran', 'manufactured/terran' ],
		[ 'slaughterhouse_tools', 40, 500, 500, 250, 'manufactured/food/terran', 'manufactured/terran' ],
		[ 'gemcutter_tools', 40, 500, 500, 150, 'manufactured/luxury/terran', 'manufactured/terran' ],
		
		# Large, individual, equipment:
		[ 'tractor', 10, 4000, 4000, 1500, 'manufactured/farming/terran', 'manufactured/terran' ],
		[ 'hovercar', 10, 4000, 4000, 2500, 'manufactured/transport/terran', 'manufactured/terran' ],
		[ 'deep_core_drill', 1, 279000, 10000, 35000, 'manufactured/mining', 'manufactured/terran' ],
		[ 'mining_system', 3, 51000, 10000, 35000, 'manufactured/mining', 'manufactured/terran' ],
		[ 'transport_barge', 1, 85000, 10000, 21000, 'manufactured/transport/terran', 'manufactured/terran' ],
		[ 'grain_processor', 2, 58000, 10000, 19000, 'manufactured/farming/terran', 'manufactured/terran' ],
		[ 'ore_processor', 2, 38000, 10000, 24000, 'manufactured/mining', 'manufactured/terran' ],

		# Generic luxury goods:		
		[ 'jewelry', 12, 3500, 1000, 1, 'luxury/terran' ],
		[ 'expensive_jewelry', 5, 9500, 1000, 1, 'luxury/terran' ],
		[ 'statue', 12, 4000, 1000, 20, 'luxury/terran', 'taboo/human_depiction' ],
		[ 'hunting_trophy', 12, 4000, 1000, 20, 'luxury/terran', 'dead/thinking' ],
		
		# Consumables:
		[ 'surgical_supplies', 20, 200, 1000, 10, 'consumables/medical/terran', 'consumables/terran' ],
		[ 'emergency_medical_kits', 80, 150, 1000, 10, 'consumables/medical/terran', 'consumables/terran' ],
		[ 'beauty_supplies', 300, 80, 1000, 10, 'consumables/personal/terran', 'consumables/terran', ],
		[ 'baby_powder', 300, 80, 1000, 10, 'consumables/personal/terran', 'consumables/terran', ],
		[ 'vitamins', 300, 80, 1000, 10, 'consumables/personal/terran', 'consumables/medical/terran', 'consumables/terran', ],

		# Durable goods:
		[ 'claw_trimmers', 20, 80, 1000, 10, 'durable/personal/terran/suvar', 'durable/terran/suvar', ],
		[ 'automatic_cooking_system', 20, 80, 1000, 150, 'durable/personal/terran/suvar', 'durable/terran/suvar', ],
		
		# Food, processed or otherwise, sold in units of 50kg
		# except for special cases. Refrigeration or other
		# preservation mechanisms are included in price+mass.
		[ 'grains', 1000, 12, 100, 50, 'consumables/food/terran' ],
		[ 'vegetables', 1000, 19, 100, 50, 'consumables/terran', 'consumables/food/terran', 'dead/thinking' ],
		[ 'fruit', 1000, 22, 100, 50, 'consumables/terran', 'consumables/food/terran', 'dead/thinking' ],
		[ 'fish', 1000, 31, 100, 50, 'consumables/terran', 'consumables/food/terran', 'dead/thinking' ],
		[ 'flour', 1000, 14, 100, 50, 'consumables/terran', 'consumables/food/terran', 'dead/thinking' ],
		[ 'sugar', 1000, 11, 100, 50, 'consumables/terran', 'consumables/food/terran', 'dead/thinking' ],
		[ 'hamburgers', 1000, 39, 100, 50, 'consumables/food/terran', 'dead/thinking', 'taboo/dead_cow' ],
		[ 'pork', 1000, 29, 100, 50, 'consumables/food/terran', 'dead/thinking', 'taboo/dead_pig' ],
		[ 'steak', 1000, 51, 100, 50, 'consumables/terran', 'consumables/food/terran', 'dead/thinking', 'taboo/dead_cow' ],
		[ 'veal', 1000, 89, 100, 50, 'consumables/terran', 'consumables/food/terran', 'dead/thinking', 'taboo/dead_cow', 'consumables/luxury/food' ],
		[ 'goat_meat', 1000, 37, 100, 50, 'consumables/terran', 'consumables/food/terran', 'dead/thinking' ],
		[ 'cheese', 1000, 28, 100, 50, 'consumables/food/terran/terran', 'live_origin/thinking', 'taboo/milk_product' ],
		[ 'fine_cheese', 1000, 131, 100, 50, 'consumables/food/terran', 'live_origin/thinking', 'taboo/milk_product', 'consumables/luxury/food' ],
		[ 'milk', 1000, 28, 100, 50, 'consumables/food/terran', 'live_origin/thinking', 'taboo/milk_product' ],
		[ 'sogross_beast_meat', 1000, 45, 100, 50, 'consumables/terran', 'consumables/food/terran', 'dead/thinking' ],
		[ 'gondron_tentacles', 1000, 33, 100, 50, 'consumables/terran', 'consumables/food/terran', 'dead/feeling' ],
		[ 'elder_tograk_flowers', 1000, 19, 100, 50, 'consumables/terran', 'consumables/food/terran' ],
		[ 'yothii_branches', 1000, 9, 100, 50, 'consumables/terran', 'consumables/food/terran' ],
		[ 'glowing_tangii_mushrooms', 1000, 21, 100, 50, 'consumables/terran', 'consumables/food/terran' ],
		[ 'synthetic_meat', 1000, 17, 100, 50, 'consumables/terran', 'consumables/food/terran', 'taboo/synthetic_food' ],
		[ 'synthetic_cheese', 1000, 19, 100, 50, 'consumables/terran', 'consumables/food/terran', 'taboo/synthetic_food' ],
		[ 'synthetic_fruit', 1000, 13, 100, 50, 'consumables/terran', 'consumables/food/terran', 'taboo/synthetic_food' ],
		[ 'synthetic_vegetables', 1000, 12, 100, 50, 'consumables/terran', 'consumables/food/terran', 'taboo/synthetic_food' ],
		[ 'military_rations', 1000, 7, 100, 50, 'consumables/terran', 'consumables/food/terran', 'taboo/synthetic_food' ],

		# Pets and live food (for spiders)
		[ 'feeding_spider', 50, 51, 100, 90, 'consumables/terran', 'consumables/food/terran/spider', 'live/thinking', 'pets/terran' ],
		[ 'large_feeding_spider', 1, 1700, 100, 1200, 'consumables/food/terran/spider', 'live/thinking', 'consumables/luxury/food' ],
		[ 'house_cat', 12, 380, 2400, 20, 'live/thinking/house_cat', 'taboo/house_cat', 'pets/terran' ],
		[ 'dog', 12, 80, 1200, 40, 'live/thinking/dog', 'pets/terran' ],
		[ 'wingless_ooreon', 12, 80, 1200, 30, 'live/thinking', 'pets/terran' ],
		
		# Slaves, including food and life support:
		[ 'human_child_slave', 10, 8000, 1000, 150, 'slaves/terran/human', 'live/sentient', 'live/sentient/human' ],
		[ 'human_worker_slave', 30, 10000, 1000, 250, 'slaves/common', 'slaves/terran/human', 'live/sentient', 'live/sentient/human' ],
		[ 'human_skilled_slave', 10, 30000, 1000, 250, 'slaves/common', 'slaves/terran/human', 'live/sentient', 'live/sentient/human' ],
		[ 'human_mated_pair', 10, 25000, 1000, 250, 'slaves/common', 'slaves/terran/human', 'live/sentient', 'live/sentient/human' ],
		[ 'suvar_child_slave', 5, 8000, 1000, 100, 'slaves/common', 'slaves/terran/suvar', 'live/sentient', 'live/sentient/human' ],
		[ 'suvar_worker_slave', 5, 10000, 1000, 200, 'slaves/common', 'slaves/terran/suvar', 'live/sentient', 'live/sentient/human' ],
		[ 'suvar_skilled_slave', 5, 30000, 1000, 200, 'slaves/common', 'slaves/terran/suvar', 'live/sentient', 'live/sentient/human' ],
		[ 'suvar_child_male', 1, 35000, 1000, 150, 'slaves/common', 'slaves/terran/suvar', 'live/sentient', 'live/sentient/human' ],
		[ 'suvar_breeding_male', 1, 65000, 1000, 150, 'slaves/common', 'slaves/terran/suvar', 'live/sentient', 'live/sentient/human' ],
		
		# Exceptionally rare slaves, only available at select locations
		[ 'suvar_prime_slave', 1, 950000, 1000, 200, 'slaves/rare', 'slaves/terran/suvar', 'live/sentient', 'live/sentient/human' ],
		[ 'spider_slave', 1, 1240000, 1000, 1500, 'slaves/rare', 'slaves/terran/spider', 'live/sentient', 'live/sentient/human' ],
		[ 'ancient_spider_slave', 1, 4600000, 1000, 1500, 'slaves/rare', 'slaves/terran/spider', 'live/sentient', 'live/sentient/human' ],
		[ 'exotic_human_slave', 10, 110000, 1000, 200, 'slaves/rare', 'slaves/terran/human', 'live/sentient', 'live/sentient/human' ],
		
		# Highly-illegal items made from killing a sentient being
		[ 'human_skin_paper', 10, 1000, 10000, 1, 'dead/sentient/terran/human' ],
		[ 'human_bone_sculptures', 10, 13500, 10000, 1, 'dead/sentient/terran/human' ],
		[ 'suvar_bone_sculptures', 10, 28000, 10000, 1, 'dead/sentient/terran/suvar' ],
		[ 'spider_armor', 10, 28000, 10000, 1, 'dead/sentient/terran/spider' ],
		[ 'human_meat', 10, 1000, 10000, 1, 'dead/sentient/terran/human', 'consumables/food/terran' ],
		[ 'suvar_meat', 10, 2000, 10000, 1, 'dead/sentient/terran/suvar', 'consumables/food/terran' ],
		[ 'suvar_pelt', 10, 26000, 10000, 10, 'dead/sentient/terran/suvar' ],
		[ 'suvar_paw', 10, 3000, 10000, 3, 'dead/sentient/terran/suvar' ],
		[ 'spider_leg', 10, 8500, 10000, 3, 'dead/sentient/terran/suvar' ],
	]
	result.add_products(expand_tags(data),null,null,null,false,range(len(data)))
	return result

func _init():
	ship_parts = shipyard_data_tables()
	assert(ship_parts)
	commodities = commodity_data_tables()
	assert(commodities)
	shipyard={
		'small_laser_terran': SmallLaserTerranShipyard.new(),
		'small_particle_terran': SmallParticleTerranShipyard.new(),
		'large_terran': LargeTerranShipyard.new(),
	}
	trading={
		'terran_government': TerranGovernment.new(),
		'forbid_intoxicants': ForbidIntoxicants.new(),
		'allow_cats': AllowCats.new(),
		'suvar': SuvarConsumers.new(),
		'human': HumanConsumers.new(),
		'spiders': SpiderConsumers.new(),
		'terran_eaters': TerranEaterTradeCenter.new(),
		'terran_illegal': TerranIllegalTradeCenter.new(),
		'terran_slaver': TerranSlaveTradeCenter.new(),
		'terran_trade': TerranTradeCenter.new(),
		'luxury_manufacturing': ManufacturingProcess.new(
			['raw_materials/gems','raw_materials/jewelry_materials','manufactured/luxury/terran'],
			['luxury/terran'],
			['live/sentient','dead/sentient']),
		'terran_mining': ManufacturingProcess.new(
			['manufactured/mining/terran'],
			['raw_materials/metal','raw_materials/gems'],
			['live/sentient','dead/sentient']),
		'terran_pets': ManufacturingProcess.new(
			['consumables/food/terran'],
			['pets/terran','consumables/pet_care/terran','durable/pet_care/terran','manufactured/pet_care/terran'],
			['live/sentient','dead/sentient']),
		'terran_weapons': ManufacturingProcess.new(
			['raw_materials/metal','raw_materials/gems','manufactured/industrial/terran'],
			['manufactured/defense/terran'],
			['live/sentient','dead/sentient']),
		'terran_industrial': ManufacturingProcess.new(
			['raw_materials/metal','raw_materials/gems'],
			['manufactured/terran'],
			['live/sentient','dead/sentient']),
		'terran_food': ManufacturingProcess.new(
			['manufactured/farming/terran'],
			['consumables/food/terran','intoxicant/terran'],
			['live/sentient','dead/sentient']),
	}
