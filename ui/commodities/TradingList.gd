extends Tree

export var show_profit: bool = false
export var show_mass: bool = true
export var buy_and_sell: bool = true
export var increment_texture: Texture
export var decrement_texture: Texture
export var market_type: int = 0

var NAME_COLUMN: int = 0
var PROFIT_COLUMN: int = 1
var MASS_COLUMN: int = 2
var PRICE_COLUMN: int = 3
var MINE_COLUMN: int = 4
var BUTTON_COLUMN: int = 5
var HERE_COLUMN: int = 6

const PRICE_ELEMENT: int = 0
const MASS_ELEMENT: int = 1
const QUANTITY_ELEMENT: int = 2
const MINE_ID_ELEMENT: int = 3
const HERE_ID_ELEMENT: int = 04

var max_cargo: int = 20000
var mine: Commodities.ManyProducts
var here: Commodities.ManyProducts
var last_sort_method: int = 1
var all_products: Commodities.ManyProducts
var product_names=null
var display_name_for: Dictionary = {}

signal product_selected
signal no_product_selected
signal cargo_mass_changed
signal product_data_changed
signal all_product_data_changed

func is_TradingList(): pass # Used for type detection; never called

func set_column_indices():
	var column_ids: Array = [ 'NAME', 'MASS', 'PROFIT', 'PRICE', 'MINE', 'BUTTON', 'HERE' ]
	if not buy_and_sell:
		column_ids.erase('BUTTON')
	if not show_profit:
		column_ids.erase('PROFIT')
	if not show_mass:
		column_ids.erase('MASS')
	NAME_COLUMN = column_ids.find('NAME')
	MASS_COLUMN = column_ids.find('MASS')
	PROFIT_COLUMN = column_ids.find('PROFIT')
	PRICE_COLUMN = column_ids.find('PRICE')
	MINE_COLUMN = column_ids.find('MINE')
	BUTTON_COLUMN = column_ids.find('BUTTON')
	HERE_COLUMN = column_ids.find('HERE')
	columns = len(column_ids)

func _ready():
	set_column_indices()
	if market_type == Commodities.MARKET_TYPE_COMMODITIES:
		all_products = Commodities.commodities
	elif market_type == Commodities.MARKET_TYPE_SHIP_PARTS:
		all_products = Commodities.ship_parts
	elif market_type == Commodities.MARKET_TYPE_UNKNOWN:
		all_products = Commodities.ManyProducts.new()
	else:
		push_error('Unknown market type '+str(market_type))
		all_products = Commodities.ManyProducts.new()
	set_column_titles_visible(true)
	var font = get_font('normal_font')
	var number_size = font.get_char_size(ord('0'),ord('0'))
	var min_width = number_size.x*7.5
	utils.Tree_set_title_and_width(self,NAME_COLUMN,'Product',font,min_width)
	if PROFIT_COLUMN>=0:
		utils.Tree_set_title_and_width(self,PROFIT_COLUMN,'Profit',font,min_width)
	if MASS_COLUMN>=0:
		utils.Tree_set_title_and_width(self,MASS_COLUMN,'Mass',font,min_width)
	utils.Tree_set_title_and_width(self,PRICE_COLUMN,'Price',font,min_width)
	utils.Tree_set_title_and_width(self,MINE_COLUMN,'Cargo',font,min_width)
	if BUTTON_COLUMN>=0:
		utils.Tree_set_title_and_width(self,BUTTON_COLUMN,'Buy/Sell',
			font,increment_texture.get_width()+decrement_texture.get_width()+10)
	utils.Tree_set_title_and_width(self,HERE_COLUMN,'For Sale',font,min_width)
	for c in [ PROFIT_COLUMN, PRICE_COLUMN, MASS_COLUMN, MINE_COLUMN, BUTTON_COLUMN, HERE_COLUMN ]:
		if c>=0:
			set_column_expand(c,false)

func clear_list():
	utils.Tree_clear(self)
#	if mine:
#		mine.clear()
	if here:
		here.clear()
		product_names=[]

