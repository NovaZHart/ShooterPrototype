extends Node

func run(console,argv):
	if argv[0] == 'echo':
		console.append_raw_bbcode(console.join_argv(argv))
	elif argv[0] == 'parse':
		console.append(console.join_argv(argv))
