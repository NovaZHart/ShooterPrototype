extends Node

var GDNativeCombatEngine = load("res://bin/CombatEngine.gdns")
var native

const FATED_TO_FLY: int = 0
const FATED_TO_DIE: int = 1
const FATED_TO_LAND: int = 2

var visual_mutex: Mutex = Mutex.new()
var physics_mutex: Mutex = Mutex.new()

func _init():
	native = GDNativeCombatEngine.new()

func clear_ai() -> void:
	# Call by ANY THREAD during a SCENE CHANGE to erase everything. This tells
	# the CombatEngine to discard everything: projectiles, ship stats,
	# multimeshes, and visual instances. Only meshes and their resource paths
	# are kept. The draw_space and draw_minimap will have nothing to display
	# until the next call to ai_step.
	visual_mutex.lock()
	physics_mutex.lock()
	native.clear_ai()
	physics_mutex.unlock()
	visual_mutex.unlock()

func clear_visuals() -> void:
	# Called in VISUAL THREAD by screens that don't show outer space, to remove
	# all projectiles and visual effects.
	visual_mutex.lock()
	physics_mutex.lock()
	native.clear_visuals()
	physics_mutex.unlock()
	visual_mutex.unlock()

func change_worlds(world: World) -> void:
	# Call by ANY THREAD during a SCENE CHANGE to erase everything. This tells
	# the CombatEngine to discard everything: projectiles, ship stats,
	# multimeshes, and visual instances. Only meshes and their resource paths
	# are kept. The draw_space and draw_minimap will have nothing to display
	# until the next call to ai_step.
	visual_mutex.lock()
	physics_mutex.lock()
	native.clear_ai()
	native.prepare_visual_frame(world.scenario)
	physics_mutex.unlock()
	visual_mutex.unlock()

func ai_step(delta: float,new_ships: Array,new_planets: Array,
		player_orders: Array,player_ship_rid: RID,
		space: PhysicsDirectSpaceState,update_request: Array) -> Dictionary:
	# Call in PHYSICS THREAD in a _physics_process() before any PhysicsBody
	# objects call their _physics_process(). This runs the ai, integrates
	# projectiles (which aren't in the physics server), damages ships,
	# and prepares all forces for the physics server.
	physics_mutex.lock()
	var array: Array = native.ai_step(delta,new_ships,new_planets,
		player_orders,player_ship_rid,space,update_request)
	var results: Dictionary = Dictionary()
	for result in array:
		if 'name' in result:
			results[result.name] = result
		else:
			results['weapon_rotations'] = result.duplicate(true)
	physics_mutex.unlock()
	return results

func draw_space(camera: Camera,viewport: Viewport) -> void:
	# Call in VISUAL THREAD to update on-screen projectiles.
	visual_mutex.lock()
	var viewport_size: Vector2 = viewport.size
	var ul: Vector3 = camera.project_position(Vector2(0,0),0)
	var lr: Vector3 = camera.project_position(viewport_size,0)
	var size: Vector3 = Vector3(abs(ul.x-lr.x),0,abs(ul.z-lr.z))
	native.update_overhead_view(camera.translation,size)
	visual_mutex.unlock()

func draw_minimap(minimap: Node2D,minimap_size: float,
		map_center: Vector2,map_radius: float) -> void:
	# Call in VISUAL THREAD to draw the minimap
	# Note: map_center&map_radius are location of minimap view in world space
	# minimap_size is the size of the minimap as a fraction of the screen linearly
	# minimap_center&minimap_radius is where the minimap will be drawn.
	visual_mutex.lock()
	var viewport_size: Vector2 = minimap.get_viewport_rect().size
	var goal = viewport_size*minimap_size*Vector2(1,1024/600.0)
	var minimap_radius = min(goal[0],goal[1])
	var minimap_center: Vector2 = Vector2(minimap_radius,minimap_radius)
	native.draw_minimap_contents(minimap.get_canvas_item(),map_center,map_radius,
		minimap_center,minimap_radius)
	visual_mutex.unlock()
