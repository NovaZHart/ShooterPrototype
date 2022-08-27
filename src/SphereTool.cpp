#include "SphereTool.hpp"

#include <array>
#include <cmath>
#include <cstdint>

#include <GodotGlobal.hpp>
#include <SurfaceTool.hpp>
#include <Mesh.hpp>
#include <ArrayMesh.hpp>
#include <Image.hpp>
#include <ImageTexture.hpp>
#include <vector>

#include "DVector3.hpp"
#include "FastProfilier.hpp"
#include "ScriptUtils.hpp"
#include "CE/CheapRand32.hpp"
#include "CE/Utils.hpp"
#include "CE/Constants.hpp"

namespace godot {

using namespace ::std;
using namespace ::godot::CE;

  union xyzw {
    real_t reals[4];
    struct {
      real_t x, y, z, w;
    };
    inline xyzw(real_t x,real_t y,real_t z,real_t w):
      x(x), y(y), z(z), w(w)
    {}
    inline xyzw(const Vector3 &xyz,real_t w):
      x(xyz.x), y(xyz.y), z(xyz.z), w(w)
    {}
    inline xyzw(const DVector3 &xyz,real_t w):
      x(xyz.x), y(xyz.y), z(xyz.z), w(w)
    {}
  };
  
void SphereTool::_register_methods() {
  register_method("make_icosphere", &SphereTool::make_icosphere);
  register_method("make_cube_sphere_v2", &SphereTool::make_cube_sphere_v2);
}

SphereTool::SphereTool() {}
SphereTool::~SphereTool() {}

void SphereTool::_init() {}

void SphereTool::make_icosphere(String name,Vector3 center, float radius, int subs) {
  set_mesh(godot::make_icosphere(subs));
  set_name(name);
  translate(center);
  scale_object_local(Vector3(radius,radius,radius));
}

void SphereTool::make_cube_sphere_v2(String name,Vector3 center, float radius, int subs) {
  set_mesh(godot::make_cube_sphere_v2(radius,subs));
  set_name(name);
  translate(center);
}

void add_tri_pair(Ref<SurfaceTool> &tool,
                  vector<vector<Vector3>> &subverts,
                  int i,int j,bool up) {
  if(up) {
    tool->add_normal(subverts[i][j]);
    tool->add_vertex(subverts[i][j]);
    tool->add_normal(subverts[i+1][j]);
    tool->add_vertex(subverts[i+1][j]);
    tool->add_normal(subverts[i][j+1]);
    tool->add_vertex(subverts[i][j+1]);
  } else {
    tool->add_normal(subverts[i][j+1]);
    tool->add_vertex(subverts[i][j+1]);
    tool->add_normal(subverts[i+1][j]);
    tool->add_vertex(subverts[i+1][j]);
    tool->add_normal(subverts[i+1][j+1]);
    tool->add_vertex(subverts[i+1][j+1]);
  }
}

Ref<ArrayMesh> make_icosphere(int subs) {
  FAST_PROFILING_FUNCTION;
  const float ICX=.525731112119133606;
  const float ICZ=.850650808352039932;
  const float ICO_VERTS[12][3]={
		{-ICX, 0.0, ICZ}, {ICX, 0.0, ICZ}, {-ICX, 0.0, -ICZ}, {ICX, 0.0, -ICZ},
		{0.0, ICZ, ICX}, {0.0, ICZ, -ICX}, {0.0, -ICZ, ICX}, {0.0, -ICZ, -ICX},
		{ICZ, ICX, 0.0}, {-ICZ, ICX, 0.0}, {ICZ, -ICX, 0.0}, {-ICZ, -ICX, 0.0}
  };
  const int ICO_TRIS[20][3]={
		{0,4,1}, {0,9,4}, {9,5,4}, {4,5,8}, {4,8,1},    
		{8,10,1}, {8,3,10}, {5,3,8}, {5,2,3}, {2,7,3},    
		{7,10,3}, {7,6,10}, {7,11,6}, {11,0,6}, {0,1,6}, 
		{6,1,10}, {9,0,11}, {9,11,2}, {9,2,5}, {7,2,11}
  };

  Ref<SurfaceTool> tool=SurfaceTool::_new();
  tool->begin(Mesh::PRIMITIVE_TRIANGLES);

  for(int t=0;t<20;t++) {
    int a=ICO_TRIS[t][0], b=ICO_TRIS[t][1], c=ICO_TRIS[t][2];
    Vector3 top(ICO_VERTS[b][0],ICO_VERTS[b][1],ICO_VERTS[b][2]);
    Vector3 left(ICO_VERTS[a][0],ICO_VERTS[a][1],ICO_VERTS[a][2]);
    Vector3 right(ICO_VERTS[c][0],ICO_VERTS[c][1],ICO_VERTS[c][2]);

    // Draw lines from left to right and subdivide each, making a 2d pyramid:
    vector < vector < Vector3 > > subverts;
    for(int i=0;i<subs;i++) {
      Vector3 v1 = left*(subs-i) + top*i;
      Vector3 v2 = right*(subs-i) + top*i;
      vector<Vector3> content;
      int n=subs+1-i;
      for(int j=0;j<n;j++)
        content.push_back(((v1*j+v2*(n-1-j))/n).normalized());
      subverts.push_back(content);
    }
    vector<Vector3> content;
    content.push_back(top);
    subverts.push_back(content);

    // Horizontal strips starting from bottom of triangle:
    for(int i=0;i<subs;i++) {
      for(int j=0;j<subs-i-1;j++) {
        add_tri_pair(tool,subverts,i,j,true);
        add_tri_pair(tool,subverts,i,j,false);
      }
      add_tri_pair(tool,subverts,i,subs-i-1,true);
    }
  }
  return tool->commit(nullptr,Mesh::ARRAY_COMPRESS_DEFAULT);
}

inline void swap32(uint32_t *data, int n) {
  for(int i=0;i<n;i++)
    data[i] = (data[i]&0xff000000 >> 24) |
              (data[i]&0x00ff0000 >>  8) |
              (data[i]&0x0000ff00 <<  8) |
              (data[i]&0x000000ff << 24);
}

static inline Vector2 normal_to_uv2(Vector3 n) {
  return Vector2(atan2(n.z,n.x),
                 clamp(atan2f(n.y,sqrtf(n.x*n.x+n.z*n.z)),-PIf/2,PIf/2));
}
  
Ref<ArrayMesh> make_cube_sphere_v2(float float_radius, int subs) {
  FAST_PROFILING_FUNCTION;

  const double u_start[6] = { 4/64.0,  4/64.0, 24/64.0,24/64.0, 44/64.0, 44/64.0 };
  const double v_start[6] = { 2/32.0, 18/32.0, 2/32.0, 18/32.0,  2/32.0, 18/32.0 };
  const double width = 1.0/sqrt(2.0), u_scale=12/64.0, v_scale=12/32.0;
  const int i_add[2][6] = { {0,0,1,1,1,0}, {0,0,1,1,0,1} };
  const int j_add[2][6] = { {0,1,1,1,0,0}, {0,1,0,0,1,1} };

  double radius = float_radius;
  PoolVector3Array vert_pool;
  PoolVector3Array normal_pool;
  PoolRealArray tangent_pool;
  PoolVector2Array uv_pool;
  PoolVector2Array uv2_pool;

  int size = subs*subs*6*6;
  vert_pool.resize(size);
  normal_pool.resize(size);
  tangent_pool.resize(size*4);
  uv_pool.resize(size);
  uv2_pool.resize(size);
  
  PoolVector3Array::Write vert_write = vert_pool.write();
  PoolVector3Array::Write normal_write = normal_pool.write();
  PoolRealArray::Write tangents_write = tangent_pool.write();
  PoolVector2Array::Write uv_write = uv_pool.write();
  PoolVector2Array::Write uv2_write = uv2_pool.write();

  // Make sure the union has no padding
  assert(sizeof(xyzw) == sizeof(real_t)*4);

  Vector3 *verts = vert_write.ptr();
  Vector3 *normals = normal_write.ptr();
  real_t *tangents_reals = tangents_write.ptr();
  xyzw *tangents = reinterpret_cast<xyzw*>(tangents_reals);
  Vector2 *uvs = uv_write.ptr();
  Vector2 *uv2s = uv2_write.ptr();

  double angles[subs+1];
  double sides[subs+1];
  double sec2[subs+1];
  for(int i=0;i<subs;i++) {
    angles[i]=PI/2 * (i-(subs/2.0))/subs;
    sides[i]=tan(angles[i])*width;
    sec2[i]=1/cos(angles[i]);
    sec2[i]*=sec2[i];
  }
  angles[subs]=-angles[0];
  sides[subs]=-sides[0];
  sec2[subs]=sec2[0];

  // Calculate everything for tile 0
  int ivert = 0;
  for(int j=0;j<subs;j++)
    for(int i=0;i<subs;i++) {
      int k=(i+j)%2; // Squares will be triangulated in alternating order, creating peaks
      for(int t=0;t<6;t++,ivert++) {
        uvs[ivert].x = u_start[0] + (i+i_add[k][t])*(u_scale/subs);
        uvs[ivert].y = v_start[0] + (j+j_add[k][t])*(v_scale/subs);
        
        double tanu = sides[i+i_add[k][t]], tan2u=tanu*tanu;
        double tanv = sides[j+j_add[k][t]], tan2v=tanv*tanv;

        DVector3 vertex = DVector3(-width,tanv,tanu);
        vertex.normalize();
        verts[ivert] = vertex*radius;
        
        //DVector3 tangent = DVector3(-tan2u,tan2u*tanv,-1-tan2v);
        DVector3 tangent = DVector3(tanu,tanv,-width);
        tangent.normalize();
        tangents[ivert] = xyzw(tangent.x,tangent.y,tangent.z,1);

        normals[ivert] = vertex;
        uv2s[ivert] = normal_to_uv2(normals[ivert]);
      }
    }

  // Copy to other tiles, rotating as needed.
  for(int n=0;n<6*subs*subs;n++,ivert++) {
    uvs[ivert].x = uvs[n].x + (u_start[1]-u_start[0]);
    uvs[ivert].y = uvs[n].y + (v_start[1]-v_start[0]);
    normals[ivert]  = Vector3( -normals[n].x,  normals[n].y, -normals[n].z);
    verts[ivert]    = Vector3(   -verts[n].x,    verts[n].y,   -verts[n].z);
    tangents[ivert] =    xyzw(-tangents[n].x, tangents[n].y,-tangents[n].z, 1);
    uv2s[ivert] = normal_to_uv2(normals[ivert]);
  }

  for(int n=0;n<6*subs*subs;n++,ivert++) {
    uvs[ivert].x = uvs[n].x + (u_start[2]-u_start[0]);
    uvs[ivert].y = uvs[n].y + (v_start[2]-v_start[0]);
    normals[ivert]  = Vector3(  normals[n].z,  normals[n].y,  -normals[n].x);
    verts[ivert]    = Vector3(    verts[n].z,    verts[n].y,    -verts[n].x);
    tangents[ivert] =    xyzw( tangents[n].z, tangents[n].y, -tangents[n].x, 1);
    uv2s[ivert] = normal_to_uv2(normals[ivert]);
  }
    
  for(int n=0;n<6*subs*subs;n++,ivert++) {
    uvs[ivert].x = uvs[n].x + (u_start[3]-u_start[0]);
    uvs[ivert].y = uvs[n].y + (v_start[3]-v_start[0]);
    normals[ivert]  = Vector3( -normals[n].z,  normals[n].y,  normals[n].x);
    verts[ivert]    = Vector3(   -verts[n].z,    verts[n].y,    verts[n].x);
    tangents[ivert] =    xyzw(-tangents[n].z, tangents[n].y, tangents[n].x, 1);
    uv2s[ivert] = normal_to_uv2(normals[ivert]);
  }

// x,-y,z was right on one edge
// x,z,-y has all colors right, but patterns match on only one edge
// -y,z,x had no color match, but patterns matched on one edge
// z,x,-y had a color match but not pattern, on one edge
// -z,-x,-y had a color match but not pattern, on one edge
// z,-y,x had a pattern match but not color, on one edge
// z,-y,-x had a pattern match but not color, on one edge
// -z,-y,-x had a pattern match but not color, on one edge
  for(int n=0;n<6*subs*subs;n++,ivert++) {
    uvs[ivert].x = uvs[n].x + (u_start[4]-u_start[0]);
    uvs[ivert].y = uvs[n].y + (v_start[4]-v_start[0]);
    normals[ivert]  = Vector3(  normals[n].y,  -normals[n].x,  normals[n].z);
    verts[ivert]    = Vector3(    verts[n].y,    -verts[n].x,    verts[n].z);
    tangents[ivert] =    xyzw( tangents[n].y, -tangents[n].x, tangents[n].z, 1);
    //tangents[ivert] =    xyzw( tangents[n].x,  tangents[n].z, -tangents[n].y, 1);
    uv2s[ivert] = normal_to_uv2(normals[ivert]);
  }

  for(int n=0;n<6*subs*subs;n++,ivert++) {
    uvs[ivert].x = uvs[n].x + (u_start[5]-u_start[0]);
    uvs[ivert].y = uvs[n].y + (v_start[5]-v_start[0]);
    normals[ivert]  = Vector3( -normals[n].y,  normals[n].x,  normals[n].z);
    verts[ivert]    = Vector3(   -verts[n].y,    verts[n].x,    verts[n].z);
    tangents[ivert] =    xyzw(-tangents[n].y, tangents[n].x, tangents[n].z, 1);
//    tangents[ivert] =    xyzw( tangents[n].x,  -tangents[n].z, tangents[n].y, 1);
    uv2s[ivert] = normal_to_uv2(normals[ivert]);
  }

  Array content;
  content.resize(ArrayMesh::ARRAY_MAX);
  content[ArrayMesh::ARRAY_VERTEX] = vert_pool;
  content[ArrayMesh::ARRAY_TEX_UV] = uv_pool;
  content[ArrayMesh::ARRAY_TEX_UV2] = uv2_pool;
  content[ArrayMesh::ARRAY_NORMAL] = normal_pool;
  content[ArrayMesh::ARRAY_TANGENT] = tangent_pool;
  Ref<ArrayMesh> mesh = ArrayMesh::_new();
  mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES,content,Array(),ArrayMesh::ARRAY_COMPRESS_VERTEX|ArrayMesh::ARRAY_COMPRESS_TEX_UV|ArrayMesh::ARRAY_COMPRESS_NORMAL|ArrayMesh::ARRAY_COMPRESS_TANGENT);
  return mesh;
}

