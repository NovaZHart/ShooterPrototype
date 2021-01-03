extends Panel

export var auto_resize: bool = false
export var hostname: String = ''
export var domain: String = ''
export var username: String = 'ai'
export var h1_font: Font
export var h2_font: Font
export var small_code_font: Font
export var initial_bbcode: String
export var follow_urls: bool = true
export var allow_input: bool = true

var tag_filters = {
	'[h1]':'[center][b]',
	'[/h1]':'[/b][/center]',
	'[h2]':'[b]',
	'[/h2]':'[/b]',
	'[ref=':'[color=#88ccff][url=help ',
	'[/ref]':'[/url][/color]',
	'{*}':'\u2022',
	'{eoln}':'\n',
	'{tab}':'\t',
	'[prompt_font]':'[color=#6688ff][code]',
	'[/prompt_font]':'[/code][/color]',
	'[command_font]':'[color=#eebb66][code]',
	'[/command_font]':'[/code][/color]',
	'[small_code]':'[code]',
	'[/small_code]':'[/code]',
}

var ZWSP: String = '\u200B' # zero-width space
var console_prompt = null
var image_path: String = 'res://ships/PurpleShips/Metal-4271-light-green-128x128.jpg'
var LoadHelp = preload('res://help/LoadHelp.gd')
var help_loader = LoadHelp.new()
var help_pages: Dictionary = {}
var help_index: Dictionary = {}
var initial_size: Rect2 = Rect2()

var commands: Dictionary = {
	'echo':'call_echo',
	'ref':'call_ref',
	'clear':'call_clear',
	'help':'call_help',
	'synopsis':'call_synopsis',
	'search':'call_search',
}

signal url_clicked

func rewrite_tags(s: String) -> String:
	var t: String = s
	for from_string in tag_filters:
		t = t.replace(from_string,tag_filters[from_string])
	return t

func _init():
	help_pages = help_loader.load_help_pages()

func fqdn() -> String:
	if not hostname:
		hostname='orbit'
	if not domain:
		var loc = game_state.get_info_or_null()
		if not loc:
			domain='cosmos'
		else:
			domain = loc.display_name.strip_escapes().replace(' ','_')+'.cosmos'
	return hostname+'.'+domain

func clean_input(input: String) -> String:
	return input.replace('[','['+ZWSP).replace(']',']'+ZWSP)

func append(what: String, clean: bool = false):
	if clean:
		$Console/Output.append_bbcode(clean_input(what))
	else:
		$Console/Output.append_bbcode(what)
	if not what.ends_with('\n'):
		$Console/Output.append_bbcode('\n')

func prompt():
	if console_prompt==null:
		console_prompt = rewrite_tags('[prompt_font]'+clean_input(username+'@'+fqdn())+'> [/prompt_font]')
	$Console/Output.append_bbcode(console_prompt)

func _ready():
	$Console/Output.clear()
	if initial_bbcode:
		append(rewrite_tags(initial_bbcode))
	if allow_input:
		prompt()
	initial_size=Rect2(rect_global_position,rect_size)
	if not auto_resize:
		set_process(false)
	if h1_font:
		tag_filters['[h1]'] = '[center][font='+h1_font.resource_path+']'
		tag_filters['[/h1]'] = '[/font][/center]'
	if h2_font:
		tag_filters['[h2]'] = '[center][font='+h2_font.resource_path+']'
		tag_filters['[/h2]'] = '[/font][/center]'
	if small_code_font:
		tag_filters['[small_code]'] = '[font='+small_code_font.resource_path+']'
		tag_filters['[/small_code]'] = '[/font]'
	$Console/Input.set_visible(allow_input)

func _process(_delta):
	var vs: Vector2 = get_viewport().get_size()
	var pos: Vector2 = Vector2(initial_size.position.x*vs.x/1024, \
		initial_size.position.y*vs.y/600)
	var siz: Vector2 = Vector2(initial_size.size.x*vs.x/1024, \
		initial_size.size.y*vs.y/600)
	siz.x = max(40,min(vs.x-pos.x+1,siz.x))
	siz.y = max(40,min(vs.y-pos.y+1,siz.y))
	rect_global_position = pos
	rect_size = siz

func _on_Input_text_entered(new_text):
	$Console/Input.clear()
	process_command(new_text)

