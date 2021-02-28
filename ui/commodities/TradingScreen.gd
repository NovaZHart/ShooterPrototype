extends Panel

var product_names: Array

func _ready():
	var info = Player.get_info_or_null()
	if info:
		$All/Left/Bottom/Tools/Label.text = 'Buy/Sell at '+info.display_name
		$All/Right/Context/Location.text = info.full_display_name()
	$All/Left/Bottom/TradingList.populate_list(Player.player_location,Player.player_ship_design)
	product_names = $All/Left/Bottom/TradingList.get_product_names()
	product_names.sort()
	$All/Right/Context/ProductList.add_item('(No product selected.)',0)
	for i in range(len(product_names)):
		$All/Right/Context/ProductList.add_item(product_names[i].capitalize(),i+1)

func _on_TradingList_cargo_mass_changed(cargo_mass,max_cargo_mass):
	$All/Right/Context/CargoMass.text = 'Cargo mass: '+str(cargo_mass)+'/'+str(max_cargo_mass)+' kg'

func _on_ProductList_item_selected(index):
	if index==0:
		Commodities.select_no_commodity()
	else:
		Commodities.select_commodity_with_name(product_names[index-1])
	$All/Right/StarmapPanel.update_starmap_visuals()
