extends TabContainer

signal surrender_focus
# warning-ignore:unused_signal
signal planet_metadata_changed
# warning-ignore:unused_signal
signal planet_location_changed
# warning-ignore:unused_signal
signal planet_visuals_changed

var planet

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

func update_planet_view():
	var planet_node = $Visual/View/Port.get_node_or_null('Planet')
	if planet_node!=null:
		$Visual/View/Port.remove_child(planet_node)
		planet_node.queue_free()
	planet_node=planet.make_planet(600,0)
	planet_node.get_sphere().scale=Vector3(7,7,7)
	planet_node.translation = Vector3(0,0,0)
	planet_node.name = 'Planet'
	$Visual/View/Port.add_child(planet_node)
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
		var planet_node = $Visual/View/Port.get_node_or_null('Planet')
		if planet_node!=null:
			planet_node.rotate_y(0.4*delta)

# warning-ignore:shadowed_variable
func set_planet(planet: simple_tree.SimpleNode):
	self.planet=planet
	sync_with_planet()

func sync_with_planet():
	$Basic/Top/IDEdit.text = str(planet.get_name())
	$Basic/Top/NameEdit.text = str(planet.display_name)
	$Basic/Top/TypeOptions.select(planet.object_type)
	$Basic/Top/OrbitRadiusEdit.text = str(planet.orbit_radius)
	$Basic/Top/OrbitPeriodEdit.text = str(planet.orbit_period)
	$Basic/Top/OrbitPhaseEdit.text = str(planet.orbit_start)
	$Basic/Gate.pressed = planet.has_astral_gate
	$Basic/Gate.disabled = planet.object_type==0
	for i in range($Basic/Services.get_item_count()):
		var id = $Basic/Services.get_item_metadata(i)
		if planet.services.has(id):
			$Basic/Services.select(i,false)
		else:
			$Basic/Services.unselect(i)
	#FIXME: $Basic/Services.disabled = planet.has_astral_gate
	$Visual/Settings/RadiusEdit.text = str(planet.size)
	$Visual/Settings/ColorScalingPicker.color = planet.color_scaling
	var c = planet.color_addition
	$Visual/Settings/ColorAdditionPicker.color = Color(c.r/2+0.5,c.g/2+0.5,c.b/2+0.5,1.0)
	$Visual/Settings/SeedEdit.text = str(planet.shader_seed)
	$Help/Data/Text.text = planet.description
	display_description()
	update_planet_view()

func display_description():
	var full_text = $Help/Data/Text.text
	if not full_text:
		full_text = '(Type a description above.)'
	else:
		full_text += '\n(This line should have default formatting.)'
	$Help/Data/Display.insert_bbcode(full_text,true)
	$Help/Data/Display.scroll_to_line(0)

func _on_SeedEdit_focus_exited():
	emit_signal('surrender_focus')

func _on_IDEdit_focus_exited():
	emit_signal('surrender_focus')

func _on_NameEdit_focus_exited():
	emit_signal('surrender_focus')

func _on_TypeOptions_focus_exited():
	emit_signal('surrender_focus')

func _on_OrbitPhaseEdit_focus_exited():
	emit_signal('surrender_focus')

func _on_RadiusEdit_focus_exited():
	emit_signal('surrender_focus')

func _on_OrbitRadiusEdit_focus_exited():
	emit_signal('surrender_focus')

func _on_OrbitPeriodEdit_focus_exited():
	emit_signal('surrender_focus')

func _on_NameEdit_text_entered(_new_text):
	pass # Replace with function body.

func _on_TypeOptions_item_selected(_index):
	pass # Replace with function body.

func _on_OrbitRadiusEdit_text_entered(_new_text):
	pass # Replace with function body.

func _on_OrbitPeriodEdit_text_entered(_new_text):
	pass # Replace with function body.

func _on_OrbitPhaseEdit_text_entered(_new_text):
	pass # Replace with function body.

func _on_Gate_toggled(_button_pressed):
	pass # Replace with function body.

func _on_Services_changed(_ignore=null,_ignore2=null):
	pass # Replace with function body.

func _on_RadiusEdit_value_changed(_value):
	pass # Replace with function body.

func _on_ColorScalingPicker_color_changed(_color):
	pass # Replace with function body.

func _on_ColorAdditionPicker_color_changed(_color):
	pass # Replace with function body.

func _on_SeedEdit_text_entered(_new_text):
	pass # Replace with function body.

func _on_RadiusEdit_text_entered(_new_text):
	pass # Replace with function body.

func _on_Text_text_changed():
	display_description()
	# FIXME: sync with planet




