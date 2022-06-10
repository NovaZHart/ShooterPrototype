#include "PreloadResources.hpp"
#include "CombatEngine.hpp"
#include "Starmap.hpp"
#include "SphereTool.hpp"
#include "VisualEffects.hpp"
#include "OSTools.hpp"
#include "HUDStatDisplay.hpp"

extern "C" void GDN_EXPORT godot_gdnative_init(godot_gdnative_init_options *o) {
    godot::Godot::gdnative_init(o);
}

extern "C" void GDN_EXPORT godot_gdnative_terminate(godot_gdnative_terminate_options *o) {
    godot::Godot::gdnative_terminate(o);
}

extern "C" void GDN_EXPORT godot_nativescript_init(void *handle) {
    godot::Godot::nativescript_init(handle);

    godot::register_class<godot::CombatEngine>();
    godot::register_class<godot::VisualEffects>();
    godot::register_class<godot::PreloadResources>();
    godot::register_class<godot::SphereTool>();
    godot::register_class<godot::Starmap>();
    godot::register_class<godot::OSTools>();
    godot::register_class<godot::HUDStatDisplay>();
}
