extends Panel

var ZWSP: String = '\u200B' # zero-width space
var console_prompt: String = '[color=#6688ff][code]user@host> [/code][/color]'
var image_path: String = 'res://ships/PurpleShips/Metal-4271-light-green-128x128.jpg'

var help_pages: Dictionary = {
	'page1': {
		'title': 'Page 1',
		'synopsis': 'A page that tells you not to look at page 3',
		'content': 'This is the information from page 1. Make sure you never look at [color=#88ccff][url=help page3]Page 3.[/url][/color]',
		'see_also': ['page2', 'page3'],
	},
	'page2': {
		'title': 'Page 2',
		'synopsis': 'A nice image.',
		'content': "Isn't this a nice image?\n[img]"+image_path+"[/img]",
		'see_also': ['page1'],
	},
	'page3': {
		'title': 'The Forbidden Page 3',
		'synopsis': 'Do not look at this page.',
		'content': "[b][color=#ff7777]I told you not to look at this page!![/color][/b]",
		'see_also': ['page1'],
	},
	'commands': {
		'title': 'Console Commands',
		'synopsis': 'List of console commands and how to use them',
		'content': 
			'Known commands:\n\n' + \
			' \u2022 Read a help page:\n\t\t[code]help[/code] [i]page_id[/i]\n' + \
			' \u2022 Search for help:\n\t\t[code]search[/code] [i]search words[/i]\n' + \
			' \u2022 Quick info from a page:\n\t\t[code]synopsis[/code] [i]page_id[/i]\n' + \
			' \u2022 Clear the terminal:\n\t\t[code]clear[/code]\n'
	},
	'help': {
		'title': 'Table of Contents',
		'synopsis': 'List of help sections.',
		'table_of_contents': [ 'commands', 'page1', 'page2', 'page3' ],
	}
}

var commands: Dictionary = {
	'echo':'call_echo',
	'clear':'call_clear',
	'help':'call_help',
	'synopsis':'call_synopsis',
	'search':'call_search',
}

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
	$Console/Output.append_bbcode('\n'+console_prompt)

func _ready():
	$Console/Output.clear()
	append('[img]'+image_path+'[/img]\n[url=help page1]blah[/url]\n'+
		'[url=help page2][img]'+image_path+'[/img][/url]\n')
	prompt()

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

func page_tooltip(id):
	var page = help_pages.get(id)
	var text = '[b][color=#88ccff][url=help '+id+']'+page.get('title',id)
	var synopsis = page.get('synopsis','')
	text += (': [/url][/color][/b]'+synopsis) if synopsis else '[/url][/color][/b]'
	return text

func page_note(id: String):
	var title = help_pages.get(id,{}).get('title',id)
	return '[url=help '+id+'][color=#88ccff]'+clean_input(title)+'[/color][/url]'

func show_page(argv):
	var id = join_argv(argv) if len(argv)>1 else 'help'
	append('[code]Searching datastore for '+id+'...[/code]')
	if not id in help_pages:
		append('[b][code]error: There is no page '+id+'!![/code][/b]')
		return
	append('[code]Loading '+id+'...[/code]')
	var title: String = help_pages[id].get('title',id)
	append('\n[center][b]'+clean_input(title)+'[/b][/center]')
	var synopsis: String = help_pages[id].get('synopsis','')
	if synopsis:
		append('\n[i]Synopsis: '+synopsis+'[/i]\n\n')
	var content: String = help_pages[id].get('content','')
	if content:
		append(content)
	var toc: Array = help_pages[id].get('table_of_contents',[])
	for t in toc:
		append(' \u2022 '+page_tooltip(t)+'\n')
	var see_also: Array = help_pages[id].get('see_also',[])
	if see_also:
		var see: String = ''
		for also in see_also:
			see += (', ' if see else '\nSee also: ')
			see += page_note(also)
		if see:
			append('[i]'+see+'[/i]')

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
		show_page(argv)
	elif len(argv)>1 and help_pages.has(argv[1]):
		return '[code]synopsis '+argv[1]+'[/code]\n'+page_tooltip(argv[1])
	elif len(argv)==1:
		return '[code]synopsis help[/code]\n'+page_tooltip('help')
	return ''

func call_invalid_command(_hover: bool,argv: PoolStringArray):
	append('Error: "'+argv[0]+'" is not a valid command. Try [color=#88ccff][url=help]help[/url][/color]')

func process_hover(line):
	var argv: PoolStringArray = line.split(' ')
	return call(commands.get(argv[0],'call_invalid_command'),true,argv)

func process_command(line):
	var argv: PoolStringArray = line.split(' ')
	append('[code]'+clean_input(line)+'[/code]\n\n')
	if argv and argv[0]:
		call(commands.get(argv[0],'call_invalid_command'),false,argv)
	prompt()

func _on_Output_meta_clicked(meta):
	process_command(str(meta))

func _on_Output_meta_hover_ended(_meta):
	$Tooltip.visible=false

func _on_Output_meta_hover_started(meta):
	var result = process_hover(str(meta))
	if result:
		$Tooltip/Text.parse_bbcode(result)
		$Tooltip.rect_global_position=get_viewport().get_mouse_position()
		$Tooltip.rect_min_size=Vector2(get_viewport().size.x/6.0,0)
		$Tooltip.visible=true
