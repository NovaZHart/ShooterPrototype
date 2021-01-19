extends GridContainer

var system

signal space_background_changed
signal system_metadata_changed
signal edit_complete

# warning-ignore:shadowed_variable
func set_system(system: simple_tree.SimpleNode):
	self.system=system
	sync_fields()

func sync_fields():
	$IDEdit.text=system.get_name()
	$NameEdit.text=system.display_name
	$PlasmaSeedEdit.text=str(system.plasma_seed)
	$StarSeedEdit.text=str(system.starfield_seed)
	$ColorPickerButton.color=system.plasma_color

func _on_NameEdit_text_entered(new_text):
	system.display_name=new_text
	emit_signal('system_metadata_changed',system)
	emit_signal('edit_complete')

func _on_PlasmaSeedEdit_text_entered(new_text):
	if new_text.is_valid_integer():
		system.plasma_seed=int(new_text)
		emit_signal('space_background_changed',system)
	else:
		$PlasmaSeedEdit.text=str(system.plasma_seed)
	emit_signal('edit_complete')

func _on_StarSeedEdit_text_entered(new_text):
	if new_text.is_valid_integer():
		system.starfield_seed=int(new_text)
		emit_signal('space_background_changed',system)
	else:
		$StarSeedEdit.text=str(system.starfield_seed)
	emit_signal('edit_complete')

func _on_NameEdit_focus_exited():
	$NameEdit.text=system.display_name

func _on_PlasmaSeedEdit_focus_exited():
	$PlasmaSeedEdit.text=str(system.plasma_seed)

func _on_StarSeedEdit_focus_exited():
	$StarSeedEdit.text=str(system.starfield_seed)

func _on_ColorPickerButton_color_changed(color):
	system.plasma_color = color
	emit_signal('space_background_changed',system)

func _on_ColorPickerButton_focus_exited():
	$ColorPickerButton.color=system.plasma_color

func _on_Button_pressed():
	system.plasma_seed = randi()%100000
	system.starfield_seed = randi()%100000
	$PlasmaSeedEdit.text=str(system.plasma_seed)
	$StarSeedEdit.text=str(system.starfield_seed)
	emit_signal('space_background_changed',system)
