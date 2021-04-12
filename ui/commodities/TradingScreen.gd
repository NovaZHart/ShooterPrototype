extends Panel

const ButtonPanel = preload('res://ui/ButtonPanel.tscn')
var cargo_mass: float = 0
var max_cargo_mass: float = 9e9
var hover_name = null # : String or null
var trading_list: Tree
var is_updating: int = 0

func _ready():
	$All/Left/Bottom/Tabs.set_tab_title(0,'Commodities')
	$All/Left/Bottom/Tabs.set_tab_title(1,'Ship Parts')
	trading_list = $All/Left/Bottom/Tabs/Market
	var info = Player.get_info_or_null()
	if info:
		$All/Right/Location.text = info.full_display_name()
	else:
		push_warning('Cannot find player location info')
	
	if not Player.player_ship_design.cargo:
		Player.player_ship_design.cargo = Commodities.ManyProducts.new()
	
	var planet_info = Player.get_info_or_null()
	
	Player.age_off_markets()
	var commodities = Player.update_markets_at(Player.player_location)
	if not commodities:
		push_error('Could not get commodity data for '+str(Player.player_location))
		commodities = Commodities.ManyProducts.new()
	$All/Left/Bottom/Tabs/Market.populate_list(commodities,Player.player_ship_design,planet_info)
	
	Player.age_off_ship_parts()
	var ship_parts = Player.update_ship_parts_at(Player.player_location)
	if not ship_parts:
		push_error('Could not get ship part data for '+str(Player.player_location))
		ship_parts = Commodities.ManyProducts.new()
	$All/Left/Bottom/Tabs/ShipParts.populate_list(ship_parts,Player.player_ship_design,planet_info)
	
	_on_Tabs_tab_changed($All/Left/Bottom/Tabs.current_tab)
	$All/Left/Bottom/Tabs/Market.product_names.sort()
	$All/Left/Bottom/Tabs/ShipParts.product_names.sort()
	$All/Right/Content/Top/BuySell.add_item('Buying Map',0)
	$All/Right/Content/Top/BuySell.add_item('Selling Map',1)
	_on_Content_resized()

func exit_to_orbit():
	var design = Player.player_ship_design
	design.cargo = $All/Left/Bottom/Tabs/Market.mine.copy()
	design.cargo.add_products($All/Left/Bottom/Tabs/ShipParts.mine,null,null,null)
	design.cargo.remove_empty_products()
	var message = null
	if Player.money<0:
		message = "You don't have enough money to buy your ship!"
	elif design.cargo:
		var max_cargo = design.get_stats()['max_cargo']*1000
		if max_cargo and design.cargo.get_mass()>max_cargo:
			message = "Your ship cannot fit all of its cargo!"
	if message:
		var panel = ButtonPanel.instance()
		panel.set_label_text(message)
		var planet_info = Player.get_space_object_or_null()
		if planet_info and planet_info.has_shipyard():
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
			$All/Left/Bottom/Tabs/Market.here.remove_empty_products()
			game_state.call_deferred('change_scene',result)
		else:
			return # do not change scene
	$All/Left/Bottom/Tabs/Market.here.remove_empty_products()
	game_state.change_scene('res://ui/OrbitalScreen.tscn')

func _input(event):
	if event.is_action_released('ui_depart'):
		get_tree().set_input_as_handled()
		exit_to_orbit()
	elif event is InputEventMouseMotion:
		var pos = utils.event_position(event) - trading_list.rect_global_position
		var size = trading_list.rect_size
		if pos.x>=0 and pos.y>=0 and pos.x<size.x and pos.y<size.y:
			var item_name = trading_list.get_product_at_position(pos)
			if item_name is String:
				return update_hover_info(item_name,false)
		update_hover_info(null,false)

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
		var product_name = trading_list.product_names[index-1]
		var display_name = trading_list.display_name_for[product_name]
		Commodities.select_commodity_with_name(product_name,trading_list.market_type)
		bs.set_item_text(0,'Purchase: '+display_name)
		bs.set_item_text(1,'Sale Value: '+display_name)
	$All/Right/Content/StarmapPanel.update_starmap_visuals()

func _on_BuySell_item_selected(index):
	$All/Right/Content/StarmapPanel.buy = index==0
