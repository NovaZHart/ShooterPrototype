extends GridContainer

export var enable_Ship: bool = true
export var enable_Help: bool = true
export var enable_Map: bool = true
export var enable_Saves: bool = true

signal page_selected

func _ready():
	$Ship.disabled = not enable_Ship
	$Help.disabled = not enable_Help
	$Map.disabled = not enable_Map
	$Saves.disabled = not enable_Saves

func _on_Ship_pressed():
	emit_signal('page_selected','Ship')

func _on_Help_pressed():
	emit_signal('page_selected','Help')

func _on_Map_pressed():
	emit_signal('page_selected','Map')

func _on_Saves_pressed():
	emit_signal('page_selected','Saves')
