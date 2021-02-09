#include "Starmap.hpp"
#include <MultiMeshInstance.hpp>
#include <assert.h>

using namespace godot;
using namespace std;

template<class T>
String str(const T &t) {
  return static_cast<String>(Variant(t));
}

template<class T, class POOL>
void copy_pool(const POOL &from_pool, POOL &to_pool) {
  int size = from_pool.size();
  to_pool.resize(size);
  typename POOL::Read read_from = from_pool.read();
  typename POOL::Write write_to = to_pool.write();
  const T *from = read_from.ptr();
  T *to = write_to.ptr();
  for(int i=0; i<size; i++)
    to[i] = from[i];
}

template<class T, class POOL>
void copy_pool(const POOL &from_pool, unordered_set<T> &to_set) {
  int size = from_pool.size();
  typename POOL::Read read_from = from_pool.read();
  const T *from = read_from.ptr();
  for(int i=0; i<size; i++)
    to_set.insert(from[i]);
}

template<class T, class POOL>
void copy_pool(const POOL &from_pool, POOL &to_pool, unordered_set<T> &to_set) {
  int size = from_pool.size();
  to_pool.resize(size);
  
  typename POOL::Read read_from = from_pool.read();
  const T *from = read_from.ptr();

  typename POOL::Write write_to = to_pool.write();
  T *to = write_to.ptr();

  to_set.clear();
  for(int i=0; i<size; i++)
    to_set.insert(to[i] = from[i]);
}

/* ------------------------------------------------------------------ */

LinkVisuals::LinkVisuals(const PoolIntArray &vis_links, bool bidirectional,
                         Color color, real_t link_scale):
  link_color(color), link_scale(link_scale), links()
{
  int size = vis_links.size(), nlinks = size/2;
  PoolIntArray::Read links_read = vis_links.read();
  const int *links_ptr = links_read.ptr();

  for(int i=0;i<nlinks;i++) {
    links.insert(pair<int,int>(links_ptr[i+0],links_ptr[i+1]));
    if(bidirectional)
      links.insert(pair<int,int>(links_ptr[i+1],links_ptr[i+0]));
  }
}

/* ------------------------------------------------------------------ */

SystemVisuals::SystemVisuals(const PoolIntArray &systems, Color system_color,
                             Color label_color, Ref<Font> label_font, real_t system_scale):
  system_color(system_color),
  label_color(label_color),
  system_scale(system_scale),
  font(label_font), systems()
{
  assert(font.is_valid());
  PoolIntArray::Read read_from = systems.read();
  const int *from = read_from.ptr();
  for(int i=0, n=systems.size(); i<n; i++) {
    this->systems.insert(from[i]);
  }
}

/* ------------------------------------------------------------------ */

Projector::Projector(const Camera &camera,const Viewport &viewport,Vector2 rect_global_position):
  view_size(viewport.get_size()),
  rect_global_position(rect_global_position)
{
  float camera_scale = camera.get_size()/view_size.y;
  from2to3 = camera.get_transform();
  from2to3 = from2to3.scaled(Vector3(camera_scale,1,camera_scale));
  from2to3.origin = camera.get_translation();
  from3to2 = from2to3.affine_inverse();
  Vector2 view_offset = view_size/2.0;
  from3to2.origin += Vector3(view_offset.x,view_offset.y,0);
}

Projector::~Projector() {}

Vector3 Projector::project_position(const Vector2 &view_point,float z_depth) const {
  Vector2 centered = view_point-view_size/2;
  Vector3 vec3 = Vector3(centered.x,-centered.y,z_depth);
  return from2to3.xform(vec3);
}

Vector2 Projector::unproject_position(const Vector3 &world_point) const {
  Vector3 view_pos = from3to2.xform(world_point);
  return Vector2(view_pos.x,view_size.y-view_pos.y);
}

/* ------------------------------------------------------------------ */

Starmap::Starmap() {}
Starmap::~Starmap() {}

