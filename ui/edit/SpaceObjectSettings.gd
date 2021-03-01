extends TabContainer

export var remove_texture: Texture

signal surrender_focus

var text_change_tick: int = -1
var object
var ignore_signals: bool = false
var have_picker: bool = false setget ,get_have_picker

func get_SystemData_anscestor(): # -> SimpleNode or null
	var anscestor=get_parent()
	while anscestor:
		if anscestor.has_method('is_SystemData'):
			return anscestor
	return null

func get_have_picker() -> bool: return have_picker

func is_SpaceObjectSettings(): pass # never called; must only exist

func _ready():
	var i: int = 0
	for service_id in game_state.services:
		var service = game_state.services[service_id]
		$Basic/Services.add_item(service.service_title)
		$Basic/Services.set_item_metadata(i,service_id)
		$Basic/Services.set_item_tooltip(i,'game_state.services["'+service_id+'"]')
		i+=1
	# IMPORTANT: These must match SpaceObjectData's enum:
	$Basic/Top/TypeOptions.add_item('Planet',0)
	$Basic/Top/TypeOptions.add_item('Star',1)
	$Basic/Top/TypeOptions.selected = 0
	$Visual/View/Port/SpaceBackground.rotate_x(PI/2-0.575959)
	$Visual/View/Port/SpaceBackground.center_view(130,90,0,100,0)
	$Visual/View/Port/SpaceBackground.update_from(Player.system)
	$Visual/View/Port/Camera.set_identity()
	$Visual/View/Port/Camera.rotate_x(-0.575959)
	$Visual/View/Port/Camera.rotate_y(-0.14399)
	$Visual/View/Port/Camera.size = 15
	$Visual/View/Port/Camera.translate_object_local(Vector3(0.0,0.0,10.0))
	$Help/Data/Text.add_color_region('[h1]','[/h1]',Color(0.7,1.0,0.7))
	$Help/Data/Text.add_color_region('[h2]','[/h2]',Color(0.7,1.0,0.7))
	$Help/Data/Text.add_color_region('[',']',Color(1.0,0.9,0.5))
	$Help/Data/Text.add_color_region('{','}',Color(0.5,0.7,1.0))
	var new_race_popup: PopupMenu = $Population/Heading/New.get_popup()
	var _discard = new_race_popup.connect('index_pressed',self,'_on_new_race')
	var new_trade_popup: PopupMenu = $Trading/Heading/New.get_popup()
	_discard = new_trade_popup.connect('index_pressed',self,'_on_new_trading')
	var new_adjust_popup: PopupMenu = $Adjust/Heading/New.get_popup()
	_discard = new_adjust_popup.connect('index_pressed',self,'_on_new_adjustment')
	set_tree_titles()
	sync_view_size()

func clear_object_view():
	var object_node = $Visual/View/Port.get_node_or_null('Object')
	if object_node!=null:
		$Visual/View/Port.remove_child(object_node)
		object_node.queue_free()

func generate_object_view():
	if not object:
		return
	var object_node = $Visual/View/Port.get_node_or_null('Object')
	if object_node:
		return
	object_node=object.make_planet(600,0)
	object_node.get_sphere().scale=Vector3(7,7,7)
	object_node.translation = Vector3(0,0,0)
	object_node.name = 'Object'
	$Visual/View/Port.add_child(object_node)
	$Visual/View/Port/SpaceBackground.update_from(Player.system)
	sync_view_size()

func sync_view_size():
	var want_size=$Visual/View.rect_size
	if $Visual/View/Port.size!=want_size:
		$Visual/View/Port.size=want_size

func _on_Adjust_Tree_button_pressed(item, _column, _id):
	universe_edits.state.push(universe_edits.SpaceObjectDataAddRemove.new(
		object.get_path(),'locality_adjustments',item.get_metadata(0),null,false))

func _on_Population_Tree_button_pressed(item, _column, _id):
	universe_edits.state.push(universe_edits.SpaceObjectDataAddRemove.new(
		object.get_path(),'population',item.get_metadata(0),null,false))

