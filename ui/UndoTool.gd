extends Reference

class Action extends Reference:
	func run() -> bool: return true
	func redo() -> bool: return true
	func undo() -> bool: return true
	func amend(_arg) -> bool: return true

class UndoStack extends Reference:
	var undo_stack: Array = []
	var redo_stack: Array = []
	func top():
		if undo_stack:
			return undo_stack[len(undo_stack)-1]
		return null
	func amend(arg):
		if undo_stack:
			undo_stack[len(undo_stack)-1].amend(arg)
	func push(action):
		if action.run():
			undo_stack.append(action)
			redo_stack.clear()
	func undo():
		if undo_stack:
			var action = undo_stack.pop_back()
			if action.undo():
				redo_stack.append(action)
	func redo():
		if redo_stack:
			var action = redo_stack.pop_back()
			if action.redo():
				undo_stack.append(action)
