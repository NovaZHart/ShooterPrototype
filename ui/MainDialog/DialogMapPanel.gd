extends Panel

var queue = utils.YieldActionQueue.new()
var trading_list
#var selected_product

var last_shown_market: NodePath = NodePath()

var last_shown_mode: String = ''
var last_shown_product: String = ''
var last_shown_path: NodePath = NodePath()

signal page_selected

func _on_DialogPageSelector_page_selected(page):
	emit_signal('page_selected',page)

func _on_StarmapPanel_select_space_object(path):
	var node = game_state.systems.get_node_or_null(path)
	if node:
		var relpath = game_state.systems.get_path_to(node)
		if relpath:
			set_market(node.get_path())
			$All/Info/Bottom/Console.clear()
			$All/Info/Bottom/Console.process_command('location '+str(relpath))

func _ready():
	Player.age_off_markets()
	Player.age_off_ship_parts()
	set_market(null)
	$All/Info/Bottom/Markets/Tabs.set_tab_title(0,'Market')
	$All/Info/Bottom/Markets/Tabs.set_tab_title(1,'Ship Parts')
	_on_Tabs_tab_changed($All/Info/Bottom/Markets/Tabs.current_tab)
	update_SalePrice_disabled()

func set_market(path):
	if path is String:
		path = NodePath(path)
	elif not path is NodePath:
		path = NodePath()
	
	var planet_info = game_state.systems.get_node_or_null(path)
	var ship_design = Player.player_ship_design
	last_shown_market = path
	print('market at '+str(planet_info)+' ship design '+str(ship_design))
	
	if planet_info:
		var system_info = planet_info.get_system()
		var planet_name = planet_info.display_name
		var system_name = system_info.display_name if system_info else planet_name
		$All/Info/Bottom/Markets/Middle/Label.text = \
			(system_name+' '+planet_name if system_name!=planet_name else planet_name)
	
	var sale_price = $All/Info/Bottom/Markets/Middle/SalePrice.pressed
	var sale_info
	
	if path:
		sale_info = Player.products_for_sale_at(planet_info.get_path(),sale_price,false)
	else:
		sale_info = {}
	
	var ship_parts = sale_info.get('ship_parts',null)
	if not ship_parts:
		ship_parts = Commodities.ship_parts.duplicate(true)
	print('Ship part count '+str(len(ship_parts.by_name))+' at '+str(path))
	$All/Info/Bottom/Markets/Tabs/ShipParts.populate_list(
		Commodities.ship_parts,ship_parts,ship_design)
	
	var commodities = null
	if path:
		commodities = sale_info.get('commodities',null)
	if not commodities:
		commodities = Commodities.commodities.duplicate(true)
	$All/Info/Bottom/Markets/Tabs/Market.populate_list(
		Commodities.commodities,commodities,ship_design)

func info_show_product(product_name):
	if last_shown_mode=='info_show_product' and last_shown_product==product_name:
		return true
	if not product_name:
		$All/Info/Bottom/Console.clear()
	elif product_name.begins_with('res://'):
		var help_page = text_gen.help_page_for_scene_path(product_name)
		if help_page:
			$All/Info/Bottom/Console.clear()
			$All/Info/Bottom/Console.process_command('help '+help_page)
		else:
			$All/Info/Bottom/Console.clear()
			return false
	else:
		var norm = trading_list.all_products.by_name.get(product_name,null)
		if norm:
			var pair = trading_list.get_product_named(product_name)
			if pair and pair[0] and pair[1]:
				$All/Info/Bottom/Console.insert_bbcode(
					text_gen.make_product_hover_info(product_name,pair[0],pair[1],norm),true)
				$All/Info/Bottom/Console.scroll_to_line(0)

func starmap_show_product(index: int):
#	var bs = $All/Right/Content/Top/BuySell
	if index==0:
		Commodities.select_no_commodity()
		$All/StarmapPanel.mode = $All/StarmapPanel.NAVIGATIONAL
#		bs.set_item_text(0,'Buying Map')
#		bs.set_item_text(1,'Selling Map')
	else:
		var product_name = trading_list.product_names[index-1]
		#var display_name = trading_list.display_name_for[product_name]
		Commodities.select_commodity_with_name(product_name,trading_list.market_type)
#		bs.set_item_text(0,'Purchase: '+display_name)
#		bs.set_item_text(1,'Sale Value: '+display_name)
		$All/StarmapPanel.mode = $All/StarmapPanel.MIN_PRICE
	$All/StarmapPanel.update_starmap_visuals()

func _on_StarmapPanel_deselect():
	set_market(NodePath())

func _on_TradingList_product_selected(product_name):
	if not trading_list:
		return
	queue.run(self,'info_show_product',[product_name])
	var index = trading_list.product_names.find(product_name)+1
	starmap_show_product(index)

func update_SalePrice_disabled():
	$All/Info/Bottom/Markets/Middle/SalePrice.disabled = \
		not $All/Info/Bottom/Markets/Tabs/Market.is_visible_in_tree()

func _on_Tabs_tab_changed(tab):
	update_SalePrice_disabled()
	var control = $All/Info/Bottom/Markets/Tabs.get_child(tab)
	if not control.has_method('is_TradingList'):
		trading_list = null
		starmap_show_product(0)
	else:
		trading_list = control
		var selected_product = trading_list.get_selected_product()
		if selected_product:
			queue.run(self,'info_show_product',[selected_product])
			var index = trading_list.product_names.find(selected_product)+1
			starmap_show_product(index)

func _on_SalePrice_toggled(_button_pressed):
	set_market(last_shown_market)
