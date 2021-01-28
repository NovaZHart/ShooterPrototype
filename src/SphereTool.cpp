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

using namespace godot;
using namespace std;

typedef vector<Vector3> vectorVector3;
typedef vector<vectorVector3> vectorVectorVector3;

void SphereTool::_register_methods() {
  register_method("make_icosphere", &SphereTool::make_icosphere);
  register_method("make_cube_sphere", &SphereTool::make_cube_sphere);
  register_method("make_cube_sphere_v2", &SphereTool::make_cube_sphere_v2);
  register_method("make_lookup_tiles_c224", &SphereTool::make_lookup_tiles_c224);
}

SphereTool::SphereTool() {}
SphereTool::~SphereTool() {}

void SphereTool::_init() {}

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

void SphereTool::make_icosphere(String name, Vector3 center, float radius, int subs) {
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
  set_mesh(tool->commit(nullptr,Mesh::ARRAY_COMPRESS_DEFAULT));
  set_name(name);
  translate(center);
  scale_object_local(Vector3(radius,radius,radius));
}

void SphereTool::make_cube_sphere(String name,Vector3 center, float float_radius, int subs) {
  double radius = float_radius;
  Ref<SurfaceTool> tool=SurfaceTool::_new();

  const double pi = 3.14159265358979323846;

  double angles[subs+1];
  double sides[subs+1];
  for(int i=0;i<=subs;i++) {
    angles[i]=pi/2 * (i-(subs/2.0))/subs;
    sides[i]=tan(angles[i])/sqrt(2);
  }
  tool->begin(Mesh::PRIMITIVE_TRIANGLES);

  const int i_add[2][6] = { {0,0,1,1,1,0}, {0,0,1,1,0,1} };
  const int j_add[2][6] = { {0,1,1,1,0,0}, {0,1,0,0,1,1} };
  const double width = 1.0/sqrt(2.0), widthsq=0.5;
  int u_add[6] = {subs,2*subs,3*subs,0,subs,0};
  int v_add[6] = {subs,subs,subs,subs,0,0};
  int ij_size = subs*4;
  Vector3 vertex;

  for(int itile=0;itile<6;itile++)
    for(int j=0;j<subs;j++)
      for(int i=0;i<subs;i++) {
        int k=(i+j)%2; // Squares will be triangulated in alternating order, creating peaks
        for(int t=0;t<6;t++) {
          double u=u_add[itile]+i+i_add[k][t];
          double v=v_add[itile]+j+j_add[k][t];
          double x=sides[i+i_add[k][t]],y=sides[j+j_add[k][t]],z=width;
          double l=sqrt(x*x+y*y+z*z);
          tool->add_uv(Vector2(u/ij_size,v/ij_size));
          x/=l;
          y/=l;
          z/=l;
          switch(itile) {
          case 1:  vertex=Vector3(z,y,-x);  break;
          case 2:  vertex=Vector3(-x,y,-z); break;
          case 3:  vertex=Vector3(-z,y,x);  break;
          case 4:  vertex=Vector3(x,-z,y);  break;
          case 5:  vertex=Vector3(x,z,-y);  break;
          case 0:
          default: vertex=Vector3(x,y,z);   break;
          };
          tool->add_normal(vertex);
          tool->add_vertex(vertex);
        }
      }
  set_mesh(tool->commit(nullptr,Mesh::ARRAY_COMPRESS_DEFAULT));
  set_name(name);
  translate(center);
  scale_object_local(Vector3(radius,radius,radius));
}

inline void swap32(uint32_t *data, int n) {
  for(int i=0;i<n;i++)
    data[i] = (data[i]&0xff000000 >> 24) |
              (data[i]&0x00ff0000 >>  8) |
              (data[i]&0x0000ff00 <<  8) |
              (data[i]&0x000000ff << 24);
}