template<int tile_size, int u_pad_size, int v_pad_size, int i_width, int j_height>
Ref<Image> make_lookup_tiles() {
  FAST_PROFILING_FUNCTION;
  const double cube_width = 1.0/sqrt(2.0);
  const int num_floats = i_width * j_height * 4;
  const double sqrt2 = sqrtf(2);

  PoolByteArray data_pool;
  data_pool.resize(num_floats*sizeof(float));
  {
    PoolByteArray::Write data_write = data_pool.write();
    xyzw *floats = reinterpret_cast<xyzw*>(data_write.ptr());

    double sides[tile_size];
    {
      double angles[tile_size];

      for(int i=0;i<tile_size;i++) {
        double m = i+0.5;
        angles[i]=PI/2 * (m-(tile_size/2.0))/tile_size;
        sides[i]=tan(angles[i])/sqrt2;
      }
    }

    // Fill tile 0 middle.
    for(int j=0;j<tile_size;j++) {
      int j_storage = j + v_pad_size;
      for(int i=0;i<tile_size;i++) {
        int i_storage = i + u_pad_size;
        DVector3 vertex = Vector3(-cube_width,sides[j],sides[i]);
        vertex.normalize();
        floats[j_storage*i_width+i_storage] = xyzw(vertex,1.0f);
      }
    }

    // Tile 0 top padding, which comes from bottom of tile 4.
    for(int j=0;j<v_pad_size;j++) {
      int j_storage = tile_size + v_pad_size + j;
      for(int i=0;i<tile_size;i++) {
        int i_storage = u_pad_size+i;
        DVector3 vertex = Vector3(sides[j],cube_width,sides[i]);
        vertex.normalize();
        floats[j_storage*i_width+i_storage] = xyzw(vertex,1.0f);
      }
    }

    // Tile 0 bottom padding, which comes from top of tile 5.
    for(int j=0;j<v_pad_size;j++) {
      int j_storage = v_pad_size-1 - j;
      for(int i=0;i<tile_size;i++) {
        int i_storage = u_pad_size+i;
        DVector3 vertex = Vector3(sides[j],-cube_width,sides[i]);
        vertex.normalize();
        floats[j_storage*i_width+i_storage] = xyzw(vertex,1.0f);
      }
    }

    // Tile 0 left padding, which comes from right edge of tile 3.
    for(int j=0;j<tile_size;j++) {
      int j_storage = v_pad_size+j;
      for(int i=0;i<u_pad_size;i++) {
        int i_storage = u_pad_size-1 - i;
        DVector3 vertex = Vector3(sides[i],sides[j],-cube_width);
        vertex.normalize();
        floats[j_storage*i_width+i_storage] = xyzw(vertex,1.0f);
      }
    }

    // Tile 0 right padding, which comes from left edge of tile 2.
    for(int j=0;j<tile_size;j++) {
      int j_storage = v_pad_size + j;
      for(int i=0;i<u_pad_size;i++) {
        int i_storage = u_pad_size+tile_size + i;
        DVector3 vertex = Vector3(sides[i],sides[j],cube_width);
        vertex.normalize();
        floats[j_storage*i_width+i_storage] = xyzw(vertex,1.0f);
      }
    }

    // Lower-right padding
    for(int j=0;j<v_pad_size;j++) {
      int j_storage = v_pad_size-1 - j;
      for(int i=0;i<u_pad_size;i++) {
        int i_storage = tile_size+u_pad_size + i;
        int ij = i+j;
        DVector3 vertex = Vector3(sides[ij],-cube_width,cube_width);
        vertex.normalize();
        floats[j_storage*i_width+i_storage] = xyzw(vertex,1.0f);
      }
    }

    // Upper-right padding
    for(int j=0;j<v_pad_size;j++) {
      int j_storage = tile_size+v_pad_size + j;
      for(int i=0;i<u_pad_size;i++) {
        int i_storage = tile_size+u_pad_size + i;
        int ij = i+j;
        DVector3 vertex = Vector3(sides[ij],cube_width,cube_width);
        vertex.normalize();
        floats[j_storage*i_width+i_storage] = xyzw(vertex,1.0f);
      }
    }

    // Lower-left padding
    for(int j=0;j<v_pad_size;j++) {
      int j_storage = v_pad_size-1 - j;
      for(int i=0;i<u_pad_size;i++) {
        int i_storage = u_pad_size-1 - i;
        int ij = i+j;
        DVector3 vertex = Vector3(sides[ij],-cube_width,-cube_width);
        vertex.normalize();
        floats[j_storage*i_width+i_storage] = xyzw(vertex,1.0f);
      }
    }

    // Upper-left padding
    for(int j=0;j<v_pad_size;j++) {
      int j_storage = tile_size+v_pad_size + j;
      for(int i=0;i<u_pad_size;i++) {
        int i_storage = u_pad_size-1 - i;
        int ij = i+j;
        DVector3 vertex = Vector3(sides[ij],cube_width,-cube_width);
        vertex.normalize();
        floats[j_storage*i_width+i_storage] = xyzw(vertex,1.0f);
      }
    }

    // Copy from tile 0 to 1-5, rotating as needed. Zero-out unused tiles 6&7

    const int u_shift_size = tile_size+2*u_pad_size;
    const int v_shift_size = tile_size+2*v_pad_size;

    for(int j=0;j<v_shift_size;j++) {
      int dst=u_shift_size; // i index in destination tile; src is in tile 0
      for(int src=0;dst<2*u_shift_size;dst++,src++) { // tile 2
        floats[j*i_width+dst].x =  floats[j*i_width+src].z;
        floats[j*i_width+dst].y =  floats[j*i_width+src].y;
        floats[j*i_width+dst].z = -floats[j*i_width+src].x;
        floats[j*i_width+dst].w = 1.0f;
        // floats[3*(j*i_width+dst)+0] =  floats[3*(j*i_width+src)+2]; // tile 2 x = 0's  z
        // floats[3*(j*i_width+dst)+1] =  floats[3*(j*i_width+src)+1]; // tile 2 y = 0's  y
        // floats[3*(j*i_width+dst)+2] = -floats[3*(j*i_width+src)+0]; // tile 2 z = 0's -x
      }
      for(int src=0;dst<3*u_shift_size;dst++,src++) { // tile 4
        floats[j*i_width+dst].x =  floats[j*i_width+src].y;
        floats[j*i_width+dst].y = -floats[j*i_width+src].x;
        floats[j*i_width+dst].z =  floats[j*i_width+src].z;
        floats[j*i_width+dst].w = 1.0f;
        // floats[3*(j*i_width+dst)+0] =  floats[3*(j*i_width+src)+1]; // tile 4 x = 0's  y
        // floats[3*(j*i_width+dst)+1] = -floats[3*(j*i_width+src)+0]; // tile 4 y = 0's -x
        // floats[3*(j*i_width+dst)+2] =  floats[3*(j*i_width+src)+2]; // tile 4 z = 0's  z
      }
      for(;dst<i_width;dst++) // beyond
        floats[j*i_width+dst] = xyzw(0,0,0,0);
    }

    for(int srcj=0,dstj=v_shift_size;srcj<v_shift_size;srcj++,dstj++) {
      int dsti=0;
      for(int srci=0;dsti<u_shift_size;dsti++,srci++) { // tile 1
        floats[dstj*i_width+dsti].x = -floats[srcj*i_width+srci].x;
        floats[dstj*i_width+dsti].y =  floats[srcj*i_width+srci].y;
        floats[dstj*i_width+dsti].z = -floats[srcj*i_width+srci].z;
        floats[dstj*i_width+dsti].w = 1.0f;
        // floats[3*(dstj*i_width+dsti)+0] = -floats[3*(srcj*i_width+srci)+0]; // tile 1 x = 0's -x
        // floats[3*(dstj*i_width+dsti)+1] =  floats[3*(srcj*i_width+srci)+1]; // tile 1 y = 0's  y
        // floats[3*(dstj*i_width+dsti)+2] = -floats[3*(srcj*i_width+srci)+2]; // tile 1 z = 0's -z
      }
      for(int srci=0;dsti<2*u_shift_size;dsti++,srci++) { // tile 3
        floats[dstj*i_width+dsti].x = -floats[srcj*i_width+srci].z;
        floats[dstj*i_width+dsti].y =  floats[srcj*i_width+srci].y;
        floats[dstj*i_width+dsti].z =  floats[srcj*i_width+srci].x;
        floats[dstj*i_width+dsti].w = 1.0f;
        // floats[3*(dstj*i_width+dsti)+0] = -floats[3*(srcj*i_width+srci)+2]; // tile 3 x = 0's -z
        // floats[3*(dstj*i_width+dsti)+1] =  floats[3*(srcj*i_width+srci)+1]; // tile 3 y = 0's  y
        // floats[3*(dstj*i_width+dsti)+2] =  floats[3*(srcj*i_width+srci)+0]; // tile 3 z = 0's  x
      }
      for(int srci=0;dsti<3*u_shift_size;dsti++,srci++) { // tile 5
        floats[dstj*i_width+dsti].x = -floats[srcj*i_width+srci].y;
        floats[dstj*i_width+dsti].y =  floats[srcj*i_width+srci].x;
        floats[dstj*i_width+dsti].z =  floats[srcj*i_width+srci].z;
        floats[dstj*i_width+dsti].w = 1.0f;
        // floats[3*(dstj*i_width+dsti)+0] = -floats[3*(srcj*i_width+srci)+1]; // tile 5 x = 0's -y
        // floats[3*(dstj*i_width+dsti)+1] =  floats[3*(srcj*i_width+srci)+0]; // tile 5 y = 0's  x
        // floats[3*(dstj*i_width+dsti)+2] =  floats[3*(srcj*i_width+srci)+2]; // tile 5 z = 0's  z
      }
      for(;dsti<i_width;dsti++) // beyond
        floats[dstj*i_width+dsti] = xyzw(0,0,0,0);
    }
  }  
  
  Ref<Image> image = Image::_new();
  image->create_from_data(i_width, j_height, false, Image::FORMAT_RGBAF, data_pool);
  //image->convert(Image::FORMAT_RGBH);
  Ref<Image> write_image = Image::_new();
  write_image->create_from_data(i_width, j_height, false, Image::FORMAT_RGBAF, data_pool);
  write_image->convert(Image::FORMAT_RGB8);
  write_image->save_png("res://lookup.png");
  return image;
}

