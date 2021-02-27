extends Panel

func _ready():
	var info = Player.get_info_or_null()
	if info:
		$All/Left/Bottom/Label.text = 'Buy/Sell at '+info.display_name
		$Location.text = info.full_display_name()
	$All/Left/Bottom/TradingList.populate_list(Player.player_location)