void SphereTool::make_cube_sphere_v2(String name,Vector3 center, float float_radius, int subs) {
  const double pi = 3.14159265358979323846;
  const double u_start[6] = { 1/64.0, 1/64.0, 17/64.0, 17/64.0, 33/64.0, 33/64.0 };
  const double v_start[6] = { 1/32.0, 17/32.0, 1/32.0, 17/32.0, 1/32.0, 17/32.0 };
  const double width = 1.0/sqrt(2.0), widthsq=0.5, u_scale=14/64.0, v_scale=14/32.0;
  const int i_add[2][6] = { {0,0,1,1,1,0}, {0,0,1,1,0,1} };
  const int j_add[2][6] = { {0,1,1,1,0,0}, {0,1,0,0,1,1} };

  double radius = float_radius;
  PoolVector3Array vert_pool;
  PoolVector3Array normal_pool;
  PoolVector2Array uv_pool;

  int size = subs*subs*6*6;
  vert_pool.resize(size);
  normal_pool.resize(size);
  uv_pool.resize(size);
  
  PoolVector3Array::Write vert_write = vert_pool.write();
  PoolVector3Array::Write normal_write = normal_pool.write();
  PoolVector2Array::Write uv_write = uv_pool.write();

  Vector3 *verts = vert_write.ptr();
  Vector3 *normals = normal_write.ptr();
  Vector2 *uvs = uv_write.ptr();

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
        normals[ivert] = vertex;
      }
    }

  // Copy to other tiles, rotating as needed.
  for(int n=0;n<6*subs*subs;n++,ivert++) {
    uvs[ivert].x = uvs[n].x + (u_start[1]-u_start[0]);
    uvs[ivert].y = uvs[n].y + (v_start[1]-v_start[0]);
    normals[ivert] = Vector3(-normals[n].x, normals[n].y,-normals[n].z);
    verts[ivert] = Vector3(-verts[n].x, verts[n].y,-verts[n].z);
  }

  for(int n=0;n<6*subs*subs;n++,ivert++) {
    uvs[ivert].x = uvs[n].x + (u_start[2]-u_start[0]);
    uvs[ivert].y = uvs[n].y + (v_start[2]-v_start[0]);
    normals[ivert] = Vector3( normals[n].z, normals[n].y,-normals[n].x);
    verts[ivert] = Vector3( verts[n].z, verts[n].y,-verts[n].x);
  }
    
  for(int n=0;n<6*subs*subs;n++,ivert++) {
    uvs[ivert].x = uvs[n].x + (u_start[3]-u_start[0]);
    uvs[ivert].y = uvs[n].y + (v_start[3]-v_start[0]);
    normals[ivert] = Vector3(-normals[n].z, normals[n].y, normals[n].x);
    verts[ivert] = Vector3(-verts[n].z, verts[n].y, verts[n].x);
  }

  for(int n=0;n<6*subs*subs;n++,ivert++) {
    uvs[ivert].x = uvs[n].x + (u_start[4]-u_start[0]);
    uvs[ivert].y = uvs[n].y + (v_start[4]-v_start[0]);
    normals[ivert] = Vector3( normals[n].y,-normals[n].x, normals[n].z);
    verts[ivert] = Vector3( verts[n].y,-verts[n].x, verts[n].z);
  }

  for(int n=0;n<6*subs*subs;n++,ivert++) {
    uvs[ivert].x = uvs[n].x + (u_start[5]-u_start[0]);
    uvs[ivert].y = uvs[n].y + (v_start[5]-v_start[0]);
    normals[ivert] = Vector3(-normals[n].y, normals[n].x, normals[n].z);
    verts[ivert] = Vector3(-verts[n].y, verts[n].x, verts[n].z);
  }

  Array content;
  content.resize(ArrayMesh::ARRAY_MAX);
  content[ArrayMesh::ARRAY_VERTEX] = vert_pool;
  content[ArrayMesh::ARRAY_TEX_UV] = uv_pool;
  content[ArrayMesh::ARRAY_NORMAL] = normal_pool;
  Ref<ArrayMesh> mesh = ArrayMesh::_new();
  mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES,content,Array(),ArrayMesh::ARRAY_COMPRESS_VERTEX|ArrayMesh::ARRAY_COMPRESS_TEX_UV|ArrayMesh::ARRAY_COMPRESS_NORMAL);
  set_mesh(mesh);
  set_name(name);
  translate(center);
}

template<int tile_size, int pad_size>
Ref<Image> make_lookup_tiles() {
  const float cube_width = 1.0/sqrt(2.0);
  const int j_height = (tile_size+2*pad_size)*2;
  const int i_width = (tile_size+2*pad_size)*4;
  const int num_floats = i_width * j_height * 3;
  const float pi = 3.141592653589793f;
  std::array<float, num_floats> floats;

  memset(floats.data(),0,sizeof(float)*num_floats);
  
  float sides[tile_size];
  {
    float angles[tile_size];

    for(int i=0;i<tile_size;i++) {
      float m = i+0.5;
      angles[i]=pi/2 * (m-(tile_size/2.0))/tile_size;
      sides[i]=tan(angles[i])/sqrt(2);
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

  // Copy from tile 0 to 1-5, rotating as needed. Zero-out unused tiles 7&8.

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
    memcpy(data_write.ptr(), floats.data(), num_floats*sizeof(float));
  }

  Ref<Image> image = Image::_new();
  image->create_from_data(i_width, j_height, false, Image::FORMAT_RGBF, data_pool);
  image->convert(Image::FORMAT_RGBH);
  return image;
}

Ref<Image> SphereTool::make_lookup_tiles_c224() const {
  return make_lookup_tiles<224,16>();
}
