extends Node

var LoadHelp = preload('res://help/LoadHelp.gd')
var help_loader = LoadHelp.new()
var help_pages: Dictionary = {}

func _init():
	help_pages = help_loader.load_help_pages()

class page_sorter extends Reference:
	var all: Dictionary
	var empty: Array = []
	func _init(all_):
		all=all_
	func compare(key1,key2):
		var array1: Array = all.get(key1,empty)
		var array2: Array = all.get(key2,empty)
# warning-ignore:narrowing_conversion
		var min_len: int = min(len(array1),len(array2))
		for i in range(min_len):
			if array1[i]<array2[i]:
				return true
			elif array1[i]>array2[i]:
				return false
		return len(array1) < len(array2)

func make_help_tree() -> Array:
	# Add missing parent pages
	var all: Dictionary = {}
	for id in help_pages.keys():
		var split = id.split('/',false)
		var combined
		for i in range(len(split)):
			combined = split[i] if not combined else combined+'/'+split[i]
			all[combined]=split
	
	var tree: Array = all.keys()
	tree.sort_custom(page_sorter.new(all),'compare')
	
	var titles: Dictionary = {}
	for i in range(len(tree)):
		var id = tree[i]
		var title = help_pages[id].get('title','')
		if not title:
			title = id.capitalize()
		titles[id] = title
	return [ tree, titles ]

func page_tooltip(console,id: String):
	var page = help_pages.get(id)
	if page==null:
		printerr('help: reference to invalid page "',id,'"')
		return ''
	var title = page.get('title','')
	if not title:
		title=id.capitalize()
	var text = '[small_code][\u200Bhelp '+id+'\u200B][/small_code] [b][ref='+id+']'+console.clean_input(title)
	var synopsis = page.get('synopsis','')
	text += (':[/ref][/b] '+synopsis) if synopsis else '[/ref][/b]'
	return console.rewrite_tags(text)

func page_note(console,id: String):
	var title = help_pages.get(id,{}).get('title',id)
	return '[url=help '+id+'][color=#88ccff]'+console.clean_input(title)+'[/color][/url]'

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

func show_page(console,id: String):
	if not id in help_pages:
		console.append_raw_bbcode('[code]Searching datastore for '+id+'...[/code]')
		console.append_raw_bbcode('[b][code]error: There is no page '+id+'!![/code][/b]')
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
	
	console.append_raw_bbcode('[code]Searching datastore for '+id+'...[/code]')
	console.append_raw_bbcode('[code]Loading '+id+'...[/code]')
	
	var title: String = help_pages[id].get('title','')
	if not title:
		title = id.capitalize()
	console.append('\n[h1]'+console.clean_input(title)+'[/h1]')

	if image_resource:
		console.append_raw_bbcode('\n[img]'+image_resource+'[/img]\n')
	
	var synopsis: String = help_pages[id].get('synopsis','')
	if synopsis:
		console.append('\n[i]Synopsis: '+synopsis+'[/i]\n\n')
	# FIXME: REPLACE {ref=...} IN CONTENT
	var content: String = help_pages[id].get('content','')
	if content:
		console.append(content)
	var toc: Array = help_pages[id].get('toc',[])
	for t in toc:
		console.append_raw_bbcode(' \u2022 '+page_tooltip(console,t)+'\n')
	if scene_bbcode:
		console.append(scene_bbcode)
	var see_also: Array = help_pages[id].get('see_also',[])
	if see_also:
		var see: String = ''
		for also in see_also:
			see += (', ' if see else '\nSee also: ')
			see += page_note(console,also)
		if see:
			console.append_raw_bbcode('[i]'+see+'[/i]')
	return ''

func call_ref(console,argv:PoolStringArray):
	if len(argv)>1:
		console.append_raw_bbcode(page_note(console,argv[1]))

func call_synopsis(console,argv: PoolStringArray):
	for i in range(1,len(argv)):
		console.append_raw_bbcode(page_tooltip(console,argv[i]))

func insert(console,argv:PoolStringArray) -> String:
	if len(argv)>1:
		if argv[0]=='ref':
			return page_note(console,argv[1])
		elif argv[0]=='synopsis':
			return page_tooltip(console,argv[1])
	return ''

func recursive_search(console,regexes,what) -> bool:
	if what is String:
		for regex in regexes:
			if regex.search(what):
				return true
	elif what is Dictionary:
		for k in what.values():
			if recursive_search(console,regexes,k):
				return true
	elif what is Array:
		for k in what:
			if recursive_search(console,regexes,k):
				return true
	return false

func call_search(console,argv: PoolStringArray):
	var matches: Array = []
	var regexes: Array = []
	for i in range(1,len(argv)):
		regexes.append(RegEx.new())
		regexes[i-1].compile('(?i)'+argv[i])
	for id in help_pages.keys():
		if recursive_search(console,regexes,help_pages[id]):
			matches.append(id)
	if matches:
		for m in matches:
			console.append_raw_bbcode(page_tooltip(console,m))
	else:
		console.append_raw_bbcode('No pages found.')

func call_help(console,argv: PoolStringArray):
	var id = console.join_argv(argv) if len(argv)>1 else 'help'
	if not console.has_command_id('help '+id):
		var here = console.get_line_count()
		var result = show_page(console,id)
		while result is GDScriptFunctionState:
			result=yield(result,'completed')
		console.add_command_id('help '+id,here+1)
#	else:
#		append('[code]Scrolling to line '+str(help_index[id])+'.[/code]')
	console.scroll_to_command_id('help '+id)

func call_invalid_command(console,argv: PoolStringArray):
	console.append('Error: "'+argv[1]+'" is not a valid command. Try [ref=help]help[/ref]')

func hover(console,argv) -> String:
	if argv[0] == 'help':
		if len(argv)>1 and help_pages.has(argv[1]):
			return page_tooltip(console,argv[1])
		elif len(argv)==1:
			return page_tooltip(console,'help')
	return ''

func run(console,argv):
	if argv[0] == 'search':
		return call_search(console,argv)
	elif argv[0] == 'ref':
		return call_ref(console,argv)
	elif argv[0] == 'help':
		return call_help(console,argv)
	elif argv[0] == 'invalid_command':
		return call_invalid_command(console,argv)