Ref<Image> make_lookup_tiles_c192() {
  FAST_PROFILING_FUNCTION;
  return make_lookup_tiles<192,64,32,1024,512>();
}

Ref<Image> make_lookup_tiles_c96() {
  FAST_PROFILING_FUNCTION;
  return make_lookup_tiles<96,32,16,512,256>();
}

/********************************************************************/

template<size_t cubelen>
class HashCube {
public:
  vector<uint8_t> hashed;
  uint32_t seed;
  HashCube(uint32_t seed):
    hashed(cubelen*cubelen*cubelen,0),
    seed(seed)
  {}
  ~HashCube() {}

  inline void randomize() {
    uint32_t h = CheapRand32::hash(seed);
    for(uint32_t k=0;k<cubelen;k++)
      for(uint32_t j=0;j<cubelen;j++)
        for(uint32_t i=0;i<cubelen;i++) {
          uint32_t h0 = CheapRand32::hash(h^i);
          uint32_t h00 = CheapRand32::hash(h0^j);
          uint32_t h000 = CheapRand32::hash(h00^k);
          hashed[i+cubelen*(j+cubelen*k)] = h000&15;
        }
  }    

  inline uint8_t at(uint32_t i,uint32_t j,uint32_t k) const {
    return hashed[i+cubelen*(j+cubelen*k)];
  }