func _on_Trading_Tree_button_pressed(item, _column, _id):
	universe_edits.state.push(universe_edits.SpaceObjectDataAddRemove.new(
		object.get_path(),'trading',item.get_metadata(0),null,false))

func reset_adjust(_parent,child):
	for i in range(3):
		child.set_text(i+1,str(child.get_metadata(i+1)))

func _on_Adjust_Tree_focus_exited():
	var _ignore = utils.Tree_depth_first(
		$Adjust/Tree.get_root(),self,'reset_adjust')

func reset_race_count(_parent,child):
	child.set_text(1,str(child.get_metadata(1)))

func _on_Population_Keys_focus_exited():
	var _ignore = utils.Tree_depth_first(
		$Population/Tree.get_root(),self,'reset_race_count')

func _on_Adjust_Tree_item_edited():
	var selected: TreeItem = $Adjust/Tree.get_selected()
	var column: int = $Adjust/Tree.get_selected_column()
	var text: String = selected.get_text(column)
	if text.is_valid_float():
		var value: Array = [1,1,1]
		for i in range(3):
			value[i] = float(text) if (i+1==column) else selected.get_metadata(i+1)
		universe_edits.state.push(universe_edits.SpaceObjectDataKeyUpdate.new(
			object.get_path(),'locality_adjustments',selected.get_metadata(0),value))
	else:
		push_warning('Invalid float "'+str(text)+'"')
		selected.set_text(column,str(selected.get_metadata(column)))

class Finder extends Reference:
	var key
	func _init(key_): key=key_
	func find(_parent: TreeItem,child: TreeItem):
		if child.get_metadata(0)==key:
			return child
		return null
	func eq(_parent: TreeItem,child: TreeItem):
		return child.get_metadata(0)==key
	func ge(_parent: TreeItem,child: TreeItem):
		return child.get_metadata(0)>=key

func update_key_space_object_data(
		path: NodePath,property: String,key,value) -> bool:
	if property=='trading':
		object.trading[key]=value
		var item = utils.Tree_depth_first($Trading/Tree.get_root(),Finder.new(key),'find')
		if item:
			fill_trading_item(item,key,true)
			$Trading/Tree.update()
			return true
	elif property=='population':
		object.population[key]=value
		var item = utils.Tree_depth_first($Population/Tree.get_root(),Finder.new(key),'find')
		if item:
			fill_races_item(item,key,true)
			$Population/Tree.update()
			return true
	elif property=='locality_adjustments':
		object.locality_adjustments[key]=value
		var item = utils.Tree_depth_first($Adjust/Tree.get_root(),Finder.new(key),'find')
		if item:
			fill_adjust_item(item,key,true)
			$Adjust/Tree.update()
			return true
	else:
		push_error('Unrecognized property "'+str(property)+'"')
		return false
	return insert_space_object_data(path,property,key,value)

func insert_space_object_data(
		_path: NodePath,property: String,key,value) -> bool:
	if property=='trading':
		object.trading[key]=value
		var i = utils.TreeItem_find_index($Trading/Tree.get_root(),Finder.new(key),'ge')
		fill_trading_item($Trading/Tree.create_item($Trading/Tree.get_root(),i),key)
		$Trading/Tree.update()
	elif property=='population':
		object.population[key]=value
		var i = utils.TreeItem_find_index($Population/Tree.get_root(),Finder.new(key),'ge')
		fill_races_item($Population/Tree.create_item($Population/Tree.get_root(),i),key)
		$Population/Tree.update()
	elif property=='locality_adjustments':
		object.locality_adjustments[key]=value
		var i = utils.TreeItem_find_index($Adjust/Tree.get_root(),Finder.new(key),'ge')
		fill_adjust_item($Adjust/Tree.create_item($Adjust/Tree.get_root(),i),key)
		$Adjust/Tree.update()
	else:
		push_error('Unrecognized property "'+str(property)+'"')
		return false
	return true

