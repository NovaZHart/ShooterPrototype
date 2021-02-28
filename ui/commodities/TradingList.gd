extends Tree

export var increment_texture: Texture
export var decrement_texture: Texture

var max_cargo: int = 20000
var mine: Commodities.ManyProducts = Commodities.ManyProducts.new()
var here: Commodities.ManyProducts = Commodities.ManyProducts.new()

signal product_selected
signal no_product_selected
signal cargo_mass_changed

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

func set_title_and_width(column: int,title: String,font: Font,min_width: int):
	var text = title
	var width = 0
	for i in range(30):
		text = ' '.repeat(i) + title + ' '.repeat(i)
		width = font.get_string_size(text).x
		if width>=min_width:
			break
	set_column_title(column,text)
	set_column_min_width(column,width+6)

func _ready():
	set_column_titles_visible(true)
	var font = get_font('default_font')
	var number_size = font.get_char_size(ord('0'),ord('0'))
	var min_width = number_size.x*7.5
	set_title_and_width(0,'Product',font,min_width)
	set_title_and_width(1,'Price',font,min_width)
	set_title_and_width(2,'Cargo',font,min_width)
	set_title_and_width(3,'Buy/Sell',font,increment_texture.get_width()+decrement_texture.get_width()+10)
	set_title_and_width(4,'For Sale',font,min_width)
	for c in [ 1,2,3,4 ]:
		set_column_expand(c,false)

func clear_list():
	utils.Tree_clear(self)
	mine.clear()
	here.clear()

func populate_list(system_path,ship_design):
	clear_list()
	var ship = ship_design.assemble_ship()
	max_cargo = int(round(ship.combined_stats['max_cargo']))*1000
	var now_cargo: int = 0
	# Populate the data structures:
	if ship.cargo:
		mine.add_products(ship.cargo)
		now_cargo = ship.cargo.get_mass()
	emit_signal('cargo_mass_changed',now_cargo,max_cargo)
	var system_node = game_state.systems.get_node_or_null(system_path)
	if system_node:
		system_node.list_products(Commodities.commodities,here,true)
		for id in here.all:
			var product = here.all[id]
			var count = product[Commodities.Products.QUANTITY_INDEX]
			product[Commodities.Products.QUANTITY_INDEX] = \
				int(round(count*(0.2+randf()*1.6)))
		here.remove_absent_products()
	else:
		push_warning('No node at player location '+str(Player.player_location))
	if mine.all:
		here.add_products(mine.all,null,null,null,true,null,   true   )
	if here.all:
		mine.add_products(here.all,null,null,null,true,null,   true   )
	
	# Populate the tree:
	var root: TreeItem = create_item()
	var names: Array = mine.by_name.keys()
	names.sort()
	for product_name in names:
		var item: TreeItem = create_item(root)
		var mine_id: int = mine.by_name[product_name]
		var here_id: int = here.by_name[product_name]
		var entry_mine: Array = mine.all[mine_id]
		var entry_here: Array = here.all[here_id]
		# FIXME: proper display name
		var price: float = max(0.0,entry_here[Commodities.Products.VALUE_INDEX])
		var fine: float = max(0.0,entry_here[Commodities.Products.FINE_INDEX])
		var mass: float = max(0.0,entry_here[Commodities.Products.MASS_INDEX])
# warning-ignore:narrowing_conversion
		var count_mine: int = max(0,entry_mine[Commodities.Products.QUANTITY_INDEX])
# warning-ignore:narrowing_conversion
		var count_here: int = max(0,entry_here[Commodities.Products.QUANTITY_INDEX])
		var display_name: String = product_name.capitalize()
		var tooltip: String = display_name+'\n Price '+str(price)+'\n Fine '+\
			str(fine)+'\n Mass '+str(mass)+' kg'
		item.set_text(0,display_name)
		item.set_metadata(0,product_name)
		item.set_editable(0,false)
		item.set_tooltip(0,tooltip)
		item.set_text(1,str(price))
		item.set_metadata(1,[price,mass,count_here+count_mine,mine_id,here_id])
		item.set_editable(1,false)
		item.set_tooltip(1,tooltip)
		item.set_text(2,str(count_mine))
		item.set_metadata(2,count_mine)
		item.set_editable(2,true)
		item.set_tooltip(2,'Number of items in your cargo hold. Click to edit.')
		item.add_button(3,increment_texture,0)
		item.add_button(3,decrement_texture,1)
		item.set_tooltip(3,'Buy/Sell\n Click: ±1\n Shift-click: ±10\n Control-click: ±10%\n Shift-Control-click: ±all')
		item.set_text(4,str(count_here))
		item.set_metadata(4,count_here)
		item.set_editable(4,true)
		item.set_tooltip(4,'Number of items in stock here. Click to edit.')

func try_set_quantity(item: TreeItem, change: int) -> bool:
	var count_mine = item.get_metadata(2)
	var count_here = item.get_metadata(4)
# warning-ignore:narrowing_conversion
	change = clamp(change,-count_mine,count_here)
	var other_ids: Array = mine.all.keys()
	var etc = item.get_metadata(1)
	var mine_id = etc[3]
	var here_id = etc[4]
	other_ids.erase(mine_id)
#	var price = etc[0]
	var item_mass = max(1,etc[1])
	var remaining_mass = max_cargo-int(round(mine.get_mass(other_ids)))
# warning-ignore:narrowing_conversion
	change = min(change,remaining_mass/item_mass-count_mine)
	# FIXME: Check cargo capacity
	# FIXME: Check money
	mine.all[mine_id][Commodities.Products.QUANTITY_INDEX] += change
	here.all[here_id][Commodities.Products.QUANTITY_INDEX] -= change
	item.set_text(2,str(count_mine+change))
	item.set_metadata(2,count_mine+change)
	item.set_text(4,str(count_here-change))
	item.set_metadata(4,count_here-change)
	emit_signal('cargo_mass_changed',mine.get_mass(),max_cargo)
	return true

func refresh_item_quantities(_parent: TreeItem, item: TreeItem) -> void:
	for i in [ 2, 4 ]:
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
	if column==2:
		change = count-item.get_metadata(2)
	elif column==4:
		change = item.get_metadata(4)-count
	var _discard = try_set_quantity(item,change)

func _on_Tree_button_pressed(item, _column, id):
	var change: int = -1 if id else 1
	var shift: bool = Input.is_key_pressed(KEY_SHIFT)
	var control: bool = Input.is_key_pressed(KEY_CONTROL)
	if shift and control:
		change*=item.get_metadata(1)[2]
	elif control:
		change=int(ceil(change*item.get_metadata(1)[2]*0.1))
	elif shift:
		change*=10
	var _discard = try_set_quantity(item, change)

func _on_Tree_item_selected():
	var selected = get_selected()
	var meta = selected.get_metadata(0)
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
		var mine_id = etc[3]
		var here_id = etc[4]
		here.all[here_id][Commodities.Products.QUANTITY_INDEX] += \
			mine.all[mine_id][Commodities.Products.QUANTITY_INDEX]
		mine.all[mine_id][Commodities.Products.QUANTITY_INDEX]=0
		item.set_text(2,str(0))
		item.set_metadata(2,0)
		var all = etc[2]
		item.set_text(4,str(all))
		item.set_metadata(4,all)
		item=item.get_next()
	emit_signal('cargo_mass_changed',0,max_cargo)