func join_argv(argv: PoolStringArray, sep: String = ' ') -> String:
	if len(argv)<2:
		return ''
	else:
		var out: String = argv[1]
		for i in range(2,len(argv)):
			out+=sep+argv[i]
		return out

func call_echo(hover,argv):
	if not hover:
		append(join_argv(argv))

func call_clear(hover,_argv):
	if not hover:
		$Console/Output.clear()
		help_index={}

func page_tooltip(id):
	var page = help_pages.get(id)
	if page==null:
		printerr('help: reference to invalid page "',id,'"')
		return ''
	var title = page.get('title','')
	if not title:
		title=id.capitalize()
	var text = '[small_code][\u200Bhelp '+id+'\u200B][/small_code] [b][ref='+id+']'+clean_input(title)
	var synopsis = page.get('synopsis','')
	text += (':[/ref][/b] '+synopsis) if synopsis else '[/ref][/b]'
	return rewrite_tags(text)

func page_note(id: String):
	var title = help_pages.get(id,{}).get('title',id)
	return '[url=help '+id+'][color=#88ccff]'+clean_input(title)+'[/color][/url]'

func combined_aabb(node: Node):
	var result: AABB = AABB()
	if node is VisualInstance:
		result = node.get_aabb()
	for child in node.get_children():
		result=result.merge(combined_aabb(child))
	if node is Spatial:
		result = node.transform.xform(result)
	return result

func load_page_scene(scene_name: String, id: String) -> Array:
	var scene = null
	if not scene_name:
		return [null,null]

	var packed_scene = load(scene_name)
	if packed_scene==null:
		printerr(scene_name+': cannot load packed scene')
		return [null,null]
	scene = packed_scene.instance()
	if scene==null:
		printerr(scene_name+': cannot instance scene')
		return [null,null]
	
	var bbcode = null
	var res = null
	
	if scene.has_method('get_bbcode'):
		bbcode = scene.get_bbcode()

	if get_tree()==null:
		return [bbcode,res]
	
	scene.name = 'scene'
	$Viewport/Content.add_child(scene)
	var aabb: AABB = combined_aabb(scene)
	$Viewport/Camera.size = max(1,max(abs(aabb.size.x),abs(aabb.size.z)))
	$Viewport/Camera.translation.x = aabb.position.x+aabb.size.x/2
	$Viewport/Camera.translation.z = aabb.position.z+aabb.size.z/2
	$Viewport/Camera.translation.y = max(aabb.position.y,aabb.position.y+aabb.size.y)+10
	$Viewport.render_target_update_mode = Viewport.UPDATE_ONCE
	yield(get_tree(),'idle_frame')
	yield(get_tree(),'idle_frame')
	
	var tex = $Viewport.get_texture()
	if tex==null:
		printerr(scene_name+': cannot get viewport texture')
		return [bbcode,res]
	var dat = tex.get_data()
	if dat==null:
		printerr(scene_name+': cannot get viewport texture data')
		return [bbcode,res]
	
	var image = Image.new()
	image.copy_from(dat)
	var itex = ImageTexture.new()
	itex.create_from_image(image)
	res='res://help/rendered/'+id+'/scene_image'
	itex.take_over_path(res)
	
	$Viewport/Content.remove_child(scene)
	scene.queue_free()
	
	return [bbcode,res]

func show_page(id):
	if not id in help_pages:
		append('[code]Searching datastore for '+id+'...[/code]')
		append('[b][code]error: There is no page '+id+'!![/code][/b]')
		return
	var scene_bbcode = null
	var scene_name = help_pages[id].get('scene','')
	var image_resource = null
	if scene_name:
		var result = load_page_scene(scene_name,id)
		while result is GDScriptFunctionState:
			result=yield(result,'completed')
		scene_bbcode = result[0]
		image_resource = result[1]
	
	append('[code]Searching datastore for '+id+'...[/code]')
	append('[code]Loading '+id+'...[/code]')
	
	var title: String = help_pages[id].get('title','')
	if not title:
		title = id.capitalize()
	append(rewrite_tags('\n[h1]'+clean_input(title)+'[/h1]'))

	if image_resource:
		append('\n[img]'+image_resource+'[/img]\n')
	
	var synopsis: String = help_pages[id].get('synopsis','')
	if synopsis:
		append(rewrite_tags('\n[i]Synopsis: '+synopsis+'[/i]\n\n'))
	# FIXME: REPLACE {ref=...} IN CONTENT
	var content: String = help_pages[id].get('content','')
	if content:
		append(rewrite_tags(content))
	var toc: Array = help_pages[id].get('toc',[])
	for t in toc:
		append(' \u2022 '+page_tooltip(t)+'\n')
	if scene_bbcode:
		append(rewrite_tags(scene_bbcode))
	var see_also: Array = help_pages[id].get('see_also',[])
	if see_also:
		var see: String = ''
		for also in see_also:
			see += (', ' if see else '\nSee also: ')
			see += page_note(also)
		if see:
			append('[i]'+see+'[/i]')
	return ''

