extends Node

class Action extends Reference:
	func run() -> bool: return true
	func redo() -> bool: return true
	func undo() -> bool: return true
	func amend(_arg) -> bool: return true
	func as_string() -> String:
		assert(not 'Subclass forgot to override as_string()')
		return 'Action'

class UndoStack extends Reference:
	var undo_stack: Array = []
	var redo_stack: Array = []
	var verbose: bool = false
# warning-ignore:shadowed_variable
	func _init(verbose: bool = false):
		self.verbose = verbose
	func top():
		if undo_stack:
			return undo_stack[len(undo_stack)-1]
		return null
	func dump():
		print('Undo/Redo Stack State')
		for i in range(len(redo_stack)):
			print('redo[',i,'] = ',redo_stack[i].as_string())
		var i=len(undo_stack)-1
		while i>=0:
			print('undo[',i,'] = ',undo_stack[i].as_string())
			i-=1
	func amend(arg) -> bool:
		if undo_stack:
			var action = undo_stack[len(undo_stack)-1]
			if action.amend(arg):
				return true
		return false
	func push(action) -> bool:
		if verbose: print('UndoStack.push: pushing ',action.as_string())
		if action.run():
			if verbose: print('UndoStack.push: push successful for ',action.as_string())
			undo_stack.append(action)
			redo_stack.clear()
			if verbose: dump()
			return true
		else:
			printerr('UndoStack.push: action.run() failed for ',action.as_string())
		if verbose: dump()
		return false
	func undo() -> bool:
		if undo_stack:
			var action = undo_stack.pop_back()
			if verbose: print('UndoStack.undo: undoing ',action.as_string())
			if action.undo():
				if verbose: print('UndoStack.undo: undo successful for ',action.as_string())
				redo_stack.append(action)
				if verbose: dump()
				return true
			else:
				printerr('UndoStack.undo: action.undo() failed for ',action.as_string())
				printerr('UndoStack is now corrupted.')
				redo_stack.clear()
		else:
			printerr('UndoStack.undo: undo stack is empty')
		dump()
		return false
	func redo() -> bool:
		if redo_stack:
			var action = redo_stack.pop_back()
			if verbose: print('UndoStack.redo: redoing ',action.as_string())
			if action.redo():
				undo_stack.append(action)
				if verbose: print('UndoStack.redo: redo successful for ',action.as_string())
				if verbose: dump()
				return true
			else:
				printerr('UndoStack.redo: action.redo() failed for ',action.as_string())
		else:
			printerr('UndoStack.redo: redo stack is empty')
		if verbose: dump()
		return false