func remove_space_object_data(
		_path: NodePath,property: String,key) -> bool:
	if property=='trading':
		object.trading.erase(key)
		$Trading/Tree.update()
		return not not utils.Tree_remove_where($Trading/Tree.get_root(),Finder.new(key),'eq')
	elif property=='population':
		object.population.erase(key)
		$Population/Tree.update()
		return not not utils.Tree_remove_where($Population/Tree.get_root(),Finder.new(key),'eq')
	elif property=='locality_adjustments':
		object.locality_adjustments.erase(key)
		$Adjust/Tree.update()
		return not not utils.Tree_remove_where($Adjust/Tree.get_root(),Finder.new(key),'eq')
	else:
		push_error('Unrecognized property "'+str(property)+'"')
		return false

func set_tree_titles():
	var font = get_font('default_font')
	var number_width = font.get_char_size(ord('0'),ord('0')).x
	utils.Tree_set_titles_and_width($Adjust/Tree,[ null,'Quantity','Value','Fine' ],font,number_width*5.5,false)
	$Adjust/Tree.set_column_title(0,'Tag')
	$Adjust/Tree.set_column_titles_visible(true)
	$Adjust/Tree.set_column_expand(0,true)
	$Adjust/Tree.set_column_min_width(0,number_width*6.5)
	utils.Tree_set_titles_and_width($Population/Tree,[null,'Population'],font,number_width*12.5,false)
	$Population/Tree.set_column_title(0,'Race')
	$Population/Tree.set_column_titles_visible(true)
	$Population/Tree.set_column_expand(0,true)
	$Population/Tree.set_column_min_width(0,number_width*10)

func fill_adjust_item(item: TreeItem,tag,update=false):
	item.set_text(0,tag)
	item.set_metadata(0,tag)
	item.set_editable(0,false)
	if not update:
		item.add_button(0,remove_texture,0,false,'Remove tag')
	var qvf = object.locality_adjustments[tag]
	for i in range(3):
		item.set_text(i+1,str(qvf[i]))
		item.set_metadata(i+1,qvf[i])
		item.set_editable(i+1,true)

func fill_adjust():
	utils.Tree_clear($Adjust/Tree)
	var root: TreeItem = $Adjust/Tree.create_item()
	var tags = object.locality_adjustments.keys()
	tags.sort()
	for tag in tags:
		var item = $Adjust/Tree.create_item(root)
		fill_adjust_item(item,tag)
	tags = Commodities.commodities.by_tag.keys()
	tags.sort()
	var popup: PopupMenu = $Adjust/Heading/New.get_popup()
	popup.clear()
	var index: int = -1
	for tag in tags:
		index += 1
		popup.add_item(tag,index)
		popup.set_item_metadata(index,tag)

func fill_races_item(item: TreeItem, race, update=false):
	item.set_text(0,race.capitalize())
	item.set_metadata(0,race)
	item.set_editable(0,false)
	if not update:
		item.add_button(0,remove_texture,0,false,'Remove race')
	var population = object.population[race]
	item.set_text(1,str(population))
	item.set_metadata(1,population)
	item.set_editable(1,true)
	item.set_tooltip(1,'Number of '+race.capitalize()+'. Set to 0 to remove.')

func fill_races():
	utils.Tree_clear($Population/Tree)
	var root: TreeItem = $Population/Tree.create_item()
	var races = object.population.keys()
	races.sort()
	for race in races:
		var item = $Population/Tree.create_item(root)
		fill_races_item(item,race)
	races = Commodities.population_names.duplicate()
	races.sort()
	var popup: PopupMenu = $Population/Heading/New.get_popup()
	popup.clear()
	var index: int = -1
	for race in races:
		index += 1
		popup.add_item(race.capitalize(),index)
		popup.set_item_metadata(index,race)

func fill_trading_item(item: TreeItem,trade,update=false):
	item.set_text(0,trade.capitalize())
	item.set_metadata(0,trade)
	if not update:
		item.add_button(0,remove_texture,0,false,'Remove trading item')

func fill_trading():
	utils.Tree_clear($Trading/Tree)
	var root: TreeItem = $Trading/Tree.create_item()
	var trades = object.trading.keys()
	trades.sort()
	for trade in trades:
		var item = $Trading/Tree.create_item(root)
		fill_trading_item(item,trade)
	var popup: PopupMenu = $Trading/Heading/New.get_popup()
	popup.clear()
	trades = Commodities.trading.keys()
	trades.sort()
	print('Trades: '+str(trades))
	var index: int = -1
	for trade in trades:
		index += 1
		popup.add_item(trade.capitalize(),index)
		popup.set_item_metadata(index,trade)

