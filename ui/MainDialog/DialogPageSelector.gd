extends GridContainer

export var enable_Ship: bool = true
export var enable_Help: bool = true
export var enable_Map: bool = true
export var enable_Saves: bool = true
export var enable_Keys: bool = true
export var enable_Exit: bool = true

signal page_selected

func _ready():
	$Ship.disabled = not enable_Ship
	$Help.disabled = not enable_Help
	$Map.disabled = not enable_Map
	$Saves.disabled = not enable_Saves
	$Keys.disabled = not enable_Keys
	$Exit.disabled = not enable_Exit

func _on_Ship_pressed():
	emit_signal('page_selected','Ship')

func _on_Help_pressed():
	emit_signal('page_selected','Help')

func _on_Map_pressed():
	emit_signal('page_selected','Map')

func _on_Saves_pressed():
	emit_signal('page_selected','Saves')

func _on_Keys_pressed():
	emit_signal('page_selected','Keys')

func _on_Exit_pressed():
	emit_signal('page_selected','Exit')
