extends Control

signal deorbit_selected
signal service_activated

func deorbit_selected():
	emit_signal('deorbit_selected')

func service_activated(service,meta):
	emit_signal('service_activated',service,meta)

func update_service_list():
	$ServiceList.update_service_list()