func _on_new_adjustment(index):
	var new_adjust_popup: PopupMenu = $Adjust/Heading/New.get_popup()
	var key = new_adjust_popup.get_item_metadata(index)
	if key and not object.locality_adjustments.has(key):
		universe_edits.state.push(universe_edits.SpaceObjectDataAddRemove.new(
			object.get_path(), 'locality_adjustments', key, [ 1.0, 1.0, 1.0 ], true))

func _on_new_trading(index):
	var new_trade_popup: PopupMenu = $Trading/Heading/New.get_popup()
	var key = new_trade_popup.get_item_metadata(index)
	if key and not object.trading.has(key):
		universe_edits.state.push(universe_edits.SpaceObjectDataAddRemove.new(
			object.get_path(), 'trading', key, 1, true))

func _on_new_race(index):
	var new_race_popup: PopupMenu = $Population/Heading/New.get_popup()
	var key = new_race_popup.get_item_metadata(index)
	if key and not object.population.has(key):
		universe_edits.state.push(universe_edits.SpaceObjectDataAddRemove.new(
			object.get_path(), 'population', key, 1e6, true))

func _on_Population_Keys_item_edited():
	var item: TreeItem = $Population/Tree.get_selected()
	var race = item.get_metadata(0)
	var edited = item.get_text(1)
	if edited.is_valid_float():
		var value = float(edited)
		if not value>=1.0:
			universe_edits.state.push(universe_edits.SpaceObjectDataAddRemove.new(
				object.get_path(), 'population', race, 0, false))
		else:
			universe_edits.state.push(universe_edits.SpaceObjectDataKeyUpdate.new(
				object.get_path(), 'population', race, value))
	else:
		push_warning('Value "'+edited+'" is not a valid floating-point number.')
		item.set_text(1,str(item.get_metadata(1)))

func _on_Visual_resized():
	sync_view_size()

func _process(delta):
	if visible and $Visual.visible:
		var object_node = $Visual/View/Port.get_node_or_null('Object')
		if object_node!=null:
			object_node.rotate_y(0.4*delta)
	if text_change_tick>0 and OS.get_ticks_msec()-text_change_tick>500:
		display_description(true,true)
		text_change_tick=-1

func _exit_tree():
	if text_change_tick>0:
		display_description(false,true)
		text_change_tick=-1

# warning-ignore:shadowed_variable
func set_object(object: simple_tree.SimpleNode):
	self.object=object
	fill_adjust()
	fill_races()
	fill_trading()
# warning-ignore:return_value_discarded
	sync_with_object()

func update_space_object_data(path: NodePath, basic: bool, visual: bool,
		help: bool, location: bool) -> bool:
	var node = game_state.systems.get_node_or_null(path)
	if node and node==object:
		return sync_with_object(basic,visual,help,location,false)
	return true

func sync_with_object(basic: bool=true, visual: bool = true, help: bool = true, location: bool = true, send_text: bool = false) -> bool:
	ignore_signals = true
	if basic:
		$Basic/Top/IDEdit.text = str(object.get_name())
		$Basic/Top/NameEdit.text = str(object.display_name)
		$Basic/Gate.pressed = object.has_astral_gate
		$Basic/Gate.disabled = object.object_type==0
		$Basic/Top/TypeOptions.select(object.object_type)
		$Basic/Top/IndustryEdit.text = str(object.industry)
		for i in range($Basic/Services.get_item_count()):
			var id = $Basic/Services.get_item_metadata(i)
			if object.services.has(id):
				$Basic/Services.select(i,false)
			else:
				$Basic/Services.unselect(i)
		#FIXME: $Basic/Services.disabled = object.has_astral_gate
	
	if visual:
		$Visual/Settings/RadiusEdit.text = str(object.size)
		$Visual/Settings/ColorScalingPicker.color = object.color_scaling
		var c = object.color_addition
		$Visual/Settings/ColorAdditionPicker.color = \
			Color(c.r/2.0+0.5,c.g/2.0+0.5,c.b/2.0+0.5,1.0)
		$Visual/Settings/SeedEdit.text = str(object.shader_seed)
		clear_object_view()
		if $Visual.visible:
			generate_object_view()
	
	if help:
		$Help/Data/Text.text = object.description
		display_description(true,send_text)
	
	if location:
		$Basic/Top/OrbitRadiusEdit.text = str(object.orbit_radius)
		$Basic/Top/OrbitPeriodEdit.text = str(object.orbit_period)
		$Basic/Top/OrbitPhaseEdit.text = str(object.orbit_start)
		$Basic/Top/RotationPeriodEdit.text = str(object.rotation_period)
	ignore_signals = false
	return true