  inline void get_data(size_t i0,size_t j0,size_t k0,float *data) const {
    size_t i1=(i0+1)%cubelen, j1=(j0+1)%cubelen, k1=(k0+1)%cubelen;
    data[0] = ((at(i1,j0,k0)<<4) | at(i0,j0,k0)) / 1024.0f;
    data[1] = ((at(i1,j1,k0)<<4) | at(i0,j1,k0)) / 1024.0f;
    data[2] = ((at(i1,j0,k1)<<4) | at(i0,j0,k1)) / 1024.0f;
    data[3] = ((at(i1,j1,k1)<<4) | at(i0,j1,k1)) / 1024.0f;
  }
};

/********************************************************************/

template<size_t cubelen>
static Ref<Image> make_hash_cube(uint32_t hash) {
  static const size_t image_x = cubelen*cubelen, image_y = cubelen;
  HashCube<cubelen> cube(hash);
  cube.randomize();

  PoolByteArray texture_data;
  texture_data.resize(cubelen*cubelen*cubelen*4*sizeof(float));
  {
    PoolByteArray::Write write_texture_data = texture_data.write();
    float *data = reinterpret_cast<float*>(write_texture_data.ptr());

    for(size_t k=0;k<cubelen;k++)
      for(size_t j=0;j<cubelen;j++)
        for(size_t i=0;i<cubelen;i++,data+=4)
          cube.get_data(i,j,k,data);
  }

  Ref<Image> image = Image::_new();
  image->create_from_data(image_x,image_y,false,Image::FORMAT_RGBAF,texture_data);
  image->convert(Image::FORMAT_RGBAH);
  return image;
}

