extends GridContainer

var system
var have_picker: bool = false setget ,get_have_picker

func get_have_picker() -> bool: return have_picker

signal edit_complete

# warning-ignore:shadowed_variable
func set_system(system: simple_tree.SimpleNode):
	self.system=system
	sync_system_data(true,true)

func sync_system_data(bkg_update: bool,meta_update: bool):
	if meta_update:
		$IDEdit.text=system.get_name()
		$NameEdit.text=system.display_name
	if bkg_update:
		$PlasmaSeedEdit.text=str(system.plasma_seed)
		$StarSeedEdit.text=str(system.starfield_seed)
		$ColorPickerButton.color=system.plasma_color

func _on_NameEdit_text_entered(new_text):
	universe_edits.state.push(universe_edits.SystemDataChange.new(
		system.get_path(),{'display_name':new_text},false,true))

func _on_PlasmaSeedEdit_text_entered(new_text):
	if new_text.is_valid_integer():
		universe_edits.state.push(universe_edits.SystemDataChange.new(
			system.get_path(),{'plasma_seed':int(new_text)},true,false))
	else:
		$PlasmaSeedEdit.text=str(system.plasma_seed)
	emit_signal('edit_complete')

func _on_StarSeedEdit_text_entered(new_text):
	if new_text.is_valid_integer():
		universe_edits.state.push(universe_edits.SystemDataChange.new(
			system.get_path(),{'starfield_seed':int(new_text)},true,false))
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
	return universe_edits.state.push(universe_edits.SystemDataChange.new(
			system.get_path(),{'plasma_color':color},true,false))

func _on_ColorPickerButton_focus_exited():
	$ColorPickerButton.color=system.plasma_color

func _on_Button_pressed():
	var changes = { 'plasma_seed':randi()%100000, 'starfield_seed':randi()%100000 }
	return universe_edits.state.push(universe_edits.SystemDataChange.new(
			system.get_path(),changes,true,false))

func _on_ColorPickerButton_picker_created():
	have_picker=true

func _on_ColorPickerButton_popup_closed():
	have_picker=false
