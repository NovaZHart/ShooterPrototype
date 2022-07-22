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

func select_no_commodity():
	selected_commodity_index = -1
	selected_commodity_type = MARKET_TYPE_COMMODITIES

func get_selected_commodity():
	if selected_commodity_type==MARKET_TYPE_COMMODITIES and commodities:
		return commodities.by_name.get(selected_commodity_index,null)
	if selected_commodity_type==MARKET_TYPE_SHIP_PARTS and ship_parts:
		return ship_parts.by_name.get(selected_commodity_index,null)
	return null

func select_commodity_with_name(product_name: String,market_type=MARKET_TYPE_COMMODITIES):
	if market_type==MARKET_TYPE_COMMODITIES:
		selected_commodity_index = commodities.by_name.get(product_name,-1)
		selected_commodity_type = MARKET_TYPE_COMMODITIES
	if market_type==MARKET_TYPE_SHIP_PARTS:
		selected_commodity_index = ship_parts.by_name.get(product_name,-1)
		selected_commodity_type = MARKET_TYPE_SHIP_PARTS

class Product extends Reference:
	var name: String = "**MISSING*NAME**"
	var quantity: float = 0.0
	var value: float = 0.0
	var fine: float = 0.0
	var mass: float = 0.0
	var tags: Dictionary = {}
	
	func _init(name_: String="**MISSING*NAME**",quantity_: float=0,value_: float=0.0,
			fine_: float=0.0,mass_: float=0.0,tags_=null):
		name=name_
		quantity=quantity_
		value=value_
		fine=fine_
		mass=mass_
		for tag in tags_:
			tags[str(tag)] = 1
		if name=='vitamins':
			assert(value>0)

	func expand_tags():
		for whole_tag in tags.keys():
			var split_tag: Array = whole_tag.split('/',false)
			var tag: String = ''
			for subtag in split_tag:
				tag += ('/'+subtag) if tag else subtag
				tags[tag]=1

	func encode() -> Array:
		return [ name,quantity,value,fine,mass ] + tags.keys()

	func decode(from) -> bool:
		if(len(from)<5):
			push_warning("Tried to decode a product from an array that was too small ("+str(len(from))+"<5)")
			return false
		name=str(from[0])
		quantity=max(0.0,float(from[1]))
		value=max(0.0,float(from[2]))
		fine=max(0.0,float(from[3]))
		mass=max(0.0,float(from[4]))
		for i in range(5,len(from)):
			tags[str(from[i])] = 1
		return true

	func is_Product(): pass # Never called; must only exist

	func duplicate(deep: bool = true):
		if deep:
			return Product.new(name,quantity,value,fine,mass,tags)
		else:
			var p = Product.new(name,quantity,value,fine,mass)
			p.tags = tags
			return p

	func apply_multiplier_list(multipliers: Dictionary):
		var f_quantity=1.0
		var f_value=1.0
		var f_fine=1.0
		for tag in tags:
			var mul = multipliers.get(tag,null)
			if mul:
				if mul[0]>=0: f_quantity*=mul[0]
				if mul[1]>=0: f_value*=mul[1]
				if mul[2]>=0: f_fine*=mul[2]
		var scale = max(1.0,value)/max(1.0,mass)
		scale = clamp(scale,3.0,30.0)
		f_quantity = f_quantity/(f_quantity+1.0)+1.0/2.0
		f_value = f_value/(f_value+scale)+scale/(scale+1)
		f_fine = f_fine/(f_fine+scale)+scale/(scale+1)
		quantity = ceil(quantity*f_quantity)
		value = ceil(value*f_value)
		fine = ceil(fine*f_fine)
	func randomize_costs(randseed: int,time: float):
		var prod_hash: int = hash(name)
		var scale = max(1.0,value)/max(1.0,mass)
		scale = clamp(scale,3.0,30.0)
		for ivar in range(2): # 0=value, 1=quantity
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
			if ivar==0:
				final = final/(final+scale)+scale/(scale+1)
			if ivar==0:
				value = int(ceil(value*final))
			else:
				quantity = int(ceil(quantity*final))
	func apply_multipliers(new,quantity_multiplier,value_multiplier,
			fine_multiplier):
		if new==null:
			new = self
		if quantity_multiplier==null and value_multiplier==null and \
				fine_multiplier==null:
			return
		if value_multiplier!=null:
			if abs(value_multiplier)<1e-12:
				value = 0
			elif value_multiplier<0:
				value = min(value,-new.value*value_multiplier)
			else:
				value = max(value,new.value*value_multiplier)
		if fine_multiplier!=null:
			if abs(fine_multiplier)<1e-12:
				fine = 0
			elif fine_multiplier<0:
				fine = min(fine,-new.fine*fine_multiplier)
			else:
				fine = max(fine,new.fine*fine_multiplier)
		if quantity_multiplier!=null:
			if abs(quantity_multiplier)<1e-12:
				quantity = 0
			elif quantity_multiplier<0:
				quantity = min(quantity,-new.quantity*quantity_multiplier)
			else:
				quantity = max(quantity,new.quantity*quantity_multiplier)
		if name=='vitamins':
			assert(value>0)

# ----------------------------------------------------------------------
# ----------------------------------------------------------------------
# ----------------------------------------------------------------------

class Products extends Reference:
	var by_name: Dictionary = {} # lookup table of product_name -> Product
	var by_tag: Dictionary = {} # lookup table of tag -> array of Product with that tag
	
	func duplicate(_deep):
		push_error('Subclass forgot to override duplicate()')
	
	func clear():
		by_name={}
		by_tag={}
	
	func is_Products(): pass # never called; must only exist
	
	func dump() -> String:
		return 'Products[]'
	
	func empty() -> bool:
		return by_name.empty()
	
	# Duplicate the `all` array, for storing the products in compressed form:
	func encode() -> Array:
		var result: Array = by_name.values()
		for i in range(len(result)):
			result[i] = by_name[i].encode()
		return result
	
	func has_quantity() -> bool:
		for name in by_name:
			if by_name[name].quantity:
				return true
		return false
	
	# Return all products in the `include` set that are not in the `exclude` set
	# The `include` and `exclude` have string tag names.
	# The `include` and `exclude` can be anything that returns tags during
	# iteration. If they evaluate to false, they're unused.
	# If include is false, include all IDs, except those in `exclude`
	func products_for_tags(_include, _exclude=null) -> Array:
		return Array()
	
	# Total value of all specified products. Takes a list of ids or null.
	func get_value(names=null):
		var value: float = 0.0
		if names!=null:
			for name in names:
				var prod = by_name.get(name,null)
				if prod:
					value += max(0.0,prod.value)
		else:
			for name in by_name:
				value += max(0.0,by_name[name].value)
		return value
	
	# Total mass of all specified products. Takes a list of ids or null.
	func get_mass(names=null) -> float:
		var mass: float = 0.0
		if names!=null:
			for name in names:
				var prod = by_name.get(name,null)
				if prod:
					mass += max(0.0,prod.mass)
		else:
			for name in by_name:
				mass += max(0.0,by_name[name].mass)
		return mass
	
	# Return a new Products object that contains only the specified IDs.
	# Intended to be used with ids_for_tags.
	func make_subset(_whatever):
		return Products.new()
	
	func copy():
		return Products.new()
	
	# Given the output of encode(), replace all data in this Product.
	func decode(_from: Array) -> bool:
		return false
	
	func add_products_from(from,include,exclude,quantity_multiplier=null,
			value_multiplier=null,fine_multiplier=0):
		add_products(from.products_for_tags(include,exclude),
			quantity_multiplier,value_multiplier,fine_multiplier,true)
	
	func add_products(_all_products, 
			_quantity_multiplier = null, _value_multiplier = null, _fine_multiplier = 0, 
			_skip_checks: bool = true, _keys_to_add = null):
		return false

	func _add_product(product, quantity_multiplier = null, value_multiplier = null, fine_multiplier = 0) -> Product:
		if by_name.has(product.name):
			_remove_product(product.name)
		var newprod = product.duplicate(true)
		newprod.apply_multipliers(newprod,quantity_multiplier,value_multiplier,fine_multiplier)
		_add_product_without_duplicating(newprod)
		return newprod

	func _add_product_without_duplicating(prod):
		by_name[prod.name] = prod
		for tag in prod.tags:
			if by_tag.has(tag):
				by_tag[tag][prod]=1
			else:
				by_tag[tag] = { prod:1 }
		
	
	func _remove_product(name):
		var product = by_name.get(name,null)
		if product:
			var _ignore = by_name.erase(product)
			for tag in product.tags:
				by_tag[tag].erase(product)

	func remove_empty_products():
		var names = by_name.keys()
		for name in names:
			var product = by_name[name]
			if product.quantity<=0:
				var  _ignore = by_name.erase(name)
				for tag in product.tags:
					_ignore = by_tag[tag].erase(product)
	
	func randomize_costs(randseed: int,time: float):
		for name in by_name:
			var product = by_name[name]
			if product:
				product.randomize_costs(randseed,time)
	
	func randomly_erase_products():
		for name in by_name.keys():
			var product = by_name.get(name,null)
			if product:
				var present: float = max(0.1,1.0-pow(0.7,log(product.quantity)))
				if randf()>present:
					product.quantity = 0

	func apply_multiplier_list(multipliers: Dictionary):
		var scan_products: Dictionary = {}
		for tag in multipliers:
			if by_tag.has(tag):
				for name in by_tag[tag]:
					scan_products[name]=1
		for name in scan_products:
			var product = by_name.get(name,null)
			if product:
				product.apply_multiplier_list(multipliers)
	
	func apply_multipliers(quantity_multiplier,value_multiplier,fine_multiplier):
		for name in by_name.keys():
			var product = by_name.get(name,null)
			if product:
				product.apply_multipliers(product,quantity_multiplier,
					value_multiplier,fine_multiplier)
	