/********************************************************************/

Ref<Image> make_hash_cube16(uint32_t hash) {
  return make_hash_cube<16>(hash);
}

/********************************************************************/

Ref<Image> make_hash_cube8(uint32_t hash) {
  return make_hash_cube<8>(hash);
}

/********************************************************************/
  
template<size_t width>
class HashSquare {
public:
  vector<float> hashed;
  uint32_t seed;
  HashSquare(uint32_t seed):
    hashed(width*width,0),
    seed(seed)
  {}
  ~HashSquare() {}

  inline void randomize() {
    uint32_t h = CheapRand32::hash(seed);
    for(uint32_t j=0;j<width;j++)
      for(uint32_t i=0;i<width;i++) {
        uint32_t h0 = CheapRand32::hash(h^i);
        uint32_t h00 = CheapRand32::hash(h0^j);
        hashed[i+width*j] = CheapRand32::int2float(h00);
      }
  }
  
  inline float at(uint32_t i,uint32_t j) const {
    return hashed[i+width*j];
  }

  inline void get_data(size_t i0,size_t j0,float *f) const {
    size_t i1=(i0+1)%width, j1=(j0+1)%width;
    f[0] = at(i0,j0);
    f[1] = at(i0,j1);
    f[2] = at(i1,j0);
    f[3] = at(i1,j1);
  }
};

