extends Panel

signal fleet_selected
signal design_selected
signal nothing_selected

func _ready():
	$Grid/Tree.create_item()
	$Grid/Tree.set_column_expand(0,false)
	fill_fleet_info()

func _process(_delta):
	if visible:
		var spawned_size = $Grid/Tree.rect_size
		$Grid/Tree.set_column_min_width(0,max(40,spawned_size.x*0.15))

func fill_fleet_info():
	var tree = $Grid/Tree
	var root = tree.get_root()
	for fleet_name in game_state.fleets.get_child_names():
		var fleet = game_state.fleets.get_child_with_name(fleet_name)
		if not fleet:
			continue
		var fleet_item = tree.create_item(root)
		fleet_item.set_text(0,'Fleet')
		fleet_item.set_text_align(0,TreeItem.ALIGN_RIGHT)
		fleet_item.set_text(1,fleet.display_name)
		fleet_item.set_metadata(0,'')
		fleet_item.set_metadata(1,fleet.get_path())
		for design_name in fleet.get_designs():
			var design = game_state.ship_designs.get_node_or_null(design_name)
			var design_item = tree.create_item(fleet_item)
			if design:
				design_item.set_metadata(0,fleet_name)
				design_item.set_metadata(1,design.get_path())
				design_item.set_text(0,str(fleet.spawn_count_for(design_name))+'x')
				design_item.set_text_align(0,TreeItem.ALIGN_RIGHT)
				design_item.set_text(1,design.display_name)
			else:
				design_item.set_text(0,str(fleet.spawn_count_for(design_name))+'x')
				design_item.set_text_align(0,TreeItem.ALIGN_RIGHT)
				design_item.set_text(1,'!! Missing '+design_name+' !!')

func on_item_select(activate: bool):
	var item = $Grid/Tree.get_selected()
	var column = $Grid/Tree.get_selected_column()
	if not item or column<0:
		emit_signal('nothing_selected')
	if item.get_metadata(0):
		# This is a ship design
		var design = game_state.ship_designs.get_node_or_null(item.get_metadata(1))
		var stats = design.get_stats()
		$Grid/Info.clear()
		$Grid/Info.insert_bbcode(text_gen.make_ship_bbcode(stats),true)
		$Grid/Info.scroll_to_line(0)
		emit_signal('design_selected',item.get_metadata(1),activate)
	else:
		var fleet = game_state.fleets.get_node_or_null(item.get_metadata(1))
		# This is a fleet
		$Grid/Info.clear()
		$Grid/Info.insert_bbcode(text_gen.make_fleet_bbcode(
			fleet.name,fleet.display_name,fleet.spawn_info),true)
		$Grid/Info.scroll_to_line(0)
		emit_signal('fleet_selected',item.get_metadata(1),activate)

func _on_Tree_item_selected():
	on_item_select(false)

func _on_Tree_nothing_selected():
	emit_signal('nothing_selected')

func _on_Tree_item_activated():
	on_item_select(true)