# ----------------------------------------------------------------------
# ----------------------------------------------------------------------
# ----------------------------------------------------------------------


class OneProduct extends Products:
	const zero_pool: PoolIntArray = PoolIntArray([0])
	var product_name: String
	
	func is_OneProduct(): pass # never called; must only exist
	
	func clear():
		by_name={}
		by_tag={}
		product_name=''
	
	func duplicate(deep=true):
		var p=OneProduct.new()
		p.product_name=product_name
		var prod = by_name.get(product_name,null)
		if prod:
			if deep:
				p.set_product(prod.duplicate(true))
			else:
				p.set_product(prod)
		return p
	
	func copy():
		return duplicate(true)
	
	func _init(product=null):
		if product!=null:
			set_product(product)
	
	func get_product(): # -> Product or null
		return by_name.values()[0] if by_name else null
	
	func products_for_tags(include, exclude=null) -> Array:
		var product = by_name.get(product_name,null)
		var found: bool = false
		if product:
			if include:
				for tag in include:
					if product.tags.has(tag):
						found=true
						break
			if found and exclude:
				for tag in exclude:
					if product.tags.has(tag):
						found=false
						break
		if found:
			return [product]
		return []	

	func remove_empty_products():
		var product = by_name.get(product_name,null)
		if product and product.quantity<=0:
			clear()
	
	func dump() -> String:
		var product = by_name.get(product_name,null)
		if product:
			return 'OneProduct['+str(product)+']'
		return 'OneProduct[null]'
	
	func set_product(product):
		if not product:
			clear()
		else:
			var prod = product.duplicate()
			by_name[prod.name]=prod
			for tag in prod.tags:
				by_tag[tag]={prod:1}

	func add_products(all_products, 
			quantity_multiplier = null, value_multiplier = null, fine_multiplier = 0, 
			_skip_checks: bool = true, keys_to_add = null):
		# Checks are never skipped because we must ensure that only the
		# selected product is processed
		if keys_to_add==null:
			if all_products is Products:
				keys_to_add = all_products.by_name.keys()
			elif all_products is Dictionary:
				keys_to_add = all_products.keys()
			elif all_products is Array:
				keys_to_add = range(len(all_products))
			else:
				keys_to_add = all_products.by_name.keys()
		if not keys_to_add:
			return
		if not by_name:
			# No product yet.
			var key = keys_to_add[0]
			set_product(all_products.by_name[key])
			by_name.values()[0].apply_multipliers(null, quantity_multiplier, value_multiplier, fine_multiplier)
		elif not all_products.by_name.has(product_name):
			push_warning('Product named "'+product_name+'" not in all_products')
			return false
		elif keys_to_add!=null:
			var has: bool = false
			for key in keys_to_add:
				var name = key
				if name is int:
					name = keys_to_add[key].name
				if name==product_name:
					by_name.values()[0].apply_multipliers(all_products.by_name[name],
						quantity_multiplier, value_multiplier, fine_multiplier)
					has=true
					break
			if not has:
				push_warning('Product named "'+product_name+'" not in keys')
		return true

# ----------------------------------------------------------------------
# ----------------------------------------------------------------------
# ----------------------------------------------------------------------

