#ifndef STARMAP_H
#define STARMAP_H

#include <Godot.hpp>
#include <Camera.hpp>
#include <MultiMesh.hpp>
#include <Viewport.hpp>
#include <Shader.hpp>
#include <Ref.hpp>
#include <PoolArrays.hpp>
#include <Node2D.hpp>
#include <Material.hpp>
#include <ArrayMesh.hpp>
#include <Font.hpp>

#include <memory>
#include <map>
#include <unordered_set>
#include <unordered_map>
#include <algorithm>
#include <string>
#include <vector>

namespace godot {

  const int int_scale = 10; // scaling factor from Vector3 to IntLocation
  const real_t default_system_scale = 0.01f;
  const real_t default_link_scale = 0.005f;
  const real_t pi = 3.141592653589793f;

  
  struct IntLocation {
    int x, y;
    IntLocation(const Vector3 &v):
      x(v.z/int_scale), y(v.x/int_scale)
    {}
    IntLocation(int x,int y):
      x(x),y(y)
    {}
    IntLocation():
      x(0), y(0)
    {}
    inline Vector3 operator() () const {
      return Vector3(-y*int_scale, 0, x*int_scale);
    }
    inline bool operator == (const IntLocation &o) const {
      return x==o.x and y==o.y;
    }
  };

  struct HashIntPair {
    struct std::hash<int> int_hash;
    HashIntPair(): int_hash() {}
    ~HashIntPair() {}
    size_t operator() (const IntLocation &i) const {
      return int_hash(i.x)^int_hash(i.y);
    }
    size_t operator() (const std::pair<int,int> &i) const {
      return int_hash(i.first)^int_hash(i.second);
    }
  };
  
  class Projector {
  public:
    Projector(const Camera &,const Viewport &,Vector2 rect_global_position);
    ~Projector();
    Vector3 project_position(const Vector2 &screen_position, real_t z=0) const;
    Vector2 unproject_position(const Vector3 &world_point) const;
  public:
    const Vector2 view_size;
    const Vector2 rect_global_position;
  private:
    Transform from2to3, from3to2;
  };

  struct DrawLabel {
    DrawLabel(const AABB &aabb, int system): aabb(aabb), system(system) {}
    DrawLabel(const DrawLabel &o): aabb(o.aabb), system(o.system) {}
    ~DrawLabel() {}

    const AABB aabb;
    const int system;
  };


  class LinkVisuals {
  public:
    LinkVisuals(const PoolIntArray &links, bool bidirectional,
                Color link_color, real_t link_scale);
    LinkVisuals(Color link_color, real_t link_scale):
      link_color(link_color),
      link_scale(link_scale),
      links()
    {}
    LinkVisuals(const std::unordered_set<std::pair<int,int>,HashIntPair> &links,
                Color link_color, real_t link_scale):
      link_color(link_color),
      link_scale(link_scale),
      links(links)
    {}
    explicit LinkVisuals(const LinkVisuals &other):
      link_color(other.link_color),
      link_scale(other.link_scale),
      links(other.links)
    {}
    ~LinkVisuals() {}
    inline bool has(std::pair<int,int> link) const {
      return links.find(link)!=links.end();
    }
    const Color link_color;
    const real_t link_scale;
  private:
    std::unordered_set<std::pair<int,int>,HashIntPair> links;
  };
  
 
  class SystemVisuals {
  public:
    SystemVisuals(const PoolIntArray &systems, Color system_color,
                  Color label_color, Ref<Font> label_font, real_t system_scale);
    
    SystemVisuals(Color system_color, Color label_color,
                  Ref<Font> label_font, real_t system_scale):
      system_color(system_color),
      label_color(label_color),
      system_scale(system_scale),
      font(label_font),
      systems()
    {}
    explicit SystemVisuals(const SystemVisuals &v):
      system_color(v.system_color),
      label_color(v.label_color),
      system_scale(v.system_scale),
      font(v.font),
      systems(v.systems)
    {}
    ~SystemVisuals() {}
    inline bool has(int system) const {
      return systems.find(system)!=systems.end();
    }
    inline Ref<Font> get_font() const {
      return font;
    }
    const Color system_color, label_color;
    const real_t system_scale;
  private:
    Ref<Font> font;
    std::unordered_set<int> systems;
  };

  
  class Starmap: public Node2D {
    GODOT_CLASS(Starmap, Node2D)
    
