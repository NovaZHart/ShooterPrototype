#ifndef MAPTOOL_H
#define MAPTOOL_H

#include <Godot.hpp>
#include <Camera.hpp>
#include <MultiMesh.hpp>
#include <Viewport.hpp>
#include <Shader.hpp>
#include <Node2D.hpp>
#include <Ref.hpp>
#include <NodePath.hpp>
#include <PoolRealArray.hpp>

#include <unordered_map>
#include <unordered_multimap>
#include <algorithm>
#include <string>

namespace godot {

  struct IntLocation {
    int x, y;
  };
  
  struct SystemInfo {
    NodePath path;
    Vector3 position;
    String display_name;
    AABB display_name_region;
    SystemInfo(Array);
    ~SystemInfo();
    SystemInfo(const SystemInfo &);
  };

  template<>
  struct hash<IntLocation> {
    struct hash<int> int_hash;
    hash(): int_hash() {}
    ~hash() {}
    size_t operator() (const IntLocation &i) {
      return int_hash(i.x)^int_hash(i.y);
    }
  };

  template<>
  struct hash<NodePath> {
    struct hash<int> int_hash;
    hash(): int_hash() {}
    ~hash() {}
    size_t operator() (const NodePath &np) {
      return int_hash(static_cast<String>(np).hash());
    }
  };
  
  struct Link {
    NodePath from_node, to_node;
    Vector3 from_pos, to_pos;
  };

  struct MapToolVisuals {
    MapToolVisuals();
    MapToolVisuals(const MapToolVisuals &v);
    ~MapToolVisuals();
    Ref<Font> highlighted_font;
    Ref<Font> label_font;
    Color connected, highlight, system, link, system_name;
    real_t system_scale, link_scale;
  };

  class Projector {
  public:
    Projector(Ref<Camera>,Ref<Viewport>);
    ~Projector();
    Vector3 project_position(const Vector2 &screen_position, real_t z=0) const;
    Vector2 unproject_position(const Vector3 &) const;

  public:
    const Vector2 viewport_size;
  private:
    Transform from2to3, from3to2;
  };

  class DrawLabel {
  public:
    DrawLabel(Ref<Font> font,Vector2 position,String label,Color color);
    DrawLabel(const DrawLabel &);
    ~DrawLabel();
    void draw(const Node2D &) const;
  private:
    Ref<Font> font;
    Vector2 position;
    String label;
    Color color;
  };
  
  class MapTool: public Node2D {
    GODOT_CLASS(MapTool, Node2D)

  public:
    static void _register_methods();
    MapTool();
    ~MapTool();
    void _init();
    void _draw();
    void set_visuals(Ref<Font> highlighted_font, Ref<Font> label_font, Color connected,
                     Color highlight, Color system, Color link, Color system_name,
                     real_t system_scale, real_t link_scale);
    void set_data(Dictionary systems, Array links);
    NodePath at_location(Vector3 where, float epsilon) const;
    void update_multimeshes(Ref<Camera> zx_orthographic_camera, Ref<Viewport> viewport);

    typedef unordered_map<NodePath,SystemInfo>::iterator system_iter;
    typedef unordered_map<NodePath,SystemInfo>::const_iterator system_citer;

    typedef unordered_multimap<IntLocation,SystemInfo>::iterator position_iter;
    typedef unordered_multimap<IntLocation,SystemInfo>::const_iterator position_citer;
    typedef pair<position_iter,position_iter> position_range;
    typedef pair<position_citer,position_citer> position_crange;
  private:
    shared_ptr<MapToolVisuals> visuals;
    Ref<MultiMesh> mm_links, mm_systems;
    vector<Link> list_links;
    unordered_map<NodePath,SystemInfo> hash_systems;
    unordered_multimap<IntLocation,SystemInfo> positions;
    PoolRealArray link_reals, system_reals;
    vector<DrawLabel> draw_commands;
  };
}

#endif
