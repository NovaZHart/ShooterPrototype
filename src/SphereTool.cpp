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
                 atan2(n.y,sqrtf(n.x*n.x+n.z*n.z)));
}
  
Ref<ArrayMesh> make_cube_sphere_v2(float float_radius, int subs) {
  FAST_PROFILING_FUNCTION;
  const double pi = 3.14159265358979323846;
  const double u_start[6] = { 1/64.0, 1/64.0, 17/64.0, 17/64.0, 33/64.0, 33/64.0 };
  const double v_start[6] = { 1/32.0, 17/32.0, 1/32.0, 17/32.0, 1/32.0, 17/32.0 };
  const double width = 1.0/sqrt(2.0), u_scale=14/64.0, v_scale=14/32.0;
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

  union xyzw {
    real_t reals[4];
    struct {
      real_t x, y, z, w;
    };
    xyzw(real_t x,real_t y,real_t z,real_t w):
      x(x), y(y), z(z), w(w)
    {}
  };

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
  for(int i=0;i<=subs;i++) {
    angles[i]=pi/2 * (i-(subs/2.0))/subs;
    sides[i]=tan(angles[i])/sqrt(2);
  }

  // Calculate everything for tile 0
  int ivert = 0;
  for(int j=0;j<subs;j++)
    for(int i=0;i<subs;i++) {
      int k=(i+j)%2; // Squares will be triangulated in alternating order, creating peaks
      for(int t=0;t<6;t++,ivert++) {
        uvs[ivert].x = u_start[0] + (i+i_add[k][t])*(u_scale/subs);
        uvs[ivert].y = v_start[0] + (j+j_add[k][t])*(v_scale/subs);
        DVector3 vertex = DVector3(-width,sides[j+j_add[k][t]],sides[i+i_add[k][t]]);
        vertex.normalize();
        verts[ivert] = vertex*radius;
        tangents[ivert] = xyzw(vertex.z,vertex.y,-vertex.x,1);
        normals[ivert] = vertex;
        uv2s[ivert] = normal_to_uv2(normals[ivert]);
      }
    }

  // Copy to other tiles, rotating as needed.
  for(int n=0;n<6*subs*subs;n++,ivert++) {
    uvs[ivert].x = uvs[n].x + (u_start[1]-u_start[0]);
    uvs[ivert].y = uvs[n].y + (v_start[1]-v_start[0]);
    normals[ivert] = Vector3(-normals[n].x, normals[n].y,-normals[n].z);
    verts[ivert] = Vector3(-verts[n].x, verts[n].y,-verts[n].z);
    tangents[ivert] = xyzw(-tangents[n].x, tangents[n].y,-tangents[n].z, 1);
    uv2s[ivert] = normal_to_uv2(normals[ivert]);
  }

  for(int n=0;n<6*subs*subs;n++,ivert++) {
    uvs[ivert].x = uvs[n].x + (u_start[2]-u_start[0]);
    uvs[ivert].y = uvs[n].y + (v_start[2]-v_start[0]);
    normals[ivert] = Vector3( normals[n].z, normals[n].y,-normals[n].x);
    verts[ivert] = Vector3( verts[n].z, verts[n].y,-verts[n].x);
    tangents[ivert] = xyzw( tangents[n].z, tangents[n].y,-tangents[n].x, 1);
    uv2s[ivert] = normal_to_uv2(normals[ivert]);
  }
    
  for(int n=0;n<6*subs*subs;n++,ivert++) {
    uvs[ivert].x = uvs[n].x + (u_start[3]-u_start[0]);
    uvs[ivert].y = uvs[n].y + (v_start[3]-v_start[0]);
    normals[ivert] = Vector3(-normals[n].z, normals[n].y, normals[n].x);
    verts[ivert] = Vector3(-verts[n].z, verts[n].y, verts[n].x);
    tangents[ivert] = xyzw(-tangents[n].z, tangents[n].y, tangents[n].x, 1);
    uv2s[ivert] = normal_to_uv2(normals[ivert]);
  }

  for(int n=0;n<6*subs*subs;n++,ivert++) {
    uvs[ivert].x = uvs[n].x + (u_start[4]-u_start[0]);
    uvs[ivert].y = uvs[n].y + (v_start[4]-v_start[0]);
    normals[ivert] = Vector3( normals[n].y,-normals[n].x, normals[n].z);
    verts[ivert] = Vector3( verts[n].y,-verts[n].x, verts[n].z);
    tangents[ivert] = xyzw( tangents[n].y,-tangents[n].x, tangents[n].z, 1);
    uv2s[ivert] = normal_to_uv2(normals[ivert]);
  }

  for(int n=0;n<6*subs*subs;n++,ivert++) {
    uvs[ivert].x = uvs[n].x + (u_start[5]-u_start[0]);
    uvs[ivert].y = uvs[n].y + (v_start[5]-v_start[0]);
    normals[ivert] = Vector3(-normals[n].y, normals[n].x, normals[n].z);
    verts[ivert] = Vector3(-verts[n].y, verts[n].x, verts[n].z);
    tangents[ivert] = xyzw(-tangents[n].y, tangents[n].x, tangents[n].z ,1);
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
  mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES,content,Array(),ArrayMesh::ARRAY_COMPRESS_VERTEX|ArrayMesh::ARRAY_COMPRESS_TEX_UV|ArrayMesh::ARRAY_COMPRESS_NORMAL|ArrayMesh::ARRAY_COMPRESS_TANGENT|ArrayMesh::ARRAY_COMPRESS_TEX_UV2);
  return mesh;
}

