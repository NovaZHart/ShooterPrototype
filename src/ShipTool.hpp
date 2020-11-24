#ifndef SHIPTOOL_H
#define SHIPTOOL_H

#include <Godot.hpp>
#include <Variant.hpp>
#include <Array.hpp>
#include <Dictionary.hpp>
#include <Node.hpp>
#include <RigidBody.hpp>
#include <Area.hpp>
#include <Spatial.hpp>
#include <PhysicsDirectBodyState.hpp>

namespace godot {

  class ShipTool: public Node {
    GODOT_CLASS(ShipTool, Node)

    public:
    static void _register_methods();
    ShipTool();
    ~ShipTool();
    void _init();

    void request_move_to_attack(RigidBody *ship, PhysicsDirectBodyState *state, RigidBody *target,Spatial *system);
    void player_auto_target(RigidBody *ship,PhysicsDirectBodyState *state, RigidBody *target);
    void auto_fire(RigidBody *ship, PhysicsDirectBodyState *state, RigidBody *target,Spatial *system);
    void request_rotation(RigidBody *ship, PhysicsDirectBodyState *state, double rotate);
    void request_thrust(RigidBody *ship, PhysicsDirectBodyState *state,double forward,double reverse);
    void request_primary_fire(RigidBody *ship, PhysicsDirectBodyState *state);
    Vector3 make_threat_vector(RigidBody *ship, Array near_objects,
                               double shape_radius, double t);
    void guide_RigidProjectile(RigidBody *projectile, PhysicsDirectBodyState *state,
                               RigidBody *target, bool use_velocity);
    void aim_turrets(RigidBody *ship, PhysicsDirectBodyState *state,
                     RigidBody *target, Spatial *system);
    
    void request_heading(RigidBody *ship, PhysicsDirectBodyState *state, Vector3 new_heading);
    bool move_to_intercept(RigidBody *ship, PhysicsDirectBodyState *state,double close, double slow,
                           Vector3 tgt_pos, Vector3 tgt_vel,
                           bool force_final_state=false);


    void velocity_to_heading(RigidBody *projectile, PhysicsDirectBodyState *state);
    Vector3 aim_forward(RigidBody *ship, PhysicsDirectBodyState *state,
                        RigidBody *target);
    Vector3 stopping_point(RigidBody *ship,PhysicsDirectBodyState *state,Vector3 tgt_vel, bool &should_reverse);
    double rendezvous_time(Vector3 target_location,Vector3 target_velocity, double interceptor_speed);
    Dictionary check_target_lock(RigidBody *ship, PhysicsDirectBodyState *state, Vector3 point1,
                                 Vector3 point2, RigidBody *target);
    void move_to_attack(RigidBody *ship, PhysicsDirectBodyState *state, RigidBody *target);

    void guide_AreaProjectile(Area *projectile, double delta,
                              RigidBody *target, bool use_velocity);
    void velocity_to_heading(Area *projectile, double delta);
  };
}


#endif
