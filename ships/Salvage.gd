extends Node

export var flotsam_mesh_path: String = ""
export var flotsam_scale: float = 1.0
export var product_name: String = ""
export var product_count: int = 0
export var armor_repair: int = 0
export var structure_repair: int = 0
export var spawn_probability: float = 0.0
export var spawn_priority: int = 50
export var grab_radius: float = 0.25

var product=null setget ,get_product
var combined_stats: Dictionary = {}

func is_Salvage(): pass # for type detection; never called

func get_product() -> Array:
	if product==null:
		var id: int = Commodities.commodities.by_name.get(product_name,-1)
		var result: Array = Commodities.commodities.all.get(id,[])
		if not result:
			product=[]
		else:
			result = Array(result)
			result[Commodities.Products.QUANTITY_INDEX]=product_count
			product=result
	return product

func pack_stats(ship_node) -> Dictionary:
	if not combined_stats.has("flotsam_mesh_path"):
		combined_stats = make_stats(ship_node)
	return combined_stats

func make_stats(ship_node) -> Dictionary:
	var stats = {}
	stats["flotsam_mesh_path"] = flotsam_mesh_path
	stats["flotsam_scale"] = flotsam_scale
	if get_product():
		stats["cargo_name"] = product[Commodities.Products.NAME_INDEX]
		stats["cargo_count"] = product[Commodities.Products.QUANTITY_INDEX]
		stats["cargo_unit_mass"] = product[Commodities.Products.MASS_INDEX]*stats["cargo_count"]
	else:
		stats["cargo_name"] = ""
		stats["cargo_count"] = 0
		stats["cargo_unit_mass"] = 0.0
	stats["armor_repair"] = armor_repair
	stats["structure_repair"] = structure_repair
	stats["spawn_probability"] = spawn_probability
	stats["spawn_priority"] = spawn_priority
	stats["spawn_duration"] = combat_engine.SALVAGE_TIME_LIMIT
	stats["grab_radius"] = grab_radius
	stats["path"] = ship_node.get_path_to(self)
	return stats

func add_stats(ship,_skip_runtime_stats,ship_node):
	ship["salvage"].append(pack_stats(ship_node))