func populate_list(all_known_products,products_here,ship_design):
	# Make sure we have no items in the tree:
	clear_list()
	
	# Set up the cargo mass stats and cargo hold info:
	if not ship_design.cargo:
		ship_design.cargo = Commodities.ManyProducts.new()
	var ship = ship_design.assemble_ship()
	max_cargo = int(round(ship.combined_stats['max_cargo']))*1000
	mine = ship_design.cargo
	var now_cargo = int(round(mine.get_mass()))
	ship.queue_free()
	emit_signal('cargo_mass_changed',now_cargo,max_cargo)
	
	# Record the list of items for sale:
	here = products_here
	all_products = all_known_products.duplicate(true)
	all_products.remove_named_products(here,true)
	
	# Ensure there are records in the cargo hold for all products for sale.
	# Products not in the cargo hold will have quantity zero.
	mine.add_products(here,null,null,null,true,null,true)
	
	# Populate the tree:
	var root: TreeItem = create_item()
	var names: Array = here.by_name.keys()
	names.sort()
	for product_name in names:
		populate_product_named(product_name,root)
	
	# Sort the products ascending by name:
	product_names = here.by_name.keys()
	product_names.sort()
	apply_last_sort_method()

func populate_product_named(product_name,root):
		var entry_norm = all_products.by_name.get(product_name,null)
		if not entry_norm:
			return # product is not of the correct type for this list
		var entry_mine: Commodities.Product = mine.by_name.get(product_name,null)
		var entry_here: Commodities.Product = here.by_name.get(product_name,null)
		#var entry_norm: Commodities.Product = all_products.by_name.get(product_name,null)
		var price: float = max(0.0,entry_here.value)
		var norm_price: float
		if entry_norm:
			norm_price = max(0.0,entry_norm.value)
		else:
			norm_price = price
		var diff: float = norm_price-price
		var mass: float = max(0.0,entry_here.mass)
# warning-ignore:narrowing_conversion
		var count_mine: int = max(0,entry_mine.quantity)
# warning-ignore:narrowing_conversion
		var count_here: int = max(0,entry_here.quantity)
#		if not show_all_products and not count_mine and not count_here:
#			return # cannot buy or sell this
		# FIXME: proper display name for products
		var display_name: String = product_name.capitalize()
		if product_name.begins_with('res://'):
			var title_name = text_gen.title_for_scene_path(product_name)
			if title_name:
				display_name = title_name
		display_name_for[product_name] = display_name
		var item: TreeItem = create_item(root)
		item.set_text(NAME_COLUMN,display_name)
		item.set_metadata(NAME_COLUMN,product_name)
		item.set_editable(NAME_COLUMN,false)
		item.set_tooltip(NAME_COLUMN,display_name+'\nClick to see prices on map.')
		item.set_text(PRICE_COLUMN,str(price))
		var data: Array = [0,0,0,0,0]
		data[PRICE_ELEMENT] = price
		data[MASS_ELEMENT] = mass
		data[QUANTITY_ELEMENT] = count_here+count_mine
		data[MINE_ID_ELEMENT] = product_name
		data[HERE_ID_ELEMENT] = product_name
		if MASS_COLUMN>0:
			item.set_text(MASS_COLUMN,str(mass))
			item.set_metadata(MASS_COLUMN,mass)
			item.set_editable(MASS_COLUMN,false)
			item.set_tooltip(MASS_COLUMN,display_name+': mass per item in kg')
		if PROFIT_COLUMN>0:
			item.set_text(PROFIT_COLUMN,str(diff))
			item.set_metadata(PROFIT_COLUMN,diff)
			item.set_editable(PROFIT_COLUMN,false)
			item.set_tooltip(PROFIT_COLUMN,display_name+': Difference between average price and price here.\nHere: '+str(price)+'\nAverage: '+str(norm_price)+'.\nClick to see prices on map.')
		item.set_metadata(PRICE_COLUMN,data)
		item.set_editable(PRICE_COLUMN,false)
		item.set_tooltip(PRICE_COLUMN,'Price of '+display_name+' here: '+str(price)+'\nClick to see prices on map.')
		item.set_text(MINE_COLUMN,str(count_mine))
		item.set_metadata(MINE_COLUMN,count_mine)
		item.set_editable(MINE_COLUMN,buy_and_sell)
		if buy_and_sell:
			item.set_tooltip(MINE_COLUMN,'Number of items in your cargo hold. Click to edit.')
		else:
			item.set_tooltip(MINE_COLUMN,'Number of items in your cargo hold.')
		if buy_and_sell:
			item.add_button(BUTTON_COLUMN,increment_texture,0)
			item.add_button(BUTTON_COLUMN,decrement_texture,1)
			item.set_tooltip(BUTTON_COLUMN,'Buy/Sell\n Click: ±1\n Shift-click: ±10\n Control-click: ±10%\n Shift-Control-click: ±all')
		item.set_text(HERE_COLUMN,str(count_here))
		item.set_metadata(HERE_COLUMN,count_here)
		item.set_editable(HERE_COLUMN,buy_and_sell)
		if buy_and_sell:
			item.set_tooltip(HERE_COLUMN,'Number of items in stock here. Click to edit.')
		else:
			item.set_tooltip(HERE_COLUMN,'Number of items in stock here.')