void Starmap::_init() {
  max_system_scale = default_system_scale;
  max_link_scale = default_link_scale;
  show_links = true;
  
  circle_mesh = make_circle_mesh(1.0f,32,Vector3(0.0f,0.0f,0.0f));
  if(not circle_mesh.is_valid())
    Godot::print("could not make circle mesh");
  circle_multimesh = Ref<MultiMesh>(MultiMesh::_new());
  circle_multimesh->set_mesh(circle_mesh);
  circle_multimesh->set_transform_format(MultiMesh::TRANSFORM_3D);
  circle_multimesh->set_custom_data_format(MultiMesh::CUSTOM_DATA_FLOAT);

  line_mesh = make_box_mesh(Vector3(-0.5f,-0.5f,-0.5f),0.5f,0.5f,2,2);
  if(not line_mesh.is_valid())
    Godot::print("could not make line mesh");
  line_multimesh = Ref<MultiMesh>(MultiMesh::_new());
  line_multimesh->set_mesh(line_mesh);
  line_multimesh->set_transform_format(MultiMesh::TRANSFORM_3D);
  line_multimesh->set_custom_data_format(MultiMesh::CUSTOM_DATA_FLOAT);

  MultiMeshInstance *circle_instance = MultiMeshInstance::_new();
  circle_instance->set_multimesh(circle_multimesh);
  add_child(circle_instance,false);

  MultiMeshInstance *line_instance = MultiMeshInstance::_new();
  line_instance->set_multimesh(line_multimesh);
  add_child(line_instance,false);
  line_instance->set_translation(Vector3(0,-0.5,0));
}

void Starmap::_register_methods() { // FIXME: UPDATE THIS
  register_method("set_show_links", &Starmap::set_show_links);
  register_method("get_show_links", &Starmap::get_show_links);
  register_method("add_extra_line", &Starmap::add_extra_line);
  register_method("clear_extra_lines", &Starmap::clear_extra_lines);
  register_method("set_camera_path", &Starmap::set_camera_path);
  register_method("set_line_material", &Starmap::set_line_material);
  register_method("set_circle_material", &Starmap::set_circle_material);
  register_method("set_max_scale", &Starmap::set_max_scale);
  register_method("set_systems", &Starmap::set_systems);
  register_method("set_default_visuals", &Starmap::set_default_visuals);
  register_method("add_system_visuals", &Starmap::add_system_visuals);
  register_method("add_astral_gate_visuals", &Starmap::add_astral_gate_visuals);
  register_method("add_link_visuals", &Starmap::add_link_visuals);
  register_method("add_adjacent_link_visuals", &Starmap::add_adjacent_link_visuals);
  register_method("add_connecting_link_visuals", &Starmap::add_connecting_link_visuals);
  register_method("clear_visuals", &Starmap::clear_visuals);
  register_method("system_at_location", &Starmap::system_at_location);
  register_method("_draw", &Starmap::_draw);
}

void Starmap::set_show_links(bool show) {
  show_links = show;
}

bool Starmap::get_show_links() const {
  return show_links;
}

void Starmap::add_extra_line(Vector3 from, Vector3 to, Color link_color, real_t link_scale) {
  extra_lines.push_back(ExtraLine(from,to,link_color,link_scale));
}

void Starmap::clear_extra_lines() {
  extra_lines.clear();
}

void Starmap::set_camera_path(NodePath path) {
  camera_path = path;
}

void Starmap::set_line_material(Ref<Material> material) {
  if(not material.is_valid())
    Godot::print("received null line material");
  line_mesh->surface_set_material(0,material);
}

void Starmap::set_circle_material(Ref<Material> material) {
  if(not material.is_valid())
    Godot::print("received null circle material");
  circle_mesh->surface_set_material(0,material);
}

