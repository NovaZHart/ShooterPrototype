extends Node2D

func set_description(var description):
	$Description.clear()
	return $Description.append_bbcode(description)

func set_panel_margins(left: float,top: float,right: float,bottom: float,_font_size: float):
	$Panel.margin_left=left
	$Panel.margin_top=top
	$Panel.margin_bottom=bottom
	$Panel.margin_right=right

func _enter_tree():
	var _discard = $Description.connect('set_margins',self,'set_panel_margins')