func try_set_quantity(item: TreeItem, change: int) -> bool:
	var count_mine = item.get_metadata(MINE_COLUMN)
	var count_here = item.get_metadata(HERE_COLUMN)
	var other_names: Array = mine.by_name.keys()
	var etc = item.get_metadata(PRICE_COLUMN)
	var mine_name = etc[MINE_ID_ELEMENT]
	var here_name = etc[HERE_ID_ELEMENT]
	other_names.erase(mine_name)
#	var price = etc[0]
	var item_mass: float = max(1,etc[MASS_ELEMENT])
	var item_value: float = max(1,etc[PRICE_ELEMENT])
	var remaining_mass = max_cargo-int(round(mine.get_mass(other_names)))
	var remaining_value = Player.money + item_value*count_mine
# warning-ignore:narrowing_conversion
	change = min(change,remaining_mass/item_mass-count_mine)
	if item_value:
# warning-ignore:narrowing_conversion
		change = min(change,remaining_value/item_value-count_mine)
# warning-ignore:narrowing_conversion
	change = clamp(change,-count_mine,count_here)
	# FIXME: Check cargo capacity
	# FIXME: Check money
	mine.by_name[mine_name].quantity += change
	here.by_name[here_name].quantity -= change
# warning-ignore:narrowing_conversion
	Player.money -= int(round(change*item_value))
	emit_signal('product_data_changed',mine_name)
	item.set_text(MINE_COLUMN,str(count_mine+change))
	item.set_metadata(MINE_COLUMN,count_mine+change)
	item.set_text(HERE_COLUMN,str(count_here-change))
	item.set_metadata(HERE_COLUMN,count_here-change)
	emit_signal('cargo_mass_changed',mine.get_mass(),max_cargo)
	return true

func refresh_item_quantities(_parent: TreeItem, item: TreeItem) -> void:
	for i in [ MINE_COLUMN, HERE_COLUMN ]:
		var meta=item.get_metadata(i)
		if meta!=null:
			item.set_text(i,str(meta))

func refresh_quantities():
	var _discard = utils.Tree_depth_first(get_root(),self,'refresh_item_quantities')

func _on_Tree_item_edited():
	var item: TreeItem = get_selected()
	var column: int = get_selected_column()
	var text: String = item.get_text(column)
	if not text.is_valid_integer():
		item.set_text(column,str(item.get_metadata(column)))
		return
	var count = max(0,int(text))
	var change = 0
	if column==MINE_COLUMN:
		change = count-item.get_metadata(MINE_COLUMN)
	elif column==HERE_COLUMN:
		change = item.get_metadata(HERE_COLUMN)-count
	var _discard = try_set_quantity(item,change)

func get_product_named(item_name: String) -> Array:
	var mine_product = mine.by_name.get(item_name,null)
	var here_product = here.by_name.get(item_name,null)
	return [mine_product, here_product]

func get_selected_product(): # -> String or null
	var item = get_selected()
	return item.get_metadata(NAME_COLUMN) if item else null

func get_product_at_position(relative_position: Vector2): # -> String or null
	var item = get_item_at_position(relative_position)
	return item.get_metadata(NAME_COLUMN) if item else null

func _on_Tree_button_pressed(item, _column, id):
	var change: int = -1 if id else 1
	var shift: bool = Input.is_key_pressed(KEY_SHIFT)
	var control: bool = Input.is_key_pressed(KEY_CONTROL)
	if shift and control:
		change*=item.get_metadata(PRICE_COLUMN)[QUANTITY_ELEMENT]
	elif control:
		change=int(ceil(change*item.get_metadata(PRICE_COLUMN)[QUANTITY_ELEMENT]*0.1))
	elif shift:
		change*=10
	var _discard = try_set_quantity(item, change)

