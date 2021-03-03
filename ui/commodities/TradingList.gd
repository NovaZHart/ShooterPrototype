extends Tree

export var increment_texture: Texture
export var decrement_texture: Texture

const NAME_COLUMN: int = 0
const PRICE_COLUMN: int = 1
const MINE_COLUMN: int = 2
const BUTTON_COLUMN: int = 3
const HERE_COLUMN: int = 4

const PRICE_ELEMENT: int = 0
const MASS_ELEMENT: int = 1
const QUANTITY_ELEMENT: int = 2
const MINE_ID_ELEMENT: int = 3
const HERE_ID_ELEMENT: int = 04

var max_cargo: int = 20000
var mine: Commodities.ManyProducts = Commodities.ManyProducts.new()
var here: Commodities.ManyProducts = Commodities.ManyProducts.new()
var last_sort_method: int = 1

signal product_selected
signal no_product_selected
signal cargo_mass_changed
signal product_data_changed
signal all_product_data_changed

func get_product_names():
	return here.by_name.keys()

#func test_commodities():
#	print('TEST')
#	var matches = Commodities.commodities.ids_for_tags(['intoxicant/terran'])
#	print('matches: '+str(matches))
#	for id in matches:
#		print('  id '+str(id)+' = '+str(Commodities.commodities.all[id]))
#	print('subset:')
#	var subset = Commodities.commodities.make_subset(matches)
#	print(subset.dump())
#	var decoded = Commodities.ManyProducts.new()
#	decoded.decode(subset.all)
#	print('decoded copy:')
#	print(decoded.dump())
#	subset.remove_product_id(0)
#	print('subset after removing 0:')
#	print(subset.dump())
#
#	var data:Array = decoded.all[0]
#	subset.add_product(data[0],data[Commodities.Products.VALUE_INDEX],
#		data[Commodities.Products.FINE_INDEX],
#		data[Commodities.Products.QUANTITY_INDEX],
#		data[Commodities.Products.MASS_INDEX],
#		data.slice(Commodities.Products.FIRST_TAG_INDEX,len(data)))
#	print('subset after adding 0 back in from decoded copy:')
#	print(subset.dump())
#
#	var modified = Commodities.ManyProducts.new()
#	modified.add_products(decoded,30,20,10,false)
#	print('New set with 30x quantity, 20x value, 10x fine:')
#	print(modified.dump())
#	modified.add_products(decoded,30,20,10,false)
#	modified.add_products(decoded,30,20,10,false)
#	print('Add that two more times:')
#	print(modified.dump())
#	modified.add_products(Commodities.commodities,5,null,null,true,
#		Commodities.commodities.ids_for_tags(['manufactured/mining','raw_materials/metal']))
#	print('Add items from some more tags:')
#	print(modified.dump())
#	print('END TEST')

func _ready():
	set_column_titles_visible(true)
	var font = get_font('normal_font')
	var number_size = font.get_char_size(ord('0'),ord('0'))
	var min_width = number_size.x*7.5
	utils.Tree_set_title_and_width(self,NAME_COLUMN,'Product',font,min_width)
	utils.Tree_set_title_and_width(self,PRICE_COLUMN,'Price',font,min_width)
	utils.Tree_set_title_and_width(self,MINE_COLUMN,'Cargo',font,min_width)
	utils.Tree_set_title_and_width(self,BUTTON_COLUMN,'Buy/Sell',
		font,increment_texture.get_width()+decrement_texture.get_width()+10)
	utils.Tree_set_title_and_width(self,HERE_COLUMN,'For Sale',font,min_width)
	for c in [ PRICE_COLUMN, MINE_COLUMN, BUTTON_COLUMN, HERE_COLUMN ]:
		set_column_expand(c,false)

func clear_list():
	utils.Tree_clear(self)
	mine.clear()
	here.clear()

func populate_list(products,ship_design):
	clear_list()
	var ship = ship_design.assemble_ship()
	max_cargo = int(round(ship.combined_stats['max_cargo']))*1000
	var now_cargo: int = 0
	# Populate the data structures:
	if ship_design.cargo:
		mine = ship_design.cargo
		now_cargo = mine.get_mass()
	emit_signal('cargo_mass_changed',now_cargo,max_cargo)
	here = products
	print('here before add '+str(here.all))
	if mine.all:
		here.add_products(mine.all,null,null,null,true,null,   true   )
	if here.all:
		mine.add_products(here.all,null,null,null,true,null,   true   )
	print('here after add '+str(here.all))
	
	# Populate the tree:
	var root: TreeItem = create_item()
	var names: Array = mine.by_name.keys()
	names.sort()
	for product_name in names:
		var mine_id: int = mine.by_name[product_name]
		var here_id: int = here.by_name[product_name]
		var entry_mine: Array = mine.all[mine_id]
		var entry_here: Array = here.all[here_id]
		# FIXME: proper display name
		var price: float = max(0.0,entry_here[Commodities.Products.VALUE_INDEX])
		var mass: float = max(0.0,entry_here[Commodities.Products.MASS_INDEX])