class ManyProducts extends Products:
	func duplicate(deep = true):
		var p=ManyProducts.new()
		p.by_name=by_name.duplicate(deep)
		p.by_tag=by_tag.duplicate(deep)
		return p
	
	func is_ManyProducts(): pass # never called; must only exist
	
	func clear():
		by_name={}
		by_tag={}
	
	func copy_from(p: Products):
		for name in p.by_name:
			var _ignore = _add_product(p.by_name[name])
	
	func copy():
		var result = ManyProducts.new()
		if by_name:
			result.by_name = by_name.duplicate(true)
			result.by_tag = by_tag.duplicate(true)
		return result

	# Given an array of Product objects, insert them in this ManyProducts.
	# This new ManyProducts owns those Product objects.
	#    load_data_from_scene = true to get the mass from the scene if the name begins with res://
	#    expand_tags = true to expand tags that contain a "/" to multiple tags ("a/b/c" => "a", "a/b", "a/b/c")
	func _init(contents: Array = [], load_data_from_scene: bool=false, expand_tags: bool = true):
		for product in contents:
			if by_name.has(product.name):
				continue
			if load_data_from_scene and product.name.begins_with('res://') and ResourceLoader.exists(product.name):
				var scene = load(product.name)
				if scene:
					var state = scene.get_state()
					for i in range(state.get_node_property_count(0)):
						var property_name = state.get_node_property_name(0,i)
						if ['base_mass','add_mass','weapon_mass'].has(property_name):
							var mass = state.get_node_property_value(0,i)
							if mass>0:
								product.mass = int(round(mass*1000)) # convert to kg
			if expand_tags:
				product.expand_tags()
			_add_product_without_duplicating(product)
	
	func add_quantity_from(all_products,product_name: String,count = null,fallback=null):
		assert(count==null or count is int)

		var prod = by_name.get(product_name,null)
		if count!=null and prod:
			prod.quantity = max(0,prod.quantity+count)
			return

		var from_product = all_products.by_name.get(product_name,null)
		
		if not from_product and fallback!=null:
			from_product = fallback.by_name.get(product_name,null)
		elif not from_product:
			push_warning('Could not find product named "'+str(product_name)+'" in all_products and no fallback was provided')
			assert(false)
		
		if not from_product:
			push_warning('No product to add for name "'+str(product_name)+'"')
			assert(false)
		elif prod: # count is null at this point
			prod.quantity = from_product.quantity
		elif from_product:
			prod = _add_product(from_product)
			prod.quantity = max(0,count)
		else:
			push_warning('Could not find product "'+str(product_name)+'" in all_products, self, or fallback.')
			assert(false)
	
	func add_products(all_products,  # : Dictionary or Products or Array
			quantity_multiplier = null, value_multiplier = null, fine_multiplier = 0, 
			skip_checks: bool = false, keys_to_add = null, zero_quantity_if_missing = false):
		var have_multipliers = (quantity_multiplier!=null or \
			value_multiplier!=null or fine_multiplier!=null)
		if keys_to_add==null:
			if all_products is Products:
				keys_to_add = all_products.by_name.keys()
			elif all_products is Dictionary:
				keys_to_add = all_products.keys()
			elif all_products is Array:
				keys_to_add = range(len(all_products))
			else:
				keys_to_add = all_products.by_name
		for key in keys_to_add:
			var product
			if all_products is Products:
				product = all_products.by_name[key]
			else:
				product = all_products[key]
			var name = product.name
			if not skip_checks:
				# Discard invalid products.
				var bad: bool = false
				if not product.has_method('is_Product'):
					push_warning('In add_products, each array element must be a Product')
					bad=true
				if not product.name is String or not product.name:
					push_warning('In add_products, names must be non-empty strings '
						+'(bad name "'+str(product[0])+'")')
					bad=true
				if bad:
					push_error('In add_products, ignoring product with key "'+str(key)+'"')
					continue

			var myprod = by_name.get(name)
			# Do we already have this product?
			var qm = quantity_multiplier
			if myprod:
				# Add information to existing product
				for tag in product.tags:
					if not skip_checks and (not tag is String or not tag):
						push_warning('In add_products, tags must be non-empty '
							+'strings (Ignoring bad tag "'+str(tag)+'".)')
					elif myprod.tags.has(tag):
						pass # tag already added
					else:
						myprod.tags[tag] = 1
						if not by_tag.has(tag):
							by_tag[tag] = { myprod:1 }
						else:
							by_tag[tag][myprod] = 1
			else:
				myprod=_add_product(product)
				if zero_quantity_if_missing:
					qm=0
			if have_multipliers or qm!=null:
				myprod.apply_multipliers(product,qm,value_multiplier,fine_multiplier)

		return false
	
	func reduce_quantity_by(this_much):
		for name in this_much.by_name:
			var product = this_much.by_name.get(name,null)
			if product:
				var remove_quantity=max(0,product.quantity)
				if remove_quantity:
					var myprod = by_name.get(name,null)
					if myprod:
						myprod.quantity = max(0,max(0,myprod.quantity)-remove_quantity)
	
	func remove_absent_products():
		for name in by_name.keys():
			var product=by_name.get(name,null)
			if product and product.quantity<=0:
				_remove_product(product)
	
	func dump() -> String:
		var result = 'ManyProducts[\n'
		for key in by_name:
			result += ' '+str(key)+' => '+str(by_name[key])+'\n'
		return result + ']'
	
	# Return all IDs in the `include` set that are not in the `exclude` set
	# The `include` and `exclude` can have string tag names or int IDs.
	# The `include` and `exclude` can be anything that returns tags during
	# iteration. If they evaluate to false, they're unused.
	# If include is false, include all IDs, except those in `exclude`
	func products_for_tags(include, exclude=null) -> Array:
		var result_set: Dictionary = {}

		for tag in include:
			var tagged = by_tag.get(tag,null)
			if tagged:
				for prod in tagged:
					result_set[prod]=1

		for tag in exclude:
			var tagged = by_tag.get(tag,null)
			if tagged:
				for prod in tagged:
					var _ignore = result_set.erase(prod)

		return result_set.keys()
	
	# Return a new Products object that contains only the specified names.
	# Intended to be used with ids_for_tags.
	func make_subset(names):
		var result = ManyProducts.new()
		for name in names:
			var prod = by_name.get(name,null)
			if prod:
				result._add_product(prod)
		return result
	
	func remove_named_products(names,negate: bool = false):
		if names.has_method('is_Products'):
			names = names.by_name.keys()
		if names is Dictionary:
			names = names.keys()
		if negate:
			for name in by_name:
				if names.has(name):
					_remove_product(name)
		else:
			for name in names:
				_remove_product(name)
	
	
	# Given the output of encode(), replace all data in this Product.
	func decode(from: Array):
		clear()
		for encoded in from:
			var prod = Product.new()
			if prod.decode(encoded):
				_add_product_without_duplicating(prod)
		return true

# ----------------------------------------------------------------------
# ----------------------------------------------------------------------
# ----------------------------------------------------------------------

func products_for_market(all_known_products,market_products,ship_products,
		product_pricer: Object,pricer_method: String,
		include_zero_value: bool = false) -> ManyProducts:
	
	# Find all products for sale that exist in the known set:
	var priced_names: Dictionary = {}
	var forbidden_names: Dictionary = {}
	for product_name in market_products.by_name:
		var market_product = market_products.by_name[product_name]
		var known_product = all_known_products.by_name.get(product_name,null)
		if known_product==null:
			continue
		elif not include_zero_value and market_product.value<=0:
			forbidden_names[product_name]=1
		elif not include_zero_value and market_product.quantity<=0:
			continue
		else:
			priced_names[product_name]=1
	var priced_products: ManyProducts = market_products.make_subset(priced_names.keys())
	
	# Find all ship cargo that exists in the known set but is not for sale here:
	var unpriced_names: Dictionary = {}
	for product_name in ship_products.by_name:
		var known_product = all_known_products.by_name.get(product_name,null)
		if known_product!=null:
			var ship_product = ship_products.by_name.get(product_name,null)
			if ship_product and ship_product.quantity:
				unpriced_names[product_name]=1
	
	# If there aren't any new products in the ship, we're done:
	if not unpriced_names.size():
		print('NO UNPRICED IDS')
		return priced_products
	
	# Get prices for all sellable products in the ship that are not for sale in market:
	var unpriced_products: ManyProducts = all_known_products.make_subset(unpriced_names)
	product_pricer.call(pricer_method,unpriced_products)
	
	# Find all products whose sale value is greater than zero.
	# Sale values of zero or less indicate the product cannot be sold here.
	var allowed_names: Dictionary = {}
	for product_name in unpriced_products.by_name:
		var product = unpriced_products.by_name.get(product_name,null)
		if product and product.value>0:
			allowed_names[product_name]=1
	
	# Add the sellable products from the ship that were not in the marketplace:
	var allowed_products: ManyProducts = unpriced_products.make_subset(allowed_names)
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
			var old_product = products.by_name.get(product_name,null)
			var new_product = update.by_name.get(product_name,null)
			if new_product!=null:
				if old_product!=null:
					old_product.value = int(ceil(weight*old_product.value + invweight*new_product.value))
					old_product.mass = int(ceil(weight*old_product.mass + invweight*new_product.mass))
					old_product.fine = int(ceil(weight*old_product.fine + invweight*new_product.fine))
					old_product.quantity = int(max(0,round(
						weight*old_product.quantity +
						invweight*new_product.quantity)))
				else:
					to_add.append(new_product)
		if to_add:
			products.add_products(to_add,1,1,1,true)
		products.remove_empty_products()
		update_time = now
	func decode_products(p: Array):
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

			

