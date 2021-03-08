extends Panel

const ButtonPanel = preload('res://ui/ButtonPanel.tscn')
var product_names: Array
var cargo_mass: float = 0
var max_cargo_mass: float = 9e9
var hover_name = null # : String or null
var selected_name = null # : String or null

func _ready():
	var info = Player.get_info_or_null()
	if info:
		$All/Left/Bottom/Tools/Label.text = info.display_name+' Market'
		$All/Right/Location.text = info.full_display_name()
	else:
		push_warning('Cannot find player location info')
	$All/Left/Bottom/Tools/Label.hint_tooltip = 'Cargo hold and sale items at '+info.full_display_name()
	Player.age_off_markets()
	var products = Player.update_markets_at(Player.player_location)
	if not products:
		push_error('Could not get market data for '+str(Player.player_location))
		products = Commodities.ManyProducts.new()
	if not Player.player_ship_design.cargo:
		Player.player_ship_design.cargo = Commodities.ManyProducts.new()
	var planet_info = Player.get_info_or_null()
	$All/Left/Bottom/TradingList.populate_list(products,Player.player_ship_design,planet_info)
	product_names = $All/Left/Bottom/TradingList.get_product_names()
	product_names.sort()
	$All/Right/Content/Top/BuySell.add_item('Buying Map',0)
	$All/Right/Content/Top/BuySell.add_item('Selling Map',1)
	_on_Content_resized()

func exit_to_orbit():
	var design = Player.player_ship_design
	design.cargo = $All/Left/Bottom/TradingList.mine.copy()
	design.cargo.remove_empty_products()
	print('marketplace thinks: '+str($All/Left/Bottom/TradingList.mine))
	print('design thinks: '+str(design.cargo))
	if design.cargo:
		var max_cargo = design.get_stats()['max_cargo']*1000
		if max_cargo and design.cargo.get_mass()>max_cargo:
			print('cargo '+str(design.cargo.get_mass())+'>'+str(max_cargo))
			var panel = ButtonPanel.instance()
			panel.set_label_text("Your ship cannot fit all of it's cargo.")
			var planet_info = Player.get_space_object_or_null()
			if planet_info and planet_info.services.has('shipeditor'):
				panel.add_button('Go to Shipyard','res://ui/ships/ShipDesignScreen.tscn')
			panel.set_cancel_text('Stay in Market')
			var parent = get_tree().get_root()
			parent.add_child(panel)
			panel.popup()
			while panel.visible:
				yield(get_tree(),'idle_frame')
			var result = panel.result
			parent.remove_child(panel)
			panel.queue_free()
			if result:
				$All/Left/Bottom/TradingList.here.remove_empty_products()
				game_state.call_deferred('change_scene',result)
			else:
				return # do not change scene
	$All/Left/Bottom/TradingList.here.remove_empty_products()
	game_state.change_scene('res://ui/OrbitalScreen.tscn')

func _input(event):
	if event.is_action_released('ui_depart'):
		get_tree().set_input_as_handled()
		exit_to_orbit()
	elif event is InputEventMouseMotion:
		var list = $All/Left/Bottom/TradingList
		var pos = utils.event_position(event) - list.rect_global_position
		var size = list.rect_size
		if pos.x>=0 and pos.y>=0 and pos.x<size.x and pos.y<size.y:
			var item_name = list.get_product_at_position(pos)
			if item_name is String and item_name!=hover_name:
				update_hover_info(item_name)
		elif selected_name and selected_name!=hover_name:
			update_hover_info(selected_name)

func _on_TradingList_cargo_mass_changed(cargo_mass_,max_cargo_mass_):
	cargo_mass=cargo_mass_
	max_cargo_mass=max_cargo_mass_
	$All/Right/CargoMass.text = 'Cargo '+str(cargo_mass)+'/'+str(max_cargo_mass)+' kg  Money: '+str(Player.money)

func starmap_show_product(index):
	var bs = $All/Right/Content/Top/BuySell
	if index==0:
		Commodities.select_no_commodity()
		bs.set_item_text(0,'Buying Map')
		bs.set_item_text(1,'Selling Map')
	else:
		var product_name = product_names[index-1]
		Commodities.select_commodity_with_name(product_name)
		product_name = product_name.capitalize()
		bs.set_item_text(0,'Purchase: '+product_name)
		bs.set_item_text(1,'Sale Value: '+product_name)
	$All/Right/Content/StarmapPanel.update_starmap_visuals()

func _on_BuySell_item_selected(index):
	$All/Right/Content/StarmapPanel.buy = index==0

func make_row3(one,two,three):
	return '[cell]'+str(one)+'[/cell][cell]  [/cell][cell]'+str(two) \
		+'[/cell][cell]  [/cell][cell]'+str(three)+'[/cell]'