Ref<Image> make_hash_square32(uint32_t seed) {
  // Makes a csq by csq big grid of width by width small grids of
  // random 4-bit integers encoded in 32-bit floating point.  Each
  // width by width grid is toroidally tiled. This is to give a
  // toroidally tiled shader several sets (csq*csq) of random numbers.
  static const size_t width = HASH_SQUARE_LENGTH;
  static const size_t csq = HASH_SQUARE_COUNT_SQRT;
  CheapRand32 seeder(seed);
  
  PoolByteArray texture_data;
  //texture_data.resize(width*width*4*sizeof(float)*csq*csq);
  texture_data.resize(1024*1024*4*sizeof(float));
  {
    PoolByteArray::Write write_texture_data = texture_data.write();
    float *data = reinterpret_cast<float*>(write_texture_data.ptr());

    memset(data,0,1024*1024*4*sizeof(float));
    
    for(size_t sq=0,last=csq*csq;sq<last;sq++) {
      HashSquare<width> square(seeder.randi());
      square.randomize();
      for(size_t j=0;j<width;j++)
        for(size_t i=0;i<width;i++,data+=4)
          square.get_data(i,j,data);
    }
  }
  
  Ref<Image> image = Image::_new();
  image->create_from_data(1024,1024,false,Image::FORMAT_RGBAF,texture_data);
  image->convert(Image::FORMAT_RGBAH);
  return image;
}

