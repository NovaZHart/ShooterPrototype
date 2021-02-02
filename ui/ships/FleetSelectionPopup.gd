extends PopupPanel

export var popup_title = 'Select a Fleet to Add'
export var accept_button_text = 'Add Fleet'
export var accept_hint_text = 'Add this fleet.'

var selected_fleet: NodePath = NodePath()

signal cancel
signal accept_fleet

func _ready():
	$All/Buttons/Accept.disabled=true
	$All/Buttons/Accept.hint_tooltip='Select a fleet first.'

func _on_Fleets_nothing_selected():
	$All/Buttons/Accept.disabled=true
	$All/Buttons/Accept.hint_tooltip='Select a fleet first.'
	selected_fleet = NodePath()

func _on_Fleets_fleet_selected(path,activate):
	$All/Buttons/Accept.disabled=false
	$All/Buttons/Accept.hint_tooltip=accept_hint_text
	selected_fleet = path
	if activate:
		emit_signal('accept_fleet',selected_fleet)

func _on_Fleets_design_selected(_path,_activate):
	$All/Buttons/Accept.disabled=true
	$All/Buttons/Accept.hint_tooltip='Select a fleet first.'
	selected_fleet = NodePath()

func _on_Cancel_pressed():
	emit_signal('cancel')

func _on_Accept_pressed():
	if selected_fleet:
		emit_signal('accept_fleet',selected_fleet)
