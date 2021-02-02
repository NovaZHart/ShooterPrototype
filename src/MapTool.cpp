#include "SphereTool.hpp"

#include <Rect2>

using namespace godot;
using namespace std;

template<class T>
T get<T>(Array a,key k) {
  return static_cast<T>(a[k]);
}

SystemInfo::SystemInfo(Array spd):
  path(spd[0]), position(spd[1]), display_name(spd[2]),
  display_name_region()
{
  position.y=0;
}

SystemInfo::SystemInfo(const SystemInfo &o):
  path(o.path),
  position(o.position),
  display_name(o.display_name),
  display_name_region(o.display_name_region)
{}

SystemInfo::~SystemInfo() {}

/* ------------------------------------------------------------------ */

MapToolVisuals::MapToolVisuals
(Ref<Font> highlighted_font, Ref<Font> label_font, Color connected,
 Color highlight, Color system, Color link, Color system_name,
 real_t system_scale, real_t link_scale):
  highlighted_font(highlighted_font),
  label_font(label_font),
  connected(connected),
  highlight(highlight),
  system(system),
  link(link),
  system_name(system_name),
  system_scale(system_scale),
  link_scale(link_scale)
{}

MapToolVisuals::MapToolVisuals(const MapToolVisuals &o):
  highlighted_font(o.highlighted_font),
  label_font(o.label_font),
  connected(o.connected),
  highlight(o.highlight),
  system(o.system),
  link(o.link),
  system_name(o.system_name),
  system_scale(o.system_scale),
  link_scale(o.link_scale)
{}

~MapToolVisuals::MapToolVisuals() {}

/* ------------------------------------------------------------------ */

Projector::Projector(Ref<Camera> camera, Ref<Viewport> viewport):
  view_size(viewport->get_size())
{
    real_t camera_scale = camera->get_size()/view_size.y;
    from2to3 = camera->get_transform();
    from2to3 = from2to3.scaled(Vector3(camera_scale,1,camera_scale));
    from2to3.origin = camera.translation;
    from3to2 = from2to3.affine_inverse();
    from3to2.origin += Vector3(view_size.x/2,view_size.y/2,0);
}

Vector3 Projector::project_position(const Vector2 &screen_point, real_t z_depth=0) const {
  Vector3 vec3 = Vector3(screen_point.x,view_size.y-screen_point.y,z_depth);
  return from2to3.xform(vec3);
}

Vector2 Projector::unproject_position(const Vector3 &world_point) {
  Vector3 screen = from3to2.xform(world_point);
  return Vector2(screen.x,view_size.y-screen.y);
}

/* ------------------------------------------------------------------ */

DrawLabel::DrawLabel(Ref<Font> font,Vector2 position,String label,Color color):
  font(font), position(position), label(label), color(color)
{}
DrawLabel(const DrawLabel &o):
  font(o.font), position(o.position), label(o.label), color(o.color)
{}
~DrawLabel() {}
void draw(const Node2D &canvas) const {
  canvas.draw_string(font,position,label,color);
}

/* ------------------------------------------------------------------ */

void MapTool::_register_methods() {
  register_method("_draw", &MapTool::_draw);
  register_method("set_data", &MapTool::set_data);
  register_method("set_visuals", &MapTool::set_visuals);
  register_method("at_location", &MapTool::at_location);
  register_method("update_multimeshes", &MapTool::update_multimeshes);
}

MapTool::MapTool():
  visuals(),
  mm_links(MultiMesh._new()),
  mm_systems(MultiMesh._new()),
  hash_systems(),
  positions(),
  link_reals(),
  system_reals()
{}

MapTool::~MapTool() {}

void MapTool::_init() {}

void MapTool::_draw() {
  for(auto &draw : draw_commands)
    draw.draw(*this);
}

void MapTool::set_visuals
(Ref<Font> highlighted_font, Ref<Font> label_font, Color connected,
 Color highlight, Color system, Color link, Color system_name,
 real_t system_scale, real_t link_scale) {
  visuals = new MapToolVisuals(highlighted_font,label_font,connected,highlight,system,
                               link,system_name,system_scale,link_scale)
}

void set_data(Array in_systems, Array in_links) {
  places.clear();
  links.clear();

  for(int i=0,n=in_systems.size(); i<n; i++) {
    SystemInfo system = SystemInfo(in_systems[i]);
    if(system.path.is_empty())
      continue; // ignore invalid systems
    if(hash_systems.find(system.path)==hash_systems.end()) {
      hash_systems[system.path]=system;
      data_systems.push_back(system);
    }
  }
 
  for(int i=0,n=in_links.size(); i<n; i++) {
    Array pair = in_links[i];
    NodePath from = pair[0];
    system_iter from_system = hash_systems.find(from);
    if(from_system==hash_systems.end())
      continue; // bad link
    
    NodePath to = pair[1];
    system_iter to_system = hash_systems.find(to);
    if(to_system==hash_systems.end())
      continue; // bad link

    Link link = { from_system.position, to_system.position };
    data_links.push_back(link);
  }
}