Ref<Image> generate_impact_craters(real_t max_size,real_t min_size,int requested_count,uint32_t seed) {
  const int width=16, height=16;
  int actual_count = clamp(requested_count,1,width*height);
  if(max_size<min_size)
    swap(max_size,min_size);
  CheapRand32 rand(seed);
  
  PoolByteArray texture_data;
  texture_data.resize(width*height*4*sizeof(float));
  {
    PoolByteArray::Write write_texture_data = texture_data.write();
    float *data=reinterpret_cast<float*>(write_texture_data.ptr());

    memset(data,0,width*height*4*sizeof(float));

    for(int i=0;i<actual_count;i++,data+=4) {
      float f=rand.randf();
      f*=f;
      float size=min_size + (max_size-min_size)*f;
      Vector3 where=rand.rand_unit3();
      data[0]=0.5+0.5*where.x;
      data[1]=0.5+0.5*where.y;
      data[2]=0.5+0.5*where.z;
      data[3]=size;
    }
  }

  Ref<Image> image = Image::_new();
  image->create_from_data(width,height,false,Image::FORMAT_RGBAF,texture_data);
  //image->convert(Image::FORMAT_RGBAH);
  return image;
}
  
Ref<Image> generate_planet_ring_noise(uint32_t log2,uint32_t seed,real_t weight_power) {
  const int width=1<<log2, height=16, nfloats=height*width;
  const int nbytes=nfloats*sizeof(real_t);
  
  CheapRand32 rand(seed);
  
  PoolByteArray bytes;
  bytes.resize(nbytes);
  {
    PoolByteArray::Write write_bytes=bytes.write();
    real_t *data=reinterpret_cast<real_t*>(write_bytes.ptr());

    for(int i=0;i<=width;i++)
      data[i]=0.0f;
    
    real_t weight=1.0f, weight_sum=0.0f;
    for(int mag=log2-1;mag>=0;mag--) {
      int step=1<<mag, step2=step<<1;
      for(int i=0;i<width;i+=step2) {
        data[i+step] = (data[i]+data[i+step2])*0.5;
        data[i+step] += weight*rand.randf();
        data[i]      += weight*rand.randf();
      }
      data[width]=data[0];
      weight_sum+=weight;
      weight*=weight_power;
    }

    for(int i=0;i<width;i++)
      data[i] /= weight_sum;

    for(int j=1;j<height;j++) {
      real_t *jdata = data+j*width;
      for(int i=0;i<width;i++)
        jdata[i]=data[i];
    }
  }

  Ref<Image> image = Image::_new();
  image->create_from_data(width,height,false,Image::FORMAT_RF,bytes);
  image->convert(Image::FORMAT_RGBH);
  Ref<Image> write_image = Image::_new();
  write_image->create_from_data(width, height, false, Image::FORMAT_RF, bytes);
  write_image->convert(Image::FORMAT_RGB8);
  write_image->save_png("res://ring_data.png");
  return image;
}

