extends Node

export var default_res_font_size = 12
export var resize_control_fonts: String = ''
export var resize_property_fonts: String = 'custom_fonts/font'
export var resize_node_theme_default_font: bool = true
export var resize_node_theme_all_fonts: bool = true

const min_font_size: float = 9.0

func _ready():
	update_font_size()
	var _discard = get_tree().root.connect('size_changed',self,'update_font_size')

func _exit_tree():
	var _discard = get_tree().root.disconnect('size_changed',self,'update_font_size')

func choose_font_size() -> float:
	var scale: Vector2 = utils.get_viewport_scale()
	return max(min_font_size,default_res_font_size*min(scale[0],scale[1]))

func update_node_property_font_sizes(parent: Node, font_size: float,property_names: PoolStringArray):
	for property_name in property_names:
		var font = parent.get(property_name)
		if not font:
			print(parent.get_path(),' has no property ',property_name)
			continue
		if not (font is Font):
			print(parent.get_path(),' property is not a font')
			continue
		print('Setting ',parent.get_path(),' ',property_name,' property font size to ',font_size)
		font.size=font_size

func update_node_font_sizes(parent: Node,font_size: float,font_names: PoolStringArray):
	if parent.has_method('get_font'):
		for font_name in font_names:
			var font: Font = parent.get_font(font_name)
			if not font:
				print(parent.get_path(),' node has no font ',font_name)
				continue
			print('Setting ',parent.get_path(),' font ',font_name,' size to ',font_size)
			font.size=font_size

func update_node_theme_default_font_size(parent: Node,font_size: float):
	if parent.has_method('get_theme'):
		var theme: Theme = parent.get_theme()
		if not theme:
			return
		var font: Font = theme.default_font
		if not font:
			return
		print('Setting ',parent.get_path(),' theme default font size to ',font_size)
		font.size=font_size

func update_node_theme_all_fonts_size(parent: Node,font_size: float):
	if parent.has_method('get_theme'):
		var theme: Theme = parent.get_theme()
		if not theme:
			print(parent.get_path(),' node has no theme')
			return
		var type: String = parent.get_class()
		var font_names: PoolStringArray = theme.get_font_list(type)
		if not font_names:
			print(parent.get_path(),' node has no font names')
		for font_name in font_names:
			var font: Font = theme.get_font(font_name,type)
			if not font:
				print(parent.get_path(),' node has no font ',font_name)
				continue
			print('Setting ',parent.get_path(),' theme type ',type,' font ',font_name,' size to ',font_size)
			font.size=font_size

func update_font_size():
	var parent: Node = get_parent()
	if parent:
		var font_size: float = choose_font_size()
		if resize_control_fonts:
			update_node_font_sizes(parent,font_size,resize_control_fonts.rsplit(' ',false))
		if resize_property_fonts:
			update_node_property_font_sizes(parent,font_size,resize_property_fonts.rsplit(' ',false))
		if resize_node_theme_default_font:
			update_node_theme_default_font_size(parent,font_size)
		if resize_node_theme_all_fonts:
			update_node_theme_all_fonts_size(parent,font_size)