# warning-ignore:narrowing_conversion
		var count_mine: int = max(0,entry_mine[Commodities.Products.QUANTITY_INDEX])
# warning-ignore:narrowing_conversion
		var count_here: int = max(0,entry_here[Commodities.Products.QUANTITY_INDEX])
		if not count_mine and not count_here:
			continue # cannot buy or sell this
		var display_name: String = product_name.capitalize()
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
		data[MINE_ID_ELEMENT] = mine_id
		data[HERE_ID_ELEMENT] = here_id
		item.set_metadata(PRICE_COLUMN,data)
		item.set_editable(PRICE_COLUMN,false)
		item.set_tooltip(PRICE_COLUMN,'Price of '+display_name+' here: '+str(price)+'\nClick to see prices on map.')
		item.set_text(MINE_COLUMN,str(count_mine))
		item.set_metadata(MINE_COLUMN,count_mine)
		item.set_editable(MINE_COLUMN,true)
		item.set_tooltip(MINE_COLUMN,'Number of items in your cargo hold. Click to edit.')
		item.add_button(BUTTON_COLUMN,increment_texture,0)
		item.add_button(BUTTON_COLUMN,decrement_texture,1)
		item.set_tooltip(BUTTON_COLUMN,'Buy/Sell\n Click: ±1\n Shift-click: ±10\n Control-click: ±10%\n Shift-Control-click: ±all')
		item.set_text(HERE_COLUMN,str(count_here))
		item.set_metadata(HERE_COLUMN,count_here)
		item.set_editable(HERE_COLUMN,true)
		item.set_tooltip(HERE_COLUMN,'Number of items in stock here. Click to edit.')

func try_set_quantity(item: TreeItem, change: int) -> bool:
	var count_mine = item.get_metadata(MINE_COLUMN)
	var count_here = item.get_metadata(HERE_COLUMN)
	var other_ids: Array = mine.all.keys()
	var etc = item.get_metadata(PRICE_COLUMN)
	var mine_id = etc[MINE_ID_ELEMENT]
	var here_id = etc[HERE_ID_ELEMENT]
	other_ids.erase(mine_id)
#	var price = etc[0]
	var item_mass: float = max(1,etc[MASS_ELEMENT])
	var item_value: float = max(1,etc[PRICE_ELEMENT])
	var remaining_mass = max_cargo-int(round(mine.get_mass(other_ids)))
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
	mine.all[mine_id][Commodities.Products.QUANTITY_INDEX] += change
	here.all[here_id][Commodities.Products.QUANTITY_INDEX] -= change
# warning-ignore:narrowing_conversion
	Player.money -= int(round(change*item_value))
	emit_signal('product_data_changed',mine.all[mine_id][Commodities.Products.NAME_INDEX])
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
	var mine_product = mine.all.get(mine.by_name.get(item_name,null),null)
	var here_product = here.all.get(here.by_name.get(item_name,null),null)
	return [mine_product, here_product]

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
	while item:
		var etc = item.get_metadata(1)
		var mine_id = etc[MINE_ID_ELEMENT]
		var here_id = etc[HERE_ID_ELEMENT]
		here.all[here_id][Commodities.Products.QUANTITY_INDEX] += \
			mine.all[mine_id][Commodities.Products.QUANTITY_INDEX]
		mine.all[mine_id][Commodities.Products.QUANTITY_INDEX]=0
		Player.money += item.get_metadata(HERE_COLUMN)*etc[PRICE_ELEMENT]
		item.set_text(MINE_COLUMN,str(0))
		item.set_metadata(MINE_COLUMN,0)
		var all = etc[QUANTITY_ELEMENT]
		item.set_text(HERE_COLUMN,str(all))
		item.set_metadata(HERE_COLUMN,all)
		item=item.get_next()
	emit_signal('cargo_mass_changed',0,max_cargo)
	emit_signal('all_product_data_changed')

class TreeSort extends Reference:
	var column: int
	var index: int = 0
	var reverse: bool = false
	func _init(column_: int, index_: int = 0):
		column=column_
		index=index_
	func text_sort(a,b) -> bool:
		return reverse != (a.get_text(column)<b.get_text(column))
	func meta_sort(a,b) -> bool:
		return reverse != (a.get_metadata(column)<b.get_metadata(column))
	func meta_index_sort(a,b) -> bool:
		return reverse != (a.get_metadata(column)[index]<b.get_metadata(column)[index])

func tree_sort(sort_method:int,object: Object,method: String):
	if abs(last_sort_method)==abs(sort_method):
		sort_method=-last_sort_method
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

func _on_TradingList_column_title_pressed(column):
	if column==0:
		tree_sort(column+1,TreeSort.new(column),'text_sort')
	elif column==1:
		tree_sort(column+1,TreeSort.new(column,0),'meta_index_sort')
	elif column!=3:
		tree_sort(column+1,TreeSort.new(column),'meta_sort')
