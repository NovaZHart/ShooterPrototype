extends TabContainer

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
	$Visual/View/Port/SpaceBackground.update_from(game_state.system)
	$Visual/View/Port/Camera.set_identity()
	$Visual/View/Port/Camera.rotate_x(-0.575959)
	$Visual/View/Port/Camera.rotate_y(-0.14399)
	$Visual/View/Port/Camera.size = 15
	$Visual/View/Port/Camera.translate_object_local(Vector3(0.0,0.0,10.0))
	$Help/Data/Text.add_color_region('[h1]','[/h1]',Color(0.7,1.0,0.7))
	$Help/Data/Text.add_color_region('[h2]','[/h2]',Color(0.7,1.0,0.7))
	$Help/Data/Text.add_color_region('[',']',Color(1.0,0.9,0.5))
	$Help/Data/Text.add_color_region('{','}',Color(0.5,0.7,1.0))
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
	$Visual/View/Port/SpaceBackground.update_from(game_state.system)
	sync_view_size()

func sync_view_size():
	var want_size=$Visual/View.rect_size
	if $Visual/View/Port.size!=want_size:
		$Visual/View/Port.size=want_size

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
			print('amend')
			top.amend(just_text)
		else:
			print('replace')
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
	print(str(selections))
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