void Starmap::set_max_scale(real_t new_system_scale, real_t new_link_scale,
                            Vector2 new_rect_global_position) {
  max_system_scale = new_system_scale;
  max_link_scale = new_link_scale;
  rect_global_position = new_rect_global_position;
  update();
}
void Starmap::set_systems(PoolStringArray new_system_names, PoolVector3Array new_system_locations,
                          PoolIntArray new_links, PoolIntArray new_astral_gates) {

  routes.clear();
  system_links.clear();

  {
    int nlinks = new_links.size()/2;
    link_list.resize(nlinks*2);
    PoolIntArray::Read links_read = new_links.read();
    const int *links_in = links_read.ptr();
    PoolIntArray::Write links_write = link_list.write();
    int *links_out = links_write.ptr();
    for(int i=0;i<nlinks;i++) {
      links_out[i*2+0] = links_in[i*2+0];
      links_out[i*2+1] = links_in[i*2+1];
      if(links_in[i*2+0]!=links_in[i*2+1]) {
        routes.emplace(links_in[i*2+0],links_in[i*2+1]);
        routes.emplace(links_in[i*2+1],links_in[i*2+0]);
        system_links.emplace(links_in[i*2+0],links_in[i*2+1]);
        system_links.emplace(links_in[i*2+1],links_in[i*2+0]);
      }
    }
  }

  {
    int ngates = new_astral_gates.size();
    astral_gate_list.resize(ngates);
    gate_set.clear();
    PoolIntArray::Read gate_read = new_astral_gates.read();
    const int *gates_in = gate_read.ptr();
    PoolIntArray::Write gate_write = astral_gate_list.write();
    int *gates_out = gate_write.ptr();

    for(int i=0;i<ngates;i++) {
      gate_set.insert(gates_in[i]);
      gates_out[i] = gates_in[i];
      for(int j=0;j<i;j++)
        routes.emplace(gates_in[i],gates_in[j]);
      for(int j=i+1;j<ngates;j++)
        routes.emplace(gates_in[i],gates_in[j]);
    }
  }
  

  system_map.clear();
  {
    int nloc = new_system_locations.size();

    // Erase all labels because their positions are now wrong, which
    // will give false collision information.
    label_map.clear();
    label_map.reserve(10+nloc/2);

    system_locations.resize(nloc);
    PoolVector3Array::Read read_system_locations = new_system_locations.read();
    const Vector3 *loc_in = read_system_locations.ptr();
    PoolVector3Array::Write write_system_locations = system_locations.write();
    Vector3 *loc_out = write_system_locations.ptr();

    system_names.resize(nloc);
    PoolStringArray::Read read_system_names = new_system_names.read();
    const String *name_in = read_system_names.ptr();
    PoolStringArray::Write write_system_names = system_names.write();
    String *name_out = write_system_names.ptr();

    for(int i=0;i<nloc;i++) {
      loc_out[i] = loc_in[i];
      loc_out[i].y = 0;
      system_map.emplace(loc_in[i],i);
      name_out[i] = name_in[i];
    }
  }
  
  update();
}

void Starmap::set_default_visuals(Color system_color, Color link_color, Color label_color,
                                  Ref<Font> label_font, real_t system_scale, real_t link_scale) {
  assert(label_font.is_valid());
  default_system_visuals = shared_ptr<SystemVisuals>(new SystemVisuals(system_color, label_color, label_font, system_scale));
  default_link_visuals = shared_ptr<LinkVisuals>(new LinkVisuals(link_color, link_scale));
  update();
}

void Starmap::add_system_visuals(PoolIntArray systems, Color system_color, Color label_color,
                                 Ref<Font> label_font, real_t system_scale) {
  system_visuals.emplace_back(new SystemVisuals(systems, system_color, label_color, label_font,system_scale));
  update();
}

void Starmap::add_astral_gate_visuals(Color system_color, Color label_color,
                                      Ref<Font> label_font, real_t system_scale) {
  system_visuals.emplace_back(new SystemVisuals(astral_gate_list, system_color, label_color, label_font, system_scale));
  update();
}

void Starmap::add_link_visuals(PoolIntArray links, Color link_color, real_t link_scale) {
  link_visuals.emplace_back(new LinkVisuals(links, true, link_color, link_scale));
  update();
}

void Starmap::add_connecting_link_visuals(PoolIntArray systems, Color link_color, real_t link_scale) {
  PoolIntArray::Read read_systems = systems.read();
  const int *sys = read_systems.ptr();
  int size = systems.size();
  unordered_set<pair<int,int>,HashIntPair> links;
  
  for(int i=0,n=systems.size();i<n-1;i++) {
    system_links_range range = system_links.equal_range(sys[i]);
    for(system_links_iter it=range.first;it!=range.second;it++)
      if(it->second==sys[i+1]) {
        links.emplace(sys[i],sys[i+1]);
        break;
      }
  }
  link_visuals.emplace_back(new LinkVisuals(links, link_color, link_scale));
  update();
}