func shipyard_data_tables() -> ManyProducts:
	return ManyProducts.new([ # name, quantity, value, fine, density, tags
		Product.new( 'res://weapons/IACivilian/AntiMissile2x2.tscn', 40, 13000, 13000, 0, [ 'antimissile', 'weapon', 'terran' ] ),
		Product.new( 'res://weapons/IACivilian/AntiMissile3x3.tscn', 40, 32000, 32000, 0, [ 'antimissile', 'weapon', 'terran' ] ),
		Product.new( 'res://weapons/IACivilian/DuteriumFluorideLaser.tscn', 40, 9000, 9000, 0, [ 'laser', 'weapon', 'terran', 'license/alliance_civilian' ] ),
		Product.new( 'res://weapons/IACivilian/DuteriumFluorideLaserTurret.tscn', 25, 16000, 16000, 0, [ 'laser', 'weapon', 'terran', 'license/alliance_civilian' ] ),
		Product.new( 'res://weapons/IACivilian/BlueMissileLauncher.tscn', 40, 13000, 13000, 0, [ 'explosive', 'homing', 'weapon', 'terran', 'license/alliance_civilian' ] ),
		Product.new( 'res://weapons/IACivilian/BlueRapidMissileLauncher.tscn', 40, 29000, 29000, 0, [ 'explosive', 'homing', 'weapon', 'terran', 'license/alliance_civilian' ] ),
		Product.new( 'res://weapons/IACivilian/GammaRayLaser.tscn', 40, 22000, 22000, 0, [ 'laser', 'weapon', 'terran', 'license/alliance_civilian' ] ),
		Product.new( 'res://weapons/IACivilian/GreenMissileLauncher.tscn', 40, 26000, 26000, 0, [ 'explosive', 'homing', 'weapon', 'terran', 'license/alliance_civilian' ] ),
		Product.new( 'res://weapons/IACivilian/GammaRayLaserTurret.tscn', 40, 39000, 39000, 0, [ 'laser', 'weapon', 'terran', 'license/alliance_civilian' ] ),
		Product.new( 'res://weapons/IACivilian/PlasmaTurret.tscn', 40, 36000, 36000, 0, [ 'plasma', 'weapon', 'terran', 'license/alliance_advanced' ] ),
		Product.new( 'res://weapons/IACivilian/PlasmaGun2x3.tscn', 40, 31000, 31000, 0, [ 'plasma', 'weapon', 'terran', 'license/alliance_advanced' ] ),
		Product.new( 'res://weapons/IACivilian/PlasmaGun1x4.tscn', 40, 26000, 26000, 0, [ 'plasma', 'weapon', 'terran', 'license/alliance_advanced' ] ),
		Product.new( 'res://weapons/IACivilian/PlasmaBallLauncher.tscn', 40, 54000, 54000, 0, [ 'plasma', 'homing', 'weapon', 'terran', 'license/alliance_advanced' ] ),
		Product.new( 'res://weapons/Old/BigRedMissileLauncher.tscn', 25, 136000, 136000, 0, [ 'explosive', 'homing', 'weapon', 'terran', 'capital', 'license/alliance_military' ] ),
		Product.new( 'res://weapons/FrontierMilitia/SpikeLauncher1x3.tscn', 40, 17000, 17000, 0, [ 'pierce', 'weapon', 'terran', 'license/frontier_militia' ] ),
		Product.new( 'res://weapons/FrontierMilitia/SpikeLauncher1x4.tscn', 40, 29000, 29000, 0, [ 'pierce', 'weapon', 'terran', 'license/frontier_militia' ] ),
		Product.new( 'res://weapons/FrontierMilitia/SpikeLauncher2x4.tscn', 40, 48000, 48000, 0, [ 'pierce', 'weapon', 'terran', 'large', 'license/frontier_militia' ] ),
		Product.new( 'res://weapons/FrontierMilitia/SpikeLauncher3x4.tscn', 40, 81000, 81000, 0, [ 'pierce', 'weapon', 'terran', 'capital', 'license/frontier_militia' ] ),
		Product.new( 'res://weapons/FrontierMilitia/SpikeLauncherTurret3x3.tscn', 40, 50000, 50000, 0, [ 'pierce', 'weapon', 'terran', 'license/frontier_militia' ] ),
		Product.new( 'res://weapons/FrontierMilitia/SpikeLauncherTurret4x4.tscn', 40, 91000, 91000, 0, [ 'pierce', 'weapon', 'terran', 'capital', 'license/frontier_militia' ] ),
		Product.new( 'res://weapons/FrontierMilitia/ElectronGun1x3.tscn', 40, 29000, 29000, 0, [ 'charge', 'weapon', 'terran', 'license/frontier_militia' ] ),
		Product.new( 'res://weapons/FrontierMilitia/ElectronGun1x4.tscn', 40, 41000, 41000, 0, [ 'charge', 'weapon', 'terran', 'license/frontier_militia' ] ),
		Product.new( 'res://weapons/FrontierMilitia/ElectronGun2x4.tscn', 40, 58000, 58000, 0, [ 'charge', 'weapon', 'terran', 'license/frontier_militia' ] ),
		Product.new( 'res://weapons/FrontierMilitia/ElectronGun3x4.tscn', 40, 11000, 110000, 0, [ 'charge', 'weapon', 'terran', 'license/frontier_militia' ] ),
		Product.new( 'res://weapons/FrontierMilitia/ElectronTurret3x3.tscn', 40, 61000, 61000, 0, [ 'charge', 'weapon', 'terran', 'license/frontier_militia' ] ),
		Product.new( 'res://weapons/FrontierMilitia/ElectronTurret4x4.tscn', 40, 101000, 101000, 0, [ 'charge', 'weapon', 'terran', 'license/frontier_militia' ] ),
		Product.new( 'res://weapons/FrontierMilitia/MagneticRailGun2x4.tscn', 40, 51000, 51000, 0, [ 'impact', 'weapon', 'terran', 'large', 'license/frontier_militia' ] ),
		Product.new( 'res://weapons/FrontierMilitia/MagneticRailTurret.tscn', 40, 56000, 56000, 0, [ 'impact', 'weapon', 'terran', 'license/frontier_militia' ] ),
		Product.new( 'res://weapons/FrontierMilitia/MagneticRailGun1x4.tscn', 40, 36000, 36000, 0, [ 'impact', 'weapon', 'terran', 'license/frontier_militia' ] ),
		Product.new( 'res://weapons/FrontierMilitia/MagneticRailGun1x3.tscn', 40, 29000, 29000, 0, [ 'impact', 'weapon', 'terran', 'license/frontier_militia' ] ),
		Product.new( 'res://weapons/FrontierMilitia/MassDriver.tscn', 40, 95000, 95000, 0, [ 'impact', 'weapon', 'terran', 'capital', 'license/frontier_militia' ] ),
		Product.new( 'res://weapons/FrontierMilitia/MassDriverTurret.tscn', 40, 99000, 99000, 0, [ 'impact', 'weapon', 'terran', 'capital', 'license/frontier_militia' ] ),
		Product.new( 'res://weapons/IAPolice/GreyMissileLauncher.tscn', 40, 59000, 59000, 0, [ 'explosive', 'homing', 'weapon', 'terran', 'large', 'license/alliance_police' ] ),
		Product.new( 'res://weapons/IAPolice/RetributionMissileLauncher.tscn', 25, 94000, 94000, 0, [ 'explosive', 'homing', 'weapon', 'terran', 'capital', 'license/alliance_police' ] ),
		Product.new( 'res://weapons/IAPolice/JusticeMissileLauncher.tscn', 25, 41000, 41000, 0, [ 'explosive', 'homing', 'weapon', 'terran', 'license/alliance_police' ] ),
		Product.new( 'res://weapons/IAPolice/CyclotronTurret4x4.tscn', 40, 103000, 103000, 0, [ 'particle', 'weapon', 'terran', 'capital', 'license/alliance_police' ] ),
		Product.new( 'res://weapons/IAPolice/CyclotronTurret3x3.tscn', 40, 55000, 55000, 0, [ 'particle', 'weapon', 'terran', 'large', 'license/alliance_police' ] ),
		Product.new( 'res://weapons/IAPolice/LinearAccelerator3x4.tscn', 40, 95000, 95000, 0, [ 'particle', 'weapon', 'terran', 'capital', 'license/alliance_police' ] ),
		Product.new( 'res://weapons/IAPolice/LinearAccelerator2x4.tscn', 40, 61000, 61000, 0, [ 'particle', 'weapon', 'terran', 'large', 'license/alliance_police' ] ),
		Product.new( 'res://weapons/IAPolice/LinearAccelerator1x4.tscn', 40, 39000, 38000, 0, [ 'particle', 'weapon', 'terran', 'license/alliance_police' ] ),
		Product.new( 'res://weapons/IAPolice/NuclearPumpedLaser1x4.tscn', 40, 38000, 38000, 0, [ 'laser', 'weapon', 'terran', 'license/alliance_police' ] ),
		Product.new( 'res://weapons/IAPolice/NuclearPumpedLaser3x4.tscn', 40, 87000, 87000, 0, [ 'laser', 'weapon', 'terran', 'capital', 'license/alliance_police' ] ),
		Product.new( 'res://weapons/IAPolice/NuclearPumpedLaser2x4.tscn', 40, 71000, 71000, 0, [ 'laser', 'weapon', 'terran', 'large', 'license/alliance_police' ] ),
		Product.new( 'res://weapons/IAPolice/NuclearPumpedLaserTurret4x4.tscn', 25, 94000, 94000, 0, [ 'laser', 'weapon', 'terran', 'capital', 'license/alliance_police' ] ),
		Product.new( 'res://weapons/IAPolice/NuclearPumpedLaserTurret3x3.tscn', 25, 53000, 53000, 0, [ 'laser', 'weapon', 'terran', 'large', 'license/alliance_police' ] ),
		Product.new( 'res://equipment/defense/DefensiveScatterer.tscn', 40, 35000, 35000, 0, [ 'equipment', 'terran' ] ),
		Product.new( 'res://equipment/defense/ReactiveArmor.tscn', 40, 45000, 45000, 0, [ 'equipment', 'terran' ] ),
		Product.new( 'res://equipment/defense/GravityControlSystem.tscn', 40, 41000, 41000, 0, [ 'equipment', 'terran', 'licence/alliance_civilian' ] ),
		Product.new( 'res://equipment/defense/ElectroMagneticDampener.tscn', 40, 46000, 46000, 0, [ 'equipment', 'terran', 'license/alliance_advanced' ] ),
		Product.new( 'res://equipment/defense/EnvironmentalControlSystem.tscn', 40, 39000, 39000, 0, [ 'equipment', 'terran', 'license/alliance_civilian' ] ),
		Product.new( 'res://equipment/defense/EntertainmentNetwork.tscn', 40, 31000, 31000, 0, [ 'equipment', 'terran', 'license/alliance_civilian' ] ),
		Product.new( 'res://equipment/defense/AblativeBiogelExcreter.tscn', 40, 51000, 51000, 0, [ 'equipment', 'terran', 'license/alliance_advanced' ] ),
		Product.new( 'res://equipment/defense/AstralShieldingPanels.tscn', 40, 48000, 48000, 0, [ 'equipment', 'terran', 'license/frontier_militia' ] ),
		Product.new( 'res://equipment/defense/SelfHealingFoam.tscn', 40, 45000, 45000, 0, [ 'equipment', 'terran', 'license/frontier_militia' ] ),
		Product.new( 'res://equipment/engines/FrontierEngine2x2.tscn', 40, 18000, 18000, 0, [ 'engine', 'terran/frontier', 'license/frontier_militia' ] ),
		Product.new( 'res://equipment/engines/FrontierEngine2x4.tscn', 40, 36000, 36000, 0, [ 'engine', 'terran/frontier', 'license/frontier_militia' ] ),
		Product.new( 'res://equipment/engines/FrontierEngine4x4.tscn', 40, 79000, 79000, 0, [ 'engine', 'terran/frontier', 'license/frontier_militia' ] ),
		Product.new( 'res://equipment/engines/Engine2x2.tscn', 40, 11000, 11000, 0, [ 'engine', 'terran', 'licence/alliance_civilian' ] ),
		Product.new( 'res://equipment/engines/Engine2x4.tscn', 40, 23000, 23000, 0, [ 'engine', 'terran', 'licence/alliance_civilian' ] ),
		Product.new( 'res://equipment/engines/Engine4x4.tscn', 40, 47000, 47000, 0, [ 'engine', 'terran', 'large', 'licence/alliance_civilian' ] ),
		Product.new( 'res://equipment/engines/IonEngine2x4.tscn', 40, 30000, 30000, 0, [ 'engine', 'terran', 'large', 'licence/alliance_civilian' ] ),
		Product.new( 'res://equipment/engines/IonEngine4x4.tscn', 40, 61000, 61000, 0, [ 'engine', 'terran', 'large', 'licence/alliance_civilian' ] ),
		Product.new( 'res://equipment/engines/FissionEngine.tscn', 40, 36000, 36000, 0, [ 'engine', 'terran', 'large', 'license/alliance_advanced' ] ),
		Product.new( 'res://equipment/engines/FusionEngine.tscn', 40, 73000, 73000, 0, [ 'engine', 'terran', 'large', 'license/alliance_advanced' ] ),
		Product.new( 'res://equipment/divinity/DivinityDrive.tscn', 40, 1, 1, 0, [ 'engine', 'terran', 'license/god_mode' ] ),
		Product.new( 'res://equipment/divinity/DivinityOrb.tscn', 40, 1, 1, 0, [ 'equipment', 'terran', 'license/god_mode' ] ),
		Product.new( 'res://equipment/engines/Hyperdrive.tscn', 40, 25000, 25000, 0, [ 'engine', 'terran' ] ),
		Product.new( 'res://equipment/engines/EscapePodEngine.tscn', 40, 7000, 7000, 0, [ 'engine', 'terran', 'licence/alliance_civilian' ] ),
		Product.new( 'res://equipment/engines/SmallHyperdrive.tscn', 40, 14000, 14000, 0, [ 'engine', 'terran' ] ),
		Product.new( 'res://equipment/engines/SmallMultisystem.tscn', 40, 19000, 19000, 0, [ 'engine', 'terran', 'licence/alliance_civilian' ] ),
		Product.new( 'res://equipment/engines/LargeMultisystem.tscn', 40, 41000, 41000, 0, [ 'engine', 'terran', 'licence/alliance_civilian' ] ),
		Product.new( 'res://equipment/repair/Structure2x2.tscn', 40, 16000, 16000, 0, [ 'equipment', 'structure', 'terran' ] ),
		Product.new( 'res://equipment/repair/FrontierRepair2x2.tscn', 40, 35000, 35000, 0, [ 'equipment', 'power', 'structure', 'terran', 'license/frontier_militia' ] ),
		Product.new( 'res://equipment/repair/Shield1x3.tscn', 40, 24500, 24500, 0, [ 'equipment', 'shield', 'terran', 'licence/alliance_civilian' ] ),
		Product.new( 'res://equipment/repair/Shield2x1.tscn', 40, 16000, 16000, 0, [ 'equipment', 'shield', 'terran', 'licence/alliance_civilian' ] ),
		Product.new( 'res://equipment/repair/Shield1x1.tscn', 40, 7500, 7500, 0, [ 'equipment', 'shield', 'terran', 'licence/alliance_civilian' ] ),
		Product.new( 'res://equipment/repair/FrontierShield1x2.tscn', 40, 29000, 29000, 0, [ 'equipment', 'shield', 'terran', 'license/frontier_militia' ] ),
		Product.new( 'res://equipment/repair/ShieldCapacitors1x2.tscn', 40, 21000, 29000, 0, [ 'equipment', 'shield', 'terran', 'license/alliance_police' ] ),
		Product.new( 'res://equipment/repair/Shield2x2.tscn', 40, 35000, 35000, 0, [ 'equipment', 'shield', 'terran', 'licence/alliance_civilian' ] ),
		Product.new( 'res://equipment/repair/FrontierShield2x3.tscn', 40, 85000, 85000, 0, [ 'equipment', 'shield', 'terran', 'license/frontier_militia' ] ),
		Product.new( 'res://equipment/repair/ShieldCapacitors2x3.tscn', 40, 65000, 85000, 0, [ 'equipment', 'shield', 'terran', 'license/alliance_police' ] ),
		Product.new( 'res://equipment/repair/Shield3x3.tscn', 40, 79000, 79000, 0, [ 'equipment', 'shield', 'terran', 'large', 'licence/alliance_civilian' ] ),
		Product.new( 'res://equipment/cargo/CargoBay1x2.tscn', 40, 6000, 6000, 0, [ 'equipment', 'cargo_bay', 'terran' ] ),
		Product.new( 'res://equipment/cargo/CargoBay2x3.tscn', 40, 19000, 19000, 0, [ 'equipment', 'cargo_bay', 'terran' ] ),
		Product.new( 'res://equipment/cargo/CargoBay3x4.tscn', 40, 40000, 40000, 0, [ 'equipment', 'cargo_bay', 'terran', 'large' ] ),
		Product.new( 'res://equipment/power/TinyBioelectricGenerator.tscn', 40, 10000, 10000, 0, [ 'terran', 'equipment', 'power', 'organic' ] ),
		Product.new( 'res://equipment/power/SmallBioelectricGenerator.tscn', 40, 19000, 19000, 0, [ 'terran', 'equipment', 'power', 'organic' ] ),
		Product.new( 'res://equipment/power/MediumBioelectricGenerator.tscn', 40, 35000, 35000, 0, [ 'terran', 'equipment', 'power', 'organic' ] ),
		Product.new( 'res://equipment/power/LargeBioelectricGenerator.tscn', 40, 72000, 72000, 0, [ 'terran', 'equipment', 'power', 'organic', 'large' ] ),
		Product.new( 'res://equipment/power/SmallReactor.tscn', 40, 31000, 31000, 0, [ 'equipment', 'terran', 'power', 'license/alliance_advanced' ] ),
		Product.new( 'res://equipment/power/MediumReactor.tscn', 40, 58000, 58000, 0, [ 'equipment', 'terran', 'power', 'license/alliance_advanced' ] ),
		Product.new( 'res://equipment/power/LargeReactor.tscn', 40, 119000, 119000, 0, [ 'equipment', 'terran', 'power', 'large', 'license/alliance_advanced' ] ),
		Product.new( 'res://equipment/cooling/AdiabaticDemagnitizationCooler.tscn', 40, 41000, 41000, 0, [ 'equipment', 'terran', 'cooling', 'license/alliance_advanced' ] ),
		Product.new( 'res://equipment/cooling/SmallOpticalCooler.tscn', 40, 6000, 6000, 0, [ 'equipment', 'terran', 'cooling' ] ),
		Product.new( 'res://equipment/cooling/LargeOpticalCooler.tscn', 40, 11000, 11000, 0, [ 'equipment', 'terran', 'cooling' ] ),
		Product.new( 'res://equipment/cooling/OrganicNanofluidCoolant.tscn', 40, 31000, 31000, 0, [ 'equipment', 'terran', 'cooling', 'licence/alliance_civilian' ] ),
		Product.new( 'res://ships/BannerShip/BannerShipHull.tscn', 3, 394000, 394000, 0, [ 'hull/civilian/advertisment', 'terran', 'large', 'license/alliance_military' ] ),
		Product.new( 'res://ships/Police/Popoto.tscn', 9, 82000, 82000, 0, [ 'hull/combat/interceptor', 'terran', 'license/alliance_police' ] ),
		Product.new( 'res://ships/Police/Bufeo.tscn', 4, 168000, 168000, 0, [ 'hull/combat/warship', 'terran', 'license/alliance_police' ] ),
		Product.new( 'res://ships/Police/Orca.tscn', 2, 421000, 421000, 0, [ 'hull/combat/warship', 'terran', 'large', 'license/alliance_police' ] ),
		Product.new( 'res://ships/Police/Ankylorhiza.tscn', 1, 1080000, 1080000, 0, [ 'hull/combat/capital', 'terran', 'capital', 'license/alliance_police' ] ),
		Product.new( 'res://ships/FrontierMilitia/Eagle.tscn', 3, 305000, 305000, 0, [ 'hull/combat/warship', 'terran', 'license/frontier_militia' ] ),
		Product.new( 'res://ships/FrontierMilitia/Condor.tscn', 1, 985000, 985000, 0, [ 'hull/combat/capital', 'terran', 'capital', 'license/frontier_militia' ] ),
		Product.new( 'res://ships/FrontierMilitia/Peregrine.tscn', 12, 79000, 79000, 0, [ 'hull/combat/interceptor', 'terran', 'license/frontier_militia' ] ),
		Product.new( 'res://ships/FrontierMilitia/Raven.tscn', 3, 128000, 128000, 0, [ 'hull/combat/warship', 'terran', 'license/frontier_militia' ] ),
		Product.new( 'res://ships/SmallCivilian/Husky.tscn', 2, 235000, 235000, 0, [ 'hull/cargo/cargo', 'terran', 'license/alliance_advanced' ] ),
		Product.new( 'res://ships/SmallCivilian/Qimmeq.tscn', 2, 61000, 61000, 0, [ 'hull/cargo/cargo', 'terran', 'license/alliance_civilian' ] ),
		Product.new( 'res://ships/Starliner/Thoroughbred.tscn', 2, 475000, 475000, 0, [ 'hull/cargo/cargo', 'terran', 'license/alliance_advanced' ] ),
		Product.new( 'res://ships/SmallCivilian/Samoyed.tscn', 2, 61000, 61000, 0, [ 'hull/cargo/cargo', 'terran', 'license/alliance_civilian' ] ),
		Product.new( 'res://ships/CargoPodShips/Monopod.tscn', 2, 273000, 273000, 0, [ 'hull/cargo/container', 'terran', 'license/alliance_civilian' ] ),
		Product.new( 'res://ships/CargoPodShips/Bipod.tscn', 2, 652000, 652000, 0, [ 'hull/cargo/container', 'terran', 'large', 'license/alliance_civilian' ] ),
		Product.new( 'res://ships/CargoPodShips/Hexapod.tscn', 2, 845000, 845000, 0, [ 'hull/cargo/container', 'terran', 'capital', 'license/alliance_advanced' ] ),
	], true, true)

