extends Panel

signal page_selected

# Called when the node enters the scene tree for the first time.
#func _ready():
#	var dock = FileSystemDock.new()
#	assert(dock is Control)
#	dock.anchor_top = 0
#	dock.anchor_bottom = 1
#	dock.anchor_left = 0
#	dock.anchor_right = 1
#	dock.margin_top = 0
#	dock.margin_right = 0
#	dock.margin_left = 0
#	dock.margin_bottom = 0
#	dock.size_flags_horizontal = SIZE_EXPAND_FILL
#	dock.size_flags_vertical = SIZE_EXPAND_FILL
#	dock.name = 'Dock'
#	$Split/Right.add_child(dock)

func _on_DialogPageSelector_page_selected(page):
	emit_signal('page_selected',page)

func _on_Info_url_clicked(meta):
	$Split/Left/Split/Help.process_command('help '+meta)
