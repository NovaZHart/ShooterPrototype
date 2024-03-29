extends Button

var starting_left: float
var starting_right: float
var starting_top: float
var starting_bottom: float
var starting_font_size: float
const min_font_size: float = 9.0

func _ready():
	starting_left=margin_left
	starting_right=margin_right
	starting_top=margin_top
	starting_bottom=margin_bottom
	anchor_left=0
	anchor_right=0
	anchor_top=0
	anchor_bottom=0
	
func _process(var _delta: float) -> void:
	var scale: Vector2 = utils.get_viewport_scale()
	
	margin_left = floor(starting_left*scale[0])
	margin_right = ceil(starting_right*scale[0])
	margin_top = floor(starting_top*scale[1])
	margin_bottom = ceil(starting_bottom*scale[1])
	
	theme.default_font.size=max(min_font_size,14*min(scale[0],scale[1]))

func _on_list_select(_index):
	disabled=false

func _on_list_activate(_meta1,_meta2):
	disabled=true
