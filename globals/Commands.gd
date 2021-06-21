extends Node

var commands
var Echo
var Help
var Clear
var Location

func _enter_tree():
	var BuiltinCommands = load('res://ui/commands/BuiltinCommands.tscn')
	commands = BuiltinCommands.instance()
	commands.name = 'Commands'
	add_child(commands)
	Echo = $Commands/Echo
	Help = $Commands/Help
	Clear = $Commands/Clear
	Location = $Commands/Location