func display_description(visual_update: bool, send_text: bool):
	var just_text: String = $Help/Data/Text.text
	if visual_update:
		var full_text: String = just_text
		if not full_text:
			full_text = '(Type a description above.)'
		else:
			full_text += '\n(This line should have default formatting.)'
		$Help/Data/Display.insert_bbcode(full_text,true)
		$Help/Data/Display.scroll_to_line(0)
	if send_text:
		var top = universe_edits.state.top()
		if top and top is universe_edits.DescriptionChange and top.object_path==object.get_path():
			top.amend(just_text)
		else:
			var old_description = object.description
			object.description = just_text
			universe_edits.state.push(universe_edits.DescriptionChange.new(
				object.get_path(),just_text,old_description))

func _on_View_visibility_changed():
	if $Visual.visible:
		generate_object_view()

func _on_SeedEdit_focus_exited():
	$Visual/Settings/SeedEdit.text = str(object.shader_seed)
	emit_signal('surrender_focus')

func _on_IDEdit_focus_exited():
	$Basic/Top/IDEdit.text = str(object.get_name())
	emit_signal('surrender_focus')

func _on_NameEdit_focus_exited():
	$Basic/Top/NameEdit.text = str(object.display_name)
	emit_signal('surrender_focus')

func _on_TypeOptions_focus_exited():
	$Basic/Top/TypeOptions.select(object.object_type)
	emit_signal('surrender_focus')

func _on_OrbitPhaseEdit_focus_exited():
	$Basic/Top/OrbitPhaseEdit.text = str(object.orbit_start)
	emit_signal('surrender_focus')

func _on_RadiusEdit_focus_exited():
	$Visual/Settings/RadiusEdit.text = str(object.size)
	emit_signal('surrender_focus')

func _on_OrbitRadiusEdit_focus_exited():
	$Basic/Top/OrbitRadiusEdit.text = str(object.orbit_radius)
	emit_signal('surrender_focus')

func _on_OrbitPeriodEdit_focus_exited():
	$Basic/Top/OrbitPeriodEdit.text = str(object.orbit_period)
	emit_signal('surrender_focus')

func _on_RotationPeriodEdit_focus_exited():
	$Basic/Top/RotationPeriodEdit.text = str(object.rotation_period)

func _on_NameEdit_text_entered(new_text):
	universe_edits.state.push(universe_edits.SpaceObjectDataChange.new(
		object.get_path(),{'display_name':new_text},true,false,false,false))
	emit_signal('surrender_focus')

func _on_TypeOptions_item_selected(index):
	if ignore_signals: return
	universe_edits.state.push(universe_edits.SpaceObjectDataChange.new(
		object.get_path(),{'object_type':index},true,true,false,false))
	emit_signal('surrender_focus')

func _on_OrbitRadiusEdit_text_entered(new_text):
	if new_text.is_valid_float():
		universe_edits.state.push(universe_edits.SpaceObjectDataChange.new(
			object.get_path(),{'orbit_radius':float(new_text)},false,false,false,true))
	else:
		$Basic/Top/OrbitRadiusEdit.text = str(object.orbit_radius)
	emit_signal('surrender_focus')