void Starmap::add_adjacent_link_visuals(PoolIntArray systems, Color link_color, real_t link_scale) {
  PoolIntArray::Read read_systems = systems.read();
  const int *sys = read_systems.ptr();
  int size = systems.size();
  unordered_set<pair<int,int>,HashIntPair> links;
  
  for(int i=0,n=systems.size();i<n;i++) {
    system_links_range range = system_links.equal_range(sys[i]);
    for(system_links_iter it=range.first;it!=range.second;it++) {
      links.emplace(sys[i],it->second);
      links.emplace(it->second,sys[i]);
    }
  }
  link_visuals.emplace_back(new LinkVisuals(links, link_color, link_scale));
  update();
}

void Starmap::clear_visuals() {
  system_visuals.clear();
  link_visuals.clear();
  update();
}

int Starmap::system_at_location(Vector3 wherein, real_t epsilon) const {
  Vector3 where(wherein.x,0,wherein.z);
  Vector3 vespilon(epsilon,epsilon,epsilon);
  IntLocation start(where-vespilon);
  IntLocation end(where+vespilon);
  PoolVector3Array::Read read_system_locations = system_locations.read();
  const Vector3 *locs = read_system_locations.ptr();
  real_t epsilonsq = epsilon*epsilon;

  real_t best_distsq=9e9;
  int best_index = -1;

  // Favor matching a system's point:
  
  for(int y=start.y; y<=end.y; y++)
    for(int x=start.x; x<=end.x; x++) {
      system_map_crange range = system_map.equal_range(IntLocation(x,y));
      for(system_map_citer it = range.first; it!=range.second; it++) {
        real_t distsq = where.distance_squared_to(locs[it->second]);
        if(distsq<epsilonsq and (distsq<best_distsq or best_index<0)) {
          best_index = it->second;
          best_distsq = distsq;
        }
      }
    }
  
  if(best_index>=0)
    return best_index;

  // If no points match, search the system name labels:
  
  for(int y=start.y; y<=end.y; y++)
    for(int x=start.x; x<=end.x; x++) {
      label_map_crange range = label_map.equal_range(IntLocation(x,y));
      for(label_map_citer it = range.first; it!=range.second; it++) {
        if(it->second.aabb.grow(epsilon).has_point(where)) {
          Vector3 center = it->second.aabb.position + it->second.aabb.size/2;
          center.y = 0;
          real_t distsq = where.distance_squared_to(center);
          if(best_index<0 or distsq<best_distsq) {
            best_index = it->second.system;
            best_distsq = distsq;
          }
        }
      }
    }
  if(best_index>=0)
    return best_index;

  return -1;
}

