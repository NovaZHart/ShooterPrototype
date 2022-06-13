extends Node

var GDNativeVisualEffects = preload("res://bin/VisualEffects.gdns")
var GDNativeCombatEngine = preload("res://bin/CombatEngine.gdns")
var RiftShader = preload('res://shaders/Rift.shader')
var ZapBallShader = preload('res://shaders/ZapBall.shader')
var ShieldEllipseShader = preload('res://shaders/ShieldEllipse.shader')
var HyperspacingPolygonShader = preload('res://shaders/HyperspacingPolygon.shader')
var native_combat_engine
var native_visual_effects
var hyperspacing_texture = preload('res://textures/blue-squiggles.jpeg')
var cargo_puff_texture = preload('res://textures/magenta-beige-puff.png')
var fade_out_texture = preload('res://shaders/FadeOutTexture.shader')

# All constants MUST match src/CombatEngineData.hpp

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
const PLAYER_GOAL_ARRIVING_MERCHANT_AI: int = 3
const PLAYER_GOAL_INTERCEPT: int = 4
const PLAYER_GOAL_RIFT: int = 5
const PLAYER_ORDERS_MAX_GOALS: int = 3
const PLAYER_ORDER_FIRE_PRIMARIES: int = 1
const PLAYER_ORDER_STOP_SHIP: int = 2
const PLAYER_ORDER_MAINTAIN_SPEED: int = 4
const PLAYER_ORDER_AUTO_TARGET: int = 8
const PLAYER_ORDER_TOGGLE_CARGO_WEB: int = 16
const PLAYER_TARGET_CONDITION: int = 61440
const PLAYER_TARGET_NEXT: int = 4096
const PLAYER_TARGET_NEAREST: int = 8192
const PLAYER_TARGET_SELECTION: int = 3840
const PLAYER_TARGET_ENEMY: int = 256
const PLAYER_TARGET_FRIEND: int = 512
const PLAYER_TARGET_PLANET: int = 1024
const PLAYER_TARGET_OVERRIDE: int = 2048
const PLAYER_TARGET_NOTHING: int = 3840

const ATTACKER_AI: int = 0
const PATROL_SHIP_AI: int = 1
const RAIDER_AI: int = 2
const ARRIVING_MERCHANT_AI: int = 3
const DEPARTING_MERCHANT_AI: int = 4

const SALVAGE_TIME_LIMIT: float = 60.0

const NUM_DAMAGE_TYPES: int = 13
const DAMAGE_TYPELESS: int = 0    # Damage that ignores resist and passthru (do not use)
const DAMAGE_LIGHT: int = 1       # Non-standing electromagnetic fields (light, photons)
const DAMAGE_HE_PARTICLE: int = 2 # Particles of matter with high kinetic energy (particle beam)
const DAMAGE_PIERCING: int = 3    # Small macroscopic things moving quickly (bullets)
const DAMAGE_IMPACT: int = 4      # Larger non-pointy things moving quickly (asteroids)
const DAMAGE_EM_FIELD: int = 5    # Standing or low-frequency EM fields (ie. EMP or big magnet)
const DAMAGE_GRAVITY: int = 6     # Strong gravity or gravity waves
const DAMAGE_ANTIMATTER: int = 7  # Antimatter particles
const DAMAGE_EXPLOSIVE: int = 8   # Ka-boom!
const DAMAGE_PSIONIC: int = 9     # Power of mind over matter
const DAMAGE_PLASMA: int = 10     # Super-heated matter
const DAMAGE_CHARGE: int = 11     # Electric charge
const DAMAGE_SPACETIME: int = 12  # Tear open rifts in the fabric of spacetime

const DAMAGE_HELP_PAGES: PoolStringArray = PoolStringArray([
	"rules/damage/typeless", # Typeless damage should never show up
	"rules/damage/light",
	"rules/damage/he_particle",
	"rules/damage/piercing",
	"rules/damage/impact",
	"rules/damage/em_field",
	"rules/damage/gravity",
	"rules/damage/antimatter",
	"rules/damage/hot_matter",
])

