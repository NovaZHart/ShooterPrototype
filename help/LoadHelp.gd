extends Object

var comment: RegEx = RegEx.new()
var statement: RegEx = RegEx.new()
var not_space: RegEx = RegEx.new()

func _init():
	if comment.compile('^\\s*#')!=OK:
		printerr('Help: cannot compile comment regex')
	if statement.compile('^(?i)\\s*@(?<dir>PAGE|.EOF|CONTENT|TITLE|SYNOPSIS|SEE_ALSO|TOC)\\s*(?<rest>.*)$')!=OK:
		printerr('Help: cannot compile statement regex')
	if not_space.compile('(?<not_space>\\S+)')!=OK:
		printerr('Help: cannot compile not_space regex')

func regex_search_all(block: String) -> Array:
	var result: Array = []
	for m in not_space.search_all(block):
		if m:
			result.append(m.get_string())
	return result

func scan_file(path: String,result: Dictionary):
	var file = File.new()
	file.open(path, File.READ)
	var content: String = file.get_as_text()
	file.close()
	var lines: PoolStringArray = content.split('\n')
	
	var page_id = null
	var page = {}
	var block: String = ''
	var block_name = null
	
	for i in range(len(lines)+1):
		var line: String = lines[i] if i<len(lines) else '@\bEOF EOF'
		if comment.search(line):
			continue # Ignore comment lines
		var dir_rest = statement.search(line)
		if not dir_rest:
			# Not on a directive line, so just append to the current string
			block+=line+'\n'
			continue
		var dir = dir_rest.get_string('dir').to_lower()
		if block_name!=null:
			# End the current block:
			if block_name=='title':
				page[block_name]=block
			elif ['synopsis','content'].has(block_name):
				page[block_name]=block
			elif ['see_also','toc'].has(block_name):
				page[block_name]=regex_search_all(block)
			if page_id!=null and len(page)>0 and (block_name=='page' or dir=='\beof'):
				# End the current page
				result[page_id] = page
				page={}
			if block_name=='page':
				page_id=block
		# Begin the next block:
		print('directive ',dir)
		block_name = dir
		block = dir_rest.get_string('rest')

func process_dir(dir_path: String,result: Dictionary):
	var dir: Directory = Directory.new()
	if dir.open(dir_path) != OK:
		return printerr('Help: ',dir_path,': cannot open directory')
	if dir.list_dir_begin(true,true)!=OK:
		return printerr('Help: ',dir_path,': cannot list directory')
	var file_name: String = dir.get_next()
	while file_name!='':
		if dir.current_is_dir():
			process_dir(dir_path+'/'+file_name,result)
		elif file_name.ends_with('.txt'):
			scan_file(dir_path+'/'+file_name,result)
		file_name=dir.get_next()
	return

func load_help_pages() -> Dictionary:
	var result: Dictionary = {}
	process_dir('res://help',result)
	return result