template<int tile_size, int pad_size>
Ref<Image> make_lookup_tiles() {
  FAST_PROFILING_FUNCTION;
  const float cube_width = 1.0/sqrt(2.0);
  const int j_height = (tile_size+2*pad_size)*2;
  const int i_width = (tile_size+2*pad_size)*4;
  const int num_floats = i_width * j_height * 3;
  const float pi = 3.141592653589793f;
  float *floats = new float[num_floats];
  memset(floats,0,sizeof(float)*num_floats);
  //std::array<float, num_floats> floats = { 0.0f };
  const float sqrt2 = sqrtf(2);
  
  float sides[tile_size];
  {
    float angles[tile_size];

    for(int i=0;i<tile_size;i++) {
      float m = i+0.5;
      angles[i]=pi/2 * (m-(tile_size/2.0))/tile_size;
      sides[i]=tanf(angles[i])/sqrt2;
    }
  }

  // Fill tile 0 middle.
  for(int j=0;j<tile_size;j++) {
    int j_storage = j + pad_size;
    for(int i=0;i<tile_size;i++) {
      int i_storage = i + pad_size;
      Vector3 vertex = Vector3(-cube_width,sides[j],sides[i]);
      vertex.normalize();
      floats[3*(j_storage*i_width+i_storage)+0] = vertex.x;
      floats[3*(j_storage*i_width+i_storage)+1] = vertex.y;
      floats[3*(j_storage*i_width+i_storage)+2] = vertex.z;
    }
  }

  // Tile 0 top padding, which comes from bottom of tile 4.
  for(int j=0;j<pad_size;j++) {
    int j_storage = tile_size + pad_size + j;
    for(int i=0;i<tile_size;i++) {
      int i_storage = pad_size+i;
      Vector3 vertex = Vector3(sides[j],cube_width,sides[i]);
      vertex.normalize();
      floats[3*(j_storage*i_width+i_storage)+0] = vertex.x;
      floats[3*(j_storage*i_width+i_storage)+1] = vertex.y;
      floats[3*(j_storage*i_width+i_storage)+2] = vertex.z;
    }
  }

  // Tile 0 bottom padding, which comes from top of tile 5.
  for(int j=0;j<pad_size;j++) {
    int j_storage = pad_size-1 - j;
    for(int i=0;i<tile_size;i++) {
      int i_storage = pad_size+i;
      Vector3 vertex = Vector3(sides[j],-cube_width,sides[i]);
      vertex.normalize();
      floats[3*(j_storage*i_width+i_storage)+0] = vertex.x;
      floats[3*(j_storage*i_width+i_storage)+1] = vertex.y;
      floats[3*(j_storage*i_width+i_storage)+2] = vertex.z;
    }
  }

  // Tile 0 left padding, which comes from right edge of tile 3.
  for(int j=0;j<tile_size;j++) {
    int j_storage = pad_size+j;
    for(int i=0;i<pad_size;i++) {
      int i_storage = pad_size-1 - i;
      Vector3 vertex = Vector3(sides[i],sides[j],-cube_width);
      vertex.normalize();
      floats[3*(j_storage*i_width+i_storage)+0] = vertex.x;
      floats[3*(j_storage*i_width+i_storage)+1] = vertex.y;
      floats[3*(j_storage*i_width+i_storage)+2] = vertex.z;
    }
  }

  // Tile 0 right padding, which comes from left edge of tile 2.
  for(int j=0;j<tile_size;j++) {
    int j_storage = pad_size + j;
    for(int i=0;i<pad_size;i++) {
      int i_storage = pad_size+tile_size + i;
      Vector3 vertex = Vector3(sides[i],sides[j],cube_width);
      vertex.normalize();
      floats[3*(j_storage*i_width+i_storage)+0] = vertex.x;
      floats[3*(j_storage*i_width+i_storage)+1] = vertex.y;
      floats[3*(j_storage*i_width+i_storage)+2] = vertex.z;
    }
  }

  // Lower-right padding
  for(int j=0;j<pad_size;j++) {
    int j_storage = pad_size-1 - j;
    for(int i=0;i<pad_size;i++) {
      int i_storage = tile_size+pad_size + i;
      int ij = i+j;
      Vector3 vertex = Vector3(sides[ij],-cube_width,cube_width);
      vertex.normalize();
      floats[3*(j_storage*i_width+i_storage)+0] = vertex.x;
      floats[3*(j_storage*i_width+i_storage)+1] = vertex.y;
      floats[3*(j_storage*i_width+i_storage)+2] = vertex.z;
    }
  }

  // Upper-right padding
  for(int j=0;j<pad_size;j++) {
    int j_storage = tile_size+pad_size + j;
    for(int i=0;i<pad_size;i++) {
      int i_storage = tile_size+pad_size + i;
      int ij = i+j;
      Vector3 vertex = Vector3(sides[ij],cube_width,cube_width);
      vertex.normalize();
      floats[3*(j_storage*i_width+i_storage)+0] = vertex.x;
      floats[3*(j_storage*i_width+i_storage)+1] = vertex.y;
      floats[3*(j_storage*i_width+i_storage)+2] = vertex.z;
    }
  }

  // Lower-left padding
  for(int j=0;j<pad_size;j++) {
    int j_storage = pad_size-1 - j;
    for(int i=0;i<pad_size;i++) {
      int i_storage = pad_size-1 - i;
      int ij = i+j;
      Vector3 vertex = Vector3(sides[ij],-cube_width,-cube_width);
      vertex.normalize();
      floats[3*(j_storage*i_width+i_storage)+0] = vertex.x;
      floats[3*(j_storage*i_width+i_storage)+1] = vertex.y;
      floats[3*(j_storage*i_width+i_storage)+2] = vertex.z;
    }
  }

  // Upper-left padding
  for(int j=0;j<pad_size;j++) {
    int j_storage = tile_size+pad_size + j;
    for(int i=0;i<pad_size;i++) {
      int i_storage = pad_size-1 - i;
      int ij = i+j;
      Vector3 vertex = Vector3(sides[ij],cube_width,-cube_width);
      vertex.normalize();
      floats[3*(j_storage*i_width+i_storage)+0] = vertex.x;
      floats[3*(j_storage*i_width+i_storage)+1] = vertex.y;
      floats[3*(j_storage*i_width+i_storage)+2] = vertex.z;
    }
  }

  // Copy from tile 0 to 1-5, rotating as needed. Zero-out unused tiles 6&7

  const int shift_size = tile_size+2*pad_size;

  for(int j=0;j<shift_size;j++) {
    int dst=shift_size; // i index in destination tile; src is in tile 0
    for(int src=0;dst<2*shift_size;dst++,src++) { // tile 2
      floats[3*(j*i_width+dst)+0] =  floats[3*(j*i_width+src)+2]; // tile 2 x = 0's  z
      floats[3*(j*i_width+dst)+1] =  floats[3*(j*i_width+src)+1]; // tile 2 y = 0's  y
      floats[3*(j*i_width+dst)+2] = -floats[3*(j*i_width+src)+0]; // tile 2 z = 0's -x
    }
    for(int src=0;dst<3*shift_size;dst++,src++) { // tile 4
      floats[3*(j*i_width+dst)+0] =  floats[3*(j*i_width+src)+1]; // tile 4 x = 0's  y
      floats[3*(j*i_width+dst)+1] = -floats[3*(j*i_width+src)+0]; // tile 4 y = 0's -x
      floats[3*(j*i_width+dst)+2] =  floats[3*(j*i_width+src)+2]; // tile 4 z = 0's  z
    }
    for(;dst<4*shift_size;dst++) { // unused tile 6
      floats[3*(j*i_width+dst)+0] = 0;
      floats[3*(j*i_width+dst)+1] = 0;
      floats[3*(j*i_width+dst)+2] = 0;
    }
  }

  for(int srcj=0,dstj=shift_size;srcj<shift_size;srcj++,dstj++) {
    int dsti=0;
    for(int srci=0;dsti<shift_size;dsti++,srci++) { // tile 1
      floats[3*(dstj*i_width+dsti)+0] = -floats[3*(srcj*i_width+srci)+0]; // tile 1 x = 0's -x
      floats[3*(dstj*i_width+dsti)+1] =  floats[3*(srcj*i_width+srci)+1]; // tile 1 y = 0's  y
      floats[3*(dstj*i_width+dsti)+2] = -floats[3*(srcj*i_width+srci)+2]; // tile 1 z = 0's -z
    }
    for(int srci=0;dsti<2*shift_size;dsti++,srci++) { // tile 3
      floats[3*(dstj*i_width+dsti)+0] = -floats[3*(srcj*i_width+srci)+2]; // tile 3 x = 0's -z
      floats[3*(dstj*i_width+dsti)+1] =  floats[3*(srcj*i_width+srci)+1]; // tile 3 y = 0's  y
      floats[3*(dstj*i_width+dsti)+2] =  floats[3*(srcj*i_width+srci)+0]; // tile 3 z = 0's  x
    }
    for(int srci=0;dsti<3*shift_size;dsti++,srci++) { // tile 5
      floats[3*(dstj*i_width+dsti)+0] = -floats[3*(srcj*i_width+srci)+1]; // tile 5 x = 0's -y
      floats[3*(dstj*i_width+dsti)+1] =  floats[3*(srcj*i_width+srci)+0]; // tile 5 y = 0's  x
      floats[3*(dstj*i_width+dsti)+2] =  floats[3*(srcj*i_width+srci)+2]; // tile 5 z = 0's  z
    }
    for(;dsti<4*shift_size;dsti++) { // unused tile 7
      floats[3*(dstj*i_width+dsti)+0] = 0;
      floats[3*(dstj*i_width+dsti)+1] = 0;
      floats[3*(dstj*i_width+dsti)+2] = 0;
    }
  }
  
  PoolByteArray data_pool;
  {
    data_pool.resize(num_floats*sizeof(float));
    PoolByteArray::Write data_write = data_pool.write();
    memcpy(data_write.ptr(), floats, num_floats*sizeof(float));
  }

  delete[] floats;
  floats = nullptr;
  
  Ref<Image> image = Image::_new();
  image->create_from_data(i_width, j_height, false, Image::FORMAT_RGBF, data_pool);
  //image->convert(Image::FORMAT_RGBH);
  return image;
}

Ref<Image> make_lookup_tiles_c224() {
  FAST_PROFILING_FUNCTION;
  return make_lookup_tiles<224,16>();
}

Ref<Image> make_lookup_tiles_c112() {
  FAST_PROFILING_FUNCTION;
  return make_lookup_tiles<112,8>();
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

}
