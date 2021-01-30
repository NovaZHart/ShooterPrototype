extends Control

signal astral_jump
signal selectable_item_selected

func astral_jump(system_name,system_path):
	emit_signal('astral_jump',system_name,system_path)

func selectable_item_selected(index):
	emit_signal('selectable_item_selected',index)
	
func update_selectability():
	$SystemList.update_selectability()

func update_system_list():
	$SystemList.update_system_list()
