extends Node

var GDNativeVisualEffects = preload("res://bin/VisualEffects.gdns")
var GDNativeCombatEngine = preload("res://bin/CombatEngine.gdns")
var RiftShader = preload('res://places/Rift.shader')
var native_combat_engine
var native_visual_effects

# These constants MUST match src/CombatEngineData.hpp

const FATED_TO_FLY: int = 0
const FATED_TO_DIE: int = 1
const FATED_TO_LAND: int = 2
const FATED_TO_RIFT: int = 3

const ENTRY_COMPLETE: int = 0
const ENTRY_FROM_ORBIT: int = 1
const ENTRY_FROM_RIFT: int = 2
const ENTRY_FROM_RIFT_STATIONARY: int = 3

const PLAYER_GOAL_ATTACKER_AI: int = 1
const PLAYER_GOAL_LANDING_AI: int = 2
const PLAYER_GOAL_COWARD_AI: int = 3
const PLAYER_GOAL_INTERCEPT: int = 4
const PLAYER_GOAL_RIFT: int = 5
const PLAYER_ORDERS_MAX_GOALS: int = 3
const PLAYER_ORDER_FIRE_PRIMARIES: int = 1
const PLAYER_ORDER_STOP_SHIP: int = 2
const PLAYER_ORDER_MAINTAIN_SPEED: int = 4
const PLAYER_ORDER_AUTO_TARGET: int = 8
const PLAYER_TARGET_CONDITION: int = 3840
const PLAYER_TARGET_NEXT: int = 256
const PLAYER_TARGET_NEAREST: int = 512
const PLAYER_TARGET_SELECTION: int = 240
const PLAYER_TARGET_ENEMY: int = 16
const PLAYER_TARGET_FRIEND: int = 32
const PLAYER_TARGET_PLANET: int = 48
const PLAYER_TARGET_OVERRIDE: int = 64
const PLAYER_TARGET_NOTHING: int = 240

var visual_mutex: Mutex = Mutex.new()
var physics_mutex: Mutex = Mutex.new()

func _init():
	native_combat_engine = GDNativeCombatEngine.new()
	native_visual_effects = GDNativeVisualEffects.new()
	native_combat_engine.set_visual_effects(native_visual_effects)
	native_visual_effects.set_shaders(RiftShader)

func clear_ai() -> void:
	# Call by ANY THREAD during a SCENE CHANGE to erase everything. This tells
	# the CombatEngine to discard everything: projectiles, ship stats,
	# multimeshes, and visual instances. Only meshes and their resource paths
	# are kept. The draw_space and draw_minimap will have nothing to display
	# until the next call to ai_step.
	visual_mutex.lock()
	physics_mutex.lock()
	native_combat_engine.clear_ai()
	native_visual_effects.clear_all_effects()
	physics_mutex.unlock()
	visual_mutex.unlock()

func clear_visuals() -> void:
	# Called in VISUAL THREAD by screens that don't show outer space, to remove
	# all projectiles and visual effects.
	visual_mutex.lock()
	physics_mutex.lock()
	native_combat_engine.clear_visuals()
	native_visual_effects.clear_all_effects()
	physics_mutex.unlock()
	visual_mutex.unlock()

func set_system_stats(hyperspace: bool = false, system_fuel_recharge: float = 0.5, 
		center_fuel_recharge = 1.5):
	native_combat_engine.set_system_stats(hyperspace, system_fuel_recharge, center_fuel_recharge)

func change_worlds(world: World) -> void:
	# Call by ANY THREAD during a SCENE CHANGE to erase everything. This tells
	# the CombatEngine to discard everything: projectiles, ship stats,
	# multimeshes, and visual instances. Only meshes and their resource paths
	# are kept. The draw_space and draw_minimap will have nothing to display
	# until the next call to ai_step.
	visual_mutex.lock()
	physics_mutex.lock()
	native_visual_effects.clear_all_effects()
	native_combat_engine.clear_ai()
	native_combat_engine.prepare_visual_frame(world.scenario)
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
	var array: Array = native_combat_engine.ai_step(delta,new_ships,new_planets,
		player_orders,player_ship_rid,space,update_request)
	var results: Dictionary = Dictionary()
	for result in array:
		if 'name' in result:
			results[result.name] = result
		else:
			results['weapon_rotations'] = result.duplicate(true)
	physics_mutex.unlock()
	return results

func set_visible_region(visible_area: AABB,
		visibility_expansion_rate: Vector3):
	native_visual_effects.set_visible_region(visible_area,visibility_expansion_rate)

func step_visual_effects(delta: float, world: World):
	native_visual_effects.step_effects(delta,world.scenario)

func draw_space(camera: Camera,viewport: Viewport) -> void:
	# Call in VISUAL THREAD to update on-screen projectiles.
	visual_mutex.lock()
	var viewport_size: Vector2 = viewport.size
	var ul: Vector3 = camera.project_position(Vector2(0,0),0)
	var lr: Vector3 = camera.project_position(viewport_size,0)
	var size: Vector3 = Vector3(abs(ul.x-lr.x),0,abs(ul.z-lr.z))
	var projectile_scale: float = pow(camera.size/30.0,0.5)
	native_combat_engine.update_overhead_view(camera.translation,size,projectile_scale)
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
	native_combat_engine.draw_minimap_contents(minimap.get_canvas_item(),map_center,map_radius,
		minimap_center,minimap_radius)
	visual_mutex.unlock()
