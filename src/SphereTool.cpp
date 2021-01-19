#include "SphereTool.hpp"

#include <cmath>
#include <GodotGlobal.hpp>
#include <SurfaceTool.hpp>
#include <Mesh.hpp>
#include <ArrayMesh.hpp>
#include <vector>

using namespace godot;
using namespace std;

typedef vector<Vector3> vectorVector3;
typedef vector<vectorVector3> vectorVectorVector3;

void SphereTool::_register_methods() {
  register_method("_process", &SphereTool::_process);
  register_method("make_icosphere", &SphereTool::make_icosphere);
  register_method("make_cube_sphere", &SphereTool::make_cube_sphere);
}

SphereTool::SphereTool() {}
SphereTool::~SphereTool() {}

void SphereTool::_init() {}
void SphereTool::_process(float delta) {}

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