func _on_Tree_item_selected():
	var selected = get_selected()
	var meta = selected.get_metadata(NAME_COLUMN)
	if meta and meta is String:
		emit_signal('product_selected',meta)

func _on_Tree_focus_exited():
	refresh_quantities()

func _on_Tree_nothing_selected():
	emit_signal('no_product_selected')

func _on_SellAll_pressed():
	var root = get_root()
	if not root:
		return
	var item = root.get_children()
	var mass_lost = 0
	while item:
		var product_name = item.get_metadata(NAME_COLUMN)
		var norm_id: int = all_products.by_name.get(product_name,-1)
		if norm_id<0:
			continue
		var etc = item.get_metadata(PRICE_COLUMN)
		var mine_name: String = etc[MINE_ID_ELEMENT]
		var here_name: String = etc[HERE_ID_ELEMENT]
		var mine_prod: Commodities.Product = mine.by_name[mine_name]
		var here_prod: Commodities.Product = here.by_name[here_name]
		var my_quantity = mine_prod.quantity
		var unit_mass = here_prod.mass
		here_prod.quantity += mine_prod.quantity
		mine_prod.quantity = 0
		mass_lost += my_quantity * unit_mass
		var sale: float = item.get_metadata(MINE_COLUMN)*etc[PRICE_ELEMENT]
		assert(sale>=0 and sale<1e9)
		Player.money += sale
		item.set_text(MINE_COLUMN,str(0))
		item.set_metadata(MINE_COLUMN,0)
		var all = etc[QUANTITY_ELEMENT]
		item.set_text(HERE_COLUMN,str(all))
		item.set_metadata(HERE_COLUMN,all)
		item=item.get_next()
	print('SellAll sold '+str(mass_lost)+' mass of items')
	if mass_lost>0:
		emit_signal('cargo_mass_changed',mine.get_mass(),max_cargo)
	emit_signal('all_product_data_changed')

class TreeSort extends Reference:
	var column: int
	var index: int = 0
	var reverse: bool = false
	func _init(column_: int, index_: int = 0):
		column=column_
		index=index_
	func text_sort(a,b) -> bool:
		if reverse:
			return a.get_text(column)>b.get_text(column)
		else:
			return a.get_text(column)<b.get_text(column)
	func meta_sort(a,b) -> bool:
		if reverse:
			return a.get_metadata(column)>b.get_metadata(column)
		else:
			return a.get_metadata(column)<b.get_metadata(column)
	func meta_index_sort(a,b) -> bool:
		if reverse:
			return a.get_metadata(column)[index]>b.get_metadata(column)[index]
		else:
			return a.get_metadata(column)[index]<b.get_metadata(column)[index]

func tree_sort(sort_method:int,object: Object,method: String):
	if abs(last_sort_method)==abs(sort_method):
		sort_method=-last_sort_method
	if not sort_method:
		sort_method = last_sort_method
	else:
		last_sort_method=sort_method
	object.reverse = sort_method<0
	var items: Array = []
	var scan = get_root().get_children()
	while scan:
		items.append(scan)
		scan = scan.get_next()
	items.sort_custom(object,method)
	var info = []
	for item in items:
		if method=='meta_sort':
			info.append(item.get_metadata(object.column))
		else:
			info.append(item.get_text(object.column))
		item.move_to_bottom()

func apply_last_sort_method():
	var column = abs(last_sort_method)-1
	if column==NAME_COLUMN:
		tree_sort(0,TreeSort.new(column),'text_sort')
	elif column==PRICE_COLUMN:
		tree_sort(0,TreeSort.new(column,0),'meta_index_sort')
	elif column!=BUTTON_COLUMN:
		tree_sort(0,TreeSort.new(column),'meta_sort')

func _on_TradingList_column_title_pressed(column):
	if column==NAME_COLUMN:
		tree_sort(column+1,TreeSort.new(column),'text_sort')
	elif column==PRICE_COLUMN:
		tree_sort(column+1,TreeSort.new(column,0),'meta_index_sort')
	elif column!=BUTTON_COLUMN:
		tree_sort(column+1,TreeSort.new(column),'meta_sort')
