extends RichTextLabel

var starting_left: float
var starting_right: float
var starting_top: float
var starting_bottom: float
var starting_font_size: float
var min_font_size: float = 9.0
var font_size_goal: float = 13.0 setget set_font_size_goal,get_font_size_goal

signal set_margins

func set_min_font_size(s: float): min_font_size=s
func get_min_font_size(): return min_font_size
func set_font_size_goal(s: float): font_size_goal=s
func get_font_size_goal(): return font_size_goal

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
	var window_size: Vector2 = get_tree().root.size
	var project_height: int = ProjectSettings.get_setting("display/window/size/height")
	var project_width: int = ProjectSettings.get_setting("display/window/size/width")
	var scale: Vector2 = window_size / Vector2(project_width,project_height)
	
	margin_left = floor(starting_left*scale[0])
	margin_right = ceil(starting_right*scale[0])
	margin_top = floor(starting_top*scale[1])
	margin_bottom = ceil(starting_bottom*scale[1])
	
	theme.default_font.size=max(min_font_size,font_size_goal*min(scale[0],scale[1]))
	
	emit_signal('set_margins',margin_left,margin_top,margin_right,margin_bottom,theme.default_font.size)