NodePath at_location(Vector3 where, float epsilon) const {
  Vector3 where0 = Vector3(where.x,0,where.y);
  float epsilon_squared = epsilon*epsilon;
  IntLocation iloc = { int(where.z)/10, -int(where.x)/10 };

  NodePath best;
  bool have_best=false;
  real_t best_distsq;

  NodePath best_rect;
  bool have_best_rect=false;
  real_t best_rect_distsq;
  
  position_range = positions.equal_range(iloc);
  for(position_iter p = position_range.first; p!=position_range.second; p++) {
    real_t distsq = p->second.position.distance_squared_to(where0);
    if(distsq<epsilon_squared and (not have_best or distsq<least_distsq)) {
      have_best=true;
      best=p->second.path;
      best_distsq=distsq;
    }

    if(not have_best and p->second.aabb.has_point(where0)) {
      Vector3 midpoint = p->second.aabb.position + p->second.aabb.size/2.0f;
      distsq = midpoint.distance_squared_to(where0);
      if(not have_best_rect or distsq<best_rect_distsq) {
        best_rect = p->second.path;
        best_rect_distsq = distsq;
        have_best_rect = true;
      }
    }
  }
  if(have_best)
    return best;
  if(have_best_rect)
    return best_rect;
  return NodePath();
}

void MapTool::update_multimeshes(Ref<Camera> zx_orthographic_camera, Ref<Viewport> viewport,
                                 Array system_path) {
  Projector proj(zx_orthographic_camera,viewport);

  real_t camera_size = camera->get_size();
  real_t system_scale = visuals->system_scale*camera_size;
  real_t link_scale = visuals->link_scale*camera_size;

  draw_commands.clear();

  Rect2 view_rect = Rect2(Vector2(-20,-20),proj.view_size+Vector2(20,20));
  real_t text_offset = fabs(proj.unproject_position(Vector3()).x -
                            proj.unproject_position(Vector3(system_scale,0,system_scale)).x);
  //  var selected_system = ''
	var child_names = game_state.systems.get_child_names()
	if selection and selection is simple_tree.SimpleNode:
		selected_system=selection.get_name()
	var selected_link = ['','']
	if selection is Dictionary:
		selected_link=selection['link_key']
	if game_state.systems.has_children():
		system_data.resize(16*len(child_names))
		var i: int=0
		var ascent: float = label_font.get_ascent()
		for system_id in child_names:
			var system = game_state.systems.get_child_with_name(system_id)
			assert(system is simple_tree.SimpleNode)
			var color: Color = system_color
			var font: Font = label_font
			if system_id==selected_system:
				color = highlight_color
				font = highlighted_font
			elif selected_link[0]==system_id or selected_link[1]==system_id:
				color = connected_color
				font = highlighted_font
			var pos2: Vector2 = proj.unproject_position(system.position)
			if view_rect.has_point(pos2):
				var text_size: Vector2 = label_font.get_string_size(system['display_name'])
				new_draw_commands.append(['draw_string',font,\
					pos2+Vector2(text_offset,ascent-text_size.y/2), \
					system['display_name'],system_name_color])
				
				# Bounding box of display name in 3d space
				var ul2 = pos2+Vector2(text_offset,ascent-text_size.y)
				var lr2 = pos2+Vector2(text_offset+text_size.x,ascent)
				var ul3 = proj.project_position(ul2)
				var lr3 = proj.project_position(lr2)
				var aabb = AABB(Vector3(min(ul3.x,lr3.x),-20,min(ul3.z,lr3.z)),
					Vector3(abs(ul3.x-lr3.x),40,abs(ul3.z-lr3.z)))
				name_bounds.append([aabb,system.get_path(),(ul3+lr3)/2])
			system_data[i +  0] = system_scale
			system_data[i +  1] = 0.0
			system_data[i +  2] = 0.0
			system_data[i +  3] = system.position.x
			system_data[i +  4] = 0.0
			system_data[i +  5] = 1.0
			system_data[i +  6] = 0.0
			system_data[i +  7] = 0.0
			system_data[i +  8] = 0.0
			system_data[i +  9] = 0.0
			system_data[i + 10] = system_scale
			system_data[i + 11] = system.position.z
			system_data[i + 12] = color.r
			system_data[i + 13] = color.g
			system_data[i + 14] = color.b
			system_data[i + 15] = color.a
			i+=16
		system_multimesh.instance_count=len(child_names)
		system_multimesh.visible_instance_count=-1
		system_multimesh.set_as_bulk_array(system_data)
	
	var links: Dictionary = game_state.universe.links
	$View/Port/Links.visible=not not links
	if links:
		link_data.resize(16*len(links))
		var i: int = 0
		for link_key in links:
			var link = game_state.universe.link_sin_cos(link_key)
			
			var pos: Vector3 = link['position']
			var link_sin: float = link['sin']
			var link_cos: float = link['cos']
			var link_len: float = link['distance']
			var color: Color = link_color
			if link_key==selected_link:
				color=highlight_color
			elif link_key[0]==selected_system or link_key[1]==selected_system:
				color=connected_color
			link_data[i +  0] = link_cos*link_len
			link_data[i +  1] = 0.0
			link_data[i +  2] = link_sin*link_scale
			link_data[i +  3] = pos.x
			link_data[i +  4] = 0.0
			link_data[i +  5] = 1.0
			link_data[i +  6] = 0.0
			link_data[i +  7] = 0.0
			link_data[i +  8] = -link_sin*link_len
			link_data[i +  9] = 0.0
			link_data[i + 10] = link_cos*link_scale
			link_data[i + 11] = pos.z
			link_data[i + 12] = color.r
			link_data[i + 13] = color.g
			link_data[i + 14] = color.b
			link_data[i + 15] = color.a
			i+=16
		link_multimesh.instance_count=len(links)
		link_multimesh.visible_instance_count=-1
		link_multimesh.set_as_bulk_array(link_data)
	game_state.universe.unlock()

	draw_mutex.lock()
	draw_commands=new_draw_commands
	draw_mutex.unlock()
	$View/Port/Annotations.update()

	time_to_draw=false
}