#
#func make_row3(one,two,three):
#	return '[cell]'+str(one)+'[/cell][cell]  [/cell][cell]'+str(two) \
#		+'[/cell][cell]  [/cell][cell]'+str(three)+'[/cell]'
#
#func make_row4(one,two,three,four):
#	return '[cell]'+str(one)+'[/cell][cell]  [/cell][cell]'+str(two) \
#		+'[/cell][cell]  [/cell][cell]'+str(three)+'[/cell]' \
#		+'[cell]  [/cell][cell]'+str(four)+'[/cell]'
#
#func concoct_other_system_info(item_name,mine,here,display_name,price) -> String:
#	var VALUE_INDEX = Commodities.Products.VALUE_INDEX
#	var QUANTITY_INDEX = Commodities.Products.QUANTITY_INDEX
#	var MASS_INDEX = Commodities.Products.MASS_INDEX
#	var s: String = '[b]'+item_name.capitalize()+'[/b]\n[table=7]'
#	s+=make_row4('  ','[b]Here[/b]','[b]At '+display_name+'[/b]','[b]Difference[/b]')
#	s+=make_row4('Price',here[VALUE_INDEX],price,price-here[VALUE_INDEX])
#	s+=make_row4('Mass per',here[MASS_INDEX],' ',' ')
#	s+=make_row4('Available',here[QUANTITY_INDEX],' ',' ')
#	s+=make_row4('In cargo',mine[QUANTITY_INDEX],' ',' ')
#	s+=make_row4('Cargo mass',mine[QUANTITY_INDEX]*mine[MASS_INDEX],' ',' ')
#	s+='[/table]\n'
#	if len(here)>Commodities.Products.FIRST_TAG_INDEX:
#		s+='\nTags:\n'
#		for itag in range(Commodities.Products.FIRST_TAG_INDEX,len(here)):
#			s+=' {*} '+here[itag]+'\n'
#	return s
#
#func concoct_hover_info(item_name,mine,here,norm) -> String:
#	var VALUE_INDEX = Commodities.Products.VALUE_INDEX
#	var FINE_INDEX = Commodities.Products.FINE_INDEX
#	var QUANTITY_INDEX = Commodities.Products.QUANTITY_INDEX
#	var MASS_INDEX = Commodities.Products.MASS_INDEX
#	var s: String = '[b]'+item_name.capitalize()+'[/b]\n[table=5]'
#	s+=make_row3('  ','[b]Here[/b]','[b]Typical[/b]')
#	s+=make_row3('Price',here[VALUE_INDEX],norm[VALUE_INDEX])
#	s+=make_row3('Fine',here[FINE_INDEX],norm[FINE_INDEX])
#	s+=make_row3('Mass per',here[MASS_INDEX],' ')
#	s+=make_row3('Available',here[QUANTITY_INDEX],' ')
#	s+=make_row3('In cargo',mine[QUANTITY_INDEX],' ')
#	s+=make_row3('Cargo mass',mine[QUANTITY_INDEX]*mine[MASS_INDEX],' ')
#	s+='[/table]\n'
#	if len(here)>Commodities.Products.FIRST_TAG_INDEX:
#		s+='\nTags:\n'
#		for itag in range(Commodities.Products.FIRST_TAG_INDEX,len(here)):
#			s+=' {*} '+here[itag]+'\n'
#	return s



func update_hover_info(item_name,force_update):
	if is_updating>0:
		return
	is_updating += 1
	if not item_name:
		item_name=trading_list.get_selected_product()
	if not force_update and item_name==hover_name:
		is_updating -= 1
		return
	hover_name=item_name
	if not item_name:
		$All/Left/Help.clear()
	elif item_name.begins_with('res://'):
		var help_page = text_gen.help_page_for_scene_path(item_name)
		if help_page:
			$All/Left/Help.clear()
			var result = $All/Left/Help.process_command('help '+help_page)
			while result is GDScriptFunctionState:
				result=yield(result,'completed')
		else:
			push_warning('no help page for scene '+str(item_name))
	else:
		var norm = trading_list.all_products.all.get(
			trading_list.all_products.by_name.get(item_name,null),null)
		if norm:
			var pair = trading_list.get_product_named(item_name)
			if pair and pair[0] and pair[1]:
				$All/Left/Help.insert_bbcode(
					text_gen.make_product_hover_info(item_name,pair[0],pair[1],norm),true)
				$All/Left/Help.scroll_to_line(0)
	is_updating-=1

func _on_TradingList_all_product_data_changed():
	update_hover_info(null,true)

func _on_TradingList_product_data_changed(item_name: String):
	update_hover_info(item_name,true)

func _on_TradingList_product_selected(item_name):
	var index = trading_list.product_names.find(item_name)+1
	starmap_show_product(index)
	update_hover_info(null,true)

func _on_Content_resized():
	$All/Right/CargoMass.margin_bottom = $All/Right/Content/Top.rect_size.y
	$All/Right/Location.margin_bottom = $All/Right/Content/Top.rect_size.y

func _on_StarmapPanel_hover_no_system():
	update_hover_info(null,false)

func _on_StarmapPanel_hover_over_player_location(_system_name,_system_display_name,_system_price):
	update_hover_info(null,false)

func _on_StarmapPanel_hover_over_system(_system_name,system_display_name,system_price):
	if hover_name and system_price and system_price>0:
		var mine = trading_list.mine
		var mine_item = mine.all.get(mine.by_name.get(hover_name,-1),null)
		var here = trading_list.here
		var here_item = here.all.get(here.by_name.get(hover_name,-1),null)
		if here_item and mine_item:
			var info: String = text_gen.make_system_product_hover_info(
				hover_name,mine_item,here_item,system_display_name,system_price)
			if info:
				$All/Left/Help.insert_bbcode(info,true)
				$All/Left/Help.scroll_to_line(0)
				return
	update_hover_info(null,false)

func _on_Tabs_tab_changed(tab):
	trading_list = $All/Left/Bottom/Tabs.get_child(tab)
	var selected_name = trading_list.get_selected_product()
	if selected_name and selected_name!=hover_name:
		update_hover_info(selected_name,true)
		var index = trading_list.product_names.find(selected_name)+1
		starmap_show_product(index)


func _on_Help_mouse_entered():
	update_hover_info(null,false)


func _on_StarmapPanel_mouse_entered():
	update_hover_info(null,false)
