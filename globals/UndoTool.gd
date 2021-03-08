extends Node

class Action extends Reference:
	func run() -> bool: return true
	func redo() -> bool: return run()
	func undo() -> bool: return true
	func amend(_arg) -> bool: return true
	func as_string() -> String:
		assert(not 'Subclass forgot to override as_string()')
		return 'Action'

class UndoStack extends Reference:
	signal undo_stack_empty
	signal redo_stack_empty
	signal undo_stack_changed
	signal redo_stack_changed
	signal undo_failed
	signal redo_failed
	signal run_failed
	var undo_stack: Array = []
	var redo_stack: Array = []
	var verbose: bool = false
	var activity: bool = false # true if anything was changed; used to detect unsaved changes
	var applying_rule: int = 0 # >0 if we're inside amend, push, undo, or redo
# warning-ignore:shadowed_variable
	func _init(verbose: bool = false):
		self.verbose = verbose
	func top():
		if undo_stack:
			return undo_stack[len(undo_stack)-1]
		return null
	func clear():
		if verbose: print('clear stack')
		undo_stack.clear()
		redo_stack.clear()
		emit_signal('undo_stack_changed')
		emit_signal('redo_stack_changed')
		emit_signal('undo_stack_empty')
		emit_signal('redo_stack_empty')
	func dump():
		print('Undo/Redo Stack State')
		for i in range(len(redo_stack)):
			print('redo[',i,'] = ',redo_stack[i].as_string())
		var i=len(undo_stack)-1
		while i>=0:
			print('undo[',i,'] = ',undo_stack[i].as_string())
			i-=1
	func amend(arg) -> bool:
		applying_rule += 1
		activity = true
		if undo_stack:
			var action = undo_stack[len(undo_stack)-1]
			if action.amend(arg):
				emit_signal('undo_stack_changed')
				applying_rule -= 1
				return true
		applying_rule -= 1
		return false
	func push(action) -> bool:
		applying_rule += 1
		activity = true
		if verbose: print('UndoStack.push: pushing ',action.as_string())
		if action.run():
			if verbose: print('UndoStack.push: push successful for ',action.as_string())
			undo_stack.append(action)
			redo_stack.clear()
			if verbose: dump()
			emit_signal('undo_stack_changed')
			emit_signal('redo_stack_changed')
			emit_signal('redo_stack_empty')
			applying_rule -= 1
			return true
		else:
			push_error('UndoStack.push: action.run() failed for '+action.as_string())
			emit_signal('run_failed')
		if verbose: dump()
		applying_rule -= 1
		return false
	func undo() -> bool:
		applying_rule += 1
		activity = true
		if undo_stack:
			var action = undo_stack.pop_back()
			if verbose: print('UndoStack.undo: undoing ',action.as_string())
			if action.undo():
				if verbose: print('UndoStack.undo: undo successful for ',action.as_string())
				redo_stack.append(action)
				if verbose: dump()
				emit_signal('undo_stack_changed')
				emit_signal('redo_stack_changed')
				if undo_stack.empty():
					emit_signal('undo_stack_empty')
				applying_rule -= 1
				return true
			else:
				push_error('UndoStack.undo: action.undo() failed for '+
					action.as_string()+'. Undo/redo stack is now corrupted')
				redo_stack.clear()
				emit_signal('undo_failed')
				emit_signal('undo_stack_changed')
				emit_signal('redo_stack_changed')
				if undo_stack.empty():
					emit_signal('undo_stack_empty')
				emit_signal('redo_stack_empty')
		elif verbose:
			printerr('UndoStack.undo: undo stack is empty')
		dump()
		applying_rule -= 1
		return false
	func redo() -> bool:
		applying_rule += 1
		activity = true
		if redo_stack:
			var action = redo_stack.pop_back()
			if verbose: print('UndoStack.redo: redoing ',action.as_string())
			if action.redo():
				undo_stack.append(action)
				if verbose: print('UndoStack.redo: redo successful for ',action.as_string())
				if verbose: dump()
				emit_signal('undo_stack_changed')
				emit_signal('redo_stack_changed')
				if redo_stack.empty():
					emit_signal('redo_stack_empty')
				applying_rule -= 1
				return true
			else:
				push_error('UndoStack.redo: action.redo() failed for '+
					action.as_string()+'. Discarding redo stack.')
				emit_signal('redo_failed')
				emit_signal('redo_stack_changed')
				if redo_stack.empty():
					emit_signal('redo_stack_empty')
		elif verbose:
			printerr('UndoStack.redo: redo stack is empty')
		if verbose: dump()
		applying_rule -= 1
		return false
