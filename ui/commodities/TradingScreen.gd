extends Panel

func _ready():
	var info = Player.get_info_or_null()
	if info:
		$All/Left/Bottom/Tools/Label.text = 'Buy/Sell at '+info.display_name
		$All/Right/Context/Location.text = info.full_display_name()
	$All/Left/Bottom/TradingList.populate_list(Player.player_location,Player.player_ship_design)


func _on_TradingList_cargo_mass_changed(cargo_mass,max_cargo_mass):
	$All/Right/Context/CargoMass.text = str(cargo_mass)+'/'+str(max_cargo_mass)+' kg'
