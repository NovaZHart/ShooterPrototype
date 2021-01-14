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
	'{<}':'[',
	'{>}':']',
	'[prompt_font]':'[color=#6688ff][code]',
	'[/prompt_font]':'[/code][/color]',
	'[command_font]':'[color=#eebb66][code]',
	'[/command_font]':'[/code][/color]',
	'[small_code]':'[code]',
	'[/small_code]':'[/code]',
}

var ZWSP: String = '\u200B' # zero-width space
var console_prompt = null
var command_index: Dictionary = {}
var initial_size: Rect2 = Rect2()
var command_regex: RegEx = RegEx.new()
var commands: Dictionary = {}

signal url_clicked

func _init():
	if OK!=command_regex.compile('\\{(?<command>[^}]+)\\}'):
		printerr('Help: cannot compile command regex')

func rewrite_tags(s: String) -> String:
	var t: String = s
	for from_string in tag_filters:
		t = t.replace(from_string,tag_filters[from_string])
	var matches = command_regex.search_all(t)
	var subs: Dictionary = {}
	for m in matches:
		var command = m.get_string('command')
		if command:
			var result = process_insert(command)
			if result:
				subs['{'+command+'}'] = result
	for sub_from in subs:
		t = t.replace(sub_from,subs[sub_from])
	return t

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

func insert_bbcode(what):
	$Console/Output.parse_bbcode(what)

func append_raw_text(what,ensure_eoln: bool = true):
	$Console/Output.append_bbcode(clean_input(what))
	if ensure_eoln and not what.ends_with('\n'):
		$Console/Output.append_bbcode('\n')

func append_raw_bbcode(what,ensure_eoln: bool = true):
	$Console/Output.append_bbcode(what)
	if ensure_eoln and not what.ends_with('\n'):
		$Console/Output.append_bbcode('\n')

func append(what,ensure_eoln: bool=true):
	$Console/Output.append_bbcode(rewrite_tags(what))
	if ensure_eoln and not what.ends_with('\n'):
		$Console/Output.append_bbcode('\n')

func prompt():
	if console_prompt==null:
		console_prompt = rewrite_tags('[prompt_font]'+clean_input(username+'@'+fqdn())+'> [/prompt_font]')
	$Console/Output.append_bbcode(console_prompt)

func get_line_count() -> int:
	return $Console/Output.get_line_count()

func has_command_id(key: String) -> bool:
	return command_index.has(key)
	
func add_command_id(key: String,value: int):
	command_index[key]=value

func scroll_to_command_id(key: String):
	if command_index.has(key):
		$Console/Output.scroll_to_line(command_index[key])

func clear():
	$Console/Output.clear()
	command_index.clear()

func add_command(name,object):
	commands[name]=object

func _ready():
	commands = {
		# For testing:
		'echo':$Commands/Echo,
		'parse':$Commands/Echo,
		
		# Basic functionality:
		'clear':$Commands/Clear,
		
		# Help pages:
		'ref':$Commands/Help,
		'help':$Commands/Help,
		'synopsis':$Commands/Help,
		'search':$Commands/Help,
		'invalid_command':$Commands/Help,
	}
	clear()
	if initial_bbcode:
		append(initial_bbcode)
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

func run_command(argv: PoolStringArray,method,allow_fallback: bool = true):
	if argv[0] in commands:
		var command = commands[argv[0]]
		if command and command.has_method(method):
			return command.call(method,self,argv)
#			while result is GDScriptFunctionState:
#				result=yield(result,'completed')
#			return result
	if allow_fallback:
		return run_command(PoolStringArray(['invalid_command',argv[0]]),method,false)
	return ''

func process_insert(line):
	var argv: PoolStringArray = line.split(' ')
	return run_command(argv,'insert',false)

func process_hover(line):
	var argv: PoolStringArray = line.split(' ')
	return run_command(argv,'hover',false)

func process_command(line):
	var argv: PoolStringArray = line.split(' ')
	if allow_input:
		$Console/Output.append_bbcode(tag_filters.get('[command_font]','') + \
			clean_input(line) + tag_filters.get('[/command_font]','') + '\n')
	if argv and argv[0]:
		var result = run_command(argv,'run')
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