func commodity_data_tables() -> ManyProducts:
	return ManyProducts.new([ # name, quantity, value, fine, density, tags
		
		# Intoxicants
		Product.new( 'catnip', 1, 100, 100, 1, [ 'intoxicant/terran/suvar' ] ),
		Product.new( 'spider_glitter', 1, 110, 100, 1, [ 'intoxicant/terran/spider' ] ),
		Product.new( 'fine_wine', 1, 140, 100, 1, [ 'intoxicant/terran/human', 'intoxicant/terran/suvar' ] ),
		Product.new( 'beer', 1, 30, 100, 1, [ 'intoxicant/terran/human', 'intoxicant/terran/suvar' ] ),
		Product.new( 'magic_crystals', 1, 400, 100, 1, [ 'intoxicant/terran/human', 'intoxicant/terran/spider' ] ),
		Product.new( 'peppy_pints', 1, 500, 100, 10, [ 'intoxicant/terran/human', 'intoxicant/terran/suvar' ] ),
		Product.new( 'happy_powder', 1, 600, 900, 1, [ 'intoxicant/terran/human',
		  'intoxicant/terran/suvar', 'deadly_drug/terran/human' ]),
		Product.new( 'rainbow_tears', 1, 900, 900, 1, [ 'intoxicant/terran/human',
		  'intoxicant/terran/suvar', 'deadly_drug/terran/suvar' ]),
		
		# Material prices for 1kg are based on Feb/Mar 2020 prices:
		#    max(3,ceil(us$/kg / 4))
		# Material fines are always 100
		# Base metals: quantity 200, mass 10kg
		# Medium-rarity metals: quantity 100, mass 10kg
		# Rare metals: quantity 30, mass 1
		Product.new( 'iron', 200, 3, 100, 10, [ 'raw_materials/metal' ]),
		Product.new( 'copper', 200, 22, 100, 10, [ 'raw_materials/metal', 'raw_materials/jewelry_materials' ]),
		Product.new( 'nickel', 200, 41, 100, 10, [ 'raw_materials/metal' ]),
		Product.new( 'aluminum', 200, 5, 100, 10, [ 'raw_materials/metal' ]),
		Product.new( 'zinc', 200, 22, 100, 10, [ 'raw_materials/metal' ]),
		Product.new( 'lead', 200, 5, 100, 10, [ 'raw_materials/metal' ]),
		
		Product.new( 'cobalt', 100, 132, 100, 10, [ 'raw_materials/metal' ]),
		Product.new( 'titanium', 100, 64, 100, 10, [ 'raw_materials/metal' ]),
		Product.new( 'silver', 100, 139, 100, 10, [ 'raw_materials/metal', 'raw_materials/jewelry_materials' ]),
		
		Product.new( 'gold', 30, 938, 100, 1, [ 'raw_materials/metal/rare', 'raw_materials/jewelry_materials' ]),
		Product.new( 'platinum', 30, 624, 100, 1, [ 'raw_materials/metal/rare', 'raw_materials/jewelry_materials' ]),
		Product.new( 'iridium', 30, 2181, 100, 1, [ 'raw_materials/metal/rare' ]),
		Product.new( 'rhodium', 30, 16093, 100, 1, [ 'raw_materials/metal/rare' ]),
		Product.new( 'palladium', 30, 1291, 100, 1, [ 'raw_materials/metal/rare' ]),
		Product.new( 'ruthenium', 30, 2020, 100, 1, [ 'raw_materials/metal/rare' ]),

		Product.new( 'refined_uranium', 30, 10254, 100, 1, [ 'raw_materials/metal/highly_radioactive', 'danger/highly_radioactive' ]),
		Product.new( 'plutonium', 30, 19504, 100, 1, [ 'raw_materials/metal/highly_radioactive', 'danger/highly_radioactive' ]),
		
		# Gems: 1kg, 300 fine. 
		# Mass includes protective and security packaging.
		# Price: max(200,real-world $/carat * 5)
		
		Product.new( 'diamonds', 1, 100000, 300, 1, [ 'raw_materials/gems', 'luxury/terran' ]),
		Product.new( 'rubies', 3, 60000, 300, 1, [ 'raw_materials/gems', 'luxury/terran' ]),
		Product.new( 'alexandrite gems', 5, 35000, 300, 1, [ 'raw_materials/gems', 'luxury/terran' ]),
		Product.new( 'emeralds', 5, 24000, 300, 1, [ 'raw_materials/gems', 'luxury/terran' ]),
		Product.new( 'sapphires', 5, 20000, 300, 1, [ 'raw_materials/gems', 'luxury/terran' ]),
		
		Product.new( 'tourmaline_gems', 12, 25000, 300, 1, [ 'raw_materials/gems' ]),
		Product.new( 'spinel_gems', 12, 17500, 300, 1, [ 'raw_materials/gems' ]),
		Product.new( 'garnet_gems', 12, 12500, 300, 1, [ 'raw_materials/gems' ]),
		Product.new( 'tanzanite_gems', 12, 5000, 300, 1, [ 'raw_materials/gems' ]),
		Product.new( 'beryl_gems', 12, 4000, 300, 1, [ 'raw_materials/gems' ]),
		Product.new( 'zircon_gems', 12, 7500, 300, 1, [ 'raw_materials/gems' ]),
		Product.new( 'topaz_gems', 12, 7500, 300, 1, [ 'raw_materials/gems' ]),
		Product.new( 'aquamarine_gems', 12, 4000, 300, 1, [ 'raw_materials/gems' ]),
		Product.new( 'chrysoberyl_gems', 30, 2500, 300, 1, [ 'raw_materials/gems' ]),
		Product.new( 'amethysts', 12, 300, 300, 1, [ 'raw_materials/gems' ]),
		Product.new( 'garnet_gems', 12, 4000, 300, 1, [ 'raw_materials/gems' ]),
		
		
		# Manufacturing: parts or bulk tools
		Product.new( 'weapon_parts', 40, 800, 800, 250, [ 'manufactured/defense/terran', 'manufactured/terran' ]),
		Product.new( 'woodworking_tools', 40, 500, 500, 250, [ 'manufactured/industrial/terran', 'manufactured/terran' ]),
		Product.new( 'metalworking_tools', 40, 500, 500, 250, [ 'manufactured/industrial/terran', 'manufactured/terran' ]),
		Product.new( 'slaughterhouse_tools', 40, 500, 500, 250, [ 'manufactured/food/terran', 'manufactured/terran' ]),
		Product.new( 'gemcutter_tools', 40, 500, 500, 150, [ 'manufactured/luxury/terran', 'manufactured/terran' ]),
		
		# Large, individual, equipment:
		Product.new( 'tractor', 10, 4000, 4000, 1500, [ 'manufactured/farming/terran', 'manufactured/terran' ]),
		Product.new( 'hovercar', 10, 4000, 4000, 2500, [ 'manufactured/transport/terran', 'manufactured/terran' ]),
		Product.new( 'deep_core_drill', 1, 279000, 10000, 35000, [ 'manufactured/mining', 'manufactured/terran' ]),
		Product.new( 'mining_system', 3, 51000, 10000, 35000, [ 'manufactured/mining', 'manufactured/terran' ]),
		Product.new( 'transport_barge', 1, 85000, 10000, 21000, [ 'manufactured/transport/terran', 'manufactured/terran' ]),
		Product.new( 'grain_processor', 2, 58000, 10000, 19000, [ 'manufactured/farming/terran', 'manufactured/terran' ]),
		Product.new( 'ore_processor', 2, 38000, 10000, 24000, [ 'manufactured/mining', 'manufactured/terran' ]),

		# Generic luxury goods:		
		Product.new( 'jewelry', 12, 3500, 1000, 1, [ 'luxury/terran' ]),
		Product.new( 'expensive_jewelry', 5, 9500, 1000, 1, [ 'luxury/terran' ]),
		Product.new( 'statue', 12, 4000, 1000, 20, [ 'luxury/terran', 'taboo/human_depiction' ]),
		Product.new( 'hunting_trophy', 12, 4000, 1000, 20, [ 'luxury/terran', 'dead/thinking' ]),
		
		# Consumables:
		Product.new( 'surgical_supplies', 20, 200, 1000, 10, [ 'consumables/medical/terran', 'consumables/terran' ]),
		Product.new( 'emergency_medical_kits', 80, 150, 1000, 10, [ 'consumables/medical/terran', 'consumables/terran' ]),
		Product.new( 'beauty_supplies', 300, 80, 1000, 10, [ 'consumables/personal/terran', 'consumables/terran', ]),
		Product.new( 'baby_powder', 300, 80, 1000, 10, [ 'consumables/personal/terran', 'consumables/terran', ]),
		Product.new( 'vitamins', 300, 80, 1000, 10, [ 'consumables/personal/terran', 'consumables/medical/terran', 'consumables/terran', ]),

		# Durable goods:
		Product.new( 'claw_trimmers', 20, 80, 1000, 10, [ 'durable/personal/terran/suvar', 'durable/terran/suvar', ]),
		Product.new( 'automatic_cooking_system', 20, 80, 1000, 150, [ 'durable/personal/terran/suvar', 'durable/terran/suvar', ]),
		
		# Food, processed or otherwise, sold in units of 50kg
		# except for special cases. Refrigeration or other
		# preservation mechanisms are included in price+mass.
		Product.new( 'grains', 1000, 12, 100, 50, [ 'consumables/food/terran' ]),
		Product.new( 'vegetables', 1000, 19, 100, 50, [ 'consumables/terran', 'consumables/food/terran', 'dead/thinking' ]),
		Product.new( 'fruit', 1000, 22, 100, 50, [ 'consumables/terran', 'consumables/food/terran', 'dead/thinking' ]),
		Product.new( 'fish', 1000, 31, 100, 50, [ 'consumables/terran', 'consumables/food/terran', 'dead/thinking' ]),
		Product.new( 'flour', 1000, 14, 100, 50, [ 'consumables/terran', 'consumables/food/terran', 'dead/thinking' ]),
		Product.new( 'sugar', 1000, 11, 100, 50, [ 'consumables/terran', 'consumables/food/terran', 'dead/thinking' ]),
		Product.new( 'hamburgers', 1000, 39, 100, 50, [ 'consumables/food/terran', 'dead/thinking', 'taboo/dead_cow' ]),
		Product.new( 'pork', 1000, 29, 100, 50, [ 'consumables/food/terran', 'dead/thinking', 'taboo/dead_pig' ]),
		Product.new( 'steak', 1000, 51, 100, 50, [ 'consumables/terran', 'consumables/food/terran', 'dead/thinking', 'taboo/dead_cow' ]),
		Product.new( 'veal', 1000, 89, 100, 50, [ 'consumables/terran', 'consumables/food/terran', 'dead/thinking', 'taboo/dead_cow', 'consumables/luxury/food' ]),
		Product.new( 'goat_meat', 1000, 37, 100, 50, [ 'consumables/terran', 'consumables/food/terran', 'dead/thinking' ]),
		Product.new( 'cheese', 1000, 28, 100, 50, [ 'consumables/food/terran/terran', 'live_origin/thinking', 'taboo/milk_product' ]),
		Product.new( 'fine_cheese', 1000, 131, 100, 50, [ 'consumables/food/terran', 'live_origin/thinking', 'taboo/milk_product', 'consumables/luxury/food' ]),
		Product.new( 'milk', 1000, 28, 100, 50, [ 'consumables/food/terran', 'live_origin/thinking', 'taboo/milk_product' ]),
		Product.new( 'sogross_beast_meat', 1000, 45, 100, 50, [ 'consumables/terran', 'consumables/food/terran', 'dead/thinking' ]),
		Product.new( 'gondron_tentacles', 1000, 33, 100, 50, [ 'consumables/terran', 'consumables/food/terran', 'dead/feeling' ]),
		Product.new( 'elder_tograk_flowers', 1000, 19, 100, 50, [ 'consumables/terran', 'consumables/food/terran' ]),
		Product.new( 'yothii_branches', 1000, 9, 100, 50, [ 'consumables/terran', 'consumables/food/terran' ]),
		Product.new( 'glowing_tangii_mushrooms', 1000, 21, 100, 50, [ 'consumables/terran', 'consumables/food/terran' ]),
		Product.new( 'synthetic_meat', 1000, 17, 100, 50, [ 'consumables/terran', 'consumables/food/terran', 'taboo/synthetic_food' ]),
		Product.new( 'synthetic_cheese', 1000, 19, 100, 50, [ 'consumables/terran', 'consumables/food/terran', 'taboo/synthetic_food' ]),
		Product.new( 'synthetic_fruit', 1000, 13, 100, 50, [ 'consumables/terran', 'consumables/food/terran', 'taboo/synthetic_food' ]),
		Product.new( 'synthetic_vegetables', 1000, 12, 100, 50, [ 'consumables/terran', 'consumables/food/terran', 'taboo/synthetic_food' ]),
		Product.new( 'military_rations', 1000, 7, 100, 50, [ 'consumables/terran', 'consumables/food/terran', 'taboo/synthetic_food' ]),

		# Pets and live food (for spiders)
		Product.new( 'feeding_spider', 50, 51, 100, 90, [ 'consumables/terran', 'consumables/food/terran/spider', 'live/thinking', 'pets/terran' ]),
		Product.new( 'large_feeding_spider', 1, 1700, 100, 1200, [ 'consumables/food/terran/spider', 'live/thinking', 'consumables/luxury/food' ]),
		Product.new( 'house_cat', 12, 380, 2400, 20, [ 'live/thinking/house_cat', 'taboo/house_cat', 'pets/terran' ]),
		Product.new( 'dog', 12, 80, 1200, 40, [ 'live/thinking/dog', 'pets/terran' ]),
		Product.new( 'wingless_ooreon', 12, 80, 1200, 30, [ 'live/thinking', 'pets/terran' ]),
		
		# Slaves, including food and life support:
		Product.new( 'human_child_slave', 10, 8000, 1000, 150, [ 'slaves/terran/human', 'live/sentient', 'live/sentient/human' ]),
		Product.new( 'human_worker_slave', 30, 10000, 1000, 250, [ 'slaves/common', 'slaves/terran/human', 'live/sentient', 'live/sentient/human' ]),
		Product.new( 'human_skilled_slave', 10, 30000, 1000, 250, [ 'slaves/common', 'slaves/terran/human', 'live/sentient', 'live/sentient/human' ]),
		Product.new( 'human_mated_pair', 10, 25000, 1000, 250, [ 'slaves/common', 'slaves/terran/human', 'live/sentient', 'live/sentient/human' ]),
		Product.new( 'suvar_child_slave', 5, 8000, 1000, 100, [ 'slaves/common', 'slaves/terran/suvar', 'live/sentient', 'live/sentient/human' ]),
		Product.new( 'suvar_worker_slave', 5, 10000, 1000, 200, [ 'slaves/common', 'slaves/terran/suvar', 'live/sentient', 'live/sentient/human' ]),
		Product.new( 'suvar_skilled_slave', 5, 30000, 1000, 200, [ 'slaves/common', 'slaves/terran/suvar', 'live/sentient', 'live/sentient/human' ]),
		Product.new( 'suvar_child_male', 1, 35000, 1000, 150, [ 'slaves/common', 'slaves/terran/suvar', 'live/sentient', 'live/sentient/human' ]),
		Product.new( 'suvar_breeding_male', 1, 65000, 1000, 150, [ 'slaves/common', 'slaves/terran/suvar', 'live/sentient', 'live/sentient/human' ]),
		
		# Exceptionally rare slaves, only available at select locations
		Product.new( 'suvar_prime_slave', 1, 950000, 1000, 200, [ 'slaves/rare', 'slaves/terran/suvar', 'live/sentient', 'live/sentient/human' ]),
		Product.new( 'spider_slave', 1, 1240000, 1000, 1500, [ 'slaves/rare', 'slaves/terran/spider', 'live/sentient', 'live/sentient/human' ]),
		Product.new( 'ancient_spider_slave', 1, 4600000, 1000, 1500, [ 'slaves/rare', 'slaves/terran/spider', 'live/sentient', 'live/sentient/human' ]),
		Product.new( 'exotic_human_slave', 10, 110000, 1000, 200, [ 'slaves/rare', 'slaves/terran/human', 'live/sentient', 'live/sentient/human' ]),
		
		# Highly-illegal items made from killing a sentient being
		Product.new( 'human_skin_paper', 10, 1000, 10000, 1, [ 'dead/sentient/terran/human' ]),
		Product.new( 'human_bone_sculptures', 10, 13500, 10000, 1, [ 'dead/sentient/terran/human' ]),
		Product.new( 'suvar_bone_sculptures', 10, 28000, 10000, 1, [ 'dead/sentient/terran/suvar' ]),
		Product.new( 'spider_armor', 10, 28000, 10000, 1, [ 'dead/sentient/terran/spider' ]),
		Product.new( 'human_meat', 10, 1000, 10000, 1, [ 'dead/sentient/terran/human', 'consumables/food/terran' ]),
		Product.new( 'suvar_meat', 10, 2000, 10000, 1, [ 'dead/sentient/terran/suvar', 'consumables/food/terran' ]),
		Product.new( 'suvar_pelt', 10, 26000, 10000, 10, [ 'dead/sentient/terran/suvar' ]),
		Product.new( 'suvar_paw', 10, 3000, 10000, 3, [ 'dead/sentient/terran/suvar' ]),
		Product.new( 'spider_leg', 10, 8500, 10000, 3, [ 'dead/sentient/terran/suvar' ]),
	], false, true)

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
