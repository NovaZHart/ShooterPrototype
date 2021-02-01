extends PopupPanel

var used_ids = {}
var result = [ null, null, null ]

func _input(event):
	if event.is_action_pressed('ui_accept'):
		accept_event()
		_on_Accept_pressed()
	elif event.is_action_pressed('ui_cancel'):
		accept_event()
		_on_Cancel_pressed()

func set_used_ids(ids):
	used_ids.clear()
	for id in ids:
		used_ids[str(id)] = 1

func _ready():
	var _discard = validate_fields()

func validate_fields() -> bool:
	if not $Split/Labels/IDEdit.text.substr(0,1).is_valid_identifier():
		$Split/Buttons/Info.text = 'ID must start with a letter or underscore'
	elif not $Split/Labels/IDEdit.text.is_valid_identifier():
		$Split/Buttons/Info.text = 'ID can have only letters, numbers, underscore'
	elif used_ids.has($Split/Buttons/Info):
		$Split/Buttons/Info.text = 'That ID is already used; pick another.'
	elif not $Split/Labels/NameEdit.text.strip_edges():
		$Split/Buttons/Info.text = 'Specify a displayed name.'
	else:
		$Split/Buttons/Info.text = ''
	var good = $Split/Buttons/Info.text==''
	$Split/Buttons/Accept.disabled = not good
	return good

# warning-ignore:unused_argument
func _on_IDEdit_text_changed(new_text):
	var _discard = validate_fields()

# warning-ignore:unused_argument
func _on_NameEdit_text_changed(new_text):
	var _discard = validate_fields()

func _on_Cancel_pressed():
	result = [ false, null, null ]
	visible = false

func _on_Accept_pressed():
	if validate_fields():
		result = [ true, $Split/Labels/IDEdit.text, $Split/Labels/NameEdit.text ]
		visible = false