Ref<ArrayMesh> make_annulus_mesh(real_t middle_radius, real_t thickness, int steps) {
  PoolVector3Array vertices_pool;
  PoolVector2Array uv_pool;
  vertices_pool.resize(steps*6);
  uv_pool.resize(steps*6);
  
  const real_t angle = 2*PI/steps;
  const real_t half_angle = angle/2;
  const real_t inner_radius = middle_radius-thickness/2;
  const real_t outer_radius = middle_radius+thickness/2;
  const real_t far_radius = outer_radius/cosf(half_angle);
  const Vector2 uvhalf = Vector2(0.5,0.5);

  {
    PoolVector3Array::Write write_vertices=vertices_pool.write();
    PoolVector2Array::Write write_uv=uv_pool.write();
    Vector3 *vertices=write_vertices.ptr();
    Vector2 *uv=write_uv.ptr();
    
    Vector3 prior_far_vertex = far_radius*Vector3(cosf((steps-1)*angle+half_angle),0,
                                                  sinf((steps-1)*angle+half_angle));
    Vector3 prior_inner_vertex = inner_radius*Vector3(cosf((steps-1)*angle),0,
                                                      sinf((steps-1)*angle));
    for(int i=0;i<steps;i++) {
      Vector3 this_far_vertex = far_radius*Vector3(cosf(i*angle+half_angle),0.0,
                                                   sinf(i*angle+half_angle));
      Vector3 this_inner_vertex = inner_radius*Vector3(cosf(i*angle),0.0,sinf(i*angle));
		
      vertices[i*6 + 0] = this_inner_vertex;
      uv      [i*6 + 0] = Vector2(this_inner_vertex.z,this_inner_vertex.x)/2.0+uvhalf;
      vertices[i*6 + 1] = prior_far_vertex;
      uv      [i*6 + 1] = Vector2(prior_far_vertex.z,prior_far_vertex.x)/2.0+uvhalf;
      vertices[i*6 + 2] = this_far_vertex;
      uv      [i*6 + 2] = Vector2(this_far_vertex.z,this_far_vertex.x)/2.0+uvhalf;

      vertices[i*6 + 3] = this_inner_vertex;
      uv      [i*6 + 3] = Vector2(this_inner_vertex.z,this_inner_vertex.x)/2.0+uvhalf;
      vertices[i*6 + 4] = prior_inner_vertex;
      uv      [i*6 + 4] = Vector2(prior_inner_vertex.z,prior_inner_vertex.x)/2.0+uvhalf;
      vertices[i*6 + 5] = prior_far_vertex;
      uv      [i*6 + 5] = Vector2(prior_far_vertex.z,prior_far_vertex.x)/2.0+uvhalf;
		
      prior_far_vertex = this_far_vertex;
      prior_inner_vertex = this_inner_vertex;
    }
  }
  
  Ref<ArrayMesh> mesh = ArrayMesh::_new();
  Array arrays;
  arrays.resize(ArrayMesh::ARRAY_MAX);
  arrays[ArrayMesh::ARRAY_VERTEX] = vertices_pool;
  arrays[ArrayMesh::ARRAY_TEX_UV] = uv_pool;
  mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
  return mesh;
}
}
