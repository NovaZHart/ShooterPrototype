extends Node

func run(console,argv):
	if len(argv)<2:
		console.append('[error_code]syntax: location system/planet/moon[/error_code]')
		return
	console.append('[code]Scanning datastore...[/code]')
	var line = null
	for iarg in range(1,len(argv)):
		console.append('[code]'+console.clean_input(argv[iarg])+':[/code]')
		line = console.get_line_count()
		var node = game_state.systems.get_node_or_null(argv[iarg])
		if node and node.has_method('is_SpaceObjectData') and node.description:
			console.append(node.description)
		else:
			console.append('  No description available.')
	if line!=null and line>0:
		console.add_command_id(console.join_argv(argv),line)