func call_ref(hover,argv:PoolStringArray):
	if not hover and len(argv)>1:
		append(page_note(argv[1]))

func call_synopsis(hover: bool,argv: PoolStringArray):
	if hover:
		return ''
	for i in range(1,len(argv)):
		append(page_tooltip(argv[i]))

func recursive_search(regexes,what) -> bool:
	if what is String:
		for regex in regexes:
			if regex.search(what):
				return true
	elif what is Dictionary:
		for k in what.values():
			if recursive_search(regexes,k):
				return true
	elif what is Array:
		for k in what:
			if recursive_search(regexes,k):
				return true
	return false

func call_search(hover: bool,argv: PoolStringArray):
	if hover:
		return ''
	var matches: Array = []
	var regexes: Array = []
	for i in range(1,len(argv)):
		regexes.append(RegEx.new())
		regexes[i-1].compile('(?i)'+argv[i])
	for id in help_pages.keys():
		if recursive_search(regexes,help_pages[id]):
			matches.append(id)
	if matches:
		for m in matches:
			append(page_tooltip(m))
	else:
		append('No pages found.')

func call_help(hover: bool,argv: PoolStringArray):
	if not hover:
		var id = join_argv(argv) if len(argv)>1 else 'help'
		if not help_index.has(id):
			var here = $Console/Output.get_line_count()
			var result = show_page(id)
			while result is GDScriptFunctionState:
				result=yield(result,'completed')
			help_index[id]=here+1
		else:
			append('[code]Scrolling to line '+str(help_index[id])+'.[/code]')
		$Console/Output.scroll_to_line(help_index[id])
	elif len(argv)>1 and help_pages.has(argv[1]):
		return page_tooltip(argv[1])
	elif len(argv)==1:
		return page_tooltip('help')

func call_invalid_command(_hover: bool,argv: PoolStringArray) -> String:
	append('Error: "'+argv[0]+'" is not a valid command. Try [color=#88ccff][url=help]help[/url][/color]')
	return ''

func process_hover(line):
	var argv: PoolStringArray = line.split(' ')
	return call(commands.get(argv[0],'call_invalid_command'),true,argv)

func process_command(line):
	var argv: PoolStringArray = line.split(' ')
	if allow_input:
		append(rewrite_tags('[command_font]'+clean_input(line)+'[/command_font]\n'))
	if argv and argv[0]:
		var result = call(commands.get(argv[0],'call_invalid_command'),false,argv)
		while result is GDScriptFunctionState:
			result=yield(result,'completed')
	if allow_input:
		prompt()

func _on_Output_meta_clicked(meta):
	if follow_urls:
		process_command(str(meta))
	emit_signal('url_clicked',str(meta))

func _on_Output_meta_hover_ended(_meta):
	$Tooltip.visible=false

func _on_Output_meta_hover_started(meta):
	var result = process_hover(str(meta))
	if result:
		$Tooltip/Text.parse_bbcode(result)
		var pos: Vector2 = get_viewport().get_mouse_position()
		$Tooltip.rect_global_position=pos
		$Tooltip.rect_min_size=Vector2(get_viewport().size.x/6.0,0)
		var siz: Vector2 = $Tooltip.rect_size
		var positions: Array = [ pos, pos-siz, Vector2(pos.x,pos.y-siz.y),
			Vector2(pos.x-siz.x,pos.y) ]
		var me: Rect2 = Rect2(rect_global_position,rect_size)
		var best_remain: float = 0
		var best_pos: Vector2 = pos
		for position in positions:
			var visible: Rect2 = Rect2(position,siz).clip(me)
			var remain: float = visible.get_area()
			if remain>best_remain:
				best_remain=remain
				best_pos=position
		$Tooltip.rect_global_position=best_pos
		$Tooltip.visible=true
