extends GridContainer

var SimpleTree = simple_tree.SimpleTree
var SimpleNode = simple_tree.SimpleNode

var tree = SimpleTree.new()
var root = tree.get_root()
var a = SimpleNode.new()
var b = SimpleNode.new()
var c = SimpleNode.new()

func _init():
	a.set_name('a')
	b.set_name('b')
	c.set_name('c')
	a.add_child(b)
	a.add_child(c)

func run(console,argv:PoolStringArray):
	if len(argv)<2:
		return
	var script: GDScript = GDScript.new()
	var cmd = ''
	for i in range(1,len(argv)):
		cmd+=' '+argv[i]
	script.set_source_code('extends Reference\nfunc go(top):\n\t'+cmd+'\n')
	var _discard = script.reload()
	var runme = script.new()
	var result = runme.call('go',self)
	if result:
		console.append_raw_text(str(result))

func _ready():
	$ConsolePanel.add_command('run',self)