func _on_OrbitPeriodEdit_text_entered(new_text):
	if new_text.is_valid_float():
		universe_edits.state.push(universe_edits.SpaceObjectDataChange.new(
			object.get_path(),{'orbit_period':float(new_text)},false,false,false,true))
	else:
		$Basic/Top/OrbitPeriodEdit.text = str(object.orbit_start)
	emit_signal('surrender_focus')

func _on_OrbitPhaseEdit_text_entered(new_text):
	if new_text.is_valid_float():
		universe_edits.state.push(universe_edits.SpaceObjectDataChange.new(
			object.get_path(),{'orbit_start':max(float(new_text),0.0)},false,false,false,true))
	else:
		$Basic/Top/OrbitPhaseEdit.text = str(object.orbit_start)
	emit_signal('surrender_focus')

func _on_Gate_toggled(button_pressed):
	if ignore_signals: return
	universe_edits.state.push(universe_edits.SpaceObjectDataChange.new(
		object.get_path(),{'has_astral_gate':button_pressed},true,false,false,false))
	emit_signal('surrender_focus')

func _on_Services_changed(_ignore=null,_ignore2=null):
	if ignore_signals: return
	var locations: PoolIntArray = $Basic/Services.get_selected_items()
	var selections: Array = []
	for i in locations:
		selections.append($Basic/Services.get_item_metadata(i))
	universe_edits.state.push(universe_edits.SpaceObjectDataChange.new(
		object.get_path(),{'services':selections},true,false,false,false))

func _on_ColorScalingPicker_color_changed(color):
	if ignore_signals: return
	universe_edits.state.push(universe_edits.SpaceObjectDataChange.new(
		object.get_path(),{'color_scaling':color},false,true,false,false))

func _on_ColorAdditionPicker_color_changed(color):
	if ignore_signals: return
	var adjust: Color = Color(color.r*2.0-1.0,color.g*2.0-1.0,color.b*2.0-1.0,1.0)
	universe_edits.state.push(universe_edits.SpaceObjectDataChange.new(
		object.get_path(),{'color_addition':adjust},false,true,false,false))

func _on_SeedEdit_text_entered(new_text):
	if new_text.is_valid_integer():
		universe_edits.state.push(universe_edits.SpaceObjectDataChange.new(
			object.get_path(),{'shader_seed':int(new_text)},false,true,false,false))
	else:
		$Visual/Settings/SeedEdit.text = str(object.shader_seed)
	emit_signal('surrender_focus')

func _on_RadiusEdit_text_entered(new_text):
	if new_text.is_valid_float():
		universe_edits.state.push(universe_edits.SpaceObjectDataChange.new(
			object.get_path(),{'size':clamp(float(new_text),0.5,20.0)},false,true,false,false))
	else:
		$Visual/Settings/RadiusEdit.text = str(object.size)
	emit_signal('surrender_focus')

func _on_Text_text_changed():
	text_change_tick = OS.get_ticks_msec()

func _on_Text_focus_exited():
	display_description(true,true)

func _on_Randomize_pressed():
	if ignore_signals: return
	var new_seed: int = randi()%99999
	universe_edits.state.push(universe_edits.SpaceObjectDataChange.new(
		object.get_path(),{'shader_seed':new_seed},false,true,false,false))

func _on_RotationPeriodEdit_text_entered(new_text):
	if new_text.is_valid_float():
		universe_edits.state.push(universe_edits.SpaceObjectDataChange.new(
			object.get_path(),{'rotation_period':float(new_text)},false,false,false,true))
	else:
		$Basic/Top/OrbitPeriodEdit.text = str(object.orbit_start)
	emit_signal('surrender_focus')

func _on_picker_created():
	have_picker=true

func _on_picker_closed():
	have_picker=false

func _on_Industry_Edit_text_entered(new_text):
	if new_text and new_text is String and new_text.is_valid_float():
		var count=int(round(float(new_text)))
		if count>=0:
			return universe_edits.state.push(universe_edits.SpaceObjectDataChange.new(
				object.get_path(),{'industry':count},true,false,false,false))
	$Basic/Top/IndustryEdit.text = str(object.industry)

func _on_Industry_Edit_focus_exited():
	$Basic/Top/IndustryEdit.text = str(object.industry)
