extends Container

export var align_left: bool = true setget set_align
export var label_font: Font
export var title_font: Font
export var bar1_color = Color('#8343a5')
export var bar2_color = Color('#00A0E9')
export var bar3_color = Color('#009944')
export var bar4_color = Color('#FFF100')
export var bar5_color = Color('#EB6100')
export var bar6_color = Color('#F63332')

var colors: PoolColorArray setget set_colors
var labels: PoolStringArray setget set_labels
var two_m: float

func _ready():
	var m_size: Vector2 = label_font.get_char_size(ord('M'))
	two_m = 2*(m_size.y-label_font.get_descent())
	$All/Content/Colors.rect_min_size.x = two_m

func set_title(text: String):
	$All/Title.text=text

func set_align(left: bool):
	align_left=left
	for child in $All/Content/Labels.get_children():
		child.align = Label.ALIGN_LEFT if align_left else Label.ALIGN_RIGHT

func append_label_control(text: String):
	var label: Label = Label.new()
	label.text = text
	label.align = Label.ALIGN_LEFT if align_left else Label.ALIGN_RIGHT
	$All/Content/Labels.add_child(label)

func set_labels(new_labels: PoolStringArray):
	labels = new_labels
	var n = len(labels)
	var Labels: GridContainer = $All/Content/Labels
	var label_count = Labels.get_child_count()
	while label_count>n:
		var child = Labels.get_child(label_count-1)
		if child:
			Labels.remove_child(child)
		label_count = Labels.get_child_count()
	for i in range(0,label_count):
		var label: Label = Labels.get_child(i)
		label.set_text(labels[i])
		label.minimum_size_changed()
	for i in range(label_count,n):
		append_label_control(labels[i])

func set_colors(new_colors: PoolColorArray):
	colors = new_colors
	$All/Content/Colors.update()

func _on_Colors_draw():
	var c: PoolColorArray = colors
	var n = len(c)
	if n<1:
		return
	var canvas: ColorRect = $All/Content/Colors
	var size: Vector2 = canvas.rect_size
	var box_size: float = size.y/(n+1)
	canvas.draw_rect(Rect2(Vector2(),size),Color(0,0,0,0))
	for ibox in range(n):
		var y_start = (0.5+ibox)*box_size
		var y_end = (1.5+ibox)*box_size
		canvas.draw_rect(Rect2(Vector2(0,y_start),Vector2(size.x,y_end-y_start)),c[ibox])
 
