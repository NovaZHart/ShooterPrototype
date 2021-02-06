extends Label

var starting_left: float
var starting_right: float
var starting_top: float
var starting_bottom: float
var starting_font_size: float
const min_font_size: float = 9.0
export var auto_info: String = ""

func _ready():
	starting_left=margin_left
	starting_right=margin_right
	starting_top=margin_top
	starting_bottom=margin_bottom
	anchor_left=0
	anchor_right=0
	anchor_top=0
	anchor_bottom=0
	var _discard = get_viewport().connect('size_changed',self,'adjust_size')
	adjust_size()

func adjust_size() -> void:
	var window_size: Vector2 = get_tree().root.size
	var project_height: int = ProjectSettings.get_setting("display/window/size/height")
	var project_width: int = ProjectSettings.get_setting("display/window/size/width")
	var scale: Vector2 = window_size / Vector2(project_width,project_height)
	
	margin_left = floor(starting_left*scale[0])
	margin_right = ceil(starting_right*scale[0])
	margin_top = floor(starting_top*scale[1])
	margin_bottom = ceil(starting_bottom*scale[1])
	
	theme.default_font.size=max(min_font_size,13*min(scale[0],scale[1]))

func _process(var _delta: float) -> void:
	if auto_info == "FPS":
		text = String(Engine.get_frames_per_second())+" FPS"
	elif auto_info == "ships":
		var ships = get_node_or_null("../System/Ships")
		if ships!=null:
			text = String(ships.get_children().size())+" ships"
		else:
			text = "<???> ships"