const MAX_RESIST: float = 0.75
const MIN_RESIST: float = -222.0
const MIN_PASSTHRU: float = 0.0
const MAX_PASSTHRU: float = 1.0

var combat_state = null
var visual_mutex: Mutex = Mutex.new()
var physics_mutex: Mutex = Mutex.new()

func _enter_tree():
	native_combat_engine = GDNativeCombatEngine.new()
	native_visual_effects = GDNativeVisualEffects.new()
	native_combat_engine.set_visual_effects(native_visual_effects)
	native_visual_effects.spatial_rift_shader=RiftShader;
	native_visual_effects.zap_ball_shader=ZapBallShader
	native_visual_effects.hyperspacing_polygon_shader=HyperspacingPolygonShader;
	native_visual_effects.fade_out_texture=fade_out_texture;
	native_visual_effects.shield_ellipse_shader=ShieldEllipseShader;
	native_visual_effects.hyperspacing_texture=hyperspacing_texture;
	native_visual_effects.cargo_puff_texture=cargo_puff_texture;
	native_visual_effects.shield_texture=hyperspacing_texture;
	# FIXME: pass the ShieldEllipseShader

func init_combat_state(system_info,system,immediate_entry: bool) -> void:
	# Call in _ready to create the CombatState for a System or Hyperspace
	# system_info = SystemData for current system or null for Hyperspace
	# system = System or Hyperspace
	# immediate_entry = if true, ships have no entry animation
	combat_state = Factions.CombatState.new(system_info,system,immediate_entry)
	visual_mutex.lock()
	physics_mutex.lock()
	var data_for_native: Dictionary = combat_state.data_for_native()
	native_combat_engine.init_factions(data_for_native)
	physics_mutex.unlock()
	visual_mutex.unlock()

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
	combat_state = null
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
	native_visual_effects.set_scenario(world.scenario)
	native_combat_engine.clear_ai()
	native_combat_engine.prepare_visual_frame(world.scenario)
	physics_mutex.unlock()
	visual_mutex.unlock()

func set_world(world: World) -> void:
	assert(world)
	visual_mutex.lock()
	physics_mutex.lock()
	native_visual_effects.set_scenario(world.scenario)
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
	var weapon_rotations = array[len(array)-3]
	var faction_info = array[len(array)-2]
	var salvaged_items = array[len(array)-1]
	var results: Dictionary = Dictionary()
	for iresult in range(len(array)-3):
		results[array[iresult]['name']] = array[iresult]
	results['weapon_rotations'] = weapon_rotations.duplicate(true)
	results['faction_info'] = faction_info.duplicate(true)
	results['salvaged_items'] = salvaged_items.duplicate(true)
	physics_mutex.unlock()
	return results

func set_visible_region(visible_area: AABB,
		visibility_expansion_rate: Vector3):
	native_visual_effects.set_visible_region(visible_area,visibility_expansion_rate)

func step_visual_effects(delta: float, camera: Camera, viewport: Viewport):
	var viewport_size: Vector2 = viewport.size
	var ul: Vector3 = camera.project_position(Vector2(0,0),0)
	var lr: Vector3 = camera.project_position(viewport_size,0)
	var size: Vector3 = Vector3(abs(ul.x-lr.x),0,abs(ul.z-lr.z))
	var projectile_scale: float = pow(camera.size/30.0,0.5)
	native_visual_effects.step_effects(delta,camera.translation,size,projectile_scale)
	native_visual_effects.free_unused_effects() # FIXME: move to another thread?

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

func draw_minimap_rect(minimap: Node2D,map_rect: Rect2,minimap_rect: Rect2) -> void:
	# Call in VISUAL THREAD to draw the minimap
	# Note: map_rect is the bounds of the minimap view in world space, and
	# minimap_rect is the bounds of the minimap on the screen
	# Large objects will extend slightly outside the bounds.
	visual_mutex.lock()
	native_combat_engine.draw_minimap_rect_contents(minimap.get_canvas_item(),map_rect,minimap_rect)
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