void Starmap::_draw() {
  Viewport *viewport = get_viewport();
  if(not viewport) {
    Godot::print("no viewport");
    return;
  }

  Node *camera_node = get_node_or_null(camera_path);
  if(not camera_node) {
    Godot::print("No camera found in Starmap::_draw()");
    return;
  } else if(not camera_node->is_class("Camera")) {
    Godot::print("Camera is not Camera class in Starmap::_draw()");
    return;
  }
  Camera *zx_orthographic_camera = static_cast<Camera*>(camera_node);
  
  Projector proj(*zx_orthographic_camera,*viewport,rect_global_position);

  real_t camera_size = zx_orthographic_camera->get_size();

  Rect2 view_rect = Rect2(Vector2(-20,-20),proj.view_size+Vector2(20,20));
  real_t padding = max(max_system_scale,max_link_scale);
  Vector3 vadding(padding,padding,padding);
  int system_count = system_map.size();
  int link_count = link_list.size()/2;
  int extra_count = extra_lines.size();
  int line_count = extra_count + int(show_links)*link_count;

  PoolVector3Array::Read system_locations_read = system_locations.read();
  const Vector3 *system_locations_ptr = system_locations_read.ptr();
  
  label_map.clear();
  
  if(system_count) {
    circle_data.resize(system_count*16);
    PoolStringArray::Read system_names_read = system_names.read();
    const String *system_name_ptr = system_names_read.ptr();
    PoolRealArray::Write circle_data_write = circle_data.write();
    real_t *circle_data_ptr = circle_data_write.ptr();

    memset(circle_data_ptr,0,sizeof(real_t)*16*system_count);
    
    int i=0;
    for(int n=0;n<system_count;n++) {
      Vector3 pos3 = system_locations_ptr[n];
      Vector2 min_view = proj.unproject_position(pos3-vadding);
      Vector2 max_view = proj.unproject_position(pos3+vadding);
      Rect2 padded_link_rect(min_view,max_view-min_view);
      if(not view_rect.intersects(padded_link_rect))
        continue; // system is outside view by more than padding

      // How do we color and label this?
      bool found = false;
      Color system_color;
      Color label_color;
      real_t system_scale = max_system_scale;
      Ref<Font> label_font;
      for(auto &visual : system_visuals)
        if(visual->has(n)) {
          found=true;
          label_font = visual->get_font();
          label_color = visual->label_color;
          system_color = visual->system_color;
          system_scale = min(system_scale,visual->system_scale);
        }
      if(not found) {
        label_font = default_system_visuals->get_font();
        label_color = default_system_visuals->label_color;
        system_color = default_system_visuals->system_color;
        system_scale = default_system_visuals->system_scale;
      }
      system_scale *= camera_size;

      if(gate_set.find(n)!=gate_set.end()) {
        system_color.a = 0.1;
        system_scale *= 1.25;
      }
      
      real_t ascent = label_font->get_ascent();
      Vector2 pos2 = proj.unproject_position(pos3);
      Vector2 text_size = label_font->get_string_size(system_name_ptr[n]);
      real_t text_offset = fabs(proj.unproject_position(Vector3()).x -
                                proj.unproject_position(Vector3(system_scale,0,system_scale)).x);
      Vector2 text_pos = pos2+Vector2(text_offset,ascent-text_size.y/2);

      draw_string(label_font,text_pos,system_name_ptr[n],label_color);

      // Bounding box of display name in 3d space
      Vector2 ul2 = pos2+Vector2(text_offset,ascent-text_size.y);
      Vector2 lr2 = pos2+Vector2(text_offset+text_size.x,ascent);
      Vector3 ul3 = proj.project_position(ul2);
      Vector3 lr3 = proj.project_position(lr2);
      Vector3 min3 = Vector3(min(ul3.x,lr3.x),min(ul3.y,lr3.y),min(ul3.z,lr3.z));
      min3.y = -100;
      Vector3 max3 = Vector3(max(ul3.x,lr3.x),max(ul3.y,lr3.y),max(ul3.z,lr3.z));
      max3.y = 100;
      IntLocation imin3 = min3;
      IntLocation imax3 = max3;
      
      for(int y=imin3.y;y<=imax3.y;y++)
        for(int x=imin3.x;x<=imax3.x;x++)
          label_map.emplace(IntLocation(x,y),DrawLabel(AABB(min3,max3-min3),n));
      
      circle_data_ptr[i +  0] = system_scale;
      circle_data_ptr[i +  1] = 0.0;
      circle_data_ptr[i +  2] = 0.0;
      circle_data_ptr[i +  3] = pos3.x;
      circle_data_ptr[i +  4] = 0.0;
      circle_data_ptr[i +  5] = 1.0;
      circle_data_ptr[i +  6] = 0.0;
      circle_data_ptr[i +  7] = 0.0;
      circle_data_ptr[i +  8] = 0.0;
      circle_data_ptr[i +  9] = 0.0;
      circle_data_ptr[i + 10] = system_scale;
      circle_data_ptr[i + 11] = pos3.z;
      circle_data_ptr[i + 12] = system_color.r;
      circle_data_ptr[i + 13] = system_color.g;
      circle_data_ptr[i + 14] = system_color.b;
      circle_data_ptr[i + 15] = system_color.a;
      i+=16;
    }// end system loop
    circle_multimesh->set_instance_count(system_count);
    circle_multimesh->set_visible_instance_count(i/16);
    circle_multimesh->set_as_bulk_array(circle_data);
  } else {
    // There are no systems
    circle_multimesh->set_visible_instance_count(0);
  } // end if(have systems)
  
  if(line_count) {
    line_data.resize(line_count*16);
    PoolRealArray::Write line_data_write = line_data.write();
    real_t *line_data_ptr = line_data_write.ptr();
    PoolIntArray::Read link_list_read = link_list.read();
    const int *link_list_ptr = link_list_read.ptr();

    memset(line_data_ptr,0,sizeof(real_t)*16*line_count);

    int extra_begin = show_links ? link_count : 0;
    int i = 0;
    for(int n=0;n<line_count;n++) {
      Color link_color;
      real_t link_scale;
      Vector3 sys1_pos, sys2_pos;
      if(n>=extra_begin) {
        link_color = extra_lines[n-extra_begin].color;
        link_scale = extra_lines[n-extra_begin].scale;
        sys1_pos = extra_lines[n-extra_begin].from;
        sys2_pos = extra_lines[n-extra_begin].to;
      } else {
        int sys1_index = link_list_ptr[n*2+0];
        if(sys1_index<0 or sys1_index>=system_count) {
          Godot::print(String("Link with out-of-bounds system index ")+
                       static_cast<String>(Variant(sys1_index)));
          continue;
        }
        sys1_pos = system_locations_ptr[sys1_index];
        
        int sys2_index = link_list_ptr[n*2+1];
        if(sys2_index<0 or sys2_index>=system_count) {
          Godot::print(String("Link with out-of-bounds system index ")+
                       static_cast<String>(Variant(sys2_index)));
          continue;
        }
        sys2_pos = system_locations_ptr[sys2_index];
        
        pair<int,int> indices = pair<int,int>(sys1_index,sys2_index);
        
        Vector3 min_pos = Vector3(min(sys1_pos.x,sys2_pos.x),min(sys1_pos.y,sys2_pos.y),
                                  min(sys1_pos.z,sys2_pos.z)) - vadding;
        Vector3 max_pos = Vector3(max(sys1_pos.x,sys2_pos.x),max(sys1_pos.y,sys2_pos.y),
                                  max(sys1_pos.z,sys2_pos.z)) + vadding;
        
        Vector2 min_view = proj.unproject_position(min_pos);
        Vector2 max_view = proj.unproject_position(max_pos);
        
        Rect2 padded_link_rect(min_view,max_view-min_view);
        // if(not view_rect.intersects(padded_link_rect))
        //   // Link is definitely off-screen;
        //   continue;

        // How do we color and label this?
        link_scale = max_link_scale;
        bool found = false;
        for(auto &visual : link_visuals)
          if(visual->has(indices)) {
            found=true;
            link_color = visual->link_color;
            link_scale = min(link_scale,visual->link_scale);
          }
        if(not found) {
          link_color = default_link_visuals->link_color;
          link_scale = default_link_visuals->link_scale;
        }
      }

      link_scale *= camera_size;
      Vector3 pos = (sys1_pos+sys2_pos)/2.0f;
      Vector3 diff = sys2_pos-sys1_pos;
      real_t link_len = diff.length();
      real_t link_sin = -diff.z/link_len;
      real_t link_cos = diff.x/link_len;

      line_data_ptr[i +  0] = link_cos*link_len;
      line_data_ptr[i +  1] = 0.0;
      line_data_ptr[i +  2] = link_sin*link_scale;
      line_data_ptr[i +  3] = pos.x;
      line_data_ptr[i +  4] = 0.0;
      line_data_ptr[i +  5] = 1.0;
      line_data_ptr[i +  6] = 0.0;
      line_data_ptr[i +  7] = 0.0;
      line_data_ptr[i +  8] = -link_sin*link_len;
      line_data_ptr[i +  9] = 0.0;
      line_data_ptr[i + 10] = link_cos*link_scale;
      line_data_ptr[i + 11] = pos.z;
      line_data_ptr[i + 12] = link_color.r;
      line_data_ptr[i + 13] = link_color.g;
      line_data_ptr[i + 14] = link_color.b;
      line_data_ptr[i + 15] = link_color.a;
      i+=16;
    }
    line_multimesh->set_instance_count(line_count);
    line_multimesh->set_visible_instance_count(i/16);
    line_multimesh->set_as_bulk_array(line_data);
  } else {
    // There are no visible lines.
    line_multimesh->set_visible_instance_count(0);
  }
}