func make_row4(one,two,three,four):
	return '[cell]'+str(one)+'[/cell][cell]  [/cell][cell]'+str(two) \
		+'[/cell][cell]  [/cell][cell]'+str(three)+'[/cell]' \
		+'[cell]  [/cell][cell]'+str(four)+'[/cell]'

func concoct_other_system_info(item_name,mine,here,display_name,price) -> String:
	var VALUE_INDEX = Commodities.Products.VALUE_INDEX
	var QUANTITY_INDEX = Commodities.Products.QUANTITY_INDEX
	var MASS_INDEX = Commodities.Products.MASS_INDEX
	var s: String = '[b]'+item_name.capitalize()+'[/b]\n[table=7]'
	s+=make_row4('  ','[b]Here[/b]','[b]At '+display_name+'[/b]','[b]Difference[/b]')
	s+=make_row4('Price',here[VALUE_INDEX],price,price-here[VALUE_INDEX])
	s+=make_row4('Mass per',here[MASS_INDEX],' ',' ')
	s+=make_row4('Available',here[QUANTITY_INDEX],' ',' ')
	s+=make_row4('In cargo',mine[QUANTITY_INDEX],' ',' ')
	s+=make_row4('Cargo mass',mine[QUANTITY_INDEX]*mine[MASS_INDEX],' ',' ')
	s+='[/table]\n'
	if len(here)>Commodities.Products.FIRST_TAG_INDEX:
		s+='\nTags:\n'
		for itag in range(Commodities.Products.FIRST_TAG_INDEX,len(here)):
			s+=' {*} '+here[itag]+'\n'
	return s

func concoct_hover_info(item_name,mine,here,norm) -> String:
	var VALUE_INDEX = Commodities.Products.VALUE_INDEX
	var FINE_INDEX = Commodities.Products.FINE_INDEX
	var QUANTITY_INDEX = Commodities.Products.QUANTITY_INDEX
	var MASS_INDEX = Commodities.Products.MASS_INDEX
	var s: String = '[b]'+item_name.capitalize()+'[/b]\n[table=5]'
	s+=make_row3('  ','[b]Here[/b]','[b]Typical[/b]')
	s+=make_row3('Price',here[VALUE_INDEX],norm[VALUE_INDEX])
	s+=make_row3('Fine',here[FINE_INDEX],norm[FINE_INDEX])
	s+=make_row3('Mass per',here[MASS_INDEX],' ')
	s+=make_row3('Available',here[QUANTITY_INDEX],' ')
	s+=make_row3('In cargo',mine[QUANTITY_INDEX],' ')
	s+=make_row3('Cargo mass',mine[QUANTITY_INDEX]*mine[MASS_INDEX],' ')
	s+='[/table]\n'
	if len(here)>Commodities.Products.FIRST_TAG_INDEX:
		s+='\nTags:\n'
		for itag in range(Commodities.Products.FIRST_TAG_INDEX,len(here)):
			s+=' {*} '+here[itag]+'\n'
	return s

func update_hover_info(item_name=null):
	if not item_name:
		item_name=hover_name
	hover_name=item_name
	if item_name:
		var norm = Commodities.commodities.all.get(
			Commodities.commodities.by_name.get(item_name,null),null)
		if not norm:
			return
		var pair = $All/Left/Bottom/TradingList.get_product_named(item_name)
		if pair and pair[0] and pair[1]:
			$All/Left/Bottom/Help.insert_bbcode(
				concoct_hover_info(item_name,pair[0],pair[1],norm),true)
			$All/Left/Bottom/Help.scroll_to_line(0)

func _on_TradingList_all_product_data_changed():
	update_hover_info()

func _on_TradingList_product_data_changed(item_name: String):
	update_hover_info(item_name)

func _on_TradingList_product_selected(item_name):
	var index = product_names.find(item_name)+1
	starmap_show_product(index)
	selected_name=item_name
	update_hover_info(selected_name)

func _on_Content_resized():
	$All/Right/CargoMass.margin_bottom = $All/Right/Content/Top.rect_size.y
	$All/Right/Location.margin_bottom = $All/Right/Content/Top.rect_size.y

func _on_StarmapPanel_hover_no_system():
	update_hover_info()

func _on_StarmapPanel_hover_over_player_location(_system_name,_system_display_name,_system_price):
	update_hover_info()

func _on_StarmapPanel_hover_over_system(_system_name,system_display_name,system_price):
	if hover_name and system_price and system_price>0:
		var mine = $All/Left/Bottom/TradingList.mine
		var mine_item = mine.all.get(mine.by_name.get(hover_name,-1),null)
		var here = $All/Left/Bottom/TradingList.here
		var here_item = here.all.get(here.by_name.get(hover_name,-1),null)
		if here_item and mine_item:
			var info: String = concoct_other_system_info(
				hover_name,mine_item,here_item,system_display_name,system_price)
			if info:
				$All/Left/Bottom/Help.insert_bbcode(info,true)
				$All/Left/Bottom/Help.scroll_to_line(0)
				return
	update_hover_info()
