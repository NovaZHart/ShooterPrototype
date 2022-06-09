extends Node

var GDNativeOSTools = preload("res://bin/OSTools.gdns")

var native_ostools

func _enter_tree():
	native_ostools = GDNativeOSTools.new()

func make_process_high_priority() -> int:
	return native_ostools.make_process_high_priority()
