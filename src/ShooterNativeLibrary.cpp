#include "PreloadResources.hpp"
#include "CE/CombatEngine.hpp"
#include "Starmap.hpp"
#include "SphereTool.hpp"
#include "CE/VisualEffects.hpp"
#include "HUDStatDisplay.hpp"
#include "IntersectionTest.hpp"

extern "C" void GDN_EXPORT godot_gdnative_init(godot_gdnative_init_options *o) {
    godot::Godot::gdnative_init(o);
}

extern "C" void GDN_EXPORT godot_gdnative_terminate(godot_gdnative_terminate_options *o) {
    godot::Godot::nativescript_terminate(godot::_RegisterState::nativescript_handle);
    godot::Godot::gdnative_terminate(o);
}

extern "C" void GDN_EXPORT godot_nativescript_init(void *handle) {
    godot::Godot::nativescript_init(handle);

    godot::register_class<godot::CE::CombatEngine>();
    godot::register_class<godot::CE::VisualEffects>();
    godot::register_class<godot::PreloadResources>();
    godot::register_class<godot::SphereTool>();
    godot::register_class<godot::Starmap>();
    godot::register_class<godot::HUDStatDisplay>();
    godot::register_class<godot::IntersectionTest>();
}