  public:
    Starmap();
    ~Starmap();
    void _init();
    static void _register_methods();

    // NOTE: GDScript must call these five functions before displaying
    // the GDNative Starmap:
    void set_camera_path(NodePath path);
    void set_line_material(Ref<Material> shader);
    void set_circle_material(Ref<Material> shader);
    void set_max_scale(real_t system_scale, real_t link_scale, Vector2 rect_global_position);
    void set_systems(PoolStringArray system_names, PoolVector3Array system_locations,
                     PoolIntArray links, PoolIntArray astral_gates);
    void set_default_visuals(Color system_color, Color link_color, Color label_color,
                             Ref<Font> label_font, real_t system_scale, real_t link_scale);

    // Additional system and link coloring:
    void add_system_visuals(PoolIntArray systems, Color system_color, Color label_color,
                            Ref<Font> label_font, real_t system_scale);
    void add_astral_gate_visuals(Color system_color, Color label_color,
                            Ref<Font> label_font, real_t system_scale);

    void add_link_visuals(PoolIntArray links, Color link_color, real_t link_scale);
    void add_adjacent_link_visuals(PoolIntArray systems, Color link_color, real_t link_scale);
    void add_connecting_link_visuals(PoolIntArray systems, Color link_color, real_t link_scale);
    // FIXME: Need to display astral gate jumps along a route.
    // void add_gate_jump_visuals(PoolIntArray jumps, color link_color, real_t link_scale);
    
    void clear_visuals();

    // What system is at this location? -1 = none
    int system_at_location(Vector3 where, real_t epsilon) const;

    // Update multimeshes, redraw labels:
    void _draw();
    
    // FIXME: IMPLEMENT THIS:
    // List of systems along the route.
    // PoolIntArray calculate_route(int from, int to) const;

  private:
    static Ref<ArrayMesh> make_circle_mesh(real_t radius,int count,Vector3 center);
    static Ref<ArrayMesh> make_box_mesh(const Vector3 &from, real_t x_step,
                                        real_t z_step, int nx, int nz);
    static Ref<ArrayMesh> tri_to_mesh(const PoolVector3Array &vertices,const PoolVector2Array &uv);
  private:
    real_t max_system_scale, max_link_scale;
    Vector2 rect_global_position;
    NodePath camera_path;
    
    PoolStringArray system_names;
    PoolVector3Array system_locations;
    PoolIntArray link_list, astral_gate_list;

    std::unordered_set<int> gate_set;
    
    std::unordered_multimap<IntLocation,int,HashIntPair> system_map;
    typedef std::unordered_multimap<IntLocation,int,HashIntPair>::iterator system_map_iter;
    typedef std::unordered_multimap<IntLocation,int,HashIntPair>::const_iterator system_map_citer;
    typedef std::pair<system_map_iter,system_map_iter> system_map_range;
    typedef std::pair<system_map_citer,system_map_citer> system_map_crange;

    std::unordered_multimap<int,int> system_links;
    typedef std::unordered_multimap<int,int>::iterator system_links_iter;
    typedef std::pair<system_links_iter,system_links_iter> system_links_range;

    std::multimap<int,int> routes;

    std::shared_ptr<SystemVisuals> default_system_visuals;
    std::shared_ptr<LinkVisuals> default_link_visuals;
    std::vector<std::shared_ptr<SystemVisuals>> system_visuals;
    std::vector<std::shared_ptr<LinkVisuals>> link_visuals;

    std::unordered_multimap<IntLocation,DrawLabel,HashIntPair> label_map;
    typedef std::unordered_multimap<IntLocation,DrawLabel,HashIntPair>::iterator label_map_iter;
    typedef std::unordered_multimap<IntLocation,DrawLabel,HashIntPair>::const_iterator label_map_citer;
    typedef std::pair<label_map_iter,label_map_iter> label_map_range;
    typedef std::pair<label_map_citer,label_map_citer> label_map_crange;
    PoolRealArray circle_data, line_data;

    Ref<MultiMesh> circle_multimesh, line_multimesh;
    Ref<ArrayMesh> circle_mesh, line_mesh;
  };
}
#endif
