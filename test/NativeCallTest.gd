extends Label

export var count: int = 11500
export var joinme: Array = [ 'a', 'dog', 'farts', 'and', 'i', 'run' ]

func script_join(a: Array,s: String):
	var result: String = ''
	var last = a.size()-1
	for i in range(last):
		result += a[i]+s
	result += a[last]
	return result

func _ready():
	print(utils.native.string_join(joinme,'   '))

func _physics_process(_delta):
	for _i in range(count):
		utils.native.string_join(joinme,'   ')
	set_text("FPS = "+str(Engine.get_frames_per_second())+" calls per frame = "+str(count))
