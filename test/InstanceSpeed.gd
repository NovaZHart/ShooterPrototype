extends Node

var scene1 = preload('res://ships/SmallCivilian/Samoyed.tscn')
var scene2 = preload('res://weapons/IACivilian/AntiMissile2x2.tscn')

var thread = Thread.new()
var done: bool = false

var x: int = 0

func _physics_process(_delta):
	call_deferred('run_test')

func run_test():
	#assert(false)
	print('Iteration '+str(x))
	for i in range(100):
		#print("Fast scene:")
		#print("Normal:")
		test_performance(['res://ships/SmallCivilian/Samoyed.tscn',"normal",x<500])
		
		#print("Threaded:")
		thread.start(self, "test_performance", ['res://ships/SmallCivilian/Samoyed.tscn',"threaded",x<500])
		thread.wait_to_finish()
		
		#print("Slow scene:")
		#print("Normal:")
		test_performance(['res://weapons/IACivilian/AntiMissile2x2.tscn',"normal",x<500])
		
		#print("Threaded:")
		thread.start(self, "test_performance", ['res://weapons/IACivilian/AntiMissile2x2.tscn',"threaded",x<500])
		thread.wait_to_finish()
		
		x=x+1
	
	if x>=30000:
		get_tree().quit()

# Called when the node enters the scene tree for the first time.
func test_performance(data=null):
	var time_before = OS.get_ticks_usec()
	var n = load(data[0]).instance()
	add_child(n)
	remove_child(n)
	if not data[2]:
		n.queue_free()
	var time_after = OS.get_ticks_usec()
	if time_after-time_before>3000:
		print(data[0]+" "+data[1]+" took %d usecs" % [time_after - time_before])