Ref<ArrayMesh> Starmap::tri_to_mesh(const PoolVector3Array &vertices,
                                    const PoolVector2Array &uv) {
  Ref<ArrayMesh> mesh = Ref<ArrayMesh>(ArrayMesh::_new());
  Array arrays = Array();
  arrays.resize(ArrayMesh::ARRAY_MAX);
  arrays[ArrayMesh::ARRAY_VERTEX] = vertices;
  arrays[ArrayMesh::ARRAY_TEX_UV] = uv;
  mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
  return mesh;
}

Ref<ArrayMesh> Starmap::make_box_mesh(const Vector3 &from, real_t x_step,
                                      real_t z_step, int nx, int nz) {
  PoolVector3Array vertex_data;
  PoolVector2Array uv_data;
  vertex_data.resize(nx*nz*6);
  uv_data.resize(nx*nz*6);
  {
    PoolVector3Array::Write write_vertices = vertex_data.write();
    PoolVector2Array::Write write_uv = uv_data.write();
    Vector3 *vertices = write_vertices.ptr();
    Vector2 *uv = write_uv.ptr();
    
    int i = 0;
    for(int zi=0;zi<nz;zi++)
      for(int xi=0;xi<nx;xi++) {
        Vector3 p00 = from+Vector3(xi*x_step,0,zi*z_step);
        Vector3 p11 = from+Vector3((xi+1)*x_step,0,(zi+1)*z_step);
        Vector3 p01 = Vector3(p00.x,from.y,p11.z);
        Vector3 p10 = Vector3(p11.x,from.y,p00.z);
        Vector2 u00 = Vector2(zi/float(nz),(nx-xi)/float(nx));
        Vector2 u11 = Vector2((zi+1)/float(nz),(nx-xi-1)/float(nx));
        Vector2 u01 = Vector2(u11.x,u00.y);
        Vector2 u10 = Vector2(u00.x,u11.y);
        vertices[i + 0] = p00;
        uv      [i + 0] = u00;
        vertices[i + 1] = p11;
        uv      [i + 1] = u11;
        vertices[i + 2] = p01;
        uv      [i + 2] = u01;
        vertices[i + 3] = p00;
        uv      [i + 3] = u00;
        vertices[i + 4] = p10;
        uv      [i + 4] = u10;
        vertices[i + 5] = p11;
        uv      [i + 5] = u11;
        i+=6;
      }
  }

  return tri_to_mesh(vertex_data, uv_data);
}

Ref<ArrayMesh> Starmap::make_circle_mesh(real_t radius,int count,Vector3 center) {
  PoolVector3Array vertex_data;
  PoolVector2Array uv_data;
  vertex_data.resize(count*3);
  uv_data.resize(count*3);
  PoolVector3Array::Write write_vertices = vertex_data.write();
  PoolVector2Array::Write write_uv = uv_data.write();
  Vector3 *vertices = write_vertices.ptr();
  Vector2 *uv = write_uv.ptr();

  real_t angle = pi*2/count;
  Vector3 prior = center + radius*Vector3(cos((count-1)*angle),0,sin((count-1)*angle));
  
  for(int i=0;i<count;i++) {
    Vector3 mine = center + radius*Vector3(cos(i*angle),0,sin(i*angle));
    vertices[i*3 + 0] = center;
    uv      [i*3 + 0] = Vector2(0.5,i/float(count));
    vertices[i*3 + 1] = prior;
    uv      [i*3 + 1] = Vector2(1.0,i/float(count));
    vertices[i*3 + 2] = mine;
    uv      [i*3 + 2] = Vector2(1.0,(i+1)/float(count));
    prior=mine;
  }
  return tri_to_mesh(vertex_data,uv_data);
}
